#!/usr/bin/env bash
set -e

UI_PORT=9090
NGO_PORT=8081
DONATION_PORT=8082
VOLUNTEER_PORT=18083
UI_IMAGE="solidarytech-ui:local"
CONTAINER_NAME="solidarytech-ui"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[UI]${NC} $*"; }
warn() { echo -e "${YELLOW}[UI]${NC} $*"; }
die()  { echo -e "${RED}[UI]${NC} $*"; exit 1; }

cleanup() {
  log "Encerrando port-forwards e container..."
  kill "$PF_NGO" "$PF_DONATION" "$PF_VOLUNTEER" 2>/dev/null || true
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  log "Encerrado."
}
trap cleanup EXIT INT TERM

# --- 1. Verificar contexto k8s ---
CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ "$CONTEXT" != "aks-solidarytech" ]]; then
  warn "Contexto atual: '$CONTEXT'. Esperado: 'aks-solidarytech'"
  warn "Tentando continuar mesmo assim..."
fi

# --- 2. Verificar pods em execução ---
log "Verificando pods no namespace solidarytech..."
NOT_READY=$(kubectl get pods -n solidarytech --no-headers 2>/dev/null \
  | grep -v "Running\|Completed" | wc -l)
if [[ "$NOT_READY" -gt 0 ]]; then
  warn "Alguns pods não estão Running. Aguardando 20s..."
  kubectl wait --for=condition=Ready pod -l app=ngo-service -n solidarytech --timeout=60s 2>/dev/null || true
  kubectl wait --for=condition=Ready pod -l app=donation-service -n solidarytech --timeout=60s 2>/dev/null || true
  kubectl wait --for=condition=Ready pod -l app=volunteer-service -n solidarytech --timeout=60s 2>/dev/null || true
fi

# --- 3. Matar port-forwards antigos ---
pkill -f "kubectl port-forward svc/ngo-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/donation-service" 2>/dev/null || true
pkill -f "kubectl port-forward svc/volunteer-service" 2>/dev/null || true
sleep 1

# --- 4. Subir port-forwards ---
log "Iniciando port-forwards..."
kubectl port-forward svc/ngo-service -n solidarytech ${NGO_PORT}:80 \
  &>/tmp/pf-ngo.log & PF_NGO=$!

kubectl port-forward svc/donation-service -n solidarytech ${DONATION_PORT}:80 \
  &>/tmp/pf-donation.log & PF_DONATION=$!

kubectl port-forward svc/volunteer-service -n solidarytech ${VOLUNTEER_PORT}:80 \
  &>/tmp/pf-volunteer.log & PF_VOLUNTEER=$!

# --- 5. Aguardar os serviços responderem ---
log "Aguardando serviços ficarem disponíveis..."
for PORT in $NGO_PORT $DONATION_PORT $VOLUNTEER_PORT; do
  for i in $(seq 1 15); do
    if curl -sf "http://localhost:${PORT}/health" &>/dev/null; then
      log "  :${PORT} OK"
      break
    fi
    sleep 1
    if [[ $i -eq 15 ]]; then
      die "Serviço na porta ${PORT} não respondeu. Verifique /tmp/pf-*.log"
    fi
  done
done

# --- 6. Build da imagem UI (só se necessário) ---
if ! docker image inspect "$UI_IMAGE" &>/dev/null; then
  log "Construindo imagem $UI_IMAGE..."
  docker build -t "$UI_IMAGE" "$SCRIPT_DIR" --quiet
else
  log "Imagem $UI_IMAGE já existe — pulando build."
  log "  (para forçar rebuild: docker rmi $UI_IMAGE e rode novamente)"
fi

# --- 7. Parar container anterior se existir ---
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

# --- 8. Subir container UI ---
log "Iniciando container UI na porta ${UI_PORT}..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --network host \
  "$UI_IMAGE" &>/dev/null

# --- 9. Aguardar UI responder ---
for i in $(seq 1 10); do
  if curl -sf "http://localhost:${UI_PORT}" &>/dev/null; then
    break
  fi
  sleep 1
done

# --- 10. Abrir browser ---
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   SolidaryTech UI está no ar!                ║${NC}"
echo -e "${GREEN}║   http://localhost:${UI_PORT}                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
log "Serviços conectados:"
log "  ngo-service       → http://localhost:${NGO_PORT}"
log "  donation-service  → http://localhost:${DONATION_PORT}"
log "  volunteer-service → http://localhost:${VOLUNTEER_PORT}"
echo ""
log "Pressione Ctrl+C para encerrar tudo."
echo ""

# Abrir browser automaticamente
if command -v xdg-open &>/dev/null; then
  xdg-open "http://localhost:${UI_PORT}" &>/dev/null &
elif command -v open &>/dev/null; then
  open "http://localhost:${UI_PORT}" &
fi

# --- 11. Manter vivo e monitorar port-forwards ---
while true; do
  for PID_VAR in PF_NGO PF_DONATION PF_VOLUNTEER; do
    PID="${!PID_VAR}"
    if ! kill -0 "$PID" 2>/dev/null; then
      warn "Port-forward caiu (PID $PID). Reiniciando..."
      case $PID_VAR in
        PF_NGO)
          kubectl port-forward svc/ngo-service -n solidarytech ${NGO_PORT}:80 \
            &>/tmp/pf-ngo.log & PF_NGO=$! ;;
        PF_DONATION)
          kubectl port-forward svc/donation-service -n solidarytech ${DONATION_PORT}:80 \
            &>/tmp/pf-donation.log & PF_DONATION=$! ;;
        PF_VOLUNTEER)
          kubectl port-forward svc/volunteer-service -n solidarytech ${VOLUNTEER_PORT}:80 \
            &>/tmp/pf-volunteer.log & PF_VOLUNTEER=$! ;;
      esac
    fi
  done
  sleep 10
done
