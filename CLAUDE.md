# PR Autofix — Agent Guide

This repo is a GitHub Action that auto-fixes bot review comments on PRs using Claude Code. When a user asks you to "set up autofix" or "add pr-autofix" to a project, follow the steps below.

## Setting up autofix in a target repo

### 1. Create the workflow file

Write `.github/workflows/autofix.yml` in the target repo. Replace `urcades` with the correct GitHub owner if the action is forked:

```yaml
name: PR Autofix

on:
  issue_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
    types: [created]

concurrency:
  group: autofix-${{ github.event.issue.number || github.event.pull_request.number }}
  cancel-in-progress: false

jobs:
  autofix:
    if: >
      (github.event.issue.pull_request || github.event.pull_request) &&
      contains(fromJSON('["bot", "Bot"]'), github.event.comment.user.type || github.event.review.user.type || '')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
    steps:
      - uses: urcades/pr-autofix@main
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Remind the user to add `ANTHROPIC_API_KEY`

The user must add their Anthropic API key as a repo secret at **Settings > Secrets and variables > Actions**. `GITHUB_TOKEN` is automatic.

### 3. (Optional) Add per-repo config

If the user wants to restrict which bots trigger fixes or adjust limits, create `.autofix.yml` in the target repo root:

```yaml
allowed_bots:
  - sonarcloud[bot]
  - codacy-production[bot]
  - github-actions[bot]

max_iterations: 3
```

Ask the user which bots they use if they don't specify. Common ones: `sonarcloud[bot]`, `codacy-production[bot]`, `github-actions[bot]`, `devin-ai[bot]`.

## How this repo works (for maintenance)

```
action.yml              Composite action entry point — orchestrates all steps
scripts/parse-event.sh  Parses the GitHub event JSON, checks allowlist + iteration limit
scripts/run-fix.sh      Builds a prompt from the comment and pipes it to Claude Code
```

- `parse-event.sh` is **sourced** (not executed) by `action.yml`. It sets shell variables (`should_fix`, `comment_body`, `comment_path`, `comment_line`, `iteration`, `pr_diff`) that the action reads as step outputs.
- `run-fix.sh` is executed as a standalone script. It builds a structured prompt and pipes it to `claude --print --dangerously-skip-permissions`.

### Key gotchas when editing

- `parse-event.sh` uses `return 0 2>/dev/null || exit 0` for early exits because it's sourced — a bare `exit` would kill the parent shell.
- The variable for file path is `FILE_PATH_VAL`, not `PATH_VAL`, to avoid shadowing `$PATH`.
- Iteration counting greps for `\[autofix` in the last 20 commit messages. The commit message format `autofix: address review comment [N/M]` must stay consistent or the counter breaks.
- The concurrency group is keyed on PR number. `issue_comment` events use `github.event.issue.number`, others use `github.event.pull_request.number`.

### Loop prevention

Three layers prevent runaway autofix loops:

1. **Iteration cap** — commit messages tagged `[N/M]`, parsed on each trigger
2. **Bot allowlist** — only opted-in bots (or lint-pattern comments) trigger fixes
3. **Natural termination** — a successful fix means the bot doesn't comment again

### Testing changes

After editing scripts, run `bash -n scripts/parse-event.sh && bash -n scripts/run-fix.sh` to catch syntax errors. For end-to-end testing, open a PR on a test repo with the consumer workflow and trigger a bot comment.
