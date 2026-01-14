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
echo "Статус pods cert-manager:"
kubectl get pods -n cert-manager -o wide || echo "⚠️  Не удалось получить статус pods"
echo ""
echo "CRDs cert-manager:"
kubectl get crds | grep cert-manager || echo "⚠️  CRDs cert-manager не найдены"

echo ""
echo "=========================================="
echo "Проверка ClusterIssuer"
echo "=========================================="
echo "Список всех ClusterIssuer:"
kubectl get clusterissuer || echo "⚠️  ClusterIssuer не найдены"
echo ""
echo "Описание ClusterIssuer yc-clusterissuer:"
kubectl describe clusterissuer yc-clusterissuer || echo "⚠️  ClusterIssuer yc-clusterissuer не найден"
echo ""
echo "Полный YAML ClusterIssuer:"
kubectl get clusterissuer yc-clusterissuer -o yaml || echo "⚠️  Не удалось получить ClusterIssuer"
echo ""
echo "Статус ClusterIssuer:"
kubectl get clusterissuer yc-clusterissuer -o jsonpath='{.status}' && echo || echo "⚠️  Не удалось получить статус ClusterIssuer"
echo ""
echo "Условия (conditions) ClusterIssuer:"
kubectl get clusterissuer yc-clusterissuer -o jsonpath='{.status.conditions[*]}' && echo || echo "⚠️  Условия не найдены"

echo ""
echo "=========================================="
echo "Проверка Issuer ресурсов"
echo "=========================================="
echo "Список всех Issuer во всех namespace'ах:"
kubectl get issuer --all-namespaces || echo "⚠️  Issuer не найдены"

echo ""
echo "=========================================="
echo "Проверка Certificate ресурсов"
echo "=========================================="
echo "Список всех Certificate во всех namespace'ах:"
kubectl get certificate --all-namespaces || echo "⚠️  Certificate не найдены"
echo ""
echo "Детальная информация о Certificate wildcard-certificate:"
for ns in envoy-gateway redis-standalone default; do
  echo "--- Проверка в namespace: $ns ---"
  kubectl get certificate wildcard-certificate -n "$ns" 2>/dev/null && {
    echo "Описание Certificate:"
    kubectl describe certificate wildcard-certificate -n "$ns" 2>/dev/null || true
    echo ""
    echo "Статус Certificate:"
    kubectl get certificate wildcard-certificate -n "$ns" -o jsonpath='{.status}' && echo || true
    echo ""
    echo "Условия (conditions) Certificate:"
    kubectl get certificate wildcard-certificate -n "$ns" -o jsonpath='{.status.conditions[*]}' && echo || true
    echo ""
  } || echo "Certificate wildcard-certificate не найден в namespace $ns"
done

echo ""
echo "=========================================="
echo "Проверка CertificateRequest ресурсов"
echo "=========================================="
echo "Список всех CertificateRequest во всех namespace'ах:"
kubectl get certificaterequest --all-namespaces || echo "⚠️  CertificateRequest не найдены"
echo ""
echo "Детальная информация о CertificateRequest:"
for ns in envoy-gateway redis-standalone default; do
  echo "--- Проверка в namespace: $ns ---"
  crs=$(kubectl get certificaterequest -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  if [ -n "$crs" ]; then
    for cr in $crs; do
      echo "CertificateRequest: $cr"
      kubectl describe certificaterequest "$cr" -n "$ns" 2>/dev/null || true
      echo ""
      echo "Статус CertificateRequest $cr:"
      kubectl get certificaterequest "$cr" -n "$ns" -o jsonpath='{.status}' && echo || true
      echo ""
      echo "Условия (conditions) CertificateRequest $cr:"
      kubectl get certificaterequest "$cr" -n "$ns" -o jsonpath='{.status.conditions[*]}' && echo || true
      echo ""
    done
  else
    echo "CertificateRequest не найдены в namespace $ns"
  fi
done

echo ""
echo "=========================================="
echo "Проверка Secrets связанных с сертификатами"
echo "=========================================="
for ns in envoy-gateway redis-standalone default; do
  echo "--- Проверка в namespace: $ns ---"
  echo "Secret wildcard-tls-cert:"
  kubectl get secret wildcard-tls-cert -n "$ns" 2>/dev/null && {
    echo "Тип secret:"
    kubectl get secret wildcard-tls-cert -n "$ns" -o jsonpath='{.type}' && echo || true
    echo ""
    echo "Ключи в secret:"
    kubectl get secret wildcard-tls-cert -n "$ns" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || kubectl get secret wildcard-tls-cert -n "$ns" -o jsonpath='{.data}' || true
  } || echo "Secret wildcard-tls-cert не найден в namespace $ns"
  echo ""
done

echo ""
echo "=========================================="
echo "Проверка событий (Events)"
echo "=========================================="
echo "События в namespace cert-manager:"
kubectl get events -n cert-manager --sort-by='.lastTimestamp' | tail -20 || echo "⚠️  Не удалось получить события"
echo ""
echo "События связанные с Certificate:"
for ns in envoy-gateway redis-standalone default; do
  echo "--- События в namespace: $ns ---"
  kubectl get events -n "$ns" --field-selector involvedObject.kind=Certificate --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "События не найдены"
done

echo ""
echo "=========================================="
echo "Проверка логов cert-manager"
echo "=========================================="
echo "Логи cert-manager-controller (последние 30 строк):"
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=30 2>/dev/null || echo "⚠️  Не удалось получить логи"
echo ""
echo "Логи cert-manager-webhook (последние 20 строк):"
kubectl logs -n cert-manager -l app.kubernetes.io/name=webhook --tail=20 2>/dev/null || echo "⚠️  Не удалось получить логи webhook"
echo ""
echo "Логи cert-manager-cainjector (последние 20 строк):"
kubectl logs -n cert-manager -l app.kubernetes.io/name=cainjector --tail=20 2>/dev/null || echo "⚠️  Не удалось получить логи cainjector"

echo ""
echo "=========================================="
echo "Проверка завершена"
echo "=========================================="
