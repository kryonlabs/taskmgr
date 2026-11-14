ZIRAN ?= ./scripts/ziran.sh
# The host-aware desktop palette reads the supervising X11 container. Kryon's
# native project linker consumes LDLIBS at the final link boundary.
export LDLIBS += -lX11
SOURCES := $(wildcard src/*.zi) $(wildcard tests/*.zi) ziran.toml ziran.lock scripts/ziran.sh Makefile

.PHONY: all build run check test x11-test memory-test shot package clean

all: build

build:
	$(ZIRAN) tool kryon build

run: build
	$(ZIRAN) tool kryon run

check:
	$(ZIRAN) check

build/model-test: $(SOURCES)
	$(ZIRAN) build --project --target=c --exe --entry model_test:main -o build/model-test-c tests/model_test.zi
	cp build/model-test-c/model_test build/model-test

test: build/model-test
	./build/model-test

build/windows-test: $(SOURCES)
	$(ZIRAN) build --project --target=c --exe --entry windows_test:main -o build/windows-test-c tests/windows_test.zi
	cp build/windows-test-c/windows_test build/windows-test

# Applications-tab integration on a scrubbed private Xvfb display.
x11-test: build build/windows-test
	./scripts/x11-test.sh

# Native RSS regression on a scrubbed private Xvfb display.
memory-test: build
	./scripts/memory-test.sh

# dist/taskmgr-linux-amd64.deb and dist/taskmgr-linux-x86_64.AppImage. The
# AppImage needs LINUXDEPLOY; see scripts/package-linux.sh.
PACKAGE_FORMAT ?= all
package: build
	./scripts/package-linux.sh $(PACKAGE_FORMAT) "$$(cat VERSION)" dist

# One rendered frame without a display; useful for interface checks.
shot: build
	$(ZIRAN) tool kryon run --profile shot > build/taskmgr.ppm

clean:
	rm -rf build
