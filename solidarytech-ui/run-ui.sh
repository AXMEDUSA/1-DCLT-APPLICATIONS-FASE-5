#!/usr/bin/env bash
set -e

UI_PORT=9090
NGO_PORT=8081
DONATION_PORT=8082
VOLUNTEER_PORT=18083
UI_IMAGE="solidarytech-ui:local"
CONTAINER_NAME="solidarytech-ui"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf "\033[0;32m[UI]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[UI]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[ERRO]\033[0m %s\n" "$*"; exit 1; }

cleanup() {
  printf "\n\033[0;32m[UI]\033[0m Encerrando...\n"
  kill "$PF_NGO" "$PF_DONATION" "$PF_VOLUNTEER" 2>/dev/null || true
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 1. Port-forwards antigos
pkill -f "kubectl port-forward svc/ngo-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/donation-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/volunteer-service" 2>/dev/null || true
sleep 1

# 2. Subir port-forwards
log "Iniciando port-forwards para os serviços no AKS..."
kubectl port-forward svc/ngo-service       -n solidarytech ${NGO_PORT}:80      &>/tmp/pf-ngo.log      & PF_NGO=$!
kubectl port-forward svc/donation-service  -n solidarytech ${DONATION_PORT}:80 &>/tmp/pf-donation.log & PF_DONATION=$!
kubectl port-forward svc/volunteer-service -n solidarytech ${VOLUNTEER_PORT}:80 &>/tmp/pf-volunteer.log & PF_VOLUNTEER=$!

# 3. Aguardar serviços
log "Aguardando serviços responderem..."
for PORT in $NGO_PORT $DONATION_PORT $VOLUNTEER_PORT; do
  for i in $(seq 1 20); do
    if curl -sf "http://localhost:${PORT}/health" &>/dev/null; then
      log "  porta ${PORT} — OK"
      break
    fi
    sleep 1
    if [[ $i -eq 20 ]]; then
      die "Serviço na porta ${PORT} não respondeu. Log: /tmp/pf-*.log"
    fi
  done
done

# 4. Build da imagem (só na primeira vez)
if ! docker image inspect "$UI_IMAGE" &>/dev/null; then
  log "Construindo imagem Docker do UI..."
  docker build -t "$UI_IMAGE" "$SCRIPT_DIR" -q
  log "Imagem criada."
else
  log "Imagem $UI_IMAGE já existe — reutilizando."
fi

# 5. Parar container anterior
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# 6. Subir container com --network host
log "Iniciando container UI..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --network host \
  "$UI_IMAGE"

# 7. Aguardar UI
sleep 2
for i in $(seq 1 10); do
  if curl -sf "http://localhost:${UI_PORT}" &>/dev/null; then break; fi
  sleep 1
done

# 8. Abrir browser
printf "\n"
printf "\033[0;32m╔═══════════════════════════════════════════╗\033[0m\n"
printf "\033[0;32m║  SolidaryTech UI rodando!                 ║\033[0m\n"
printf "\033[0;32m║  http://localhost:%s                     ║\033[0m\n" "$UI_PORT"
printf "\033[0;32m╚═══════════════════════════════════════════╝\033[0m\n"
printf "\n"
log "ngo-service       → http://localhost:${NGO_PORT}"
log "donation-service  → http://localhost:${DONATION_PORT}"
log "volunteer-service → http://localhost:${VOLUNTEER_PORT}"
printf "\n"
log "Pressione Ctrl+C para encerrar tudo."
printf "\n"

xdg-open "http://localhost:${UI_PORT}" 2>/dev/null || \
  open    "http://localhost:${UI_PORT}" 2>/dev/null || true

# 9. Loop de manutenção — reinicia port-forwards que caem
while true; do
  for ENTRY in "PF_NGO:ngo-service:${NGO_PORT}" "PF_DONATION:donation-service:${DONATION_PORT}" "PF_VOLUNTEER:volunteer-service:${VOLUNTEER_PORT}"; do
    VAR="${ENTRY%%:*}"
    REST="${ENTRY#*:}"
    SVC="${REST%%:*}"
    PORT="${REST#*:}"
    PID="${!VAR}"
    if ! kill -0 "$PID" 2>/dev/null; then
      warn "Port-forward do $SVC caiu — reiniciando..."
      kubectl port-forward "svc/${SVC}" -n solidarytech "${PORT}:80" &>"/tmp/pf-${SVC}.log" &
      eval "$VAR=$!"
    fi
  done
  sleep 10
done
