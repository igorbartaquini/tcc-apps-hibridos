#!/usr/bin/env bash
# =====================================================================
# Linha de base do sistema em repouso (cenario C0) no Ubuntu
# Mede a memoria em uso da MAQUINA INTEIRA, nao de um aplicativo.
#
# Rode logo depois de reiniciar, sem nada aberto.
#
#   bash ~/tcc/scripts/baseline.sh 300
# =====================================================================
export LC_ALL=C LC_NUMERIC=C

SEGUNDOS="${1:-300}"
SAIDA="${SAIDA:-$HOME/tcc/dados}"
RUN_ID="${2:-baseline_linux_$(date +%Y%m%d_%H%M)}"
mkdir -p "$SAIDA"
ARQ="$SAIDA/$RUN_ID.csv"

echo "timestamp,run_id,app,camada,cenario,so,n_processos,memoria_em_uso_mb,memoria_livre_mb,memoria_total_mb,commit_mb" > "$ARQ"

echo "Linha de base do sistema, $SEGUNDOS segundos. Nao toque na maquina."

for ((i=0; i<SEGUNDOS; i++)); do
  T0=$(date +%s%N)
  # MemAvailable e a medida correta de memoria disponivel no Linux:
  # MemFree ignora cache e buffers recuperaveis e subestima muito.
  read -r TOT DISP COMMIT < <(awk '
    /^MemTotal:/      {t=$2}
    /^MemAvailable:/  {d=$2}
    /^Committed_AS:/  {c=$2}
    END {print t, d, c}' /proc/meminfo)
  NPROC=$(ls -1d /proc/[0-9]* 2>/dev/null | wc -l)

  awk -v ts="$(date -Is)" -v r="$RUN_ID" -v n="$NPROC" -v t="$TOT" -v d="$DISP" -v c="$COMMIT" \
    'BEGIN{printf "%s,%s,sistema,nenhuma,C0,Linux,%d,%.2f,%.2f,%.2f,%.2f\n", ts, r, n, (t-d)/1024, d/1024, t/1024, c/1024}' >> "$ARQ"

  if [ $((i % 60)) -eq 0 ]; then
    awk -v i="$i" -v t="$TOT" -v d="$DISP" -v n="$NPROC" 'BEGIN{printf "  %ds  -  %.0f MB em uso  -  %d processos\n", i, (t-d)/1024, n}'
  fi

  GASTO=$(( ($(date +%s%N) - T0) / 1000000 ))
  ESPERA=$(( 1000 - GASTO ))
  [ "$ESPERA" -gt 0 ] && sleep "$(awk -v e=$ESPERA 'BEGIN{print e/1000}')"
done

echo "Pronto: $ARQ"
