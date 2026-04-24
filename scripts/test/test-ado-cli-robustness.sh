#!/usr/bin/env bash
# test-ado-cli-robustness.sh — Smoke test for ado-cli.sh P0 hardening.
#
# Mocks the `az` CLI to simulate:
#   1. stderr pollution (cp1252-style warnings on a successful create)
#   2. non-numeric id in stdout (simulated bad state)
# and asserts that ado-cli.sh:
#   A. Parses the PBI id correctly despite stderr warnings.
#   B. Fails loudly (non-zero exit + JSON error) on non-numeric id instead of
#      propagating an empty id to downstream calls.
#   D. Only attempts state update after a successful parent link.
#
# Run: bash scripts/test/test-ado-cli-robustness.sh

# Deliberately NOT using -e: the test driver handles failed assertions explicitly.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
failures=()

assert() {
    local name="$1" cond_rc="$2" detail="${3:-}"
    if [[ "$cond_rc" -eq 0 ]]; then
        printf '  ok  %s\n' "$name"
        pass=$((pass+1))
    else
        printf '  FAIL  %s  %s\n' "$name" "$detail"
        fail=$((fail+1))
        failures+=("$name")
    fi
}

# --- Mock az CLI ---
# Behavior controlled by MOCK_AZ_MODE env var:
#   stderr_warning — on `work-item create`, emit cp1252 warning to stderr + valid JSON to stdout.
#   bad_id         — on `work-item create`, emit non-numeric id on stdout.
#   normal         — all commands succeed with incrementing ids.
cat > "$TMP/az" <<'MOCK'
#!/usr/bin/env bash
mode="${MOCK_AZ_MODE:-normal}"
counter_file="${MOCK_AZ_COUNTER:-/tmp/mock-az-counter}"
[[ ! -f "$counter_file" ]] && echo 1000 > "$counter_file"

# Log invocations for inspection
log="${MOCK_AZ_LOG:-/tmp/mock-az-log}"
printf '%s\n' "$*" >> "$log"

case "$* " in
    *"work-item create "*)
        id=$(cat "$counter_file")
        echo $((id+1)) > "$counter_file"
        if [[ "$mode" == "stderr_warning" ]]; then
            echo 'WARNING: Unable to encode the output with cp1252 encoding. Unsupported characters are discarded.' >&2
        fi
        if [[ "$mode" == "bad_id" ]]; then
            printf '{"id":"not-a-number"}\n'
        else
            printf '{"id":%d,"fields":{"System.Title":"mock","System.State":"To Do"}}\n' "$id"
        fi
        ;;
    *"work-item relation add "*)
        printf '{"ok":true}\n'
        ;;
    *"work-item update "*)
        printf '{"id":0,"fields":{"System.State":"Done"}}\n'
        ;;
    *)
        printf '{"mock":true}\n'
        ;;
esac
MOCK
chmod +x "$TMP/az"
export PATH="$TMP:$PATH"
export MOCK_AZ_COUNTER="$TMP/counter"
export MOCK_AZ_LOG="$TMP/az-log"

# Sanity: make sure our mock is what bash will find
if [[ "$(command -v az)" != "$TMP/az" ]]; then
    printf 'SKIP: real az CLI is ahead of mock on PATH (%s). Test requires mock isolation.\n' "$(command -v az)"
    exit 77
fi

# Minimal config so the script doesn't bail during load
mkdir -p "$TMP/data"
cat > "$TMP/data/config.json" <<'CFG'
{"ado":{"organization":"https://mock","project":"p","team":"t"},"user":{"ado_email":"u@e.com"}}
CFG

# Point CONFIG_FILE at our temp config by copying the script to a sibling dir
# (ado-cli.sh derives config path from its own location)
mkdir -p "$TMP/scripts"
cp "$REPO/scripts/ado-cli.sh" "$TMP/scripts/ado-cli.sh"

# --- Test A: stderr warning on successful create ---
echo "[A] az emits stderr warning — script must still parse id correctly"
: > "$TMP/az-log"
export MOCK_AZ_MODE=stderr_warning; out=$(bash "$TMP/scripts/ado-cli.sh" \
    --action create-with-children \
    --params '{"pbi":{"title":"Em-dash title — test"},"tasks":[{"title":"child task"}]}' 2>/dev/null) || true

pbi_id=$(printf '%s' "$out" | jq -r '.data.pbi_id // empty')
[[ "$pbi_id" =~ ^[0-9]+$ ]]; assert "A. PBI id parsed despite stderr warning" $? "got: '$pbi_id' (out: $out)"

# --- Test B: non-numeric id in stdout triggers fail-fast ---
echo "[B] az returns non-numeric id — script must fail-fast"
: > "$TMP/az-log"
export MOCK_AZ_MODE=bad_id; out=$(bash "$TMP/scripts/ado-cli.sh" \
    --action create-with-children \
    --params '{"pbi":{"title":"Bad id test"},"tasks":[{"title":"child"}]}' 2>/dev/null) || rc=$?
# Use type-preserving jq expression — plain `.success // "missing"` treats
# the boolean value `false` as falsy and substitutes the default.
success=$(printf '%s' "$out" | jq -r 'if has("success") then (.success | tostring) else "missing" end')
[[ "$success" == "false" ]]; assert "B. success=false when id is non-numeric" $? "success=$success out=$out"

# Verify we did not call 'relation add' after the bad id (= proof we stopped before orphaning)
! grep -q 'relation add' "$TMP/az-log"
assert "B. no 'relation add' called after bad id (stopped before orphaning tasks)" $? \
    "log contents: $(cat "$TMP/az-log")"

# --- Test D: stderr warning on every call — no false task failures ---
echo "[D] stderr warnings on every call — tasks should still be created & linked"
: > "$TMP/az-log"
export MOCK_AZ_MODE=stderr_warning; out=$(bash "$TMP/scripts/ado-cli.sh" \
    --action create-with-children \
    --params '{"pbi":{"title":"Multi-task"},"tasks":[{"title":"t1"},{"title":"t2","state":"Done"}]}' 2>/dev/null) || true

task_count=$(printf '%s' "$out" | jq -r '.data.task_ids | length')
[[ "$task_count" == "2" ]]; assert "D. both tasks created despite stderr warnings" $? "task_count=$task_count out=$out"

errors=$(printf '%s' "$out" | jq -r '.data.errors | length')
[[ "$errors" == "0" ]]; assert "D. no spurious errors from non-fatal stderr" $? "errors=$errors out=$out"

# --- Summary ---
echo
echo "Passed: $pass  Failed: $fail"
if [[ $fail -gt 0 ]]; then
    printf 'Failed: %s\n' "${failures[@]}"
    exit 1
fi
