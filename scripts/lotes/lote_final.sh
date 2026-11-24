#!/usr/bin/env bash
# =====================================================================
# Lote do cenario C1 (repouso) no Linux  -  versao final
# Uso: ./lote_final.sh <app> <comando> <nome_processo> <url> [reps] [seg]
# Ex:  ./lote_final.sh discord discord Discord "https://discord.com/app" 12 600
#
# Correcoes acumuladas:
#   - pkill -x (nao -f), para o script nao matar a si mesmo
#   - espera de 15s apos encerrar, por causa da limpeza do snap
#   - ate 3 tentativas de abertura antes de pular a execucao
#   - sem set -u e sem pipefail, que derrubavam o script
# =====================================================================
source "$HOME/tcc/scripts/ambiente.sh" 2>/dev/null
export LC_ALL=C LC_NUMERIC=C
export DISPLAY="${DISPLAY:-:0}"

APP="$1"; CMD="$2"; PROC="$3"; URL="$4"
REPS="${5:-12}"; SEG="${6:-600}"; PISO="${7:-200}"
D="$HOME/tcc/dados"; mkdir -p "$D"
LOG="$D/lote_${APP}_C1_linux.log"

if [ -z "$APP" ] || [ -z "$CMD" ] || [ -z "$PROC" ] || [ -z "$URL" ]; then
  echo "Uso: $0 <app> <comando> <nome_processo> <url> [reps] [segundos]"; exit 1
fi

# ---- mede a memoria da arvore de um processo, em MB ----
medir() {
  local alvo="$1" total=0 p v
  for p in $(pgrep -x "$alvo" 2>/dev/null); do
    v=$(awk '/^Pss:/{s+=$2} END{print int(s/1024)}' "/proc/$p/smaps_rollup" 2>/dev/null)
    [ -z "$v" ] && v=0
    total=$((total+v))
  done
  echo "$total"
}

# ---- encerra tudo e espera de fato terminar ----
limpar() {
  pkill -x "$PROC"  >/dev/null 2>&1
  pkill -x chrome   >/dev/null 2>&1
  local w=0
  while [ $w -lt 20 ]; do
    if [ -z "$(pgrep -x "$PROC" 2>/dev/null)" ] && [ -z "$(pgrep -x chrome 2>/dev/null)" ]; then break; fi
    sleep 1; w=$((w+1))
  done
  sleep 15
}

LISTA=$(for i in $(seq 1 "$REPS"); do n=$(printf %02d "$i")
  echo "electron $n"; echo "navegador $n"; done | shuf)
echo "$LISTA" > "$D/ordem_${APP}_C1_linux.txt"
TOTAL=$(echo "$LISTA" | wc -l)
N=0

echo "===== LOTE $APP INICIADO EM $(date) =====" | tee -a "$LOG"

while read -r cam i; do
  N=$((N+1))
  RUN="${APP}_${cam}_C1_linux_$i"
  if [ "$cam" = "electron" ]; then ALVO="$PROC"; else ALVO="chrome"; fi
  echo "[$N/$TOTAL] $cam rep $i  $(date +%H:%M)"

  NP=0; MB=0
  for tent in 1 2 3; do
    limpar
    if [ "$cam" = "electron" ]; then
      setsid "$CMD" >/dev/null 2>&1 &
    else
      setsid google-chrome --new-window "$URL" >/dev/null 2>&1 &
    fi
    echo "  tentativa $tent, aguardando 60s..."
    sleep 60
    NP=$(pgrep -x "$ALVO" 2>/dev/null | wc -l)
    MB=$(medir "$ALVO")
    if [ "$NP" -gt 0 ] && [ "$MB" -ge "$PISO" ]; then break; fi
    echo "  tentativa $tent falhou ($NP proc, ${MB}MB)"
  done

  if [ "$NP" -eq 0 ] || [ "$MB" -lt "$PISO" ]; then
    echo "  PULADO: $RUN ($NP proc, ${MB}MB) apos 3 tentativas" | tee -a "$LOG"
    limpar
  else
    echo "  ok: $NP proc, ${MB}MB -> $RUN" | tee -a "$LOG"
    "$HOME/tcc/scripts/coletar.sh" "$RUN" "$APP" "$cam" C1 "$ALVO" "$SEG"
    limpar
    echo "  intervalo de 2 min"
    sleep 120
  fi
done <<< "$LISTA"

echo "===== LOTE $APP CONCLUIDO EM $(date) =====" | tee -a "$LOG"
