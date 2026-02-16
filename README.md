# PR Autofix

A GitHub Action that automatically fixes PR review comments using Claude Code. When a bot (linter, security scanner, CI tool) leaves a comment on a PR, this action reads the comment, fixes the code, and pushes to the same branch. The cycle repeats until the PR is clean, then a human reviews what's left.

## Quick start

1. **Add the secret** — In your repo, go to Settings > Secrets > Actions and add `ANTHROPIC_API_KEY`

2. **Add the workflow** — Create `.github/workflows/autofix.yml`:

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
      - uses: YOUR_USERNAME/pr-autofix@main
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

3. **Done** — Bot comments on PRs now trigger automatic fixes.

See [CONSUMER.md](CONSUMER.md) for detailed setup, per-repo config, and examples.

## How it works

```
Bot comments on PR
        │
        ▼
  Guard checks pass?  ──no──▶  Skip
        │
       yes
        │
        ▼
  Claude Code reads
  comment + context
        │
        ▼
  Makes targeted fix
        │
        ▼
  Commits + pushes
        │
        ▼
  Bot re-runs CI...
  (cycle continues)
```

## Loop prevention

Three layers prevent runaway loops:

1. **Iteration counting** — Each autofix commit is tagged `[N/M]`. The action parses recent commit messages and stops when the limit is reached (default: 5).

2. **Bot allowlist** — Only comments from opted-in bot usernames (or comments matching lint patterns) trigger fixes. Human comments and unknown bots are ignored.

3. **Natural termination** — If the fix resolves the issue, the bot doesn't comment again, so the action doesn't trigger.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | Yes | — | Anthropic API key |
| `github_token` | Yes | — | GitHub token with repo write access |
| `max_iterations` | No | `5` | Max autofix attempts per PR |
| `allowed_bots` | No | `""` | Comma-separated bot usernames |
| `config_file` | No | `.autofix.yml` | Path to per-repo config |

## Considerations

- **Cost** — Each invocation uses Anthropic API credits. Lint fixes are cheap; complex security findings may need more reasoning.
- **Model** — Claude Code defaults to Sonnet, which is well-suited for targeted code fixes. Model selection could be made configurable in a future version.
- **Concurrency** — The workflow uses a concurrency group per PR to prevent parallel pushes to the same branch.
