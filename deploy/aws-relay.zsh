#!/bin/zsh
# The Borderless public relay on AWS (us-east-1). Holds no secrets: the operator's secrets script
# puts META_API_KEY into SSM; the box reads it with its own role. The release client key ships in
# the app (public by nature) and is passed as plain config from .budget/release-relay-token.
#
#   zsh deploy/aws-relay.zsh up         create what is missing (bucket, role, SG, EIP, box), then deploy
#   zsh deploy/aws-relay.zsh deploy     ship HEAD of this checkout to the box and restart it
#   zsh deploy/aws-relay.zsh pause      kill switch on: refuse new paid sessions (no redeploy)
#   zsh deploy/aws-relay.zsh resume     kill switch off
#   zsh deploy/aws-relay.zsh limit DAILY_NANODOLLARS 5000000000    change one limit (restarts relay)
#   zsh deploy/aws-relay.zsh secrets    re-read SSM on the box (after the secrets script)
#   zsh deploy/aws-relay.zsh status
#
# Needs an AWS session for the project's own account, named explicitly so a client account can
# never be used by accident:
#   AWS_PROFILE=<profile> BORDERLESS_AWS_ACCOUNT=<account id> zsh deploy/aws-relay.zsh up
set -euo pipefail

readonly PROFILE=${AWS_PROFILE:?set AWS_PROFILE to the project profile}
readonly ACCOUNT=${BORDERLESS_AWS_ACCOUNT:?set BORDERLESS_AWS_ACCOUNT to the expected account id}
readonly REGION=us-east-1
readonly NAME=borderless-relay
readonly INSTANCE_TYPE=t4g.nano
readonly AMI_PARAMETER=/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64
readonly VOLUME_GB=8
readonly SSM_PREFIX=/borderless/prod
# Local dev spend allowed after a deploy before the hosted ledger is re-seeded (nanodollars, $1).
readonly LOCAL_HEADROOM=1000000000
readonly ONLINE_TRIES=60
readonly COMMAND_TRIES=120
readonly POLL_SECONDS=5

readonly REPO=${0:A:h:h}
readonly MAIN_CHECKOUT=${$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir):h}
readonly LOCAL_LEDGER=${BORDERLESS_LOCAL_LEDGER:-$MAIN_CHECKOUT/.budget/ledger.sqlite3}
readonly RELEASE_KEY_FILE=$MAIN_CHECKOUT/.budget/release-relay-token
readonly DEV_TOKEN_FILE=$MAIN_CHECKOUT/.budget/relay-token
readonly WORK=$REPO/.build/deploy

die() { print -u2 -r -- "aws-relay: $*"; exit 1; }
step() { print -r -- "==> $*"; }
aws_() { aws --profile "$PROFILE" --region "$REGION" "$@"; }

check_account() {
  local account
  account=$(aws_ sts get-caller-identity --query Account --output text 2>/dev/null) \
    || die "no AWS session: the operator runs 'aws sso login --profile $PROFILE'"
  [[ "$account" == "$ACCOUNT" ]] || die "profile $PROFILE is account $account, not $ACCOUNT"
}

bucket() { print -r -- "borderless-deploy-$ACCOUNT"; }

ensure_bucket() {
  local name=$(bucket)
  if ! aws_ s3api head-bucket --bucket "$name" >/dev/null 2>&1; then
    step "create bucket $name"
    aws_ s3api create-bucket --bucket "$name" >/dev/null
  fi
  aws_ s3api put-public-access-block --bucket "$name" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
}

ensure_role() {
  if ! aws_ iam get-role --role-name "$NAME" >/dev/null 2>&1; then
    step "create IAM role $NAME"
    aws_ iam create-role --role-name "$NAME" --assume-role-policy-document \
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  fi
  # Run Command and Session Manager without the managed policy's ssm:GetParameter on every parameter.
  local policy
  policy=$(python3 - "$ACCOUNT" "$REGION" "$SSM_PREFIX" "$(bucket)" <<'PY'
import json, sys
account, region, prefix, bucket = sys.argv[1:]
print(json.dumps({"Version": "2012-10-17", "Statement": [
    {"Sid": "Agent", "Effect": "Allow", "Resource": "*", "Action": [
        "ssm:DescribeAssociation", "ssm:GetDeployablePatchSnapshotForInstance", "ssm:GetDocument",
        "ssm:DescribeDocument", "ssm:GetManifest", "ssm:ListAssociations", "ssm:ListInstanceAssociations",
        "ssm:PutInventory", "ssm:PutComplianceItems", "ssm:PutConfigurePackageResult",
        "ssm:UpdateAssociationStatus", "ssm:UpdateInstanceAssociationStatus", "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
        "ec2messages:AcknowledgeMessage", "ec2messages:DeleteMessage", "ec2messages:FailMessage",
        "ec2messages:GetEndpoint", "ec2messages:GetMessages", "ec2messages:SendReply"]},
    {"Sid": "Secrets", "Effect": "Allow", "Action": "ssm:GetParameter",
     "Resource": f"arn:aws:ssm:{region}:{account}:parameter{prefix}/*"},
    {"Sid": "SecretsKey", "Effect": "Allow", "Action": "kms:Decrypt", "Resource": "*",
     "Condition": {"StringEquals": {"kms:ViaService": f"ssm.{region}.amazonaws.com"}}},
    {"Sid": "Bundles", "Effect": "Allow", "Action": "s3:GetObject",
     "Resource": f"arn:aws:s3:::{bucket}/bundles/*"},
]}))
PY
)
  aws_ iam put-role-policy --role-name "$NAME" --policy-name "$NAME" --policy-document "$policy"
  if ! aws_ iam get-instance-profile --instance-profile-name "$NAME" >/dev/null 2>&1; then
    step "create instance profile $NAME"
    aws_ iam create-instance-profile --instance-profile-name "$NAME" >/dev/null
    aws_ iam add-role-to-instance-profile --instance-profile-name "$NAME" --role-name "$NAME"
    sleep 10   # instance profiles take a moment to become usable by run-instances
  fi
}

