#!/bin/bash

# Скрипт для проверки всех компонентов установки
# Собран из команд Debug из README.md

set -e

echo "=========================================="
echo "Проверка установки компонентов"
echo "=========================================="

# 1. Проверка key.json
echo ""
echo "1. Проверка key.json"
echo "----------------------------------------"
if [ -f "key.json" ]; then
    echo "Файл key.json существует"
    cat key.json | jq -r '.service_account_id'
else
    echo "⚠️  Файл key.json не найден"
fi

# 2. Проверка cert-manager
echo ""
echo "2. Проверка установки cert-manager"
echo "----------------------------------------"
echo "Helm releases в namespace cert-manager:"
helm list -n cert-manager || echo "⚠️  Не удалось получить список Helm releases"
echo ""
echo "Pods в namespace cert-manager:"
kubectl get pods -n cert-manager || echo "⚠️  Namespace cert-manager не найден"
echo ""
echo "CRDs cert-manager:"
kubectl get crds | grep cert-manager || echo "⚠️  CRDs cert-manager не найдены"

# 3. Проверка ClusterIssuer
echo ""
echo "3. Проверка ClusterIssuer"
echo "----------------------------------------"
kubectl describe clusterissuer yc-clusterissuer || echo "⚠️  ClusterIssuer yc-clusterissuer не найден"
echo ""
kubectl get clusterissuer yc-clusterissuer -o yaml | grep -A 5 "status:" || echo "⚠️  Не удалось получить статус ClusterIssuer"

# 4. Проверка Helm репозитория Redis оператора
echo ""
echo "4. Проверка Helm репозитория Redis оператора"
echo "----------------------------------------"
helm repo update ot-helm || echo "⚠️  Репозиторий ot-helm не найден"

# 5. Проверка установки Redis оператора
echo ""
echo "5. Проверка установки Redis оператора"
echo "----------------------------------------"
echo "Helm releases в namespace ot-operators:"
helm list -n ot-operators || echo "⚠️  Namespace ot-operators не найден"
echo ""
echo "Deployments в namespace ot-operators:"
kubectl get deployment -n ot-operators || echo "⚠️  Deployments не найдены"
echo ""
echo "CRDs Redis:"
kubectl get crds | grep redis || echo "⚠️  CRDs Redis не найдены"

# 6. Проверка подов Redis оператора
echo ""
echo "6. Проверка подов Redis оператора"
echo "----------------------------------------"
echo "Pods с redis в namespace ot-operators:"
kubectl get pods -n ot-operators | grep redis || echo "⚠️  Pods Redis оператора не найдены"
echo ""
echo "Детальная информация о подах Redis оператора:"
kubectl get pods -n ot-operators -l app.kubernetes.io/name=redis-operator || echo "⚠️  Pods с label app.kubernetes.io/name=redis-operator не найдены"
echo ""
echo "Логи Redis оператора (последние 20 строк):"
kubectl logs -n ot-operators -l app.kubernetes.io/name=redis-operator --tail=20 || echo "⚠️  Не удалось получить логи"

# 7. Проверка Redis standalone
echo ""
echo "7. Проверка Redis standalone"
echo "----------------------------------------"
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

# 8. Проверка сертификата
echo ""
echo "8. Проверка сертификата"
echo "----------------------------------------"
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

# 9. Проверка GatewayClass
echo ""
echo "9. Проверка GatewayClass"
echo "----------------------------------------"
echo "GatewayClass:"
kubectl get gatewayclass || echo "⚠️  GatewayClass не найдены"
echo ""
echo "Описание GatewayClass envoy:"
kubectl describe gatewayclass envoy || echo "⚠️  GatewayClass envoy не найден"

# 10. Проверка Gateway
echo ""
echo "10. Проверка Gateway"
echo "----------------------------------------"
echo "Gateways в namespace envoy-gateway:"
kubectl get gateway -n envoy-gateway || echo "⚠️  Namespace envoy-gateway не найден или Gateways отсутствуют"
echo ""
echo "Описание Gateway redis-gateway:"
kubectl describe gateway redis-gateway -n envoy-gateway || echo "⚠️  Gateway redis-gateway не найден"
echo ""
echo "Адрес Gateway:"
kubectl get gateway redis-gateway -n envoy-gateway -o jsonpath='{.status.addresses[*].value}' && echo || echo "⚠️  Адрес Gateway не назначен"
echo ""
echo "Services envoy-gateway:"
kubectl get svc -n envoy-gateway | grep envoy || echo "⚠️  Services envoy-gateway не найдены"

# 11. Проверка ReferenceGrant
echo ""
echo "11. Проверка ReferenceGrant"
echo "----------------------------------------"
echo "ReferenceGrants в namespace redis-standalone:"
kubectl get referencegrant -n redis-standalone || echo "⚠️  ReferenceGrants не найдены"
echo ""
echo "Описание ReferenceGrant allow-gateway-to-cert:"
kubectl describe referencegrant allow-gateway-to-cert -n redis-standalone || echo "⚠️  ReferenceGrant allow-gateway-to-cert не найден"

# 12. Проверка TLSRoute
echo ""
echo "12. Проверка TLSRoute"
echo "----------------------------------------"
echo "TLSRoutes в namespace redis-standalone:"
kubectl get tlsroute -n redis-standalone || echo "⚠️  TLSRoutes не найдены"
echo ""
echo "Описание TLSRoute:"
kubectl describe tlsroute redis-cluster-1-route -n redis-standalone || echo "⚠️  TLSRoute redis-cluster-1-route не найден"
echo ""
echo "Статус TLSRoute:"
kubectl get tlsroute redis-cluster-1-route -n redis-standalone -o jsonpath='{.status.parents[*].conditions[*].type}' && echo || echo "⚠️  Не удалось получить статус TLSRoute"
echo ""
echo "Listeners Gateway:"
kubectl get gateway redis-gateway -n envoy-gateway -o yaml | grep -A 10 "listeners:" || echo "⚠️  Не удалось получить информацию о listeners"

# 12. Проверка подключения
echo ""
echo "12. Проверка подключения и логов"
echo "----------------------------------------"
echo "Логи envoy-gateway (последние 50 строк, фильтр по redis):"
kubectl logs -n envoy-gateway -l app.kubernetes.io/name=envoy-gateway --tail=50 | grep -i redis || echo "⚠️  Логи с упоминанием redis не найдены. Проверьте логи envoy-gateway вручную"
echo ""
echo "Проверка доступности Redis через Service (без TLS):"
kubectl run debug-client --rm -i --restart=Never --image=busybox -- nc -zv redis-standalone1.redis-standalone.svc.cluster.local 6379 || echo "⚠️  Не удалось подключиться к Redis через Service"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
