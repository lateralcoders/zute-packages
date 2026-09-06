# Can GitHub Pro / Team / Enterprise enforce this gate?

Survey date: 2026-08-30. Sources: [GitHub's plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans), [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches), [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets), [Creating rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository), [github.com/pricing](https://github.com/pricing).

**Short answer:** GitHub can enforce the *process* (no direct push to `main`, required PR, human review, required CI). It cannot natively assert “this hash equals Keeper’s SHASUM256.txt” or “this URL is keepersecurity.com.” That stays in Actions (`verify.yml` job **`verify PKGBUILD gate`**). It cannot stop a laptop from `yay -S` — that is the work-standard collector (C-21), not git.

**Buy GitHub Team on a company org. Do not buy Enterprise for this. Do not use Free org + private repo. Personal Pro works as a fallback but the repo owner can turn the lock off.**

Do not flip live GitHub settings from this file until a human confirms the org, handles, and who is allowed to merge.

---

## What “all of that” means

| Rule | GitHub native? | How it actually holds |
|---|---|---|
| PKGBUILD may wrap only names in `allowlist.txt` | No | Required status check runs `scripts/verify-pkgbuild.sh` |
| `source=` host is `keepersecurity.com` | No | Same check |
| `sha256sums` equals vendor `SHASUM256.txt` | No | Same check (curl of https://keepersecurity.com/desktop_electron/SHASUM256.txt) |
| Allowlist does not grow without a human PR | Process only | Required reviews + CODEOWNERS on `allowlist.txt`; bot must not merge |
| Bot opens bump PRs, never merges | Yes, if configured | Required 1 review from someone other than last pusher; bot **not** on bypass list; auto-merge **off** |
| No force-push / no deleting `main` | Yes | Branch protection or ruleset |
| No AUR / no `yay` / no `omarchy pkg aur add` | **No** | Laptop collector. GitHub never sees that. |

GitHub Free (personal or org) on a **private** repo does **not** give you required reviewers or enforced rulesets. A Free org can *create* rulesets that then show: *“won't be enforced on this private repository until you upgrade this organization account to GitHub Team.”* ([community #184363](https://github.com/orgs/community/discussions/184363))

---

## Plan vs plan (private repo)

List prices from [github.com/pricing](https://github.com/pricing) as of 2026-08 (Team and Enterprise quoted “for the first 12 months”). Recheck before buying.

| | **Free org, private repo** | **GitHub Pro (personal)** | **GitHub Team (org)** | **GitHub Enterprise Cloud** |
|---|---|---|---|---|
| Typical cost | $0 | $4 / month, personal account | $4 / user / month | From $21 / user / month |
| Account shape | Company org, weak locks | One engineer’s account | **Company org** | Company enterprise |
| Protected branches + required PR reviews | Public only | Yes | Yes | Yes |
| Required status checks | Public only | Yes | Yes | Yes |
| CODEOWNERS required reviews | Public only | Yes (`@user`) | Yes (`@org/team`) | Yes |
| Rulesets **enforced** on private repos | No | Yes (repo-level) | Yes (repo + **org-wide**) | Yes (repo + org + enterprise) |
| Org-wide ruleset (repo admin cannot edit) | — | No (no org) | **Yes** | Yes |
| Restrict who can push to `main` | Org Team+ | **No** (personal repos) | Yes | Yes |
| “Do not allow bypassing” / empty bypass list | — | Stops *merge* bypass; owner can still **delete the rule** | Org ruleset survives repo admins | Enterprise ruleset survives org owners |
| Team reviewers / scheduled reminders | — | No | Yes | Yes |
| SAML SSO, SCIM, audit log stream, IP allow list | No | No | No | Yes |
| Required org workflows / ruleset “require workflows” | No | No | Limited / not the reason to buy | Yes (Enterprise Cloud docs) |
| Actions minutes (private) | 2,000 | 3,000 | 3,000 | 50,000 |
| Enough for *this* gate? | **No** | Fallback | **Yes — buy this** | Overkill |

**GitHub Pro is not an organization plan.** It unlocks branch protection on *personal* private repos. There are no org teams, no org-owned rulesets, and “restrict who can push” is documented as org Team / Enterprise Cloud only.

**Enterprise does not make the hash check stronger.** SAML, audit-log streaming, and IP allow lists are identity/compliance features. They do not read PKGBUILDs. For two Omarchy laptops and a Keeper wrapper, they are not the control.

---

## Recommended buy

For this company (small marketing org, two named AI engineers, outsourced IT, insurance file):

1. Create a **GitHub organization owned by the company** (not an engineer’s personal namespace).
2. Upgrade that org to **GitHub Team**. Seats: the two engineers, plus whoever is allowed to approve (CTO / vCIO / outsourced IT — only if they will actually click Approve).
3. Repo `company-arch-packages`. The PKGBUILD is not secret. **Make the repo public** so `pacman` can anonymous-GET `…/releases/latest/download` (private Releases 404 with no GitHub token, and pacman does not send one). Required reviews still gate merges on a public repo. Keep the *process* locked; do not hide the binary repo.
4. Skip Enterprise unless the company already has it for SAML, or the broker literally requires SSO on the git host.

Personal Pro is acceptable only as a stopgap: one engineer owns the repo, the other is a collaborator, branch protection is on. Document in the exception pack that the owner can disable protection. That is a weaker insurance story than an org ruleset.

---

## Exact GitHub settings (Team org)

Apply after the first CI run on a PR so the check name exists in the picker.

### 1. Repository

- Visibility: **Public** (pacman GETs release assets anonymously; private Releases 404)
- Default branch: `main`
- Collaborators: two engineers = **Write**. Do **not** make the bump bot an admin.
- Auto-merge: **disabled**
- Allow merge commits or squash; either is fine. Do not need linear history for this.

### 2. Actions

- Actions enabled.
- Workflow permissions: **Read repository contents and packages permissions** as the default. The propose workflow already requests `contents: write` and `pull-requests: write` for itself. `publish.yml` requests `contents: write` so it can create the GitHub Release. Do not grant org-wide write.
- Repo secret **`GPG_SECRET_KEY`**: armored private key from `scripts/export-ci-secret.sh --set`. Optional **`GPG_PASSPHRASE`**. Never put these on `pull_request`.
- Do **not** add `github-actions[bot]` (or a bot PAT) to a ruleset bypass list.
- Do **not** give the propose workflow `contents: write` on `main`. It pushes a *feature* branch and opens a PR. Required reviews block merge.
- `publish.yml` runs on `main` / `workflow_dispatch` only. A version-bump PR merge is what publishes `v<pkgver>`. Do not add `pull_request` to that workflow.

### 3. Branch protection **or** (better) a ruleset

Prefer a **ruleset** named `pkgbuild-gate` targeting `main` (and `master` if it exists).

Enforcement: **Active**. Bypass list: **empty**. Do not tick “repository admins” as bypass actors.

Rules:

- Block force pushes
- Block deletions
- Require a pull request before merging
- Required approvals: **1**
- Require approval of the most recent reviewable push (someone other than the last pusher) — this is how a bot PR still needs a human
- Dismiss stale reviews when new commits are pushed
- Require review from Code Owners
- Require status checks to pass, and require the branch to be up to date
- Required check name: **`verify PKGBUILD gate`**  
  (workflow `.github/workflows/verify.yml`, job id `verify-pkgbuild-gate`, job `name:` `verify PKGBUILD gate`. After the first PR, pick the name GitHub shows in the merge box if it differs slightly.)
- Restrict who can push / create the matching branch: the two humans only. **Not** `github-actions[bot]`. The bot still pushes *other* branches.

On GitHub Team, put this ruleset on the **organization** targeting this repository (or a custom property). Then a repo admin cannot delete the lock. Repo-level protection on a personal Pro repo can always be turned off by the owner — that is the two-person hole.

Classic branch protection equivalent if you refuse rulesets:

- Settings → Branches → add rule `main`
- Require a pull request before merging
- Require approvals: 1
- Dismiss stale reviews
- Require review from Code Owners
- Require approval of the most recent reviewable push
- Require status checks: `verify PKGBUILD gate` (strict)
- Do not allow bypassing the above settings
- Do not allow force pushes
- Do not allow deletions

“Restrict who can push” will be missing on a personal Pro repo.

### 4. CODEOWNERS

Copy `CODEOWNERS.example` to `CODEOWNERS` at the repo root. Replace the `@REPLACE-…` handles. On Team, a `@org/linux-packagers` team is cleaner than two usernames.

### 5. What the bot is allowed to do

`.github/workflows/propose-update.yml` already:

- Runs on a daily cron + `workflow_dispatch`
- Rewrites only `packages/keeper-password-manager/PKGBUILD` `pkgver` / `sha256sums` from the vendor file
- Opens a PR whose body says the human must merge

It must **not**:

- Edit `allowlist.txt`
- Add `packages/*`
- Merge
- Use a PAT with `admin:org` or repo **admin**

If a future “AI agent” opens PRs, treat it like this bot: **write to a branch, never merge, never expand the allowlist.**

---

## What still fails even on Enterprise

These are out of GitHub’s reach. Do not tell the broker that “GitHub Enterprise means no AUR.”

1. **Laptop install path.** `pacman -S` from the signed `[company]` GitHub Release is policy. `yay -S keeper-password-manager` from the public AUR is still a C-21 FAIL on the collector. GitHub never sees that.
2. **Hash/URL truth.** GitHub required checks only *require that a named job is green*. If someone deletes `verify.yml` in the same PR, the check never runs unless you also protect `.github/` (CODEOWNERS + required owners) **and** refuse to merge a PR that removes the workflow. Org-required workflows (Enterprise) are the only GitHub-native “you cannot delete this check.” On Team, CODEOWNERS on `.github/` plus a human who will not approve ripping it out is the control.
3. **Self-approval.** One engineer with admin who is also the only reviewer can still approve their own work unless you require “approval of the most recent reviewable push” *and* a second person has Write. Two-person shop: the second engineer (or CTO) must be the approver on every bump. If only one person will ever click Merge, GitHub cannot invent a second human.
4. **Settings rollback.** On Pro, the repo owner disables protection in thirty seconds. On Team, an org owner can still edit the org ruleset. Log that. Enterprise audit log streaming is how you *notice* it after the fact, not how you prevent it.
5. **Push rulesets** (file size / path / extension). Documented as Team in some pages and Enterprise Cloud in others. Irrelevant here: we want PKGBUILD edits, not to ban them.

---

## Insurance wording (use this, not “we have MDM on git”)

Safe:

> Vendor Linux packages that Arch does not ship are wrapped in a company git. Merges to the default branch require a pull request, one human approval from someone other than the last pusher, and a passing GitHub Actions check that the PKGBUILD URL is on keepersecurity.com and the SHA-256 equals Keeper’s published SHASUM256.txt. Merge to main publishes a GPG-signed pacman repo as a GitHub Release; laptops install with pacman -S from that HTTPS prefix. The automation that detects new versions may open pull requests only. It cannot merge, cannot add packages, and cannot publish from a pull request. Public AUR is not the update channel.

Not safe:

> GitHub Enterprise enforces that we never install untrusted packages.  
> We are AUR-equivalent but private.  
> Required reviewers mean two-person integrity even if both engineers are admins and one of them turns the rule off.

---

## Checklist before first production merge

- [ ] Company GitHub **Team** org exists; repo is **public** under that org (anonymous pacman GET)
- [ ] Two humans have Write; nobody’s personal token is admin on the repo except org owners
- [ ] `CODEOWNERS` committed with real handles
- [ ] Ruleset or branch protection on `main` as above; bypass list empty
- [ ] First PR has run; required check is exactly the name GitHub shows for **`verify PKGBUILD gate`**
- [ ] Auto-merge off
- [ ] Propose workflow has opened a dry-run PR (or `workflow_dispatch`) and a human merged it
- [ ] `GPG_SECRET_KEY` set; `keys/company-arch-packages.asc` and `keys/fingerprint.txt` committed
- [ ] Repo is **public** (or otherwise anonymously GET-able); first `publish.yml` run created Release `v<keeper pkgver>`
- [ ] Laptops `enable-repo.sh` + `pacman -S keeper-password-manager` from GitHub Releases, not AUR, not `makepkg -si` from a laptop
- [ ] Work-standard collector still FAILs `keeper-password-manager` from AUR / `pacman -Qm` foreign names not on the company allowlist
