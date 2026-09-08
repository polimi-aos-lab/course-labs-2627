# AOS Linux Labs

Reproducible Linux-kernel development environment for the Advanced Operating
Systems course. Docker builds an amd64 Linux 5.16 kernel and a BusyBox
initramfs; the host-driven Make targets rebuild released modules, open sources
in LazyVim, and run the result in QEMU.

The public companion grows progressively. A checkout contains only the
infrastructure and laboratory material already released for the course.

## Prerequisites

- amd64 Linux with Docker Engine, or Intel/Apple-silicon macOS with Docker
  Desktop capable of running privileged `linux/amd64` containers;
- Git, GNU Make, a running Docker daemon, and outbound HTTPS access;
- at least 25 GiB free disk and 4 GiB RAM available to Docker;
- TCP port 1234 free.

The supported student configuration is `T=amd64 E=full`. Native Windows,
WSL2, and the experimental `aarch64` build are not supported.

## Repository layout

- `Dockerfile` and `scripts/`: container, kernel, and initramfs build;
- `modules/`: build infrastructure and currently released lab sources;
- `stage/`: QEMU launcher and locally generated kernel/initramfs artifacts.

Generated images and module build products are intentionally not versioned.

## Build the environment

From a fresh clone:

```sh
T=amd64 E=full make build-container
T=amd64 E=full make dev-up
T=amd64 E=full make dev-build
```

`dev-build` must create non-empty files:

```text
stage/bzImage-amd64
stage/initramfs-busybox-amd64.cpio.gz
```

## Open a released source file

The full image includes LazyVim and clangd. `dev-build` creates a
`compile_commands.json` in each released module directory.

```sh
T=amd64 E=full make dev-vi F=scripts/init
```

Replace `scripts/init` with a released lab source path when directed by its
handout. Exit LazyVim with `:qa`.

## Run the kernel

```sh
T=amd64 E=full make dev-run
```

A successful boot prints `Welcome to aos-mini-linux` and opens a BusyBox
shell. `uname -r` should report `5.16.0-rc1`. Exit QEMU with
<kbd>Ctrl-]</kbd>, then <kbd>x</kbd>.

## Clean up

```sh
T=amd64 E=full make dev-down
```
