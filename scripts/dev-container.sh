#!/usr/bin/env bash

set -euo pipefail

ARCH="${__BUILD_ARCH:-amd64}"
SMP="${SMP:-1}"

usage() {
    cat <<'EOF'
usage: dev-container.sh build|ccdb|run|debug

Commands run inside the persistent development container:
  build  rebuild modules and initramfs, then refresh compile databases
  ccdb   refresh kernel and per-module compile_commands.json files
  run    boot QEMU; configure architecture with __BUILD_ARCH and CPUs with SMP
  debug  boot QEMU paused with the GDB server on TCP port 1234
EOF
}

run_as_root() {
    if [ "$(id -u)" -ne 0 ]; then
        exec sudo -E "$0" "$@"
    fi
}

generate_compile_databases() {
    local module

    cd /sources/linux
    python3 scripts/clang-tools/gen_compile_commands.py
    for module in /repo/modules/lab-*; do
        [ -d "$module" ] || continue
        python3 scripts/clang-tools/gen_compile_commands.py \
            -o "$module/compile_commands.json" "$module" 2>/dev/null
    done
    echo "compile_commands.json written under /sources/linux and each /repo/modules/lab-*"
    echo "per-module databases use /sources/linux as their compilation directory"
}

case "${1:-}" in
    build)
        run_as_root "$@"
        cd /repo/modules
        make build-modules
        generate_compile_databases
        ;;
    ccdb)
        run_as_root "$@"
        generate_compile_databases
        ;;
    run)
        run_as_root "$@"
        exec /repo/stage/start-qemu.sh --arch "$ARCH" --smp "$SMP"
        ;;
    debug)
        run_as_root "$@"
        exec /repo/stage/start-qemu.sh --arch "$ARCH" --smp "$SMP" --dbg
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
