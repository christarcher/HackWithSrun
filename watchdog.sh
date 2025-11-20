#!/bin/bash

current_time=$(date +%H%M)

# 2:50-3:10之间跳过执行, 避免和更新mac脚本冲突
if [ "$current_time" -ge 0250 ] && [ "$current_time" -le 0310 ]; then
    exit 0
fi

TARGET_HOST="8.8.8.8"
MAX_PING_COUNT=5
PING_TIMEOUT=3
FAILURE_SCRIPT="/root/wifi_renew.sh"
LOG_FILE="/root/watchdog.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

do_ping() {
    ping -c 1 -W "$PING_TIMEOUT" "$1" &>/dev/null
    return $?
}

# ==================== Main ====================
success=0

for ((i=1; i<=MAX_PING_COUNT; i++)); do
    if do_ping "$TARGET_HOST"; then
        success=1
        break
    fi
    [ $i -lt $MAX_PING_COUNT ] && sleep 1
done

if [ $success -eq 1 ]; then
    log_message "Network OK: $TARGET_HOST"
    exit 0
else
    log_error "Network failed: $TARGET_HOST unreachable after $MAX_PING_COUNT attempts"
    
    if [ -f "$FAILURE_SCRIPT" ] && [ -x "$FAILURE_SCRIPT" ]; then
        log_message "Executing failure script: $FAILURE_SCRIPT"
        "$FAILURE_SCRIPT"
    else
        log_error "Failure script not found or not executable: $FAILURE_SCRIPT"
    fi
    
    exit 1
fi