ensure_security_group() {
  local vpc group
  vpc=$(aws_ ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
  [[ "$vpc" == vpc-* ]] || die "no default VPC in $REGION"
  group=$(aws_ ec2 describe-security-groups --filters Name=group-name,Values="$NAME" Name=vpc-id,Values="$vpc" \
    --query 'SecurityGroups[0].GroupId' --output text)
  if [[ "$group" != sg-* ]]; then
    step "create security group $NAME (80/443 only, no SSH)" >&2
    group=$(aws_ ec2 create-security-group --group-name "$NAME" --vpc-id "$vpc" \
      --description "Borderless relay: HTTP for ACME, HTTPS/WSS" --query GroupId --output text)
    aws_ ec2 authorize-security-group-ingress --group-id "$group" --ip-permissions \
      'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}],Ipv6Ranges=[{CidrIpv6=::/0}]' \
      'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}],Ipv6Ranges=[{CidrIpv6=::/0}]' >/dev/null
  fi
  print -r -- "$group"
}

instance_id() {
  aws_ ec2 describe-instances --filters Name=tag:Name,Values="$NAME" \
    Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}

ensure_instance() {
  local id group ami attempt
  id=$(instance_id)
  if [[ "$id" == i-* ]]; then
    print -r -- "$id"
    return
  fi
  group=$(ensure_security_group)
  ami=$(aws_ ssm get-parameter --name "$AMI_PARAMETER" --query Parameter.Value --output text)
  step "launch $INSTANCE_TYPE $NAME from $ami" >&2
  for attempt in 1 2 3 4 5 6; do
    if id=$(aws_ ec2 run-instances --image-id "$ami" --instance-type "$INSTANCE_TYPE" \
        --iam-instance-profile Name="$NAME" --security-group-ids "$group" \
        --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled \
        --credit-specification CpuCredits=standard --disable-api-termination \
        --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$VOLUME_GB,\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":false}}]" \
        --user-data "file://$REPO/deploy/hosted/box/user-data.sh" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=borderless}]" \
          "ResourceType=volume,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=borderless}]" \
        --query 'Instances[0].InstanceId' --output text 2>/dev/null); then
      print -r -- "$id"
      return
    fi
    sleep 10   # a fresh instance profile can be "invalid" for a few seconds
  done
  die "run-instances kept failing (instance profile not ready?)"
}

ensure_address() {
  local id=$1 allocation ip
  allocation=$(aws_ ec2 describe-addresses --filters Name=tag:Name,Values="$NAME" \
    --query 'Addresses[0].AllocationId' --output text)
  if [[ "$allocation" != eipalloc-* ]]; then
    step "allocate Elastic IP" >&2
    allocation=$(aws_ ec2 allocate-address --domain vpc \
      --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=borderless}]" \
      --query AllocationId --output text)
  fi
  aws_ ec2 wait instance-running --instance-ids "$id"
  aws_ ec2 associate-address --instance-id "$id" --allocation-id "$allocation" --allow-reassociation >/dev/null
  ip=$(aws_ ec2 describe-addresses --allocation-ids "$allocation" --query 'Addresses[0].PublicIp' --output text)
  print -r -- "$ip"
}

hostname_for() { print -r -- "borderless.${1//./-}.sslip.io"; }

current_host() {
  local ip
  ip=$(aws_ ec2 describe-addresses --filters Name=tag:Name,Values="$NAME" --query 'Addresses[0].PublicIp' --output text)
  [[ "$ip" == <->.<->.<->.<-> ]] || die "no Elastic IP yet: run 'up'"
  hostname_for "$ip"
}

wait_online() {
  local id=$1 attempt ping
  for ((attempt = 1; attempt <= ONLINE_TRIES; attempt++)); do
    ping=$(aws_ ssm describe-instance-information --filters "Key=InstanceIds,Values=$id" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)
    [[ "$ping" == Online ]] && return 0
    sleep "$POLL_SECONDS"
  done
  die "$id never came online in SSM"
}

