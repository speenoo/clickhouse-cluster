#!/bin/bash

# Wait for ClickHouse Keeper to be ready.
# KEEPER_01_HOST and KEEPER_02_HOST are required for the two-node bootstrap.

KEEPER_HOSTS=("$KEEPER_01_HOST" "$KEEPER_02_HOST")

for host in "${KEEPER_HOSTS[@]}"; do
    if [ -z "$host" ]; then
        echo "Missing required Keeper host env var"
        exit 1
    fi
done

echo "Waiting for All ClickHouse Keepers to be ready..."

for host in "${KEEPER_HOSTS[@]}"; do
    echo "Waiting for $host:2181 to be ready"
    
    while true; do
        # First check if the port is open
        if nc -w 1 -z $host 2181; then
            # Now check if the service is actually ready using the 'ruok' command
            if echo "ruok" | nc -w 1 -q 1 $host 2181 | grep -q "imok"; then
                echo "$host:2181 is ready"
                break
            fi
        fi
        
        echo "Still waiting for $host:2181..."
        
        sleep 1
    done
done

echo "All ClickHouse Keepers are ready"

exec /entrypoint.sh
