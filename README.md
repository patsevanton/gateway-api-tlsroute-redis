# Маршрутизация трафика к Redis в другом k8s через один LB используя TLSRoute

## Цель статьи
Показать, как осуществить маршрутизацию трафика к кластеру Redis, расположенному в другом Kubernetes-кластере, через один LoadBalancer. Решение предполагает терминацию TLS-соединений в `envoy-gateway` и проксирование незашифрованного TCP-трафика к Redis без TLS.

### Какие задачи решаем
- Managed-сервисы требуют существенных затрат, тогда как stateful-сервисы позволяют использовать собственные кластеры с контролем затрат.
- Размещение stateful-сервисов в том же кластере ограничивает возможности обновления операторов и самих сервисов, поэтому стоит вынести их в отдельный кластер.

## 1. Установка кластера Kubernetes

```bash
terraform apply -auto-approve
yc managed-kubernetes cluster get-credentials --id id-кластера-k8s --external --force
```

### 1. Установка cert-manager с Yandex Cloud DNS ACME webhook

Для работы с wildcard-сертификатами через DNS-01 challenge установите webhook для Yandex Cloud DNS (webhook также устанавливает cert-manager):


# Получаем ключ сервисного аккаунта из Terraform output
```bash
terraform output -raw dns_manager_service_account_key | python3 -m json.tool | grep -v description | grep -v encrypted_private_key | grep -v format | grep -v key_fingerprint | grep -v pgp_key > key.json
```

# Debug: проверяем созданный файл
```
cat key.json | jq -r '.service_account_id'
```

```
helm upgrade --install \
  cert-manager-webhook-yandex \
  oci://cr.yandex/yc-marketplace/yandex-cloud/cert-manager-webhook-yandex/cert-manager-webhook-yandex \
  --version 1.0.9 \
  --namespace cert-manager \
  --create-namespace \
  --set-file config.auth.json=key.json \
  --set config.email='my-email@mycompany.com' \
  --set config.folder_id='b1g972v94kscfi3qmfmh' \
  --set config.server='https://acme-v02.api.letsencrypt.org/directory'
```

# Debug: проверяем установку cert-manager
```bash
helm list -n cert-manager
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
```

### Проверка установки ClusterIssuer
Проверяем, что ClusterIssuer `yc-clusterissuer` успешно создан:

```bash
kubectl describe clusterissuer yc-clusterissuer
kubectl get clusterissuer yc-clusterissuer -o yaml | grep -A 5 "status:"
```

**Примечание:** 
- Замените `<адрес_электронной_почты_для_уведомлений_от_Lets_Encrypt>` на ваш email адрес.
- Замените `<идентификатор_каталога_с_зоной_Cloud_DNS>` на folder_id (можно получить через `terraform output -raw folder_id`).
- Файл `key.json` должен содержать ключ сервисного аккаунта с ролью `dns.editor` (создаётся через Terraform, см. раздел 1.1).
- При установке автоматически создаётся ClusterIssuer с именем `yc-clusterissuer`, который можно использовать вместо создания собственного (см. раздел 1.3).


## 2. Развертывание Redis-оператора (рекомендуемый способ)
### Добавление репозитория Helm
```bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
# Debug: проверяем добавленный репозиторий
helm repo update ot-helm
```

### Установка Redis-оператора
```bash
helm upgrade --install redis-operator ot-helm/redis-operator \
  --create-namespace --namespace ot-operators --wait --version 0.22.2
# Debug: проверяем установку оператора
helm list -n ot-operators
kubectl get deployment -n ot-operators
kubectl get crds | grep redis
```

### Проверка установки
```bash
kubectl get pods -n ot-operators | grep redis
# Debug: детальная информация о подах
kubectl get pods -n ot-operators -l name=redis-operator
kubectl logs -n ot-operators -l name=redis-operator --tail=20
```

## 3. Развёртывание standalone-Redis через YAML-манифест
Создаём манифест с экземпляром Redis:

```bash
cat <<EOF > redis-standalone.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: redis-standalone
---
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: redis-standalone1
  namespace: redis-standalone
spec:
  podSecurityContext:
    runAsUser: 1000
    fsGroup: 1000
  kubernetesConfig:
    image: quay.io/opstree/redis:v7.0.12
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
EOF
```

### Применение манифеста
Redis-оператор автоматически создаёт Service-ресурс `redis-standalone1`, который открывает порт 6379. TLSRoute в дальнейшем будет ссылаться на этот сервис, чтобы пробросить трафик от Envoy к экземпляру.
```bash
kubectl apply -f redis-standalone.yaml
# Debug: проверяем созданные ресурсы
kubectl get redis -n redis-standalone
kubectl get pods -n redis-standalone
kubectl get svc -n redis-standalone
kubectl describe redis redis-standalone1 -n redis-standalone | tail -20
```

## 4. Установка envoy-gateway
Развёртывание проходит через Terraform, в котором задаётся IP для LoadBalancer. Фрагмент модуля:

```hcl
resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.6.2"
  namespace        = "envoy-gateway"
  create_namespace = true
  depends_on       = [yandex_kubernetes_node_group.k8s_node_group_cilium_redis]

  set = [
    {
      name  = "service.type"
      value = "LoadBalancer"
    },
    {
      name  = "service.loadBalancerIP"
      value = yandex_vpc_address.addr.external_ipv4_address[0].address
    }
  ]
}
```


## 5. Создание TLS-сертификата для Redis

