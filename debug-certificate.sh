#!/bin/bash

# Скрипт для проверки сертификата

echo "=========================================="
echo "Проверка сертификата"
echo "=========================================="
echo "Certificates в namespace redis-standalone:"
kubectl get certificate -n redis-standalone || echo "⚠️  Certificates не найдены"
echo ""
echo "Описание сертификата:"
kubectl describe certificate wildcard-certificate -n redis-standalone || echo "⚠️  Сертификат wildcard-certificate не найден"
echo ""
echo "CertificateRequests:"
kubectl get certificaterequest -n redis-standalone || echo "⚠️  CertificateRequests не найдены"
echo ""
echo "Secret wildcard-tls-cert:"
kubectl get secret wildcard-tls-cert -n redis-standalone || echo "⚠️  Secret wildcard-tls-cert не найден"
echo ""
echo "Статус сертификата:"
kubectl get certificate wildcard-certificate -n redis-standalone -o jsonpath='{.status.conditions[*].type}' && echo || echo "⚠️  Не удалось получить статус сертификата"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
