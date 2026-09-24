#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

[[ -f .env ]] && set -a && . ./.env && set +a

SSH_TARGET="${SSH_TARGET:-dmitry_buldakov@90.188.89.63}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
NODE_EXPORTER_LOCAL_PORT="${NODE_EXPORTER_LOCAL_PORT:-9100}"
PIDFILE=".tunnel.pid"

usage() {
  cat <<'EOF'
Нагрузочное тестирование бэкендов makeup, chat и world-country-monitoring (k6 + Prometheus + Grafana).
Серверные метрики (CPU/RAM/диск/сеть) идут с node_exporter через SSH-туннель.

Использование:
  ./run.sh up                  Запустить туннель + Prometheus + Grafana
  ./run.sh down                Остановить стек и туннель (метрики сохраняются)
  ./run.sh reset               Остановить стек, туннель и удалить метрики/дашборды
  ./run.sh logs                Смотреть логи стека
  ./run.sh status              Статус контейнеров
  ./run.sh tunnel              Поднять только SSH-туннель к node_exporter
  ./run.sh tunnel-down         Закрыть SSH-туннель

  ./run.sh makeup [PEAK_RPS]   Read-only тест makeup (по умолчанию 50 RPS на пике)
  ./run.sh chat   [PEAK_RPS]   Read-only тест chat   (по умолчанию 30 RPS на пике)
  ./run.sh wcm    [PEAK_RPS]   Read-only тест world-country-monitoring (по умолчанию 50 RPS на пике)

Переменные (можно задать в .env):
  SSH_TARGET=dmitry_buldakov@90.188.89.63   куда туннелировать
  SSH_PORT=2222                             SSH-порт сервера
  SSH_KEY=~/.ssh/id_ed25519                 приватный ключ
  TESTID=my-run                             метка прогона для фильтра в Grafana
  LOAD_PEAK_RPS=100                         пиковый RPS (аналог аргумента PEAK_RPS)
  CHAT_USERNAME / CHAT_PASSWORD             логин существующим юзером (иначе lt_<ts>)

Grafana:    http://localhost:3000   (admin/admin)
            дашборды "k6 Prometheus" и "Node Exporter Full"
            datasource Loki — логи бэкендов (нужен туннель, см. выше)
Prometheus: http://localhost:9090
Alertmanager: http://localhost:9093  (алерты о недоступности -> email, SMTP в .env)
Health:     blackbox проверяет /actuator/health бэкендов (job blackbox-http-health)
EOF
}

require_compose() {
  docker compose version >/dev/null 2>&1 || { echo "Нужен Docker Compose v2"; exit 1; }
}

# Рендерит alertmanager.local.yml из шаблона и .env (подставляет SMTP_*/ALERT_*).
render_alertmanager() {
  local tpl="alertmanager/alertmanager.yml.tmpl"
  local out="alertmanager/alertmanager.local.yml"
  [[ -f "$tpl" ]] || return 0
  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$tpl" > "$out"
  else
    python3 - "$tpl" "$out" <<'PY'
import os, re, sys
tpl, out = sys.argv[1], sys.argv[2]
s = open(tpl).read()
s = re.sub(r'\$\{(\w+)\}', lambda m: os.environ.get(m.group(1), ''), s)
open(out, 'w').write(s)
PY
  fi
  echo "==> alertmanager: сгенерирован $out (SMTP из .env)"
}

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

tunnel_up() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "==> туннель уже запущен (pid $(cat "$PIDFILE"))"
    return 0
  fi
  if port_open "$NODE_EXPORTER_LOCAL_PORT"; then
    echo "==> порт $NODE_EXPORTER_LOCAL_PORT уже занят — считаю, что туннель поднят"
    return 0
  fi
  # Пробрасываем наружу два сервиса: node_exporter (9100) и Loki/logs (3100)
  echo "==> поднимаю SSH-туннели: $SSH_TARGET (9100 node_exporter, 3100 Loki)"
  nohup ssh -N \
    -L "127.0.0.1:${NODE_EXPORTER_LOCAL_PORT}:127.0.0.1:${NODE_EXPORTER_LOCAL_PORT}" \
    -L "127.0.0.1:3100:127.0.0.1:3100" \
    -p "$SSH_PORT" -i "$SSH_KEY" \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ConnectTimeout=10 \
    -o BatchMode=yes \
    "$SSH_TARGET" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  sleep 2
  if port_open "$NODE_EXPORTER_LOCAL_PORT"; then
    echo "==> туннель работает (pid $(cat "$PIDFILE"))"
  else
    echo "!! не удалось поднять туннель к $SSH_TARGET:$SSH_PORT (ключ $SSH_KEY)" >&2
    rm -f "$PIDFILE"
    return 1
  fi
}

tunnel_down() {
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "==> туннель остановлен"
  else
    echo "==> туннель не запущен"
  fi
}

run_test() {
  local script="$1" peak="${2:-}"
  require_compose
  render_alertmanager
  tunnel_up
  docker compose up -d prometheus alertmanager grafana blackbox

  local testid="${TESTID:-$(date +%Y%m%d-%H%M%S)}"
  local extra=()
  if [[ -n "$peak" ]]; then
    extra+=(-e "LOAD_PEAK_RPS=${peak}")
  elif [[ -n "${LOAD_PEAK_RPS:-}" ]]; then
    extra+=(-e "LOAD_PEAK_RPS=${LOAD_PEAK_RPS}")
  fi

  echo "==> script=${script} testid=${testid} peak_rps=${peak:-default}"
  echo "==> Grafana: http://localhost:3000 -> 'k6 Prometheus', testid=${testid}"

  docker compose run --rm "${extra[@]}" k6 \
    run -o experimental-prometheus-rw \
    --tag "testid=${testid}" \
    "/scripts/${script}.js"
}

case "${1:-}" in
  up)          require_compose; render_alertmanager; tunnel_up; docker compose up -d prometheus alertmanager grafana blackbox ;;
  down)        require_compose; docker compose down; tunnel_down ;;
  reset)       require_compose; docker compose down -v; tunnel_down ;;
  logs)        require_compose; docker compose logs -f --tail=100 ;;
  status)      require_compose; docker compose ps ;;
  tunnel)      tunnel_up ;;
  tunnel-down) tunnel_down ;;
  makeup)      shift; run_test makeup-read "${1:-}" ;;
  chat)        shift; run_test chat-read "${1:-}" ;;
  wcm)         shift; run_test wcm-read "${1:-}" ;;
  ""|-h|--help|help) usage ;;
  *) echo "Неизвестная команда: $1"; echo; usage; exit 1 ;;
esac