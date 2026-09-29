#!/usr/bin/env bash
# Нагрузочное тестирование бэкендов makeup, chat и world-country-monitoring.
#
# Репозиторий — только генератор нагрузки (k6). Метрики прогона отправляются
# в постоянный стек наблюдаемости (репозиторий `monitoring`) через remote-write,
# смотрят их в Grafana оттуда: дашборд "k6 Prometheus", фильтр по testid.
# Если K6_PROMETHEUS_RW_SERVER_URL недоступен, прогон всё равно идёт —
# результаты печатаются в stdout, но в Grafana не попадут.
#
# Использование:
#   ./run.sh makeup [PEAK_RPS]   Read-only тест makeup (по умолчанию 50 RPS на пике)
#   ./run.sh chat   [PEAK_RPS]   Read-only тест chat   (по умолчанию 30 RPS на пике)
#   ./run.sh wcm    [PEAK_RPS]   Read-only тест world-country-monitoring (по умолчанию 50 RPS на пике)
#
#   ./run.sh shell               Интерактивная оболочка k6 (отладка сценария)
#   ./run.sh targets             Проверить доступность адресов из .env
#   ./run.sh lint [script]       Проверить сценарий без запуска (k6 inspect)
#
# Переменные (см. .env.example):
#   MAKEUP_BASE_URL / CHAT_BASE_URL / WCM_BASE_URL   адреса приложений
#   K6_PROMETHEUS_RW_SERVER_URL                      куда сливать метрики
#   TESTID=my-run                                    метка прогона для фильтра в Grafana
#   LOAD_PEAK_RPS=100                                пиковый RPS (аналог аргумента PEAK_RPS)
#   LOAD_RAMP / LOAD_HOLD / LOAD_DOWN                тайминги рампы
#   PREALLOC_FACTOR=0.15                             доля RPS на preAllocatedVUs
#   CHAT_USERNAME / CHAT_PASSWORD                    логин существующим юзером (иначе lt_<ts>)
set -euo pipefail
cd "$(dirname "$0")"

[[ -f .env ]] && set -a && . ./.env && set +a

TESTID="${TESTID:-$(date +%Y%m%d-%H%M%S)}"

require_compose() {
  docker compose version >/dev/null 2>&1 || { echo "Нужен Docker Compose v2"; exit 1; }
}

run_test() {
  local script="$1" peak="${2:-}"
  require_compose

  local extra=()
  if [[ -n "$peak" ]]; then
    extra+=(-e "LOAD_PEAK_RPS=${peak}")
  elif [[ -n "${LOAD_PEAK_RPS:-}" ]]; then
    extra+=(-e "LOAD_PEAK_RPS=${LOAD_PEAK_RPS}")
  fi

  local rw="${K6_PROMETHEUS_RW_SERVER_URL:-http://127.0.0.1:9090/api/v1/write}"
  local host_port="${rw#*://}"
  host_port="${host_port%%/*}"
  local rw_host="${host_port%%:*}" rw_port="${host_port##*:}"

  echo "==> script=${script} testid=${TESTID} peak_rps=${peak:-${LOAD_PEAK_RPS:-default}}"
  if timeout 5 bash -c "</dev/tcp/${rw_host}/${rw_port}" 2>/dev/null; then
    echo "==> метрики: ${rw} (Grafana -> 'k6 Prometheus', testid=${TESTID})"
  else
    echo "!! ${rw_host}:${rw_port} недоступен — прогон пойдёт, но метрики в Grafana не попадут" >&2
  fi

  docker compose run --rm "${extra[@]}" k6 \
    run -o experimental-prometheus-rw \
    --tag "testid=${TESTID}" \
    "/scripts/${script}.js"
}

check_targets() {
  set -a; [[ -f .env ]] && . ./.env; set +a
  local name
  for name in MAKEUP_BASE_URL CHAT_BASE_URL WCM_BASE_URL; do
    local url="${!name:-}"
    [[ -n "$url" ]] || { printf '%-16s не задан\n' "$name"; continue; }
    local code
    code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "${url%/}/actuator/health" || echo 000)
    printf '%-16s %-6s http %s\n' "$name" "$url" "$code"
  done
}

case "${1:-}" in
  makeup) shift; run_test makeup-read "${1:-}" ;;
  chat)   shift; run_test chat-read "${1:-}" ;;
  wcm)    shift; run_test wcm-read "${1:-}" ;;
  shell)  require_compose; docker compose run --rm -it k6 shell ;;
  lint)   require_compose; docker compose run --rm k6 inspect --execution-requirements "/scripts/${2:-makeup-read}.js" ;;
  targets) check_targets ;;
  ""|-h|--help|help) sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "Неизвестная команда: $1"; exit 1 ;;
esac
