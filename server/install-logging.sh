#!/usr/bin/env bash
# Установка Loki + Promtail на тестируемый сервер: сбор логов всех docker-контейнеров.
# Loki слушает 127.0.0.1:3100 (наружу не торчит), Promtail читает docker.sock
# и шлёт логи локально в Loki. Хранилище файловое, ретеншн 14 дней (см. loki/loki.yaml).
#
# Grafana на машине-генераторе читает Loki через SSH-туннель: ./run.sh up (или tunnel).
#
# Запуск НА сервере (из корня репозитория, нужен docker):
#   ./server/install-logging.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${LOGGING_DIR:-$HOME/logging}"

echo "==> разворачиваю Loki+Promtail в $DEST"
mkdir -p "$DEST"
cp "$SRC_DIR/loki/loki.yaml"      "$DEST/loki.yaml"
cp "$SRC_DIR/promtail/promtail.yml" "$DEST/promtail.yml"

cat > "$DEST/docker-compose.yaml" <<'YAML'
services:
  loki:
    image: grafana/loki:3.4.2
    container_name: loki
    restart: unless-stopped
    command: -config.file=/etc/loki/loki.yaml
    network_mode: host
    mem_limit: 512m
    user: "0"
    volumes:
      - ./loki.yaml:/etc/loki/loki.yaml:ro
      - loki-data:/loki

  promtail:
    image: grafana/promtail:3.4.2
    container_name: promtail
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail.yml
    network_mode: host
    user: "0"
    depends_on:
      - loki
    volumes:
      - ./promtail.yml:/etc/promtail/promtail.yml:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail-positions:/promtail

volumes:
  loki-data:
YAML

cd "$DEST"
docker compose up -d
sleep 6
echo "==> Loki ready:   $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3100/ready || echo n/a)"
echo "==> Loki status:  http://127.0.0.1:3100/ready должен отвечать 200"
echo "==> Promtail:     $(docker ps --filter name=promtail --format '{{.Status}}')"
echo
echo "Дальше (на генераторе): ./run.sh up — поднимет туннели 3100+9100, "
echo "Grafana datasource 'Loki' уже прописан. Примеры LogQL:"
echo "  {app=\"chat\"}   — все логи chat"
echo "  {app=\"chat\"} |= \"error\""
echo "  {app=\"makeup\"} |=\"HTTP\" | json user=user, request_id=request_id"