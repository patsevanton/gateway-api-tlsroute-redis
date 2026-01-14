resource "yandex_vpc_address" "addr" {
  name = "public-ip"

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.k8s-subnet.zone
  }
}

# DNS-зона для домена apatsev.org.ru
# Используется cert-manager с Yandex Cloud DNS ACME webhook для автоматического
# управления DNS-записями при получении wildcard-сертификатов через DNS-01 challenge
resource "yandex_dns_zone" "apatsev-org-ru" {
  name = "apatsev-org-ru-zone"

  zone   = "apatsev.org.ru."
  public = true

  private_networks = [yandex_vpc_network.k8s-network.id]
}
