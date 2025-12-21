#!/bin/bash

NGINX_IP="158.160.108.15"  # замените на ваш IP
LOG_COUNT=100
PARALLEL=10

echo "Отправляем $LOG_COUNT логов ($((LOG_COUNT/PARALLEL)) на поток) на $NGINX_IP..."

for i in $(seq 1 $PARALLEL); do
  (
    for j in $(seq 1 $((LOG_COUNT/PARALLEL))); do
      curl -s -X POST "http://$NGINX_IP/write_log" \
        -d "{\"log\":\"test-log-$i-$j\",\"timestamp\":\"$(date -Iseconds)\"}" &
    done
    wait
  ) &
done

