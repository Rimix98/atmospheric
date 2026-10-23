# atmospheric — проверки, установка и релизный архив.
#
#   make            # то же, что make check
#   make check      # bash -n + qmllint + cargo check
#   make install    # ./install.sh (PATH + автозапуск + город)
#   make uninstall  # убрать команду из PATH и автозапуск
#   make run        # запустить оверлей
#   make dist       # dist/atmospheric-<версия>.tar.gz
#   make clean      # убрать dist/ и target/

VERSION := $(shell cat VERSION)
QMLDIR  := $(shell qtpaths6 --query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)
QMLLINT := $(firstword $(wildcard /usr/lib/qt6/bin/qmllint) $(shell command -v qmllint6 2>/dev/null))
QML     := shell.qml Config.qml Weather.qml WeatherOverlay.qml Radar.qml \
           OverlayWindowWayland.qml OverlayWindowX11.qml effects/*.qml
DIST    := dist/atmospheric-$(VERSION).tar.gz

.PHONY: all check qml rust install uninstall run dist clean

all: check

check: qml rust
	@bash -n atmospheric
	@bash -n install.sh
	@bash -n scripts/*.sh
	@echo "✓ bash: синтаксис OK"
	@echo "✓ версия: $(VERSION)"

qml:
	@if [ -z "$(QMLLINT)" ]; then \
		echo "! qmllint не найден — QML-линт пропущен"; \
	else \
		$(QMLLINT) -I $(QMLDIR) $(QML) && echo "✓ QML: линт OK"; \
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

clean:
	rm -rf dist
	cd radar-backend && cargo clean
