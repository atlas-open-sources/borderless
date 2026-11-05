#!/bin/zsh
# Keeps the even-companion pin equal in every manifest and checks the SHA is on the remote.
#   scripts/even-companion-pin.sh --check
#   scripts/even-companion-pin.sh --set <sha>   (push the kit first)
set -euo pipefail

root=${0:A:h:h}
files=(
  "$root/native/BorderlessKit/Package.swift"
  "$root/native/BorderlessG2/Package.swift"
  "$root/native/MetaDATAdapter/Package.swift"
  "$root/native/BorderlessApp/project.yml"
)
remote=https://github.com/local-ai-cat/even-companion.git

current_pins() {
  grep -hoE '[0-9a-f]{40}' "${files[@]}" | sort -u
}

case ${1:-} in
  --check)
    pins=($(current_pins))
    if (( ${#pins} != 1 )); then
      print -u2 "pin mismatch: ${pins[*]}"
      exit 1
    fi
    if ! git ls-remote "$remote" | grep -q "^${pins[1]}"; then
      # ls-remote lists only ref tips; fall back to fetching the commit.
      scratch=$(mktemp -d "$root/.pin-check.XXXXXX")
      trap 'rm -rf -- "${scratch:?}"' EXIT
      git -C "$scratch" init -q
      git -C "$scratch" fetch -q --depth 1 "$remote" "${pins[1]}" || { print -u2 "pin ${pins[1]} not on $remote"; exit 1 }
    fi
    print "ok ${pins[1]}"
    ;;
  --set)
    new=${2:?usage: --set <sha>}
    [[ $new =~ ^[0-9a-f]{40}$ ]] || { print -u2 "need a full 40-char sha"; exit 1 }
    old=$(current_pins | head -1)
    sed -i '' "s/$old/$new/g" "${files[@]}"
    print "pinned $new (was $old); regenerate the Xcode project with xcodegen"
    ;;
  *)
    print -u2 "usage: $0 --check | --set <sha>"
    exit 2
    ;;
esac
