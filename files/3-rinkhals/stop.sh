. $(dirname $(realpath $0))/tools.sh

cd $RINKHALS_ROOT
mkdir -p $RINKHALS_LOGS

if [ ! -d /useremain/rinkhals/.current ]; then
    echo Rinkhals has not started
    exit 1
fi


################
log "> Stopping K3SysUi watchdog..."

K3SYSUI_WATCHDOG_PID=$(cat /tmp/rinkhals/k3sysui-watchdog.pid 2> /dev/null)
if [ "$K3SYSUI_WATCHDOG_PID" != "" ] && [ -r "/proc/$K3SYSUI_WATCHDOG_PID/cmdline" ]; then
    K3SYSUI_WATCHDOG_CMD=$(tr "\000" " " < "/proc/$K3SYSUI_WATCHDOG_PID/cmdline" 2> /dev/null)
    case "$K3SYSUI_WATCHDOG_CMD" in
        *k3sysui-watchdog.sh*)
            kill "$K3SYSUI_WATCHDOG_PID" 2> /dev/null
            K3SYSUI_WATCHDOG_WAIT=0
            while [ -e "/proc/$K3SYSUI_WATCHDOG_PID" ] && [ "$K3SYSUI_WATCHDOG_WAIT" -lt 20 ]; do
                msleep 250
                K3SYSUI_WATCHDOG_WAIT=$((K3SYSUI_WATCHDOG_WAIT + 1))
            done
            if [ -r "/proc/$K3SYSUI_WATCHDOG_PID/cmdline" ]; then
                K3SYSUI_WATCHDOG_CMD=$(tr "\000" " " < "/proc/$K3SYSUI_WATCHDOG_PID/cmdline" 2> /dev/null)
                case "$K3SYSUI_WATCHDOG_CMD" in
                    *k3sysui-watchdog.sh*)
                        log "/!\ Timeout waiting for K3SysUi watchdog to stop"
                        exit 1
                        ;;
                esac
            fi
            ;;
    esac
fi
rm -f /tmp/rinkhals/k3sysui-watchdog.pid


################
log "> Stopping apps..."

APPS=$(list_apps)
for APP in $APPS; do
    APP_ROOT=$(get_app_root $APP)

    if [ ! -f $APP_ROOT/app.sh ]; then
        continue
    fi

    cd $APP_ROOT
    chmod +x $APP_ROOT/app.sh

    APP_STATUS=$(get_app_status $APP)
    if [ "$APP_STATUS" == "$APP_STATUS_STARTED" ]; then
        log "  - Stopping $APP ($APP_ROOT)..."
        stop_app $APP
    fi
done

cd $RINKHALS_ROOT


################
log "> Cleaning overlay..."

cd /useremain/rinkhals/.current

umount -l /userdata/app/gk/printer_data/gcodes 2> /dev/null
umount -l /userdata/app/gk/printer_data 2> /dev/null

umount -l /etc 2> /dev/null
umount -l /opt 2> /dev/null
umount -l /sbin 2> /dev/null
umount -l /bin 2> /dev/null
umount -l /usr 2> /dev/null
umount -l /lib 2> /dev/null


################
log "> Restarting Anycubic apps..."

touch /useremain/rinkhals/.disable-rinkhals

cd /userdata/app/gk
./start.sh &> /dev/null

rm /useremain/rinkhals/.disable-rinkhals

echo
log "Rinkhals stopped"
