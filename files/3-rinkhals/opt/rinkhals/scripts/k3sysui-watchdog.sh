#!/bin/sh

. /useremain/rinkhals/.current/tools.sh

PID_FILE=/tmp/rinkhals/k3sysui-watchdog.pid
GRACE=15
RECOVERY_PID=""

is_k3sysui_running() {
    for P in /proc/[0-9]*; do
        [ -r "$P/comm" ] || continue
        [ "$(cat "$P/comm" 2>/dev/null)" = "K3SysUi" ] && return 0
    done
    return 1
}

is_watchdog_pid() {
    PID="$1"

    [ -n "$PID" ] || return 1
    [ -r "/proc/$PID/cmdline" ] || return 1

    CMD="$(tr '\000' ' ' < "/proc/$PID/cmdline" 2>/dev/null)"

    case "$CMD" in
        *k3sysui-watchdog.sh*) return 0 ;;
    esac

    return 1
}

restore_names() {
    cd /userdata/app/gk || return 1

    [ -e K3SysUi.recovery-original ] || return 0

    # State after:
    #   mv K3SysUi K3SysUi.recovery-original
    #
    # canonical is missing, .patch still exists.
    if [ ! -e K3SysUi ] && [ -e K3SysUi.patch ]; then
        mv K3SysUi.recovery-original K3SysUi || return 1
        return 0
    fi

    # State after:
    #   mv K3SysUi.patch K3SysUi
    #
    # canonical contains the patched binary, .patch is missing.
    if [ -e K3SysUi ] && [ ! -e K3SysUi.patch ]; then
        mv K3SysUi K3SysUi.patch || return 1
        mv K3SysUi.recovery-original K3SysUi || return 1
        return 0
    fi

    # Any other combination is ambiguous. Never delete a file here.
    log "/!\ K3SysUi recovery transaction could not be restored safely"
    return 1
}

cleanup() {
    if [ "$RECOVERY_PID" != "" ]; then
        kill "$RECOVERY_PID" 2>/dev/null
        RECOVERY_PID=""
    fi

    restore_names

    CURRENT_PID="$(cat "$PID_FILE" 2>/dev/null)"
    if [ "$CURRENT_PID" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
}

terminate() {
    trap - TERM INT EXIT
    cleanup
    exit 0
}

recover_k3sysui() {
    cd /userdata/app/gk || return 1

    if is_k3sysui_running; then
        return 0
    fi

    # Repair an interrupted previous recovery before starting a new one.
    if [ -e K3SysUi.recovery-original ]; then
        if ! restore_names; then
            log "/!\ Refusing K3SysUi recovery because an old transaction is ambiguous"
            return 1
        fi
    fi

    if [ ! -x K3SysUi ] || [ ! -x K3SysUi.patch ]; then
        log "/!\ K3SysUi recovery files are not available"
        return 1
    fi

    mv K3SysUi K3SysUi.recovery-original || return 1

    if ! mv K3SysUi.patch K3SysUi; then
        restore_names
        return 1
    fi

    ./K3SysUi >> "$RINKHALS_LOGS/K3SysUi.log" 2>&1 &
    RECOVERY_PID=$!

    sleep 1

    if ! restore_names; then
        log "/!\ K3SysUi recovery filenames could not be restored"
        kill "$RECOVERY_PID" 2>/dev/null
        RECOVERY_PID=""
        return 1
    fi

    sleep 1

    if kill -0 "$RECOVERY_PID" 2>/dev/null; then
        log "K3SysUi recovered (PID $RECOVERY_PID)"
        RECOVERY_PID=""
        return 0
    fi

    log "/!\ K3SysUi recovery failed"
    RECOVERY_PID=""
    return 1
}

mkdir -p /tmp/rinkhals

OLD_PID="$(cat "$PID_FILE" 2>/dev/null)"
if is_watchdog_pid "$OLD_PID"; then
    exit 0
fi

echo $$ > "$PID_FILE"

trap terminate TERM INT
trap cleanup EXIT

log "K3SysUi watchdog started"

while true; do
    if ! is_k3sysui_running; then
        log "K3SysUi is not running, waiting ${GRACE}s before recovery"
        sleep "$GRACE"

        if ! is_k3sysui_running; then
            recover_k3sysui
            sleep 5
        fi
    fi

    sleep 2
done
