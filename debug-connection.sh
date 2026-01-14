#!/bin/bash

# Скрипт для проверки подключения и логов

echo "=========================================="
echo "Проверка подключения и логов"
echo "=========================================="
echo "Логи envoy-gateway (последние 50 строк, фильтр по redis):"
kubectl logs -n envoy-gateway -l app.kubernetes.io/instance=envoy-gateway --tail=50 | grep -i redis || echo "⚠️  Логи с упоминанием redis не найдены. Проверьте логи envoy-gateway вручную"
echo ""
echo "Проверка доступности Redis через Service (без TLS):"
kubectl run debug-client --rm -i --restart=Never --image=busybox -- nc -zv redis-standalone1.redis-standalone.svc.cluster.local 6379 || echo "⚠️  Не удалось подключиться к Redis через Service"
echo ""
echo "Примечание: Для проверки TLS-подключения к redis1.apatsev.org.ru:443 выполните вручную:"
echo "  kubectl run redis-client --rm -it --restart=Never --image=redis:alpine -- /bin/sh -c \"redis-cli --tls --insecure -h redis1.apatsev.org.ru -p 443 PING\""

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
