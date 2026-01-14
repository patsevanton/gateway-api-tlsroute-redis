#!/bin/bash

# Скрипт для проверки cert-manager и ClusterIssuer

echo "=========================================="
echo "Проверка установки cert-manager"
echo "=========================================="
echo "Helm releases в namespace cert-manager:"
helm list -n cert-manager || echo "⚠️  Не удалось получить список Helm releases"
echo ""
echo "Pods в namespace cert-manager:"
kubectl get pods -n cert-manager || echo "⚠️  Namespace cert-manager не найден"
echo ""
echo "CRDs cert-manager:"
kubectl get crds | grep cert-manager || echo "⚠️  CRDs cert-manager не найдены"

echo ""
echo "=========================================="
echo "Проверка ClusterIssuer"
echo "=========================================="
kubectl describe clusterissuer yc-clusterissuer || echo "⚠️  ClusterIssuer yc-clusterissuer не найден"
echo ""
kubectl get clusterissuer yc-clusterissuer -o yaml | grep -A 5 "status:" || echo "⚠️  Не удалось получить статус ClusterIssuer"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
