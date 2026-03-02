# docker/Makefile

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# 依赖 jq 从 mapping.json 解析矩阵
JQ := $(shell command -v jq 2>/dev/null)
ifeq ($(JQ),)
  $(error "jq 未安装，请先安装 jq 以解析 $(ROOT)/mapping.json")
endif

MATRIX   := $(shell jq -r '.matrix[] | "\(.android):\(.clang):\(.rust // "")"' $(ROOT)/mapping.json | tr '\n' ' ')

# ghcr.io/ylarod
# docker.cnb.cool/ylarod/ddk
REG ?= docker.cnb.cool/ylarod/ddk
IMG ?= ddk
PUSH ?= 0
FORCE ?= 0
PLAT ?= linux/amd64

DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
REV  := $(shell git -C $(ROOT) rev-parse HEAD)
BUILDKIT ?= 1
DOCKER ?= docker

.PHONY: list builder cnb-dev toolchains build build-all push push-all push-toolchains

list:
	@for i in $(MATRIX); do echo $$i; done

builder:
	@echo "==> Building $(REG)/ddk-builder:latest"
	DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--push,--load) \
	  -f $(ROOT)/docker/ddk-builder/Dockerfile \
	  -t $(REG)/ddk-builder:latest $(ROOT)

cnb-dev:
	@echo "==> Building $(REG)/ddk-cnb-dev:latest"
	DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--push,--load) \
	  -f $(ROOT)/docker/ddk-cnb-dev/Dockerfile \
	  -t $(REG)/ddk-cnb-dev:latest $(ROOT)

toolchains:
	@for pair in $(MATRIX); do \
	  CLANG=$$(echo $$pair | cut -d: -f2); \
	  RUST=$$(echo $$pair | cut -d: -f3); \
	  if [ "$(FORCE)" = "1" ] || ! $(DOCKER) image inspect $(REG)/ddk-toolchain:$$CLANG >/dev/null 2>&1; then \
	    echo "==> Building toolchain $(REG)/ddk-toolchain:$$CLANG"; \
	    DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	      $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,--load) \
	      --build-arg CLANG_VER=$$CLANG \
	      --build-arg RUST_VER=$$RUST \
	      -f $(ROOT)/docker/ddk-toolchain/Dockerfile \
	      -t $(REG)/ddk-toolchain:$$CLANG $(ROOT) || exit $$?; \
	  fi; \
	done

push-toolchains:
	@for pair in $(MATRIX); do \
	  CLANG=$$(echo $$pair | cut -d: -f2); \
	  echo "==> Pushing $(REG)/ddk-toolchain:$$CLANG"; \
	  $(DOCKER) push $(REG)/ddk-toolchain:$$CLANG || exit $$?; \
	done

# 用法：make build VER=android14-6.1
build:
	@if [ -z "$(VER)" ]; then echo "Usage: make build VER=<androidX-Y>"; exit 1; fi
	@ENTRY=$$(echo "$(MATRIX)" | tr ' ' '\n' | grep "^$(VER):"); \
	CLANG=$$(echo $$ENTRY | cut -d: -f2); \
	RUST=$$(echo $$ENTRY | cut -d: -f3); \
	if [ -z "$$CLANG" ]; then echo "CLANG not found for $(VER)"; exit 2; fi; \
	echo "==> Building $(REG)/$(IMG):$(VER) with $$CLANG $${RUST:+(rust: $$RUST)}"; \
	DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,) \
	  --build-arg CLANG_VER=$$CLANG \
	  --build-arg RUST_VER=$$RUST \
	  --build-arg ANDROID_VER=$(VER) \
	  --build-arg VERSION=$(VER) \
	  --build-arg REVISION=$(REV) \
	  --build-arg CREATED=$(DATE) \
	  -f $(ROOT)/docker/ddk/Dockerfile \
	  -t $(REG)/$(IMG):$(VER) $(ROOT)

build-all:
	@for pair in $(MATRIX); do \
	  VER=$${pair%%:*}; \
	  $(MAKE) build VER=$$VER || exit $$?; \
	done

push:
	@if [ -z "$(VER)" ]; then echo "Usage: make push VER=<androidX-Y>"; exit 1; fi
	@echo "==> Pushing $(REG)/$(IMG):$(VER)"; \
	$(DOCKER) push $(REG)/$(IMG):$(VER)

push-all:
	@for pair in $(MATRIX); do \
	  VER=$${pair%%:*}; \
	  echo "==> Pushing $(REG)/$(IMG):$$VER"; \
	  $(DOCKER) push $(REG)/$(IMG):$$VER || exit $$?; \
	done
