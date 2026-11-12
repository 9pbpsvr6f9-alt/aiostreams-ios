# Repository working rules

- Protect the owner's identity. For commits made on their behalf, both author and
  committer MUST use `9pbpsvr6f9-alt` and
  `289419752+9pbpsvr6f9-alt@users.noreply.github.com`.
- Run `python3 scripts/check-git-privacy.py` before every commit, and
  `python3 scripts/check-git-privacy.py main..HEAD` before every push. Do not print
  or copy an unexpected identity into logs, PRs or messages; correct it locally.
- Configure `git config --local core.hooksPath .githooks` to enable the checks.
- Automation must explicitly use GitHub's no-reply bot author and committer.
- Preserve the owner's existing native subtitle renderer changes.
- Work on feature branches and open PRs. Do not merge into main without a new,
  explicit instruction from the owner.
