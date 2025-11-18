#!/bin/bash

NMID="starbucks-hacker"
INTERFACE="wls192"
MAX_RETRIES=5
AUTH_SCRIPT="wifi-auth.py"
LOG_FILE="/root/wifi-refresh.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

wait_for_connection() {
    local timeout=30
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if nmcli -t -f GENERAL.STATE device show "$INTERFACE" 2>/dev/null | grep -q "connected"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

authenticate_network() {
    log_message "Authenticating..."
    
    local output
    output=$(python3 "$AUTH_SCRIPT" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_message "✓ Auth successful"
        return 0
    else
        log_message "✗ Auth failed (code: $exit_code)"
        [ -n "$output" ] && echo "$output" | head -n2 >> "$LOG_FILE"
        return 1
    fi
}

refresh_connection() {
    local attempt=$1
    
    log_message "Attempt $attempt/$MAX_RETRIES"
    
    if ! nmcli connection down "$NMID" 2>&1 | grep -i "error" >> "$LOG_FILE"; then
        sleep 3
    else
        log_message "✗ Down failed"
        return 1
    fi
    
    local output
    output=$(nmcli connection up "$NMID" 2>&1)
    if [ $? -ne 0 ]; then
        log_message "✗ Up failed: $(echo "$output" | head -n1)"
        return 1
    fi
    
    if ! wait_for_connection; then
        log_message "✗ Connection timeout"
        return 1
    fi
    
    NEW_MAC=$(ip link show "$INTERFACE" 2>/dev/null | grep link/ether | awk '{print $2}')
    NEW_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep inet | awk '{print $2}')
    log_message "✓ Connected - MAC: $NEW_MAC, IP: $NEW_IP"
    
    # 网络认证
    if ! authenticate_network; then
        return 1
    fi
    
    return 0
}

main() {
    if [ ! -f "$AUTH_SCRIPT" ]; then
        log_message "✗ Auth script not found: $AUTH_SCRIPT"
        exit 1
    fi
    
    log_message "=== WiFi Refresh Started ==="
    
    for i in $(seq 1 $MAX_RETRIES); do
        if refresh_connection $i; then
            log_message "=== Completed ===\n"
            exit 0
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            log_message "Retrying in 10s..."
            sleep 10
        fi
    done
    
    log_message "✗✗✗ All attempts failed ✗✗✗\n"
    exit 1
}

main