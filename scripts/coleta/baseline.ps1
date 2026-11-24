# =====================================================================
# Linha de base do sistema em repouso (cenario C0) no Windows
# Mede a memoria em uso da MAQUINA INTEIRA, nao de um aplicativo.
# Serve para a secao 5.1 dos resultados: sem essa referencia, nenhum
# numero de aplicativo tem significado.
#
# Rode logo depois de reiniciar, sem nada aberto, e nao toque na maquina.
#
#   .\baseline.ps1 -Segundos 300
# =====================================================================
param(
  [int]$Segundos = 300,
  [string]$Saida = "C:\tcc\dados",
  [string]$RunId = ""
)

[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$inv = [Globalization.CultureInfo]::InvariantCulture
function N2 { param($v) ([double]$v).ToString("0.##", $inv) }

if (-not $RunId) { $RunId = "baseline_win_$(Get-Date -Format yyyyMMdd_HHmm)" }
if (-not (Test-Path $Saida)) { New-Item -ItemType Directory $Saida -Force | Out-Null }
$arq = Join-Path $Saida "$RunId.csv"

$os  = Get-CimInstance Win32_OperatingSystem
$tot = [math]::Round($os.TotalVisibleMemorySize / 1024)

"timestamp,run_id,app,camada,cenario,so,n_processos,memoria_em_uso_mb,memoria_livre_mb,memoria_total_mb,commit_mb" |
  Out-File -FilePath $arq -Encoding utf8

Write-Host "Linha de base do sistema, $Segundos segundos. Nao toque na maquina." -ForegroundColor Cyan
Write-Host "RAM total: $tot MB" -ForegroundColor Cyan

for ($i = 0; $i -lt $Segundos; $i++) {
  $t0 = Get-Date
  $o  = Get-CimInstance Win32_OperatingSystem
  $livre  = [math]::Round($o.FreePhysicalMemory / 1024)
  $emUso  = $tot - $livre
  $commit = [math]::Round(($o.TotalVirtualMemorySize - $o.FreeVirtualMemory) / 1024)
  $nproc  = @(Get-Process -ErrorAction SilentlyContinue).Count

  "{0},{1},sistema,nenhuma,C0,Windows,{2},{3},{4},{5},{6}" -f `
    (Get-Date -Format 'o'), $RunId, $nproc, (N2 $emUso), (N2 $livre), (N2 $tot), (N2 $commit) |
    Add-Content -Path $arq

  if ($i % 60 -eq 0) {
    Write-Host ("  {0}s  -  {1} MB em uso  -  {2} processos" -f $i, $emUso, $nproc) -ForegroundColor DarkGray
  }
  $espera = 1000 - ((Get-Date) - $t0).TotalMilliseconds
  if ($espera -gt 0) { Start-Sleep -Milliseconds $espera }
}
Write-Host "Pronto: $arq" -ForegroundColor Green
