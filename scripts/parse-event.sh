#!/usr/bin/env bash
# parse-event.sh — Extract and validate comment from GitHub event payload
# Sourced by action.yml; sets variables for downstream steps.
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────
should_fix="false"
comment_body=""
comment_path=""
comment_line=""
iteration=0
pr_diff=""

# ── Parse event payload ──────────────────────────────────────────────
EVENT=$(cat "$EVENT_PATH")

# Detect event shape: pull_request_review uses .review, others use .comment
if echo "$EVENT" | jq -e '.review' > /dev/null 2>&1; then
  # pull_request_review event
  AUTHOR=$(echo "$EVENT" | jq -r '.review.user.login // empty')
  comment_body=$(echo "$EVENT" | jq -r '.review.body // empty')
  # Reviews don't have file/line — they're top-level
  comment_path=""
  comment_line=""
elif echo "$EVENT" | jq -e '.comment' > /dev/null 2>&1; then
  # issue_comment or pull_request_review_comment
  AUTHOR=$(echo "$EVENT" | jq -r '.comment.user.login // empty')
  comment_body=$(echo "$EVENT" | jq -r '.comment.body // empty')
  # Inline comment fields (present on pull_request_review_comment, absent on issue_comment)
  FILE_PATH_VAL=$(echo "$EVENT" | jq -r '.comment.path // empty')
  comment_path="${FILE_PATH_VAL}"
  comment_line=$(echo "$EVENT" | jq -r '.comment.line // .comment.original_line // empty')
else
  echo "::warning::Unrecognized event shape — no .review or .comment found"
  return 0 2>/dev/null || exit 0
fi

# Skip empty comments
if [ -z "$comment_body" ]; then
  echo "::notice::Empty comment body, skipping"
  return 0 2>/dev/null || exit 0
fi

# ── Load per-repo config ─────────────────────────────────────────────
REPO_ALLOWED_BOTS=""
REPO_MAX_ITERATIONS=""

if [ -f "$CONFIG_FILE" ]; then
  echo "::notice::Loading config from $CONFIG_FILE"
  if command -v yq &> /dev/null; then
    REPO_ALLOWED_BOTS=$(yq -r '.allowed_bots // [] | join(",")' "$CONFIG_FILE" 2>/dev/null || echo "")
    REPO_MAX_ITERATIONS=$(yq -r '.max_iterations // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  else
    # Fallback: grep-based parsing
    REPO_ALLOWED_BOTS=$(grep -A 20 '^allowed_bots:' "$CONFIG_FILE" 2>/dev/null \
      | grep '^\s*-' \
      | sed 's/^\s*-\s*//' \
      | tr '\n' ',' \
      | sed 's/,$//' || echo "")
    REPO_MAX_ITERATIONS=$(grep '^max_iterations:' "$CONFIG_FILE" 2>/dev/null \
      | head -1 \
      | awk '{print $2}' || echo "")
  fi
fi

# Merge config: action input takes precedence, repo config fills in gaps
if [ -n "$REPO_ALLOWED_BOTS" ] && [ -z "$ALLOWED_BOTS" ]; then
  ALLOWED_BOTS="$REPO_ALLOWED_BOTS"
elif [ -n "$REPO_ALLOWED_BOTS" ] && [ -n "$ALLOWED_BOTS" ]; then
  ALLOWED_BOTS="$ALLOWED_BOTS,$REPO_ALLOWED_BOTS"
fi

if [ -n "$REPO_MAX_ITERATIONS" ] && [ "$MAX_ITERATIONS" = "5" ]; then
  MAX_ITERATIONS="$REPO_MAX_ITERATIONS"
fi

# ── Bot allowlist check ──────────────────────────────────────────────
is_allowed="false"

# Always allow lint-pattern comments (common CI bot output patterns)
if echo "$comment_body" | grep -qiE '(eslint|prettier|flake8|pylint|rubocop|stylelint|shellcheck|warning:|error:|⚠|❌|\[lint\]|\[style\])'; then
  is_allowed="true"
  echo "::notice::Comment matches lint pattern — allowed regardless of bot list"
fi

# Check explicit allowlist
if [ "$is_allowed" = "false" ] && [ -n "$ALLOWED_BOTS" ]; then
  IFS=',' read -ra BOT_LIST <<< "$ALLOWED_BOTS"
  for bot in "${BOT_LIST[@]}"; do
    bot=$(echo "$bot" | xargs) # trim whitespace
    if [ "$AUTHOR" = "$bot" ]; then
      is_allowed="true"
      echo "::notice::Author '$AUTHOR' is in the allowed bot list"
      break
    fi
  done
fi

# If allowlist is empty (no bots configured), allow all
if [ "$is_allowed" = "false" ] && [ -z "$ALLOWED_BOTS" ]; then
  is_allowed="true"
  echo "::notice::No bot allowlist configured — allowing all authors"
fi

if [ "$is_allowed" = "false" ]; then
  echo "::notice::Author '$AUTHOR' is not in the allowed bot list, skipping"
  return 0 2>/dev/null || exit 0
fi

# ── Iteration counting ───────────────────────────────────────────────
iteration=$(git log --oneline -20 2>/dev/null | grep -c '\[autofix' || echo "0")
iteration=$((iteration + 1))

if [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
  echo "::warning::Iteration limit reached ($iteration > $MAX_ITERATIONS), skipping"
  return 0 2>/dev/null || exit 0
fi

echo "::notice::Autofix iteration $iteration / $MAX_ITERATIONS"

# ── Fetch PR diff for context ────────────────────────────────────────
if [ -n "${PR_NUMBER:-}" ]; then
  pr_diff=$(gh pr diff "$PR_NUMBER" 2>/dev/null || echo "")
else
  pr_diff=""
fi

# ── Result ────────────────────────────────────────────────────────────
should_fix="true"
echo "::notice::Proceeding with fix — author=$AUTHOR, file=$comment_path, line=$comment_line"
