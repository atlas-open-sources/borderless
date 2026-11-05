# Public relay (TestFlight and judges)

The release app talks to `wss://<host>/live`. The host is one AWS EC2 box in the project's account,
us-east-1: t4g.nano, Amazon Linux 2023, Elastic IP, hostname `borderless.<ip-with-dashes>.sslip.io`.
Caddy terminates TLS (automatic certificate) and proxies `/live` and `/health` to the relay. The
relay runs `python -m conversation_relay.hosted` in Docker and listens plain on the private Docker
network (`--behind-proxy`). The box also serves `/.well-known/apple-app-site-association` (app id
`599WAZ6282.ai.atlascodes.borderless`, paths `/meta-callback/*`) and `/privacy`.

Cost: about $7.40 a month (t4g.nano $3.07, public IPv4 $3.65, 8 GB gp3 $0.64; S3 bundles cost
cents). No load balancer, no cold start: the box is always on.

## Operate

From a checkout, with an AWS session for the project account (`aws sso login`, the operator), run
every command as `AWS_PROFILE=<profile> BORDERLESS_AWS_ACCOUNT=<account id> zsh deploy/aws-relay.zsh …`:

| Command | What it does |
| --- | --- |
| `zsh deploy/aws-relay.zsh up` | create what is missing (S3 bundle bucket, IAM role, security group 80/443, EIP, box), then deploy |
| `zsh deploy/aws-relay.zsh deploy` | ship committed HEAD (bundle to S3, SSM Run Command builds the image on the box), check `/health` |
| `zsh deploy/aws-relay.zsh pause` / `resume` | kill switch: refuse / admit new paid sessions, no restart |
| `zsh deploy/aws-relay.zsh limit DAILY_NANODOLLARS 5000000000` | change one limit (restarts the relay) |
| `zsh deploy/aws-relay.zsh secrets` | the box re-reads SSM (after the auth script) |
| `zsh deploy/aws-relay.zsh status` | SHA, host, kill switch, limits, containers, health, sessions in 24 h |

The first install starts **paused**. No SSH port: operator access is SSM only.

Secrets: only `META_API_KEY`, an SSM SecureString at `/borderless/prod/META_API_KEY`, put there by
the operator's secrets script. The box renders it into tmpfs (`/run/borderless`, 0400, relay user)
at deploy, at boot and on `secrets`. The box role can read only that SSM path and the bundle prefix
of its bucket.

The release client key is not a secret: it ships inside every app build. It lives in the ignored
`.budget/release-relay-token` of the main checkout, `deploy` passes it to the box as plain config
(`BORDERLESS_RELAY_TOKEN` in a 0600 env file), and `deploy` refuses a key equal to the dev token, so
the hosted relay never accepts the dev token. Rotate it by writing a new key and redeploying (old
app builds then stop authenticating).

## Spend safety

Meta has no provider-side cap, so the relay enforces these before any paid call. State is SQLite on
the `borderless-data` volume (ledger and counters), so restarts reset nothing.

| Limit | Default | Env override (`BORDERLESS_LIMIT_…`) |
| --- | --- | --- |
| Paid sessions at once (then "busy, try again in a minute") | 3 | `CAPACITY` |
| Audio per capture | 60 s | `AUDIO_SECONDS` |
| Wall clock per session (audio + translation tail) | 120 s | `SESSION_SECONDS` |
| Translations per session | 8 | `SESSION_TRANSLATIONS` |
| Per install: sessions per hour / audio per 24 h | 12 / 15 min | `INSTALL_SESSIONS_PER_HOUR`, `INSTALL_SECONDS_PER_DAY` |
| Per IP: sessions per hour / audio per 24 h | 30 / 45 min | `ADDRESS_SESSIONS_PER_HOUR`, `ADDRESS_SECONDS_PER_DAY` |
| Spend per UTC day | $3 | `DAILY_NANODOLLARS` |
| Hosted spend in total (judging budget) | the whole remaining allowance | `HOSTED_NANODOLLARS` |
| All-time allowance, local + hosted | $20 (AGENTS.md, fixed in code) | none |

- **Allowance:** the hosted ledger is a copy of the same $20 cap. At first start it records the
  local ledger's committed + pending total plus $1 of headroom for further local dev spend as a
  `prior:` charge (`BORDERLESS_PRIOR_NANODOLLARS`, computed by `aws-relay.zsh` through the `Ledger`
  class). Re-deploying raises it if local spend grew; it never lowers it. Local dev spend beyond
  the $1 headroom between deploys is the one gap: re-deploy after a dev session.
- **Admission is conservative:** a session starts only if today's spend, plus the worst case of
  every session in flight, plus its own worst case fits under each cap. The worst case for one
  session is $0.40 (60 s of ASR plus 8 translations at the ledger's maximum reservation), far above
  the typical $0.02.
- **Install id:** the app may send `install_id` (a random UUID it keeps) in the start message. Old
  clients without it are limited per IP only. The id is client-chosen, so the per-IP and global
  caps are what stop abuse.
- **The release token is public.** It ships inside the app; anyone can extract it. It only keeps
  scanners out. It is separate from the dev token.
- **Kill switch:** `pause` creates `/var/lib/borderless/control/paused`; the relay refuses new paid
  sessions with code `paused` at once. `BORDERLESS_PAUSED=1` in the env does the same.
- **Errors the app can show:** `{"type":"error","code":…,"message":…}` with code `busy`,
  `rate_limited`, `daily_cap`, `budget`, `paused`, `unavailable` (no key yet), `time_limit`,
  `unauthorized` or `ended`. Older apps read only `type`.
- **Logs:** one JSON line per session (outcome code, seconds, active count). No transcript, audio,
  token, IP or install id. Caddy keeps no access log. Counters store HMAC-hashed IP and install
  ids and are deleted after two days. IPv6 clients are counted per /64, IPv4 per address.
- **Health:** `GET /health` returns `{"status":"ok","accepting":bool,"reason":null|"paused"|"unconfigured","active":n,"capacity":3}`.

## Cost of one capture

From the code's rates (ASR $0.18 per hour, settled at the 60 s ceiling; Spark text $1.25/M input,
$4.25/M output) and the 2026-11-02 live run (one guest turn with two replies cost $0.0042 of
translation):

- ASR for one 60 s capture: $0.003.
- Translation: about $0.004 per finished turn; a 60 s capture with about four turns is $0.016.
- Typical 60 s capture: about $0.02. A heavy one (8 translations, long context) is about $0.05.
