T?=amd64
E?=full
JOBS?=4
SMP?=1
CONTAINER_BUILD_FLAGS?=
CONTAINER_RUN_FLAGS?=

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


# Normalize F: accept either repo-relative or absolute host path,
# strip the host repo prefix, prepend /repo/ for the container view.
F_REL = $(patsubst $(CURDIR)/%,%,$(abspath $(F)))

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
	docker exec -it -e TERM=$$TERM $(LKP) nvim /repo/$(F_REL)

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


## Optional repository-local targets.
-include local.mk
