#!/bin/bash

# Wait for ClickHouse to be ready

CLICKHOUSE_HOSTS=("$CLICKHOUSE_01_01_HOST" "$CLICKHOUSE_01_02_HOST")

for host in "${CLICKHOUSE_HOSTS[@]}"; do
    if [ -z "$host" ]; then
        echo "Missing required ClickHouse host env var"
        exit 1
    fi
done

echo "Waiting for All ClickHouse Instances to be ready..."

for host in "${CLICKHOUSE_HOSTS[@]}"; do
    echo "Waiting for $host:8123 to be ready"
    
    while true; do
        # First check if the port is open
        if nc -w 1 -z $host 8123; then
            # Now check if the service is actually ready using the replicas_status endpoint
            http_status=$(curl --max-time 1 -s -o /dev/null -w "%{http_code}" "http://$host:8123/replicas_status")
            if [ "$http_status" -eq 200 ]; then
                echo "$host:8123 is ready"
                break
            fi
        fi
        
        echo "Still waiting for $host:8123..."
        sleep 1
    done
done

echo "All ClickHouse Instances are ready"

exec haproxy -f haproxy.cfg
