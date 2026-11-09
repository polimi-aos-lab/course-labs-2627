# Accelerated Apple Silicon workflow (experimental)

This optional workflow keeps the teaching kernel, modules, initramfs, and guest
on AMD64. Docker Desktop uses Rosetta for the AMD64 code-server, clangd, and
build tools, while an ARM64 Homebrew QEMU runs natively on the Mac.

The split is necessary because `qemu-system-x86_64` does not run through
Docker's Rosetta path: Rosetta terminates it on the unimplemented x86-64
`signalfd` system call. The standard AMD64 workflow remains the supported
fallback.

## Prerequisites

This workflow requires an Apple Silicon Mac and Docker Desktop. Enable **Use
Rosetta for x86_64/amd64 emulation on Apple Silicon** in Docker Desktop, apply
the change, and restart Docker Desktop.

Install native host QEMU once:

```sh
brew install qemu
```

## Start the browser environment

Build and start the AMD64 browser container normally:

```sh
make build-container
make vscode-build-container
make vscode-up
```

Open <http://127.0.0.1:8080> and use the password `aos-linux-labs`. Edit in the
Explorer and use **Terminal → Run Build Task** to generate the AMD64 kernel,
modules, and initramfs in `stage/`.

Do not use the `AOS: Run QEMU` or `AOS: Debug QEMU` tasks while Rosetta is
enabled.

## Run the AMD64 guest

In a separate macOS terminal at the repository root, run:

```sh
make SMP=1 macos-qemu-run
```

That terminal is the guest console. Quit QEMU with <kbd>Ctrl-]</kbd>, then
<kbd>x</kbd>.

For Lab 5, add COM2 on TCP port 6000 and attach to it from a second macOS
terminal:

```sh
make SMP=1 UART2=6000 macos-qemu-run
nc 127.0.0.1 6000
```

## Debug from the browser

Start host QEMU paused:

```sh
make SMP=1 macos-qemu-debug
```

In the browser, open **Run and Debug**, select
`AOS: Attach to host QEMU (macOS experimental)`, and press <kbd>F5</kbd>. GDB
runs inside the browser container and reaches the host stub through
`host.docker.internal:1234`. The QEMU GDB server itself listens only on the Mac
loopback interface.

The debugger stops in `start_kernel`; press <kbd>F5</kbd> again to continue.
Module debugging uses the same `aos-module-symbols` procedure documented in the
main README.

## Stop and fallback

Remove the browser container with:

```sh
make vscode-down
```

If this experimental workflow causes problems, disable Rosetta, restart Docker
Desktop, and use the standard in-container AMD64 QEMU tasks from the main
README. The image and generated guest artifacts do not need to be rebuilt only
because Rosetta was toggled.
