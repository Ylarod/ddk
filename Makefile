# Nix-based build + packaging helpers

ROOT := $(CURDIR)
DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
REV  := $(shell git -C $(ROOT) rev-parse HEAD)

# Android version to clang mapping
MATRIX := \
  android12-5.10:clang-r416183b \
  android13-5.10:clang-r450784e \
  android13-5.15:clang-r450784e \
  android14-5.15:clang-r487747c \
  android14-6.1:clang-r487747c \
  android15-6.6:clang-r510928 \
  android16-6.12:clang-r536225

VERSIONS := $(foreach pair,$(MATRIX),$(firstword $(subst :, ,$(pair))))
CLANGS   := $(foreach pair,$(MATRIX),$(word 2,$(subst :, ,$(pair))))

# GHCR registry options
REG ?= ghcr.io/ylarod
DEST_CREDS ?=

# Utility to map VER->CLANG
find-clang = $(shell echo $(MATRIX) | tr ' ' '\n' | awk -F: '$$1=="$(1)" {print $$2}')

# Convert version like android12-5.10 -> android12_5_10 for Nix attr paths
to_attr = $(subst .,_,$(subst -,_,$(1)))

.PHONY: help list matrix clangs pack pack-all clean-pack \
	ci-shell ci-run build-base push-base \
	build-ddk push-ddk build-dev push-dev build-all-ddk push-all-ddk \
	pack-all

help:
	@echo "Available targets:"
	@echo "  pack VER=android14-6.1 [FORCE=1]" 
	@echo "  pack-all [FORCE=1]"
	@echo "  build-*/push-* (base, ddk, dev)"
	@echo "  ci-shell, ci-run CMD=..."
	@echo "  list (matrix overview)"

list: matrix

matrix:
	@for pair in $(MATRIX); do echo $$pair; done

clangs:
	@printf '%s\n' $(CLANGS)

# -----------------------------------------------------------------------------
# Packaging helpers (host-produced artifacts)
# -----------------------------------------------------------------------------

pack:
	@if [ -z "$(VER)" ]; then echo "Usage: make pack VER=<androidX-Y> [FORCE=1]"; exit 1; fi
	@mkdir -p $(ROOT)/.pkg
	@echo "==> Packing src/$(VER) and kdir/$(VER) -> $(ROOT)/.pkg/ (FORCE=$(FORCE))"
	@if [ ! -d $(ROOT)/src/$(VER) ]; then echo "Missing src/$(VER)" >&2; exit 2; fi
	@if [ ! -d $(ROOT)/kdir/$(VER) ]; then echo "Missing kdir/$(VER)" >&2; exit 2; fi
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

pack-all:
	@for ver in $(VERSIONS); do \
	  $(MAKE) pack VER=$$ver FORCE=$(FORCE) || exit $$?; \
	done

clean-pack:
	rm -rf $(ROOT)/.pkg

# -----------------------------------------------------------------------------
# Nix development shells
# -----------------------------------------------------------------------------

ci-shell:
	nix develop

ci-run:
	@if [ -z "$(CMD)" ]; then echo "Usage: make ci-run CMD=\"<command>\""; exit 1; fi
	nix develop --command bash -lc "$(CMD)"

# -----------------------------------------------------------------------------
# Nix build helpers
# -----------------------------------------------------------------------------

build-base:
	DDK_ROOT=$(ROOT) nix build --impure .#ddk-base

push-base:
	@if [ -z "$(DEST_CREDS)" ]; then echo "Usage: make push-base DEST_CREDS=\"user:token\""; exit 1; fi
	DDK_ROOT=$(ROOT) nix run --impure .#ddk-base.copyToRegistry -- --dest-creds "$(DEST_CREDS)"

build-ddk:
	@if [ -z "$(VER)" ]; then echo "Usage: make build-ddk VER=<androidX-Y>"; exit 1; fi
	DDK_ROOT=$(ROOT) nix build --impure .#ddk.$(call to_attr,$(VER))

push-ddk:
	@if [ -z "$(VER)" ]; then echo "Usage: make push-ddk VER=<androidX-Y> DEST_CREDS=..."; exit 1; fi
	@if [ -z "$(DEST_CREDS)" ]; then echo "DEST_CREDS required"; exit 1; fi
	DDK_ROOT=$(ROOT) nix run --impure .#ddk.$(call to_attr,$(VER)).copyToRegistry -- --dest-creds "$(DEST_CREDS)"

build-dev:
	@if [ -z "$(VER)" ]; then echo "Usage: make build-dev VER=<androidX-Y>"; exit 1; fi
	DDK_ROOT=$(ROOT) nix build --impure .#ddk-dev.$(call to_attr,$(VER))

push-dev:
	@if [ -z "$(VER)" ]; then echo "Usage: make push-dev VER=<androidX-Y> DEST_CREDS=..."; exit 1; fi
	@if [ -z "$(DEST_CREDS)" ]; then echo "DEST_CREDS required"; exit 1; fi
	DDK_ROOT=$(ROOT) nix run --impure .#ddk-dev.$(call to_attr,$(VER)).copyToRegistry -- --dest-creds "$(DEST_CREDS)"

build-all-ddk:
	@for ver in $(VERSIONS); do \
	  $(MAKE) build-ddk VER=$$ver || exit $$?; \
	done

push-all-ddk:
	@for ver in $(VERSIONS); do \
	  $(MAKE) push-ddk VER=$$ver DEST_CREDS="$(DEST_CREDS)" || exit $$?; \
	done
