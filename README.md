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


```bash
# Получаем ключ сервисного аккаунта из Terraform output
terraform output -raw dns_manager_service_account_key | python3 -m json.tool | grep -v description | grep -v encrypted_private_key | grep -v format | grep -v key_fingerprint | grep -v pgp_key > key.json

helm install \
  cert-manager-webhook-yandex \
  oci://cr.yandex/yc-marketplace/yandex-cloud/cert-manager-webhook-yandex/cert-manager-webhook-yandex \
  --version 1.0.9 \
  --namespace cert-manager \
  --create-namespace \
  --set-file config.auth.json=key.json \
  --set config.email='<адрес_электронной_почты_для_уведомлений_от_Lets_Encrypt>' \
  --set config.folder_id='<идентификатор_каталога_с_зоной_Cloud_DNS>' \
  --set config.server='https://acme-v02.api.letsencrypt.org/directory'
```

### Проверка установки ClusterIssuer
Проверяем, что ClusterIssuer `yc-clusterissuer` успешно создан:

```bash
kubectl get clusterissuer yc-clusterissuer
```

**Примечание:** 
- Замените `<адрес_электронной_почты_для_уведомлений_от_Lets_Encrypt>` на ваш email адрес.
- Замените `<идентификатор_каталога_с_зоной_Cloud_DNS>` на folder_id (можно получить через `terraform output -raw folder_id`).
- Файл `key.json` должен содержать ключ сервисного аккаунта с ролью `dns.editor` (создаётся через Terraform, см. раздел 1.1).
- При установке автоматически создаётся ClusterIssuer с именем `yc-clusterissuer`, который можно использовать вместо создания собственного (см. раздел 1.3).


#### 1.2. Создание Kubernetes Secret (опционально)

**Примечание:** Если вы используете автоматически созданный ClusterIssuer `yc-clusterissuer` (см. раздел 1.3), создание Secret вручную не требуется, так как ключ передаётся через `--set-file config.auth.json=key.json` при установке.

Создание Secret необходимо только если вы хотите использовать собственный ClusterIssuer:

Создайте Secret в кластере с ключом сервисного аккаунта из Terraform output:

```bash
# Получаем ключ из Terraform output и сохраняем в файл
terraform output -raw dns_manager_service_account_key | python3 -m json.tool | grep -v description | grep -v encrypted_private_key | grep -v format | grep -v key_fingerprint | grep -v pgp_key > iamkey.json

# Создаём Secret в кластере
kubectl create secret generic cert-manager-yandex-dns \
  --from-file=iamkey.json=iamkey.json \
  -n cert-manager

# Удаляем временный файл (опционально)
rm iamkey.json
```

## 2. Развертывание Redis-оператора (рекомендуемый способ)
### Добавление репозитория Helm
```bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
```

### Установка Redis-оператора
```bash
helm upgrade --install redis-operator ot-helm/redis-operator \
  --create-namespace --namespace ot-operators --wait --version 0.22.2
```

### Проверка установки
```bash
kubectl get pods -n ot-operators | grep redis
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
kubectl get pods -n redis-standalone
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

### Получение стандартных значений чарта
```bash
helm show values oci://docker.io/envoyproxy/gateway-helm --version v1.6.2 > default-values.yaml
yq -i 'del(.. | select( length == 0))' default-values.yaml
sed -i '/{}/d' default-values.yaml
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

kubectl apply -f wildcard-certificate.yaml
```

## 6. Настройка TLSRoute и Gateway
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

kubectl apply -f gatewayclass.yaml
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

kubectl apply -f gateway.yaml
```

### TLSRoute
Маршрут должен быть объявлен в том же пространстве имён, где расположены backend-сервисы (`redis-standalone`) и сертификаты. `sectionName` `parentRef` должен совпадать с именем listener'а в Gateway, а `backendRefs` — ссылаться на сервис, который expose'ит порт 6379 для Redis.

```bash
cat <<EOF > tlsroute.yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
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

kubectl apply -f tlsroute.yaml
```

## 7. Проверка доступности
Для проверки TLS-соединения запускаем временный под и обращаемся к слушателю на порту 443 через TLS. Поскольку Envoy выполняет termination, клиент должен установить TLS-сессию и, при необходимости, доверить сертификату (для теста можно использовать `--insecure`).

```bash
kubectl run redis-client --rm -it --restart=Never --image=redis:alpine -- /bin/sh -c "
redis-cli --tls --insecure -h redis1.apatsev.org.ru -p 443 PING"
```
