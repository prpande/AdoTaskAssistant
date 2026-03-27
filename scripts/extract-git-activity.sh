#!/usr/bin/env bash
# extract-git-activity.sh — Extract git commits across repos for a date range
#
# Usage:
#   bash scripts/extract-git-activity.sh --from <YYYY-MM-DD> --to <YYYY-MM-DD> [--repos '<json-array>'] [--auto-detect <parent-dir>]
#
# Examples:
#   bash scripts/extract-git-activity.sh --from 2026-03-26 --to 2026-03-27 --repos '["C:/src/Repo1","C:/src/Repo2"]'
#   bash scripts/extract-git-activity.sh --from 2026-03-26 --to 2026-03-27 --auto-detect "C:/src"

set -o pipefail

# --- Helpers ---

json_ok() {
    jq -n --argjson data "$1" '{"success":true,"data":$data}'
}

json_error() {
    jq -n --arg msg "$1" '{"success":false,"error":$msg}'
}

# --- Parse arguments ---

FROM_DATE=""
TO_DATE=""
REPOS="[]"
AUTO_DETECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_DATE="$2"; shift 2 ;;
        --to) TO_DATE="$2"; shift 2 ;;
        --repos) REPOS="$2"; shift 2 ;;
        --auto-detect) AUTO_DETECT="$2"; shift 2 ;;
        *) json_error "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
    json_error "Missing required arguments: --from and --to (YYYY-MM-DD)"
    exit 1
fi

# --- Auto-detect repos if needed ---

repo_list=()

if [[ -n "$AUTO_DETECT" ]]; then
    if [[ ! -d "$AUTO_DETECT" ]]; then
        json_error "Auto-detect directory does not exist: $AUTO_DETECT"
        exit 1
    fi
    while IFS= read -r dir; do
        if [[ -d "$dir/.git" ]]; then
            repo_list+=("$dir")
        fi
    done < <(find "$AUTO_DETECT" -maxdepth 1 -type d 2>/dev/null)
fi

# Add explicitly listed repos
while IFS= read -r repo; do
    repo_list+=("$repo")
done < <(echo "$REPOS" | jq -r '.[]')

if [[ ${#repo_list[@]} -eq 0 ]]; then
    json_error "No repos found. Provide --repos or --auto-detect."
    exit 1
fi

# --- Get current git user ---

GIT_USER_NAME=$(git config user.name 2>/dev/null || echo "")
GIT_USER_EMAIL=$(git config user.email 2>/dev/null || echo "")

# --- Extract commits ---

all_commits="[]"

for repo in "${repo_list[@]}"; do
    if [[ ! -d "$repo/.git" ]]; then
        continue
    fi

    repo_name=$(basename "$repo")

    # Get commits by the current user in the date range
    commits_json=$(git -C "$repo" log \
        --after="$FROM_DATE" \
        --before="$TO_DATE" \
        --author="$GIT_USER_EMAIL" \
        --format='{"hash":"%H","short_hash":"%h","subject":"%s","date":"%ai","author":"%an"}' \
        2>/dev/null | jq -s --arg repo "$repo_name" --arg repo_path "$repo" '[.[] | . + {"repo": $repo, "repo_path": $repo_path}]')

    if [[ -n "$commits_json" && "$commits_json" != "[]" ]]; then
        all_commits=$(echo "$all_commits" "$commits_json" | jq -s '.[0] + .[1]')
    fi
done

# --- Build summary ---

summary=$(echo "$all_commits" | jq '{
    total_commits: length,
    repos: (group_by(.repo) | map({
        repo: .[0].repo,
        commit_count: length,
        commits: [.[] | {hash: .short_hash, subject: .subject, date: .date}]
    })),
    date_range: {from: "'"$FROM_DATE"'", to: "'"$TO_DATE"'"}
}')

json_ok "$summary"
