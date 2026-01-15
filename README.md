# Маршрутизация трафика к Redis в другом k8s через один LB используя TLSRoute

## Цель статьи
Показать, как осуществить маршрутизацию трафика к кластеру Redis, расположенному в другом Kubernetes-кластере, через один LoadBalancer. Решение предполагает терминацию TLS-соединений в `envoy-gateway` и проксирование незашифрованного TCP-трафика к Redis без TLS.

**Особенность реализации:** Используется функция **Merge Gateways** (`mergeGateways: true`), которая объединяет все Gateway ресурсы в один Envoy Proxy fleet. Это обеспечивает экономию ресурсов и упрощённое управление при использовании одного LoadBalancer для всех Gateway.

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


# Получаем ключ сервисного аккаунта из Terraform output и удаляем неподдерживаемые поля
```bash
terraform output -raw dns_manager_service_account_key | python3 -m json.tool | jq 'del(.description, .encrypted_private_key, .format, .key_fingerprint, .pgp_key, .output_to_lockbox, .output_to_lockbox_version_id)' > key.json
```

# Debug: проверяем созданный файл
```bash
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
helm repo update ot-helm
```

### Установка Redis-оператора
```bash
helm upgrade --install redis-operator ot-helm/redis-operator \
  --create-namespace --namespace ot-operators --wait --version 0.22.2
```

# Debug: проверяем установку оператора
```bash
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
```

# Debug: проверяем созданные ресурсы
```
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
}

resource "local_file" "envoyproxy_yaml" {
  content = templatefile("${path.module}/envoyproxy.yaml.tpl", {
    load_balancer_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
  })
  filename = "${path.module}/envoyproxy.yaml"
}
```

**Примечание:** Файл `envoyproxy.yaml` генерируется автоматически через Terraform из шаблона `envoyproxy.yaml.tpl` с использованием функции `templatefile`. IP-адрес LoadBalancer получается из `yandex_vpc_address.addr.external_ipv4_address[0].address` и вставляется в секцию `provider.kubernetes.envoyService.patch.value.spec.loadBalancerIP`.


### EnvoyProxy (Merge Gateways)

**Рекомендуется:** Использование `mergeGateways: true` позволяет объединить все Gateway ресурсы в один Envoy Proxy fleet, что даёт следующие преимущества:
- Один LoadBalancer на все Gateway ресурсы
- Экономия ресурсов
- Упрощённое управление

Все listeners из разных Gateway будут объединены в один Envoy Proxy. Должны быть уникальны комбинации: (port, protocol, hostname).

**Важно:** Файл `envoyproxy.yaml` генерируется автоматически через Terraform при применении конфигурации. Шаблон `envoyproxy.yaml.tpl` содержит конфигурацию с LoadBalancer IP, который настраивается через секцию `provider.kubernetes.envoyService.patch`.

Сгенерированный файл будет содержать:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: merged-proxy
  namespace: envoy-gateway
spec:
  mergeGateways: true
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        patch:
          type: StrategicMerge
          value:
            spec:
              type: LoadBalancer
              loadBalancerIP: <IP_из_yandex_vpc_address>
```

Создаем EnvoyProxy
```bash
# Файл envoyproxy.yaml генерируется через Terraform
kubectl apply -f envoyproxy.yaml
```

# Debug: проверяем EnvoyProxy
```bash
kubectl get envoyproxy -n envoy-gateway
kubectl describe envoyproxy merged-proxy -n envoy-gateway
```

### GatewayClass
GatewayClass ссылается на EnvoyProxy для активации Merge Gateways:

```bash
cat <<EOF > gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: merged-proxy
    namespace: envoy-gateway
EOF
```

**Примечание:** Имя EnvoyProxy должно быть `merged-proxy` (как указано в сгенерированном файле `envoyproxy.yaml`).

Создаем GatewayClass
```bash
kubectl apply -f gatewayclass.yaml
```
# Debug: проверяем GatewayClass
```
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
      allowedRoutes:
        namespaces:
          from: All
EOF
```

# Debug: проверяем Gateway и его статус
```bash
kubectl apply -f gateway.yaml
kubectl get gateway -n envoy-gateway
kubectl describe gateway redis-gateway -n envoy-gateway
kubectl get gateway redis-gateway -n envoy-gateway -o jsonpath='{.status.addresses[*].value}' && echo
```

# Проверяем адрес LoadBalancer
```
kubectl get svc -n envoy-gateway | grep envoy
```

**Устранение проблем:** Если Gateway показывает ошибку "No addresses have been assigned" или проблемы с сертификатом, выполните:

```bash
# Пересоздаём Gateway (если он был создан до сертификата)
kubectl delete -f gateway.yaml && kubectl apply -f gateway.yaml
# Проверяем статус после пересоздания
kubectl get gateway redis-gateway -n envoy-gateway -o jsonpath='{.status.conditions[*].type}' && echo
# Проверяем наличие Secret в правильном namespace
kubectl get secret wildcard-tls-cert -n envoy-gateway
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
  namespace: envoy-gateway
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

