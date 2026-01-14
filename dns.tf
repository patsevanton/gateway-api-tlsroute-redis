resource "yandex_vpc_address" "addr" {
  name = "public-ip"

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.impulse-a.zone
  }
}

# Создание публичной DNS-зоны в Yandex Cloud DNS
# 
# ВАЖНО: Для wildcard-сертификатов (например, *.apatsev.org.ru) требуется DNS-01 challenge
# вместо HTTP-01. В этом случае настройте DNS-01 solver для Yandex DNS в ClusterIssuer.
#
# Для настройки cert-manager с DNS-01 challenge необходимо:
# 1. Установить cert-manager-webhook-yandex (webhook для Yandex Cloud DNS)
# 2. Создать Secret с ключом service account (yandex_iam_service_account_key.sa-dns-manager-key)
# 3. Настроить ClusterIssuer с dns01 solver, использующим webhook:
#    solvers:
#    - dns01:
#        webhook:
#          groupName: acme.cloud.yandex.com
#          solverName: yandex-cloud-dns
#          config:
#            folder: <folder-id>
#            serviceAccountSecretRef:
#              name: cert-manager-secret
#              key: iamkey.json
#
resource "yandex_dns_zone" "apatsev-org-ru" {
  name = "apatsev-org-ru-zone"

  zone   = "apatsev.org.ru."
  public = true

  private_networks = [yandex_vpc_network.impulse.id]
}
