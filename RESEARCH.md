# Existing tools — do not rebuild AUR

Survey date: 2026-08-30. Goal: company git that gates vendor `.deb` updates (Keeper first) for two Omarchy laptops.

## Verdict

Nothing is a drop-in “private AUR for two PCs” that you just deploy.

**Closest already-built pieces:**

1. **Omarchy’s own package factory** — [omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs)  
   Vendor packages use `.omarchy/package.json` `upstream` (GitHub tag + checksums asset) or `.omarchy/upstream.sh`. Workflows `sync-upstream.yml` / `sync-aur.yml` open PRs. Edge AUR sync requires review.  
   **Do not fork the whole repo.** It is a distro: stable/edge/rc, rclone to pkgs.omarchy.org, GPG, aarch64, systemd on their builders. You would inherit their operational load. **Steal the upstream+checksums+PR pattern.**

2. **nvchecker** — [lilydjwg/nvchecker](https://github.com/lilydjwg/nvchecker), Arch package `nvchecker`, wired into official `pkgctl version`.  
   This is the standard “is there a new version?” tool. Chaotic-AUR uses it with `CI_NVCHECKER_REVIEW=true` to **open PRs instead of auto-push**.

3. **aurutils** — [aurutils/aurutils](https://github.com/aurutils/aurutils)  
   Local `file://` pacman repo + `aur-build`. Philosophy: never `pacman -U` foreign packages; put them in a repo you control. Optional git hosting of the *built* repo ([docs](https://thedocumentation.org/aurutils/reference/aurhosting/)).  
   **Use later** if you want `pacman -S keeper-password-manager`. Still needs *your* PKGBUILDs, not AUR RPC.

**Do not deploy:** public AUR, Chaotic-AUR (Omarchy dropped it), a self-hosted aurweb, Renovate-as-PKGBUILD-manager (not released).

---

## Inventory

### Version bump / PRs

| Name | URL | License | Fits? |
|---|---|---|---|
| nvchecker | https://github.com/lilydjwg/nvchecker | MIT | **Yes.** HTTP/regex on Keeper SHASUM256.txt. |
| pkgctl version | Arch `devtools` | GPL | Yes if you already use pkgctl; wraps nvchecker. |
| Chaotic PKGBUILDs CI | https://gitlab.com/chaotic-aur/pkgbuilds | (their tree) | Pattern only: `CI_NVCHECKER_REVIEW` → human PR. Do not consume chaotic binaries. |
| arch4edu aur-auto-update | https://github.com/arch4edu/aur-auto-update | | **No.** Pushes to *public* AUR when build succeeds. Opposite of a gate. |
| Renovate regex manager | https://docs.renovatebot.com/user-stories/maintaining-aur-packages-with-renovate/ | AGPL | Maybe later. Native PKGBUILD manager is still an open issue ([#16923](https://github.com/renovatebot/renovate/issues/16923)). Regex manager needs a comment on `pkgver=`. Keeper is not GitHub tags. |
| osam-cologne nvchecker PRs | https://github.com/osam-cologne/archlinux-proaudio | | Same pattern, Matrix notify + PRs. |

### Build + private repo

| Name | URL | Fits? |
|---|---|---|
| makepkg | Arch | **Yes** for two hosts. |
| aurutils local repo | https://github.com/aurutils/aurutils | Yes if you want pacman -Syu from `file://`. |
| Gitea Arch package registry | https://docs.gitea.com/usage/packages/arch/ | Only if you already run Gitea. Overkill to install Gitea for this. |
| GitHub raw + repo-add | https://disconnected.systems/blog/archlinux-repo-in-a-git-repo | Works; binaries in git is ugly. GitHub Releases is cleaner. |
| Slinet6056/archpkg-build | GitHub Action: arch container + optional repo-add | Optional CI. Uses pikaur (AUR helper) — **do not** let it pull AUR. |
| heyhusen/archlinux-package-action | namcap, updpkgsums, makepkg | Fine for CI verify. |
| omarchy-pkgs `bin/repo` | https://github.com/omacom-io/omarchy-pkgs | Distro factory. Do not run as a two-laptop product. |

### “Just install Keeper and let it update”

| Path | Auto-update | Trust | Notes |
|---|---|---|---|
| AUR `keeper-password-manager` | When a volunteer bumps | PKGBUILD is untrusted | Maintainer `malina`. Deb URL is official; recipe is not. Checksums have broken when Keeper hotfixed. |
| Vendor `.deb` / `.rpm` | **No** (Keeper Linux desktop: Auto-Updates No) | Vendor | Manual. |
| Snap `keepersecurity` | Yes | Snap store + `snapd` | `snapd` is AUR on Arch. Extra daemon. Omarchy is not a Snap distro. |
| Web vault | n/a | Keeper | **No SSH agent.** Cannot satisfy C-37. |

---

## Keeper facts (pin these)

- Checksums: https://keepersecurity.com/desktop_electron/SHASUM256.txt
- Deb pattern: `https://keepersecurity.com/desktop_electron/Linux/repo/deb/keeperpasswordmanager_${pkgver}_amd64.deb`
- Official Linux list: Fedora, RHEL, CentOS, Debian, Ubuntu, Mint — **not Arch**.
- SSH agent: Desktop app, Settings → Developer. Socket path is **not** stable like 1Password’s `~/.1password/agent.sock`. Use `IdentityAgent` in `~/.ssh/config`, never `export SSH_AUTH_SOCK` in bashrc.

---

## Recommended deploy (this repo)

1. Keep PKGBUILDs here plus `packages/<name>/upstream`. Allowlist starts with `keeper-password-manager`.
2. Cron/Actions: `scripts/propose-update.sh` fetches each package's checksums file, opens one PR per bump.
3. PR CI: `scripts/verify-pkgbuild.sh` — host, hash equality, no extra `source=`, no extra package dirs.
4. Human merge to `main`.
5. Actions `publish.yml` signs and uploads GitHub Release `repo-<UTC>` (full db). Laptops `pacman -S` over HTTPS. Do not `gh release upload` from a machine.

That is nvchecker + Omarchy-upstream + Chaotic-review, without their infrastructure.

GitHub Pro / Team / Enterprise cannot replace the hash/URL script. They can require the PR, the human, and that the script is green. See [GITHUB-ENFORCEMENT.md](GITHUB-ENFORCEMENT.md).

## Addendum (second pass)

- **AUR `keeper-password-manager` is already stale:** AUR 18.4.0 vs vendor **18.6.1** in SHASUM256.txt (this tree was filled from the vendor file on 2026-08-30). That is the whole argument against `yay`.
- **Checksum URL redirects** to `https://download.keepersecurity.com/desktop_electron/SHASUM256.txt`. Docs say “SHA1”; the file is SHA-256.
- **Gitea/Forgejo Arch package registry** can host `.pkg.tar.zst` if you already run git there. Do not install Gitea for two laptops. GitLab Package Registry has **no Arch format**.
- **aurpublish** (Arch `extra`) is the right *source git layout* (`pkgname/PKGBUILD`). Its job is pushing to public AUR — keep the layout, drop the push.
- **paru `--aururl`** talks to AUR RPC, not a git of PKGBUILDs. Wrong API.
- **lilac / archlinuxcn** is a community build farm. Overkill.
- **Renovate** has no released PKGBUILD manager ([#16923](https://github.com/renovatebot/renovate/issues/16923)). Regex manager will not update `sha256sums`.
- **Dependabot:** no pacman ecosystem.
- **Snap `keepersecurity`:** vendor auto-update, but `snapd` on Arch is itself AUR. Chicken-egg with C-21. Web vault has no SSH agent.
- **There is no `archlinux/al-actions`.** CI: `container: archlinux:base-devel`.
- Omarchy **removed Chaotic-AUR** as default once they had `omarchy-pkgs`. Do not re-add it.

## Do not build

- aurweb
- A fork of chaotic-aur/pkgbuilds
- A fork of omarchy-pkgs as a company product
- `yay` / paru pointed at a custom AUR URL
- Auto-merge of version bumps
- AI merge rights
