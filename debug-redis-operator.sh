#!/bin/bash

# Скрипт для проверки Redis оператора

echo "=========================================="
echo "Проверка Helm репозитория Redis оператора"
echo "=========================================="
helm repo update ot-helm || echo "⚠️  Репозиторий ot-helm не найден"

echo ""
echo "=========================================="
echo "Проверка установки Redis оператора"
echo "=========================================="
echo "Helm releases в namespace ot-operators:"
helm list -n ot-operators || echo "⚠️  Namespace ot-operators не найден"
echo ""
echo "Deployments в namespace ot-operators:"
kubectl get deployment -n ot-operators || echo "⚠️  Deployments не найдены"
echo ""
echo "CRDs Redis:"
kubectl get crds | grep redis || echo "⚠️  CRDs Redis не найдены"

echo ""
echo "=========================================="
echo "Проверка подов Redis оператора"
echo "=========================================="
echo "Pods с redis в namespace ot-operators:"
kubectl get pods -n ot-operators | grep redis || echo "⚠️  Pods Redis оператора не найдены"
echo ""
echo "Детальная информация о подах Redis оператора:"
kubectl get pods -n ot-operators -l name=redis-operator || echo "⚠️  Pods с label name=redis-operator не найдены"
echo ""
echo "Логи Redis оператора (последние 20 строк):"
kubectl logs -n ot-operators -l name=redis-operator --tail=20 || echo "⚠️  Не удалось получить логи"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