**Важно:** Для wildcard-сертификатов (`*.apatsev.org.ru`) используется DNS-01 challenge через Yandex Cloud DNS ACME webhook, который был настроен в разделе 1. Webhook автоматически создаст необходимые TXT-записи в DNS-зоне для прохождения ACME challenge.

Создаём один wildcard-сертификат для всех поддоменов `*.apatsev.org.ru`:

```bash
cat <<EOF > wildcard-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-certificate
  namespace: redis-standalone
spec:
  secretName: wildcard-tls-cert
  issuerRef:
    name: yc-clusterissuer
    kind: ClusterIssuer
  duration: 720h
  renewBefore: 360h
  dnsNames:
  - "*.apatsev.org.ru"
EOF
```

```bash
kubectl apply -f wildcard-certificate.yaml
# Debug: проверяем создание сертификата
kubectl get certificate -n redis-standalone
kubectl describe certificate wildcard-certificate -n redis-standalone
kubectl get certificaterequest -n redis-standalone
kubectl get secret wildcard-tls-cert -n redis-standalone
# Проверяем статус сертификата (может занять время)
kubectl get certificate wildcard-certificate -n redis-standalone -o jsonpath='{.status.conditions[*].type}' && echo
```

## 6. Настройка TLSRoute и Gateway
### ReferenceGrant

**Важно:** Gateway API требует создания ReferenceGrant для кросс‑неймспейсных ссылок на ресурсы. Поскольку Gateway в пространстве имён `envoy-gateway` ссылается на Secret `wildcard-tls-cert` в пространстве имён `redis-standalone`, необходимо создать ReferenceGrant в пространстве имён `redis-standalone`, который разрешает эту ссылку.

```bash
cat <<EOF > referencegrant.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-to-cert
  namespace: redis-standalone
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: envoy-gateway
  to:
  - group: ""
    kind: Secret
    name: wildcard-tls-cert
EOF
```

```bash
kubectl apply -f referencegrant.yaml
# Debug: проверяем ReferenceGrant
kubectl get referencegrant -n redis-standalone
kubectl describe referencegrant allow-gateway-to-cert -n redis-standalone
```

### GatewayClass
```bash
cat <<EOF > gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
```

```bash
kubectl apply -f gatewayclass.yaml
# Debug: проверяем GatewayClass
kubectl get gatewayclass
kubectl describe gatewayclass envoy
```

### Gateway
```bash
cat <<EOF > gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: redis-gateway
  namespace: envoy-gateway
spec:
  gatewayClassName: envoy
  listeners:
    - name: redis-cluster-1
      protocol: TLS
      port: 443
      hostname: "redis1.apatsev.org.ru"
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-tls-cert
            namespace: redis-standalone
      allowedRoutes:
        namespaces:
          from: All
EOF
```

```bash
kubectl apply -f gateway.yaml
# Debug: проверяем Gateway и его статус
kubectl get gateway -n envoy-gateway
kubectl describe gateway redis-gateway -n envoy-gateway
kubectl get gateway redis-gateway -n envoy-gateway -o jsonpath='{.status.addresses[*].value}' && echo
# Проверяем адрес LoadBalancer
kubectl get svc -n envoy-gateway | grep envoy
# Важно: Если Gateway был создан до ReferenceGrant, может потребоваться пересоздать Gateway:
# kubectl delete -f gateway.yaml && kubectl apply -f gateway.yaml
```

### TLSRoute
Маршрут должен быть объявлен в том же пространстве имён, где расположены backend-сервисы (`redis-standalone`) и сертификаты. `sectionName` `parentRef` должен совпадать с именем listener'а в Gateway, а `backendRefs` — ссылаться на сервис, который expose'ит порт 6379 для Redis.

```bash
cat <<EOF > tlsroute.yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: TLSRoute
metadata:
  name: redis-cluster-1-route
  namespace: redis-standalone
spec:
  parentRefs:
    - name: redis-gateway
      namespace: envoy-gateway
      sectionName: redis-cluster-1
  hostnames:
    - "redis1.apatsev.org.ru"
  rules:
    - backendRefs:
        - name: redis-standalone1
          port: 6379
EOF
```

```bash
kubectl apply -f tlsroute.yaml
# Debug: проверяем TLSRoute и его статус
kubectl get tlsroute -n redis-standalone
kubectl describe tlsroute redis-cluster-1-route -n redis-standalone
kubectl get tlsroute redis-cluster-1-route -n redis-standalone -o jsonpath='{.status.parents[*].conditions[*].type}' && echo
# Проверяем связанные ресурсы
kubectl get gateway redis-gateway -n envoy-gateway -o yaml | grep -A 10 "listeners:"
```

## 7. Проверка доступности
Для проверки TLS-соединения запускаем временный под и обращаемся к слушателю на порту 443 через TLS. Поскольку Envoy выполняет termination, клиент должен установить TLS-сессию и, при необходимости, доверить сертификату (для теста можно использовать `--insecure`).

```bash
kubectl run redis-client --rm -it --restart=Never --image=redis:alpine -- /bin/sh -c "
redis-cli --tls --insecure -h redis1.apatsev.org.ru -p 443 PING"
# Debug: проверяем подключение и логи
kubectl logs -n envoy-gateway -l app.kubernetes.io/instance=envoy-gateway --tail=50 | grep -i redis || echo "Проверьте логи envoy-gateway"
# Альтернативная проверка через telnet (без TLS)
kubectl run debug-client --rm -i --restart=Never --image=busybox -- nc -zv redis-standalone1.redis-standalone.svc.cluster.local 6379
```
