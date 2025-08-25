# docker/Makefile

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

MATRIX := \
  android12-5.10:clang-r416183b \
  android13-5.10:clang-r450784e \
  android13-5.15:clang-r450784e \
  android14-5.15:clang-r487747c \
  android14-6.1:clang-r487747c \
  android15-6.6:clang-r510928  \
  android16-6.12:clang-r536225

REG ?= ghcr.io/ylarod
IMG ?= ddk
DEV_IMG ?= ddk-dev
BASE_IMG ?= ddk-base
PUSH ?= 0
FORCE ?= 0
PLAT ?= linux/amd64

DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
REV  := $(shell git -C $(ROOT) rev-parse HEAD)
BUILDKIT ?= 1
DOCKER ?= docker

.PHONY: list toolchains build build-all pack clean \
	push push-all push-toolchains \
	base devcontainer push-devcontainer devcontainer-all push-devcontainer-all

list:
	@for i in $(MATRIX); do echo $$i; done

toolchains:
	@for pair in $(MATRIX); do \
	  CLANG=$${pair##*:}; \
	  if ! $(DOCKER) image inspect $(REG)/$(IMG)/clang:$$CLANG >/dev/null 2>&1; then \
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
	$(MAKE) pack VER=$(VER); \
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

pack:
	@if [ -z "$(VER)" ]; then echo "Usage: make pack VER=<androidX-Y>"; exit 1; fi
	@mkdir -p $(ROOT)/.pkg
	@echo "==> Packing src/$(VER) and kdir/$(VER) -> $(ROOT)/.pkg/ (FORCE=$(FORCE))"
	@if [ "$(FORCE)" = "1" ]; then \
	  echo "    FORCE=1: rebuilding src.$(VER).tar"; \
	  tar --sort=name --mtime='UTC 2025-01-01' --owner=0 --group=0 --numeric-owner \
	    -C $(ROOT)/src -cf $(ROOT)/.pkg/src.$(VER).tar $(VER); \
	else \
	  if [ -f $(ROOT)/.pkg/src.$(VER).tar ]; then \
	    echo "    Reuse existing src.$(VER).tar"; \
	  else \
	    tar --sort=name --mtime='UTC 2025-01-01' --owner=0 --group=0 --numeric-owner \
	      -C $(ROOT)/src -cf $(ROOT)/.pkg/src.$(VER).tar $(VER); \
	  fi; \
	fi
	@if [ "$(FORCE)" = "1" ]; then \
	  echo "    FORCE=1: rebuilding kdir.$(VER).tar"; \
	  tar --sort=name --mtime='UTC 2025-01-01' --owner=0 --group=0 --numeric-owner \
	    -C $(ROOT)/kdir -cf $(ROOT)/.pkg/kdir.$(VER).tar $(VER); \
	else \
	  if [ -f $(ROOT)/.pkg/kdir.$(VER).tar ]; then \
	    echo "    Reuse existing kdir.$(VER).tar"; \
	  else \
	    tar --sort=name --mtime='UTC 2025-01-01' --owner=0 --group=0 --numeric-owner \
	      -C $(ROOT)/kdir -cf $(ROOT)/.pkg/kdir.$(VER).tar $(VER); \
	  fi; \
	fi


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

clean:
	rm -rf $(ROOT)/.pkg

base:
	@echo "==> Building base image $(REG)/$(BASE_IMG):latest";
	DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,--load) \
	  -f $(ROOT)/docker/devcontainer/Dockerfile.base \
	  -t $(REG)/$(BASE_IMG):latest $(ROOT)

devcontainer:
	@if [ -z "$(VER)" ]; then echo "Usage: make devcontainer VER=<androidX-Y>"; exit 1; fi
	@if ! $(DOCKER) image inspect $(REG)/$(BASE_IMG):latest >/dev/null 2>&1; then \
	  echo "==> Base image $(REG)/$(BASE_IMG):latest not found locally. Building..."; \
	  $(MAKE) base || exit $$?; \
	 fi
	@CLANG=$$(echo "$(MATRIX)" | tr ' ' '\n' | grep "^$(VER):" | cut -d: -f2); \
	 if [ -z "$$CLANG" ]; then echo "CLANG not found for $(VER)"; exit 2; fi; \
	 echo "==> Building $(REG)/$(DEV_IMG):$(VER) (CLANG=$$CLANG) from $(REG)/$(IMG):$(VER)"; \
	 DOCKER_BUILDKIT=$(BUILDKIT) $(DOCKER) buildx build \
	  $(if $(filter 1,$(PUSH)),--platform $(PLAT) --push,--load) \
	  --build-arg VER=$(VER) \
	  --build-arg CLANG_VER=$$CLANG \
	  -f $(ROOT)/docker/devcontainer/Dockerfile \
	  -t $(REG)/$(DEV_IMG):$(VER) $(ROOT)

push-devcontainer:
	@if [ -z "$(VER)" ]; then echo "Usage: make push-devcontainer VER=<androidX-Y>"; exit 1; fi
	@echo "==> Pushing $(REG)/$(DEV_IMG):$(VER)";
	$(DOCKER) push $(REG)/$(DEV_IMG):$(VER)

devcontainer-all:
	@for pair in $(MATRIX); do \
	  VER=$${pair%%:*}; \
	  echo "==> [dev] Building $(REG)/$(DEV_IMG):$$VER"; \
	  $(MAKE) devcontainer VER=$$VER || exit $$?; \
	 done

push-devcontainer-all:
	@for pair in $(MATRIX); do \
	  VER=$${pair%%:*}; \
	  echo "==> [dev] Pushing $(REG)/$(DEV_IMG):$$VER"; \
	  $(MAKE) push-devcontainer VER=$$VER || exit $$?; \
	 done
