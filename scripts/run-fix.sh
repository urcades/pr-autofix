#!/usr/bin/env bash
# run-fix.sh — Build prompt and invoke Claude Code to fix a review comment
set -euo pipefail

# ── Build the prompt ─────────────────────────────────────────────────
PROMPT="You are fixing a code review comment on a pull request. Make minimal, targeted changes to address the comment.

## Review Comment
${COMMENT_BODY}
"

if [ -n "${COMMENT_PATH:-}" ]; then
  PROMPT+="
## Location
File: ${COMMENT_PATH}"
  if [ -n "${COMMENT_LINE:-}" ]; then
    PROMPT+="
Line: ${COMMENT_LINE}"
  fi
fi

if [ -n "${PR_DIFF:-}" ]; then
  PROMPT+="

## PR Diff (for context)
\`\`\`diff
${PR_DIFF}
\`\`\`"
fi

PROMPT+="

## Instructions
- Read the relevant file(s) and understand the context
- Make the minimum change needed to address the review comment
- Do not refactor unrelated code
- Do not add comments explaining the fix unless the review asked for comments
- If the comment is unclear or you cannot determine a fix, make no changes"

# ── Invoke Claude Code ───────────────────────────────────────────────
echo "::group::Claude Code output"
echo "$PROMPT" | claude --print --dangerously-skip-permissions || true
echo "::endgroup::"
