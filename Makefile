# atmospheric — checks, install and release archive.
#
#   make            # same as make check
#   make check      # bash -n + qmllint + cargo check
#   make install    # ./install.sh (PATH + autostart + city)
#   make uninstall  # remove the command from PATH and autostart
#   make run        # start the overlay
#   make dist       # dist/atmospheric-<version>.tar.gz
#   make aur        # build the AUR package (aur/, needs makepkg)
#   make aur-srcinfo  # regenerate aur/.SRCINFO after editing the PKGBUILD
#   make aur-sums   # refresh sha256sums after a new release tag
#   make aur-sync   # copy the packaging files into an AUR clone (AURDIR=...)
#   make clean      # remove dist/ and target/

VERSION := $(shell cat VERSION)
QMLDIR  := $(shell qtpaths6 --query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)
QMLLINT := $(firstword $(wildcard /usr/lib/qt6/bin/qmllint) $(shell command -v qmllint6 2>/dev/null))
QML     := shell.qml Config.qml Weather.qml WeatherOverlay.qml Radar.qml \
           OverlayWindowWayland.qml OverlayWindowX11.qml effects/*.qml
DIST    := dist/atmospheric-$(VERSION).tar.gz

.PHONY: all check qml rust install uninstall run dist aur aur-srcinfo aur-sums aur-sync clean

all: check

check: qml rust
	@bash -n atmospheric
	@bash -n install.sh
	@bash -n scripts/*.sh
	@echo "✓ bash: syntax OK"
	@echo "✓ version: $(VERSION)"

qml:
	@if [ -z "$(QMLLINT)" ]; then \
		echo "! qmllint not found — QML lint skipped"; \
	else \
		$(QMLLINT) -I $(QMLDIR) $(QML) && echo "✓ QML: lint OK"; \
	fi

rust:
	@cd radar-backend && cargo check --quiet
	@echo "✓ Rust: cargo check OK"

install:
	./install.sh

uninstall:
	./atmospheric uninstall

run:
	./atmospheric start

dist: check
	@mkdir -p dist
	@tar --exclude='./dist' \
	     --exclude='./radar-backend/target' \
	     --exclude='./.git' \
	     --exclude='./.qmlls.ini' \
	     --exclude='*.bak-atmospheric-*' \
	     --exclude='*.log' \
	     --transform='s,^\.,atmospheric-$(VERSION),' \
	     -czf $(DIST) .
	@ls -lh $(DIST) | awk '{print "✓ " $$9 " (" $$5 ")"}'

# --- AUR ----------------------------------------------------------
# The package lives in aur/ and is pushed to ssh://aur@aur.archlinux.org.
# See aur/README.md for the release procedure.
aur:
	cd aur && makepkg -s -f

aur-srcinfo:
	@cd aur && makepkg --printsrcinfo > .SRCINFO && echo "✓ aur/.SRCINFO updated"

aur-sums:
	@cd aur && updpkgsums && echo "✓ aur/PKGBUILD sha256sums updated"

# The AUR holds its own git repository (PKGBUILD + .SRCINFO + helpers only);
# this target copies the canonical files from aur/ into such a clone.
#   git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/atmospheric.git ../atmospheric-aur
AURDIR ?= ../atmospheric-aur

aur-sync: aur-srcinfo
	@test -d "$(AURDIR)/.git" || { \
		echo "! $(AURDIR) is not a git clone. Create one with:"; \
		echo "  git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/atmospheric.git $(AURDIR)"; \
		exit 1; }
	cp -f aur/PKGBUILD aur/atmospheric-launcher aur/atmospheric.install \
	      aur/LICENSE aur/.gitignore aur/.SRCINFO "$(AURDIR)/"
	@echo "✓ synced to $(AURDIR) — review, commit and push from there"

clean:
	rm -rf dist
	cd radar-backend && cargo clean
