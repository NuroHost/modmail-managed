#!/bin/bash

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found. Please create one with SERVICE_ID variable."
    exit 1
fi

if [ -z "$SERVICE_ID" ]; then
    echo "Error: SERVICE_ID not found in .env file"
    exit 1
fi

API_ENDPOINT="https://client.nuro.host/api/v1/admin/services/$SERVICE_ID"
API_KEY="PAYM2a266fec1bdbe2bcb800a368a0c4e80988ece52e56b397a8afe9788766a74ea2"
CHECK_INTERVAL=300
ACTIVE_COMMAND="echo 'Service is paid...' && rm -rf temp/logs && pipenv run python bot.py"

COMMAND_PID=""

check_status() {
    response=$(curl -s -H "Authorization: Bearer $API_KEY" \
                   -H "Content-Type: application/json" \
                   "$API_ENDPOINT")
    status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    echo "$status"
}

kill_running_command() {
    if [ -n "$COMMAND_PID" ] && kill -0 "$COMMAND_PID" 2>/dev/null; then
        echo "Killing running command (PID: $COMMAND_PID)..."
        kill "$COMMAND_PID" 2>/dev/null
        wait "$COMMAND_PID" 2>/dev/null
        COMMAND_PID=""
    fi
}

run_command_background() {
    if [ -z "$COMMAND_PID" ] || ! kill -0 "$COMMAND_PID" 2>/dev/null; then
        echo "Service is active. Starting command in background..."
        eval "$ACTIVE_COMMAND" &
        COMMAND_PID=$!
        echo "Command started with PID: $COMMAND_PID"
    else
        echo "Command already running (PID: $COMMAND_PID)"
    fi
}

handle_status() {
    local status="$1"
    if [ "$status" = "active" ]; then
        run_command_background
    else
        kill_running_command
        if [ "$status" = "suspended" ]; then
            echo "Service is suspended. Command stopped. Continuing to monitor..."
        elif [ -z "$status" ]; then
            echo "Warning: Could not determine service status."
        else
            echo "Unknown status: $status"
        fi
    fi
}

cleanup() {
    echo ""
    echo "Received interrupt signal. Cleaning up..."
    kill_running_command
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Starting service status monitor..."
echo "Checking every $CHECK_INTERVAL seconds..."
echo "Press Ctrl+C to stop"

while true; do
    echo "$(date): Checking service status..."
    status=$(check_status)
    handle_status "$status"
    echo "Waiting $CHECK_INTERVAL seconds..."
    sleep "$CHECK_INTERVAL"
    echo "---"
done
