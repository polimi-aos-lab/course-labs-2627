#!/bin/bash

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --arch <arch>            Specify architecture ('amd64' or 'aarch64')"
    echo "  --smp <n>                Number of processors (default 1)"
    echo "  --with-gui               Open QEMU gui"
    echo "  --dbg                    Start paused with the GDB server on port 1234"
    echo "  --gdb-host <address>     Bind the GDB server to this address"
    echo "  --uart2 <port>           amd64: attach COM2 (0x2F8, IRQ 3) to TCP 127.0.0.1:<port>"
    echo "  --dry                    Dry run"
    echo "  --help                   Display this help and exit"
}

QEMUMAC=""
QEMUCMD=""
QEMUAPP=""
BUILD_ARCH=""
DRY=0
SMP=1
GDB_HOST=""
UART2=""
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Use a while-shift loop: `for arg in "$@"` snapshots the list and
# doesn't see shifts inside the body, which breaks multi-value flags.
while [ $# -gt 0 ]; do
  case "$1" in
    --arch)      ARCH="$2";      shift 2 ;;
    --smp)       SMP="$2";       shift 2 ;;
    --with-gui)  GRAPHIC_MODE=1; shift ;;
    --dbg)       DEBUG_MODE=1;   shift ;;
    --gdb-host)  GDB_HOST="$2";  shift 2 ;;
    --uart2)     UART2="$2";     shift 2 ;;
    --dry)       DRY=1;          shift ;;
    --help)      show_help; exit 0 ;;
    *)           shift ;;
  esac
done

# Remap QEMU's stdio escape from Ctrl-a to Ctrl-] (ASCII 29) to avoid
# clashing with tmux, which uses Ctrl-a as a secondary prefix.
# Quit sequence becomes: Ctrl-] then x.
NOGFX_FLAGS="-display none -serial mon:stdio -echr 29"

if [ "$ARCH" == "amd64" ]; then
    QEMUCMD="qemu-system-x86_64"
    QEMUMAC="-smp $SMP"
    if [ -z "$GRAPHIC_MODE" ]; then
       QEMUMAC+=" $NOGFX_FLAGS"
       QEMUAPP="console=ttyS0 init=/init nokaslr"
    else
       QEMUAPP="init=/init nokaslr"
    fi
    BUILD_ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    QEMUCMD="qemu-system-aarch64"
    QEMUMAC="-smp $SMP -machine virt -cpu cortex-a57"
    if [ -z "$GRAPHIC_MODE" ]; then
       QEMUMAC+=" $NOGFX_FLAGS"
       QEMUAPP="console=ttyAMA0 init=/init nokaslr"
    else
       QEMUAPP="init=/init nokaslr"
    fi
    BUILD_ARCH="aarch64"
else
    echo "Error: Architecture not specified or is invalid."
    exit 1
fi

if [ "$DEBUG_MODE" == "1" ]; then
    if [ -n "$GDB_HOST" ]; then
        QEMUMAC+=" -gdb tcp:$GDB_HOST:1234 -S"
    else
        QEMUMAC+=" -s -S"
    fi
fi

# Optional COM2 (I/O 0x2F8, IRQ 3) for the Lab 5 UART driver. The guest kernel
# registers only ttyS0, so COM2 stays free for a module. QEMU listens on
# 127.0.0.1:<port> and boots without waiting; connect a client such as nc.
if [ -n "$UART2" ]; then
    if [ "$BUILD_ARCH" != "amd64" ]; then
        echo "Error: --uart2 is supported only with --arch amd64." >&2
        exit 1
    fi
    # -serial options fill COM1, COM2, ... in order; in GUI mode COM1 is the
    # default virtual console and must be listed explicitly.
    [ -n "$GRAPHIC_MODE" ] && QEMUMAC+=" -serial vc"
    QEMUMAC+=" -serial tcp:127.0.0.1:$UART2,server,nowait"
fi

CMD="$QEMUCMD $QEMUMAC -kernel $DIR/bzImage-$BUILD_ARCH -initrd $DIR/initramfs-busybox-$BUILD_ARCH.cpio.gz -append \"$QEMUAPP\""

echo -e "${CMD}" 

if [ "$DRY" == "0" ]; then 
        eval "$CMD"
fi
