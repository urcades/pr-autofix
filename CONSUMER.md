# Consumer Setup Guide

How to add PR Autofix to any repository.

## 1. Add the workflow

Create `.github/workflows/autofix.yml` in your repo:

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
    # Only run on PR-related events from bot accounts
    if: >
      (github.event.issue.pull_request || github.event.pull_request) &&
      contains(fromJSON('["bot", "Bot"]'), github.event.comment.user.type || github.event.review.user.type || '')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
    steps:
      - uses: YOUR_USERNAME/pr-autofix@main
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

## 2. Add the secret

Go to **Settings > Secrets and variables > Actions** and add:

- `ANTHROPIC_API_KEY` — your Anthropic API key

`GITHUB_TOKEN` is provided automatically by GitHub Actions.

## 3. (Optional) Per-repo config

Create `.autofix.yml` in the repo root:

```yaml
# Which bot usernames can trigger autofix
allowed_bots:
  - sonarcloud[bot]
  - codacy[bot]
  - devin-ai[bot]
  - eslint[bot]

# Max autofix iterations per PR (default: 5)
max_iterations: 3

# PRs with these labels skip autofix (not yet implemented)
skip_labels:
  - no-autofix
  - manual-review
```

## Event types explained

| Trigger | When it fires | Example |
|---------|---------------|---------|
| `issue_comment` | Bot leaves a top-level PR comment | SonarCloud summary |
| `pull_request_review` | Bot submits a review (approve/request changes) | Codacy review |
| `pull_request_review_comment` | Bot leaves an inline code comment | ESLint annotation |

## The `if` guard

The `if` condition on the job filters to:
1. **PR-related events only** — `issue_comment` fires on issues too, so we check for `github.event.issue.pull_request`
2. **Bot authors** — GitHub marks bot accounts with `user.type: "Bot"`, preventing human comments from triggering autofix

You can adjust the `if` guard to match your needs. For example, to also allow specific human reviewers:

```yaml
if: >
  (github.event.issue.pull_request || github.event.pull_request) &&
  (
    contains(fromJSON('["bot", "Bot"]'), github.event.comment.user.type || github.event.review.user.type || '') ||
    contains(fromJSON('["your-username"]'), github.event.comment.user.login || github.event.review.user.login || '')
  )
```

## Common bot configurations

### SonarCloud
```yaml
allowed_bots:
  - sonarcloud[bot]
```

### Codacy
```yaml
allowed_bots:
  - codacy-production[bot]
```

### ESLint (via reviewdog or similar)
```yaml
allowed_bots:
  - github-actions[bot]
```

### Devin
```yaml
allowed_bots:
  - devin-ai[bot]
```

### Multiple bots
```yaml
allowed_bots:
  - sonarcloud[bot]
  - codacy-production[bot]
  - github-actions[bot]
```