# run_on_box <commands…>: one SSM Run Command, waits, prints its output, fails with it.
run_on_box() {
  local id parameters command_id attempt result
  id=$(instance_id)
  [[ "$id" == i-* ]] || die "no box yet: run 'up'"
  parameters=$(python3 -c 'import json, sys; print(json.dumps({"commands": sys.argv[1:], "executionTimeout": ["900"]}))' "$@")
  command_id=$(aws_ ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
    --comment "borderless relay" --parameters "$parameters" --query Command.CommandId --output text)
  for ((attempt = 1; attempt <= COMMAND_TRIES; attempt++)); do
    sleep "$POLL_SECONDS"
    result=$(aws_ ssm get-command-invocation --command-id "$command_id" --instance-id "$id" \
      --query Status --output text 2>/dev/null || true)
    case "$result" in
      Success|Failed|Cancelled|TimedOut) break ;;
    esac
  done
  aws_ ssm get-command-invocation --command-id "$command_id" --instance-id "$id" \
    --query '[StandardOutputContent, StandardErrorContent]' --output text
  [[ "$result" == Success ]] || die "box command ended: ${result:-no answer}"
}

prior_spend() {
  [[ -f "$LOCAL_LEDGER" ]] || die "local ledger missing at $LOCAL_LEDGER"
  # Read-only total (committed + pending) through the project's own Ledger class.
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from budget_relay.core import Ledger; print(Ledger(sys.argv[2]).used() + int(sys.argv[3]))' \
    "$REPO" "$LOCAL_LEDGER" "$LOCAL_HEADROOM"
}

release_key() {
  # The hosted relay must never accept the dev token: refuse a release key equal to it.
  python3 -c '
import hashlib, re, sys
key = open(sys.argv[1]).read().strip()
try:
    dev = open(sys.argv[2]).read().strip()
except OSError:
    dev = ""
if not re.fullmatch(r"[A-Za-z0-9_-]{32,256}", key):
    sys.exit("release client key must be 32-256 url-safe characters")
if hashlib.sha256(key.encode()).digest() == hashlib.sha256(dev.encode()).digest():
    sys.exit("release client key equals the dev token; make a new one")
print(key)' "$RELEASE_KEY_FILE" "$DEV_TOKEN_FILE" || die "no usable release client key at $RELEASE_KEY_FILE"
}

deploy() {
  [[ -z "$(git -C "$REPO" status --porcelain -- budget_relay conversation_relay voice_relay deploy)" ]] \
    || die "uncommitted relay or deploy changes; commit first"
  local sha prior host bundle key
  sha=$(git -C "$REPO" rev-parse HEAD)
  prior=$(prior_spend)
  key=$(release_key)
  host=$(current_host)
  mkdir -p "$WORK"
  bundle="$WORK/$sha.tgz"
  git -C "$REPO" archive --format=tar.gz -o "$bundle" "$sha" -- budget_relay conversation_relay voice_relay deploy
  step "upload bundle $sha"
  aws_ s3 cp --only-show-errors "$bundle" "s3://$(bucket)/bundles/$sha.tgz"
  step "deploy $sha to $host (prior spend $prior nanodollars)"
  run_on_box "set -euo pipefail" \
    "release=/opt/borderless/releases/$sha" \
    "mkdir -p \"\$release\"" \
    "aws s3 cp --only-show-errors --region $REGION s3://$(bucket)/bundles/$sha.tgz /opt/borderless/$sha.tgz" \
    "tar -xzf /opt/borderless/$sha.tgz -C \"\$release\"" \
    "bash \"\$release/deploy/hosted/box/borderless-host\" deploy \"\$release\" $sha $host $prior $key"
  step "check from here"
  curl -fsS --max-time 10 "https://$host/health"
  print -r -- "wss://$host/live"
}

up() {
  ensure_bucket
  ensure_role
  local id ip
  id=$(ensure_instance)
  ip=$(ensure_address "$id")
  step "box $id at $ip, waiting for SSM"
  wait_online "$id"
  run_on_box "for i in \$(seq 60); do systemctl is-active --quiet docker && exit 0; sleep 5; done; exit 1"
  deploy
}

export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off
check_account
case "${1:-status}" in
  up) up ;;
  deploy) deploy ;;
  pause|resume|secrets) run_on_box "/usr/local/sbin/borderless-host $1" ;;
  limit)
    (( $# == 3 )) || die "usage: limit NAME VALUE"
    [[ "$2" =~ '^[A-Z_]+$' && "$3" =~ '^[0-9]+$' ]] || die "NAME must be A-Z_, VALUE an integer"
    run_on_box "/usr/local/sbin/borderless-host limit $2 $3"
    ;;
  status) run_on_box "/usr/local/sbin/borderless-host status" ;;
  *) die "unknown command ${1}" ;;
esac
