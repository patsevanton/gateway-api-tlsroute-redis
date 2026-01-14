#!/bin/bash

# Скрипт для проверки Redis standalone

echo "=========================================="
echo "Проверка Redis standalone"
echo "=========================================="
echo "Redis ресурсы в namespace redis-standalone:"
kubectl get redis -n redis-standalone || echo "⚠️  Namespace redis-standalone не найден или ресурсы Redis отсутствуют"
echo ""
echo "Pods в namespace redis-standalone:"
kubectl get pods -n redis-standalone || echo "⚠️  Pods не найдены"
echo ""
echo "Services в namespace redis-standalone:"
kubectl get svc -n redis-standalone || echo "⚠️  Services не найдены"
echo ""
echo "Описание Redis (последние 20 строк):"
kubectl describe redis redis-standalone1 -n redis-standalone | tail -20 || echo "⚠️  Не удалось получить описание Redis"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
