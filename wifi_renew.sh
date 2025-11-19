#!/bin/bash

NMID="wifi"
INTERFACE="wls192"
MAX_RETRIES=5
AUTH_CMD="python3 /root/srun/srun_login.py"
LOG_FILE="/root/change_mac.log"
LOCK_FILE="/var/run/wifi_refresh.lock"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

cleanup() {
    rm -f "$LOCK_FILE"
}

trap cleanup EXIT INT TERM

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another instance is running (PID: $pid)"
            exit 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

check_dependencies() {
    local missing=""
    for cmd in nmcli ip; do
        if ! command -v "$cmd" &>/dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        log_error "Missing commands:$missing"
        return 1
    fi
    
    return 0
}

check_nm_service() {
    if ! systemctl is-active --quiet NetworkManager; then
        log_error "NetworkManager service not running"
        return 1
    fi
    return 0
}

check_interface_exists() {
    if [ ! -d "/sys/class/net/$INTERFACE" ]; then
        log_error "Interface $INTERFACE not found"
        return 1
    fi
    return 0
}

enable_interface() {
    local state=$(ip link show "$INTERFACE" 2>/dev/null | grep -oP 'state \K\w+')
    if [ "$state" != "UP" ] && [ "$state" != "UNKNOWN" ]; then
        log_message "Bringing up interface (current: $state)..."
        local up_output=$(ip link set "$INTERFACE" up 2>&1)
        if [ $? -ne 0 ]; then
            log_error "Failed to bring up interface | $up_output"
            return 1
        fi
        sleep 2
    fi
    
    local nm_state=$(nmcli -t -f GENERAL.STATE device show "$INTERFACE" 2>/dev/null | cut -d: -f2)
    if [ "$nm_state" == "unavailable" ] || [ "$nm_state" == "unmanaged" ]; then
        log_error "Device is $nm_state in NetworkManager"
        return 1
    fi
    
    return 0
}

check_connection_exists() {
    if ! nmcli connection show "$NMID" &>/dev/null; then
        log_error "Connection '$NMID' not found"
        return 1
    fi
    return 0
}

wait_for_connection() {
    local timeout=30
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local conn_state=$(nmcli -t -f GENERAL.STATE con show "$NMID" 2>/dev/null | cut -d: -f2)
        local dev_state=$(nmcli -t -f GENERAL.STATE device show "$INTERFACE" 2>/dev/null | cut -d: -f2)
        
        if [ "$conn_state" == "activated" ] || [ "$dev_state" == "connected" ] || [ "$dev_state" == "100" ]; then
            return 0
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    local final_conn_state=$(nmcli -t -f GENERAL.STATE con show "$NMID" 2>/dev/null | cut -d: -f2)
    local final_dev_state=$(nmcli -t -f GENERAL.STATE device show "$INTERFACE" 2>/dev/null | cut -d: -f2)
    log_error "Connection timeout | conn_state: ${final_conn_state:-unknown} | dev_state: ${final_dev_state:-unknown}"
    return 1
}

authenticate_network() {
    local output
    local exit_code
    
    if command -v timeout &>/dev/null; then
        output=$(timeout 60 $AUTH_CMD 2>&1)
        exit_code=$?
        
        if [ $exit_code -eq 124 ]; then
            log_error "Auth timeout"
            return 1
        fi
    else
        output=$($AUTH_CMD 2>&1)
        exit_code=$?
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_message "✓ Auth successful"
        return 0
    else
        log_error "Auth failed (exit: $exit_code)"
        if [ -n "$output" ]; then
            echo "$output" | head -n3 | while IFS= read -r line; do
                log_error "  $line"
            done
        fi
        return 1
    fi
}

refresh_connection() {
    local attempt=$1
    
    log_message "--- Attempt $attempt/$MAX_RETRIES ---"
    
    if ! enable_interface; then
        return 1
    fi
    
    local current_state=$(nmcli -t -f GENERAL.STATE device show "$INTERFACE" 2>/dev/null | cut -d: -f2)
    if [ "$current_state" == "connected" ] || [ "$current_state" == "100" ]; then
        log_message "Disconnecting..."
        local down_output=$(nmcli connection down "$NMID" 2>&1)
        local down_code=$?
        if [ $down_code -ne 0 ]; then
            log_error "Disconnect failed (exit: $down_code) | $down_output"
        fi
        sleep 3
    fi
    
    log_message "Connecting..."
    local up_output=$(nmcli connection up "$NMID" 2>&1)
    local up_code=$?
    
    if [ $up_code -ne 0 ]; then
        log_error "Connection up failed (exit: $up_code)"
        local error_msg=$(echo "$up_output" | head -n1)
        if [ -n "$error_msg" ]; then
            log_error "$error_msg"
        fi
        return 1
    fi
    
    if ! wait_for_connection; then
        return 1
    fi
    
    local new_mac=$(ip link show "$INTERFACE" 2>/dev/null | grep link/ether | awk '{print $2}')
    local new_ip=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    
    if [ -z "$new_mac" ] || [ -z "$new_ip" ]; then
        log_error "Failed to get network info"
        return 1
    fi
    
    log_message "✓ Connected | MAC: $new_mac | IP: $new_ip"
    
    if ! authenticate_network; then
        return 1
    fi
    
    return 0
}

main() {
    log_message "=== WiFi Refresh Started ==="
    
    check_lock
    
    if ! check_dependencies; then
        exit 1
    fi
    
    if ! check_nm_service; then
        exit 1
    fi
    
    if ! check_interface_exists; then
        exit 1
    fi
    
    if ! check_connection_exists; then
        exit 1
    fi
    
    for i in $(seq 1 $MAX_RETRIES); do
        if refresh_connection $i; then
            log_message "=== Completed Successfully ==="
            exit 0
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            local wait_time=$((10 + i * 5))
            log_message "Retry in ${wait_time}s..."
            sleep $wait_time
        fi
    done
    
    log_error "All attempts failed"
    exit 1
}

main