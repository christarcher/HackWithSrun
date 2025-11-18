#!/bin/bash

NMID="starbucks-hacker"
INTERFACE="wls192"
MAX_RETRIES=3
LOG_FILE="/root/wifi-refresh.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

wait_for_connection() {
    local timeout=30
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if nmcli -t -f GENERAL.STATE device show "$INTERFACE" | grep -q "connected"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

refresh_connection() {
    local attempt=$1
    
    log_message "Attempt $attempt of $MAX_RETRIES"
    
    nmcli connection down "$NMID" &>/dev/null
    sleep 3
    
    if nmcli connection up "$NMID" &>/dev/null; then
        if wait_for_connection; then
            NEW_MAC=$(ip link show "$INTERFACE" | grep link/ether | awk '{print $2}')
            NEW_IP=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}')
            log_message "✓ Success - MAC: $NEW_MAC, IP: $NEW_IP"
            return 0
        fi
    fi
    
    log_message "✗ Failed to reconnect"
    return 1
}

main() {
    log_message "=== WiFi MAC Refresh Started ==="
    
    for i in $(seq 1 $MAX_RETRIES); do
        if refresh_connection $i; then
            log_message "=== Refresh Completed Successfully ===\n"
            exit 0
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            log_message "Waiting 10 seconds before retry..."
            sleep 10
        fi
    done
    
    log_message "✗✗✗ All attempts failed ✗✗✗\n"
    exit 1
}

main