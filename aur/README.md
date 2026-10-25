# AUR packaging

The `atmospheric` package for the [Arch user repository](https://aur.archlinux.org/packages/atmospheric).
This directory is the canonical copy; the AUR git repository holds only the
files listed below.

| File | Installed as | Purpose |
|---|---|---|
| `PKGBUILD` | — | build recipe |
| `.SRCINFO` | — | generated metadata, **must be committed with every `PKGBUILD` change** |
| `atmospheric-launcher` | `/usr/bin/atmospheric` | keeps a writable per-user copy and runs it |
| `atmospheric.install` | pacman scriptlet | first-run hints after install/upgrade |
| `LICENSE` | — | 0BSD, covers these packaging files (AUR submission rule) |
| `.gitignore` | — | keeps `src/`, `pkg/` and built packages out of the AUR repo |

## How the package works

pacman cannot write to `$HOME`, but this project is a quickshell *config* as
much as a program: `atmospheric city` rewrites `Config.qml` in place and
quickshell hot-reloads the save. So the package splits the two:

```
/usr/share/atmospheric/                     program, read-only (pacman)
/usr/lib/atmospheric/atmospheric-radar      radar daemon binary (pacman)
/usr/bin/atmospheric                        launcher
        └─ mirrors the program into
~/.config/quickshell/atmospheric/           private copy, writable, auto-refreshed
        ├─ Config.qml                       your city lives here
        └─ radar-backend/target/release/
             atmospheric-radar ──────────► /usr/lib/atmospheric/atmospheric-radar
```

- The launcher refreshes the copy whenever `VERSION` differs — on first run and
  after every package upgrade. Nothing else has to know about the split:
  autostart writes `quickshell -p ~/.config/quickshell/atmospheric`, IPC uses
  the same path, `qs -c atmospheric` works too.
- `city`/`latitude`/`longitude` are carried from the old `Config.qml` into the
  new one (exactly the three lines the picker writes).
- Other hand edits are **not** merged: the previous file is kept at
  `~/.local/state/atmospheric/Config.qml.bak-<old version>` and the path is
  printed on upgrade.
- `Radar.qml` looks for the daemon relative to the config directory, so the
  launcher puts a symlink to the packaged binary there — the radar works
  whether quickshell was started through the launcher or by autostart.

## Build and test locally

```bash
make aur                       # cd aur && makepkg -s -f
sudo pacman -U aur/atmospheric-*.pkg.tar.zst
atmospheric city               # pick a city, then:
atmospheric rain               # the overlay should start
```

**Why `build()` adds `-fno-lto` to `CFLAGS`/`CXXFLAGS`:** CachyOS (and any
setup that puts `-flto=auto` into `CFLAGS`) makes `cc`-rs compile ring's C
sources into GCC LTO bitcode. The final link is done by `rust-lld`, which
cannot read that bitcode — the build dies with `undefined symbol:
ring_core_*`. LTO buys nothing for those few C files, so it is switched off
for them only. Drop that line if your environment has no LTO in `CFLAGS`; keep
it if you want the package to build everywhere.

## Release procedure

```bash
# 1. upstream release
#    bump VERSION and radar-backend/Cargo.toml, run cargo check (refreshes
#    Cargo.lock), write CHANGELOG.md, then:
make check
git commit -am "atmospheric 1.0.2 — …"
git tag -a v1.0.2 -m "atmospheric 1.0.2"
git push origin HEAD --follow-tags        # the branch must be `main` on GitHub

# 2. point the PKGBUILD at the new tag
sed -i 's/^pkgver=.*/pkgver=1.0.2/' aur/PKGBUILD
make aur-sums                             # updpkgsums → both sha256 sums
make aur-srcinfo                          # regenerate .SRCINFO

# 3. push to the AUR (see below)
make aur-sync                             # copies files into the AUR clone
```

The source tarball is the GitHub archive of the tag
(`…/archive/refs/tags/v<pkgver>.tar.gz`) — pushing the tag is all the release
step upstream needs.

## Publishing to the AUR

One-time setup (the AUR account is separate from GitHub):

1. Register at <https://aur.archlinux.org> and confirm the e-mail.
2. Make a dedicated key and add its **public** part under *My Account → SSH
   Public Key* (multiple keys are allowed, newline-separated):

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/aur -C "aur@$(hostname)" -N ''
   cat ~/.ssh/aur.pub        # ← paste this into the AUR profile
   ```

   ```sshconfig
   # ~/.ssh/config
   Host aur.archlinux.org
     User aur
     IdentityFile ~/.ssh/aur
   ```

3. Clone the (still empty) package repository — the AUR accepts a first push
   of a package that does not exist yet. The AUR only accepts the **`master`**
   branch, hence `init.defaultBranch=master`:

   ```bash
   git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/atmospheric.git ../atmospheric-aur
   ```

Every update is then: `make aur-sync`, `cd ../atmospheric-aur`, review
(`git diff`), `git add … && git commit -m "…" && git push`.

Files that belong in the AUR repository: `PKGBUILD`, `.SRCINFO`,
`atmospheric-launcher`, `atmospheric.install`, `LICENSE`, `.gitignore` —
nothing else (no source tarballs, no built packages).

## Notes

- Name `atmospheric` is free of both the AUR and the official repositories;
  check again before the first push: <https://aur.archlinux.org/packages/atmospheric>.
- Users installing from a git checkout should keep using `./install.sh`; the
  two must not be mixed — a leftover `~/.local/bin/atmospheric` symlink or
  `/usr/local/bin/atmospheric` shadows the package command (the install
  scriptlet prints a warning when it finds one).
- Do not commit mere `pkgver` bumps without other changes for VCS packages —
  not applicable here, this is a release package: a new `pkgver` per tag.
