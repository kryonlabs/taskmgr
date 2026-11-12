ZIRAN ?= ./scripts/ziran.sh
SOURCES := $(wildcard src/*.zi) $(wildcard tests/*.zi) ziran.toml ziran.lock scripts/ziran.sh Makefile

.PHONY: all build run check test shot clean

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

# One rendered frame without a display; useful for interface checks.
shot: build
	$(ZIRAN) tool kryon run --profile shot > build/taskmgr.ppm

clean:
	rm -rf build
