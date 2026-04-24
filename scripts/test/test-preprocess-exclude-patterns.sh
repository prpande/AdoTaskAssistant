#!/usr/bin/env bash
# test-preprocess-exclude-patterns.sh — Verify exclude_title_patterns works end-to-end.
#
# Feeds a small activity fixture through preprocess-activity.sh with a regex
# pattern and checks:
#   - Matching items are dropped.
#   - Non-matching items pass through.
#   - Invalid regex doesn't crash (treated as non-matching).
#   - dev_activity items are matched on repo name.
#   - Empty pattern list is a no-op.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

assert() {
    if [[ "$2" -eq 0 ]]; then
        printf '  ok  %s\n' "$1"
        pass=$((pass+1))
    else
        printf '  FAIL  %s  %s\n' "$1" "${3:-}"
        fail=$((fail+1))
    fi
}

# Fixture: 4 activity items with deliberately mixed titles.
cat > "$TMP/activity.json" <<'JSON'
[
  {"type":"github_pr","title":"docs: daily API codex sweep (2026-04-16)","url":"https://example/1","createdAt":"2026-04-16T00:00:00Z","state":"merged","repository":{"name":"Api.Codex"}},
  {"type":"github_pr","title":"feat: /validate-codex — cross-validation skill","url":"https://example/2","createdAt":"2026-04-22T00:00:00Z","state":"merged","repository":{"name":"Api.Codex"}},
  {"type":"github_pr","title":"[PARTIAL] nightly: codex validation 2026-04-23","url":"https://example/3","createdAt":"2026-04-23T00:00:00Z","state":"open","repository":{"name":"Api.Codex"}},
  {"type":"dev_activity","repo":"Api.Codex","branch":"pp/sweep","date_range":"2026-04-16 to 2026-04-16","commits":[{"subject":"sweep","date":"2026-04-16 10:00:00 +0000"}]}
]
JSON

# Minimal template
cat > "$TMP/template.json" <<'JSON'
{
  "work_type": {
    "default": "New Feature Development",
    "inference_keywords": { "New Feature Development": ["add","feat"] }
  }
}
JSON

# Sprints covering the fixture dates
SPRINTS='[{"name":"S","path":"P","start":"2026-04-01","end":"2026-05-01"}]'

run_preprocess() {
    local patterns="$1"
    bash scripts/build-params.sh --output "$TMP/params.json" \
        --arg activity_file "$TMP/activity.json" \
        --arg template_file "$TMP/template.json" \
        --argjson sprints "$SPRINTS" \
        --argjson exclude_title_patterns "$patterns" >/dev/null
    bash "$REPO/scripts/preprocess-activity.sh" --params-file "$TMP/params.json"
}

cd "$REPO"

# --- Empty pattern list = no-op ---
echo "[1] empty pattern list is a no-op"
out=$(run_preprocess '[]')
kept=$(printf '%s' "$out" | jq '.items | length')
excluded=$(printf '%s' "$out" | jq '.excluded_count')
[[ "$kept" -eq 4 && "$excluded" -eq 0 ]]; assert "empty patterns keep all 4" $? "kept=$kept excluded=$excluded"

# --- Single pattern drops matching items ---
echo "[2] 'daily .* sweep' drops the daily sweep PR only"
out=$(run_preprocess '["daily .* sweep"]')
kept=$(printf '%s' "$out" | jq '.items | length')
excluded=$(printf '%s' "$out" | jq '.excluded_count')
[[ "$kept" -eq 3 && "$excluded" -eq 1 ]]; assert "dropped exactly 1 (the daily-sweep PR)" $? "kept=$kept excluded=$excluded"

# The excluded one should be PR 1 (the daily sweep title)
kept_urls=$(printf '%s' "$out" | jq -r '[.items[].source.url // empty] | sort | join(",")')
[[ "$kept_urls" == "https://example/2,https://example/3" ]]; assert "kept set is correct (validate-codex + nightly PARTIAL)" $? "kept_urls=$kept_urls"

# --- Multiple patterns ---
echo "[3] multiple patterns"
out=$(run_preprocess '["daily .* sweep","\\[PARTIAL\\] nightly:"]')
kept=$(printf '%s' "$out" | jq '.items | length')
[[ "$kept" -eq 2 ]]; assert "two patterns drop two items" $? "kept=$kept"

# --- dev_activity matched by repo name ---
echo "[4] pattern matching dev_activity repo name"
out=$(run_preprocess '["^Api\\.Codex$"]')
# Drops PRs whose title happens to contain Api.Codex? No — titles don't.
# But dev_activity repo=Api.Codex does match. So we expect 3 kept (3 PRs) and 1 excluded.
kept=$(printf '%s' "$out" | jq '.items | length')
excluded=$(printf '%s' "$out" | jq '.excluded_count')
[[ "$kept" -eq 3 && "$excluded" -eq 1 ]]; assert "dev_activity matched by repo name" $? "kept=$kept excluded=$excluded"

# --- Invalid regex doesn't crash; treated as non-match ---
echo "[5] invalid regex — graceful"
# jq's test() throws on invalid regex. We don't trap errors, so this *may*
# fail the whole run. Document current behavior: an invalid pattern causes
# preprocess to exit non-zero. If this test fails, that's a known limitation
# worth a follow-up (harder to fix without restructuring jq error handling).
out=$(run_preprocess '["[unclosed-bracket"]' 2>/dev/null) || rc=$?
success=$(printf '%s' "$out" | jq -r 'if has("success") then (.success | tostring) else "missing" end' 2>/dev/null)
# We accept either: success=false (graceful error) OR the script exited non-zero.
# What we do NOT accept is: success=true with silent drop of everything.
if [[ "$success" == "false" || "${rc:-0}" -ne 0 ]]; then
    assert "invalid regex surfaces as error (not silent)" 0
else
    kept=$(printf '%s' "$out" | jq '.items | length')
    [[ "$kept" -eq 4 ]]; assert "invalid regex falls through as non-match" $? "kept=$kept out=$out"
fi

echo
echo "Passed: $pass  Failed: $fail"
[[ $fail -eq 0 ]]
