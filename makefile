T?=amd64
E?=full
JOBS?=4
SMP?=1
CONTAINER_BUILD_FLAGS?=
CONTAINER_RUN_FLAGS?=
VSCODE_TAG?=lkp-amd64-full-vscode
VSCODE_LKP?=lkp-vscode-dev-amd64
VSCODE_PORT?=8080
VSCODE_PASSWORD?=aos-linux-labs
HOST_UID?=$(shell id -u)
HOST_GID?=$(shell id -g)


# image tag
TAG?=lkp-$(T)-$(E)

# container name
LKP ?= lkp-dev-$(T)

build-container:
	docker build $(CONTAINER_BUILD_FLAGS) --platform linux/$(T) . \
	    -t $(TAG) \
	    --build-arg __ARCH=$(T) \
	    --build-arg __ENV=$(E) \
	    --build-arg __JOBS=$(JOBS)


## Host-driven dev workflow (no need to enter the container explicitly)
#
# Usage:
#   make dev-up                                    # start persistent container
#   make dev-vi F=modules/<released-lab>/module.c # LazyVim inside
#   make dev-build                                 # rebuild modules + initramfs
#   make dev-ccdb                                  # gen compile_commands.json
#   make SMP=4 dev-run                             # qemu with four virtual CPUs
#   make dev-dbg                                   # qemu paused, gdb on :1234
#   make dev-sh                                    # bash inside
#   make dev-down                                  # tear down


# F may be repo-relative or an absolute host path. The prefix is stripped in
# the shell (see dev-vi) because make's patsubst/abspath break on paths that
# contain spaces.

dev-up:
	docker run -d --name $(LKP) --privileged $(CONTAINER_RUN_FLAGS) \
	    -p 1234:1234 \
	    -v "$(CURDIR):/repo" \
	    $(TAG):latest sleep infinity

dev-down:
	-docker rm -f $(LKP)

dev-sh:
	docker exec -it -e TERM=$$TERM $(LKP) /bin/bash

dev-vi:
	@test -n "$(F)" || { echo "usage: make dev-vi F=<path>"; exit 2; }
	@f='$(F)'; f="$${f#'$(CURDIR)'/}"; \
	docker exec -it -e TERM=$$TERM $(LKP) nvim "/repo/$$f"

dev-build:
	docker exec -e __BUILD_ARCH=$(T) -e BUILD_JOBS=$(JOBS) $(LKP) /bin/bash -c "cd /repo/modules && make build-modules"
	$(MAKE) dev-ccdb

dev-ccdb:
	docker exec -w /sources/linux $(LKP) \
	    python3 scripts/clang-tools/gen_compile_commands.py
	@docker exec -w /sources/linux $(LKP) bash -c \
	    'for d in /repo/modules/lab-*; do [ -d "$$d" ] || continue; \
	     python3 scripts/clang-tools/gen_compile_commands.py \
	         -o "$$d/compile_commands.json" "$$d" 2>/dev/null ; \
	     done'
	@echo "compile_commands.json written under /sources/linux and each /repo/modules/lab-*"
	@echo "(per-module dbs have directory=/sources/linux so -I./ resolves correctly)"

dev-run:
	docker exec -it -e TERM=$$TERM $(LKP) /repo/stage/start-qemu.sh --arch $(T) --smp $(SMP)

dev-dbg:
	docker exec -it -e TERM=$$TERM $(LKP) /repo/stage/start-qemu.sh --arch $(T) --smp $(SMP) --dbg

.PHONY: macos-qemu-check macos-qemu-run macos-qemu-debug

macos-qemu-check:
	@test "$$(uname -s)" = Darwin && test "$$(uname -m)" = arm64 || { \
	    echo "The accelerated host-QEMU workflow requires Apple Silicon macOS." >&2; \
	    exit 2; \
	}
	@command -v qemu-system-x86_64 >/dev/null || { \
	    echo "qemu-system-x86_64 not found; install it with: brew install qemu" >&2; \
	    exit 2; \
	}
	@test -s stage/bzImage-amd64 \
	    && test -s stage/initramfs-busybox-amd64.cpio.gz || { \
	    echo "Missing AMD64 guest artifacts; run the browser build task first." >&2; \
	    exit 2; \
	}

macos-qemu-run: macos-qemu-check
	./stage/start-qemu.sh --arch amd64 --smp $(SMP)

macos-qemu-debug: macos-qemu-check
	./stage/start-qemu.sh --arch amd64 --smp $(SMP) --dbg \
	    --gdb-host 127.0.0.1


## Optional browser-based VS Code workflow. It uses a separate image and
## container, leaving the teaching image/tag and dev-* workflow untouched.
vscode-build-container:
	docker build $(CONTAINER_BUILD_FLAGS) --platform linux/amd64 \
	    -f Dockerfile.vscode . \
	    -t $(VSCODE_TAG) \
	    --build-arg USER_UID=$(HOST_UID) \
	    --build-arg USER_GID=$(HOST_GID)

vscode-up:
	@repo_owner="$$(docker run --rm --platform linux/amd64 \
	    -v "$(CURDIR):/repo:ro" \
	    $(VSCODE_TAG):latest stat -c '%u:%g' /repo)"; \
	test -n "$$repo_owner" || { \
	    echo "Cannot determine the container-visible owner of $(CURDIR)" >&2; \
	    exit 2; \
	}; \
	docker run -d --name $(VSCODE_LKP) --platform linux/amd64 \
	    --privileged $(CONTAINER_RUN_FLAGS) \
	    --user "$$repo_owner" \
	    -e HOME=/home/vscode \
	    -e PASSWORD="$(VSCODE_PASSWORD)" \
	    -p 127.0.0.1:$(VSCODE_PORT):8080 \
	    -v "$(CURDIR):/repo" \
	    $(VSCODE_TAG):latest
	@echo "VS Code: http://127.0.0.1:$(VSCODE_PORT)"
	@echo "Password: $(VSCODE_PASSWORD)"

vscode-down:
	-docker rm -f $(VSCODE_LKP)

vscode-sh:
	docker exec -it -e TERM=$$TERM $(VSCODE_LKP) /bin/bash

## Optional repository-local targets.
-include local.mk
