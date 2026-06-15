#!/usr/bin/env bash
set -e

UI_PORT=9090
NGO_PORT=8081
DONATION_PORT=8082
VOLUNTEER_PORT=18083

log()  { printf "\033[0;32m[UI]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[UI]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[ERRO]\033[0m %s\n" "$*"; exit 1; }

cleanup() {
  printf "\n\033[0;32m[UI]\033[0m Encerrando port-forwards...\n"
  kill "$PF_UI" "$PF_NGO" "$PF_DONATION" "$PF_VOLUNTEER" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 1. Matar port-forwards antigos
pkill -f "kubectl port-forward svc/solidarytech-ui" 2>/dev/null || true
pkill -f "kubectl port-forward svc/ngo-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/donation-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/volunteer-service" 2>/dev/null || true
sleep 1

# 2. Verificar se o pod do UI está Running
log "Verificando pod solidarytech-ui..."
UI_STATUS=$(kubectl get pods -n solidarytech-ui -l app=solidarytech-ui --no-headers 2>/dev/null | awk '{print $3}' | head -1)
if [[ "$UI_STATUS" != "Running" ]]; then
  warn "Pod solidarytech-ui está '$UI_STATUS'. Aguardando ficar Running..."
  kubectl wait --for=condition=Ready pod -l app=solidarytech-ui -n solidarytech-ui --timeout=120s \
    || die "Pod não ficou Ready. Verifique: kubectl get pods -n solidarytech-ui"
fi
log "Pod solidarytech-ui — Running"

# 3. Subir port-forwards
log "Iniciando port-forwards..."
kubectl port-forward svc/solidarytech-ui  -n solidarytech-ui ${UI_PORT}:80       &>/tmp/pf-ui.log       & PF_UI=$!
kubectl port-forward svc/ngo-service      -n solidarytech    ${NGO_PORT}:80      &>/tmp/pf-ngo.log      & PF_NGO=$!
kubectl port-forward svc/donation-service -n solidarytech    ${DONATION_PORT}:80 &>/tmp/pf-donation.log & PF_DONATION=$!
kubectl port-forward svc/volunteer-service -n solidarytech   ${VOLUNTEER_PORT}:80 &>/tmp/pf-volunteer.log & PF_VOLUNTEER=$!

# 4. Aguardar todos responderem
log "Aguardando serviços ficarem disponíveis..."
for ENTRY in "${UI_PORT}:solidarytech-ui" "${NGO_PORT}:ngo-service" "${DONATION_PORT}:donation-service" "${VOLUNTEER_PORT}:volunteer-service"; do
  PORT="${ENTRY%%:*}"
  NAME="${ENTRY#*:}"
  for i in $(seq 1 20); do
    if curl -sf "http://localhost:${PORT}" &>/dev/null || curl -sf "http://localhost:${PORT}/health" &>/dev/null; then
      log "  ${NAME} → http://localhost:${PORT}  OK"
      break
    fi
    sleep 1
    [[ $i -eq 20 ]] && die "${NAME} não respondeu na porta ${PORT}. Log: /tmp/pf-${NAME}.log"
  done
done

# 5. Abrir browser
printf "\n"
printf "\033[0;32m╔═══════════════════════════════════════════════╗\033[0m\n"
printf "\033[0;32m║   SolidaryTech UI está no ar!                 ║\033[0m\n"
printf "\033[0;32m║   http://localhost:%-26s║\033[0m\n" "${UI_PORT}"
printf "\033[0;32m╚═══════════════════════════════════════════════╝\033[0m\n"
printf "\n"
log "Pressione Ctrl+C para encerrar todos os port-forwards."
printf "\n"

xdg-open "http://localhost:${UI_PORT}" 2>/dev/null &

# 6. Loop de manutenção — reinicia port-forwards que caem
while true; do
  for ENTRY in "PF_UI:solidarytech-ui:solidarytech-ui:${UI_PORT}:80" \
               "PF_NGO:ngo-service:solidarytech:${NGO_PORT}:80" \
               "PF_DONATION:donation-service:solidarytech:${DONATION_PORT}:80" \
               "PF_VOLUNTEER:volunteer-service:solidarytech:${VOLUNTEER_PORT}:80"; do
    VAR="${ENTRY%%:*}"        ; REST="${ENTRY#*:}"
    SVC="${REST%%:*}"         ; REST="${REST#*:}"
    NS="${REST%%:*}"          ; REST="${REST#*:}"
    LPORT="${REST%%:*}"       ; RPORT="${REST#*:}"
    PID="${!VAR}"
    if ! kill -0 "$PID" 2>/dev/null; then
      warn "${SVC} port-forward caiu — reiniciando..."
      kubectl port-forward "svc/${SVC}" -n "${NS}" "${LPORT}:${RPORT}" &>"/tmp/pf-${SVC}.log" &
      eval "$VAR=$!"
    fi
  done
  sleep 10
done