Создаем сертификат
```bash
kubectl apply -f wildcard-certificate.yaml
```

# Debug: проверяем создание сертификата
```bash
kubectl get certificate -n envoy-gateway
kubectl describe certificate wildcard-certificate -n envoy-gateway
kubectl get certificaterequest -n envoy-gateway
kubectl get secret wildcard-tls-cert -n envoy-gateway
# Проверяем статус сертификата (может занять время)
kubectl get certificate wildcard-certificate -n envoy-gateway -o jsonpath='{.status.conditions[*].type}' && echo
```

## 6. Настройка TLSRoute и Gateway

**Важно:** Перед созданием Gateway убедитесь, что сертификат готов и Secret `wildcard-tls-cert` существует. Проверьте статус сертификата:

```bash
# Ожидаем готовности сертификата (может занять несколько минут)
kubectl wait --for=condition=Ready certificate/wildcard-certificate -n envoy-gateway --timeout=5m
# Проверяем наличие Secret
kubectl get secret wildcard-tls-cert -n envoy-gateway
```

**Примечание:** Secret `wildcard-tls-cert` создаётся в том же namespace `envoy-gateway`, где находится Gateway, поэтому ReferenceGrant не требуется. Gateway API позволяет ссылаться на ресурсы в том же namespace без дополнительных разрешений.

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

Создаем TLSRoute
```bash
kubectl apply -f tlsroute.yaml
```

# Debug: проверяем TLSRoute и его статус
```bash
kubectl get tlsroute -n redis-standalone
kubectl describe tlsroute redis-cluster-1-route -n redis-standalone
kubectl get tlsroute redis-cluster-1-route -n redis-standalone -o jsonpath='{.status.parents[*].conditions[*].type}' && echo
```

# Проверяем связанные ресурсы
```
kubectl get gateway redis-gateway -n envoy-gateway -o yaml | grep -A 10 "listeners:"
```

## 7. Проверка доступности

### Вариант 1: Быстрая проверка через внешний адрес (рекомендуется)
Для проверки TLS-соединения запускаем временный под без интерактивного режима. Поскольку Envoy выполняет termination, клиент должен установить TLS-сессию и, при необходимости, доверить сертификату (для теста можно использовать `--insecure`).

```bash
# Быстрая проверка без интерактивного режима (--rm удалит под автоматически)
kubectl run redis-client --rm -i --restart=Never --image=redis:alpine --timeout=30s -- \
  redis-cli --tls --insecure -h redis1.apatsev.org.ru -p 443 PING
```

### Вариант 2: Проверка через существующий под Redis (самый быстрый)
Если у вас уже есть под Redis в кластере, можно использовать его для проверки:

```bash
# Получаем имя пода Redis
REDIS_POD=$(kubectl get pods -n redis-standalone -l app=redis-standalone1 -o jsonpath='{.items[0].metadata.name}')
# Проверяем подключение через внешний адрес
kubectl exec -n redis-standalone $REDIS_POD -- \
  redis-cli --tls --insecure -h redis1.apatsev.org.ru -p 443 PING
```

### Вариант 3: Проверка напрямую через сервис (без TLS)
Для проверки доступности Redis внутри кластера (минуя Gateway, без TLS):

```bash
# Проверка через внутренний сервис
kubectl run debug-client --rm -i --restart=Never --image=busybox --timeout=10s -- \
  nc -zv redis-standalone1.redis-standalone.svc.cluster.local 6379
```

### Вариант 4: Проверка через openssl (для диагностики TLS)
Для проверки TLS-соединения и сертификата:

```bash
# Проверка TLS-соединения
kubectl run tls-check --rm -i --restart=Never --image=alpine/openssl --timeout=15s -- \
  sh -c "echo | openssl s_client -connect redis1.apatsev.org.ru:443 -servername redis1.apatsev.org.ru 2>&1 | grep -E '(Verify return code|subject=|issuer=)'"
```

### Debug: проверка подключения и логов
```bash
# Проверяем логи envoy-gateway
kubectl logs -n envoy-gateway -l app.kubernetes.io/instance=envoy-gateway --tail=50 | grep -i redis || echo "Проверьте логи envoy-gateway"
# Проверяем статус Gateway
kubectl get gateway redis-gateway -n envoy-gateway -o jsonpath='{.status.addresses[*].value}' && echo
# Проверяем статус TLSRoute
kubectl get tlsroute redis-cluster-1-route -n redis-standalone -o jsonpath='{.status.parents[*].conditions[*].type}' && echo
```
