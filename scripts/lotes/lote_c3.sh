#!/usr/bin/env bash
# =====================================================================
# Cenario C3, carga acumulada (Ubuntu)
# Mede a memoria TOTAL DO SISTEMA enquanto os aplicativos sao abertos
# um a um, com cinco minutos de patamar em cada.
#
# Dois bracos, com os dois aplicativos que existem no Linux:
#   desktop   = Slack (Electron) + Discord (Electron)
#   navegador = os mesmos dois como abas do Chrome
#
# Rode NA MAQUINA FISICA, nao por SSH, porque abre janelas.
#
#   bash ~/tcc/scripts/lote_c3.sh conferir
#   bash ~/tcc/scripts/lote_c3.sh desktop   3
#   bash ~/tcc/scripts/lote_c3.sh navegador 3
# =====================================================================
export LC_ALL=C LC_NUMERIC=C
source ~/tcc/scripts/ambiente.sh 2>/dev/null

BRACO="${1:?use conferir, desktop ou navegador}"
REPS="${2:-3}"
SEG_BASE="${3:-180}"
SEG_PATAMAR="${4:-300}"
PISO_MB=80
D="$HOME/tcc/dados"; mkdir -p "$D"
LOG="$D/lote_c3_linux.log"

NOMES=(slack discord)
URLS=("https://app.slack.com/client" "https://discord.com/app")

mem_sistema() {
  awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.1f",(t-a)/1024}' /proc/meminfo
}
nproc_alvo() {
  if [ "$BRACO" = "navegador" ]; then
    pgrep -x chrome 2>/dev/null | wc -l
  else
    echo $(( $(pgrep -x slack 2>/dev/null | wc -l) + $(pgrep -x Discord 2>/dev/null | wc -l) ))
  fi
}
fechar() {
  pkill -x slack   >/dev/null 2>&1
  pkill -x Discord >/dev/null 2>&1
  pkill -x chrome  >/dev/null 2>&1
  local w=0
  while [ $w -lt 20 ]; do
    if ! pgrep -x slack >/dev/null 2>&1 && ! pgrep -x Discord >/dev/null 2>&1 && ! pgrep -x chrome >/dev/null 2>&1; then
      break
    fi
    sleep 1; w=$((w+1))
  done
  sleep 8
}
abrir() {   # $1 indice  $2 modo
  local i="$1" modo="$2"
  if [ "$modo" = "desktop" ]; then
    if [ "${NOMES[$i]}" = "slack" ]; then
      setsid slack >/dev/null 2>&1 &
    else
      setsid discord >/dev/null 2>&1 &
    fi
  else
    if [ "$i" -eq 0 ]; then
      setsid google-chrome --new-window "${URLS[$i]}" >/dev/null 2>&1 &
    else
      setsid google-chrome --new-tab "${URLS[$i]}" >/dev/null 2>&1 &
    fi
  fi
}

# ---------------------------------------------------------------
# Conferencia
# ---------------------------------------------------------------
if [ "$BRACO" = "conferir" ]; then
  echo ""
  echo "=== CONFERENCIA DO C3 ==="
  echo "Nao grava dado. Leva cerca de 4 minutos."
  falhou=0
  for modo in desktop navegador; do
    BRACO="$modo"
    echo ""
    echo "[$modo] fechando tudo..."
    fechar
    base=$(mem_sistema)
    echo "  base do sistema: $base MB"
    for i in "${!NOMES[@]}"; do
      abrir "$i" "$modo"
      sleep 45
      m=$(mem_sistema); np=$(nproc_alvo)
      d=$(awk -v a="$m" -v b="$base" 'BEGIN{printf "%.1f", a-b}')
      ok=$(awk -v d="$d" -v p="$PISO_MB" 'BEGIN{print (d<p)?0:1}')
      if [ "$np" -eq 0 ] || [ "$ok" -eq 0 ]; then
        echo "  FALHOU ${NOMES[$i]}: $np proc, +$d MB sobre a base"
        falhou=$((falhou+1))
      else
        echo "  OK     ${NOMES[$i]}: $np proc, sistema em $m MB, +$d MB sobre a base"
      fi
      base="$m"
    done
    fechar
  done
  echo ""
  if [ "$falhou" -eq 0 ]; then
    echo "OS DOIS BRACOS PASSARAM. Pode soltar o lote:"
    echo "   bash ~/tcc/scripts/lote_c3.sh desktop   3"
    echo "   bash ~/tcc/scripts/lote_c3.sh navegador 3"
  else
    echo "$falhou passo(s) falharam. Me mande esta saida."
  fi
  exit 0
fi

if [ "$BRACO" != "desktop" ] && [ "$BRACO" != "navegador" ]; then
  echo "ERRO: use conferir, desktop ou navegador"; exit 1
fi

POR_EXEC=$(( SEG_BASE + ${#NOMES[@]} * SEG_PATAMAR + 130 ))
echo "Braco: $BRACO  |  $REPS execucoes  |  cerca de $(( REPS * POR_EXEC / 60 )) minutos"

for r in $(seq 1 "$REPS"); do
  rep=$(printf %02d "$r")
  RUN="acumulado_${BRACO}_C3_linux_$rep"
  ARQ="$D/$RUN.csv"

  if [ -f "$ARQ" ]; then
    echo "[$r/$REPS] $RUN ja existe, pulando"
  else
    echo "[$r/$REPS] $BRACO rep $rep  $(date +%H:%M)"
    fechar

    echo "timestamp,run_id,braco,cenario,so,n_apps,app_aberto,seg_no_patamar,mem_sistema_mb,n_processos" > "$ARQ"

    for ((t=0; t<SEG_BASE; t++)); do
      echo "$(date -Is),$RUN,$BRACO,C3,Linux,0,nenhum,$t,$(mem_sistema),$(nproc_alvo)" >> "$ARQ"
      sleep 1
    done
    BASE=$(tail -60 "$ARQ" | awk -F, '{s+=$9; n++} END{printf "%.1f", s/n}')
    echo "  base do sistema: $BASE MB"

    for i in "${!NOMES[@]}"; do
      abrir "$i" "$BRACO"
      echo "  abriu ${NOMES[$i]} ($((i+1)) de ${#NOMES[@]}), patamar de ${SEG_PATAMAR}s"
      for ((t=0; t<SEG_PATAMAR; t++)); do
        echo "$(date -Is),$RUN,$BRACO,C3,Linux,$((i+1)),${NOMES[$i]},$t,$(mem_sistema),$(nproc_alvo)" >> "$ARQ"
        sleep 1
      done
      FIM_P=$(tail -60 "$ARQ" | awk -F, '{s+=$9; n++} END{printf "%.1f", s/n}')
      awk -v p="$((i+1))" -v f="$FIM_P" -v b="$BASE" -v n="$(nproc_alvo)" \
        'BEGIN{printf "    patamar %s: %s MB, %s processos, +%.1f MB sobre a base\n", p, f, n, f-b}'
    done

    fechar
    echo "  ok: $RUN (base $BASE MB)" | tee -a "$LOG"
    echo "  pronto: $ARQ"
    sleep 120
  fi
done

echo "LOTE C3 CONCLUIDO: braco $BRACO"
echo "lote c3 $BRACO concluido $(date -Is)" >> "$LOG"
