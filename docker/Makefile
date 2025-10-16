# docker/Makefile

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# 依赖 jq 从 mapping.json 解析矩阵
JQ := $(shell command -v jq 2>/dev/null)
ifeq ($(JQ),)
  $(error "jq 未安装，请先安装 jq 以解析 $(ROOT)/mapping.json")
endif

MATRIX := $(shell jq -r '.matrix[] | "\(.android):\(.clang)"' $(ROOT)/mapping.json | tr '\n' ' ')

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

.PHONY: list toolchains build build-all push push-all push-toolchains

list:
	@for i in $(MATRIX); do echo $$i; done

toolchains:
	@for pair in $(MATRIX); do \
	  CLANG=$${pair##*:}; \
	  if [ "$(FORCE)" = "1" ] || ! $(DOCKER) image inspect $(REG)/$(IMG)/clang:$$CLANG >/dev/null 2>&1 || $(FORCE); then \
	    echo "==> Building toolchain $(REG)/$(IMG)/clang:$$CLANG"; \
	    DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	      $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,--load) \
	      --build-arg CLANG_VER=$$CLANG \
	      -f $(ROOT)/docker/toolchain/Dockerfile.clang \
	      -t $(REG)/$(IMG)/clang:$$CLANG $(ROOT) || exit $$?; \
	  fi; \
	done

push-toolchains:
	@for pair in $(MATRIX); do \
	  CLANG=$${pair##*:}; \
	  echo "==> Pushing $(REG)/$(IMG)/clang:$$CLANG"; \
	  $(DOCKER) push $(REG)/$(IMG)/clang:$$CLANG || exit $$?; \
	done

# 用法：make build VER=android14-6.1
build:
	@if [ -z "$(VER)" ]; then echo "Usage: make build VER=<androidX-Y>"; exit 1; fi
	@CLANG=$$(echo "$(MATRIX)" | tr ' ' '\n' | grep "^$(VER):" | cut -d: -f2); \
	if [ -z "$$CLANG" ]; then echo "CLANG not found for $(VER)"; exit 2; fi; \
	echo "==> Building $(REG)/$(IMG):$(VER) with $$CLANG"; \
	DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,) \
	  --build-arg CLANG_VER=$$CLANG \
	  --build-arg ANDROID_VER=$(VER) \
	  --build-arg VERSION=$(VER) \
	  --build-arg REVISION=$(REV) \
	  --build-arg CREATED=$(DATE) \
	  -f $(ROOT)/docker/Dockerfile \
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
