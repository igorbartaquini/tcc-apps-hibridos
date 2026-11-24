#!/usr/bin/env bash
# Lote generico do cenario C1 (repouso) no Linux
# Uso: ./lote_app.sh discord discord "https://discord.com/app" 12 600
set -uo pipefail
export LC_ALL=C LC_NUMERIC=C
source ~/tcc/scripts/ambiente.sh 2>/dev/null || export DISPLAY=${DISPLAY:-:0}
APP="${1:?app}"; PROC="${2:?nome do processo}"; URL="${3:?url web}"
REPS="${4:-12}"; SEG="${5:-600}"; PISO="${6:-200}"
LOG=~/tcc/dados/lote_${APP}_C1_linux.log
LISTA=$(for i in $(seq 1 $REPS); do n=$(printf %02d $i); echo "electron $n"; echo "navegador $n"; done | shuf)
echo "$LISTA" > ~/tcc/dados/ordem_${APP}_C1_linux.txt
TOTAL=$(echo "$LISTA"|wc -l); N=0
echo "$LISTA" | while read cam i; do
  N=$((N+1)); echo "[$N/$TOTAL] $cam rep $i  $(date +%H:%M)"
  pkill -f "$PROC" 2>/dev/null; pkill -f chrome 2>/dev/null; sleep 5
  if [ "$cam" = "electron" ]; then
    ALVO="$PROC"; RUN="${APP}_electron_C1_linux_$i"; setsid "$PROC" >/dev/null 2>&1 &
  else
    ALVO="chrome"; RUN="${APP}_navegador_C1_linux_$i"
    setsid google-chrome --new-window "$URL" >/dev/null 2>&1 &
  fi
  sleep 60
  NP=$(pgrep -x "$ALVO" 2>/dev/null|wc -l); MB=0
  for p in $(pgrep -x "$ALVO" 2>/dev/null); do
    v=$(awk '/^Pss:/{s+=$2}END{print int(s/1024)}' /proc/$p/smaps_rollup 2>/dev/null||echo 0); MB=$((MB+v))
  done
  if [ "$NP" -eq 0 ] || [ "$MB" -lt "$PISO" ]; then
    echo "  PULADO: $RUN ($NP proc, ${MB}MB)" | tee -a $LOG
    pkill -f "$PROC" 2>/dev/null; pkill -f chrome 2>/dev/null; sleep 120; continue
  fi
  echo "  ok: $NP proc, ${MB}MB -> $RUN" | tee -a $LOG
  ~/tcc/scripts/coletar.sh "$RUN" "$APP" "$cam" C1 "$ALVO" $SEG
  pkill -f "$PROC" 2>/dev/null; pkill -f chrome 2>/dev/null
  echo "  intervalo de 2 min"; sleep 120
done
echo "LOTE CONCLUIDO"
