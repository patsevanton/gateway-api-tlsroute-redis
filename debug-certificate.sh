#!/bin/bash

# Скрипт для проверки сертификата

echo "=========================================="
echo "Проверка сертификата"
echo "=========================================="
echo "Certificates в namespace envoy-gateway:"
kubectl get certificate -n envoy-gateway || echo "⚠️  Certificates не найдены"
echo ""
echo "Описание сертификата:"
kubectl describe certificate wildcard-certificate -n envoy-gateway || echo "⚠️  Сертификат wildcard-certificate не найден"
echo ""
echo "CertificateRequests:"
kubectl get certificaterequest -n envoy-gateway || echo "⚠️  CertificateRequests не найдены"
echo ""
echo "Secret wildcard-tls-cert:"
kubectl get secret wildcard-tls-cert -n envoy-gateway || echo "⚠️  Secret wildcard-tls-cert не найден"
echo ""
echo "Статус сертификата:"
kubectl get certificate wildcard-certificate -n envoy-gateway -o jsonpath='{.status.conditions[*].type}' && echo || echo "⚠️  Не удалось получить статус сертификата"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
