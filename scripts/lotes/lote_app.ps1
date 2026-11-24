# =====================================================================
# Lote generico do cenario C1 (repouso) no Windows
# Serve para qualquer aplicativo: Slack, Discord, Teams, Outlook
#
# Exemplos:
#   .\lote_app.ps1 -App discord -ProcElectron discord -UrlWeb "https://discord.com/app" -Reps 12
#   .\lote_app.ps1 -App slack   -ProcElectron slack   -UrlWeb "https://app.slack.com/client" -Reps 12
# =====================================================================
param(
  [Parameter(Mandatory=$true)][string]$App,
  [Parameter(Mandatory=$true)][string]$ProcElectron,
  [Parameter(Mandatory=$true)][string]$UrlWeb,
  [string]$ProtoElectron = "",          # ex: "discord://" ; vazio = procura o .exe
  [int]$Reps = 12,
  [int]$Segundos = 600,
  [int]$PisoMB = 150,
  [string]$Scripts = "C:\tcc\scripts",
  [string]$Saida   = "C:\tcc\dados"
)
[Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::InvariantCulture
$col = Join-Path $Scripts "coletar_windows.ps1"
if (-not (Test-Path $col)) { Write-Host "ERRO: falta $col" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Saida)) { New-Item -ItemType Directory $Saida -Force | Out-Null }
$log = Join-Path $Saida "lote_${App}_C1_windows.log"

$chrome = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") |
          Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Write-Host "ERRO: Chrome nao encontrado" -ForegroundColor Red; exit 1 }

# como abrir a camada Electron
$exeElectron = $null
if (-not $ProtoElectron) {
  $pr = Get-Process -Name $ProcElectron -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pr -and $pr.Path) { $exeElectron = $pr.Path }
  else {
    $exeElectron = Get-ChildItem "$env:LOCALAPPDATA" -Filter "$ProcElectron.exe" -Recurse -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
  }
}
Write-Host "App       : $App" -ForegroundColor Cyan
Write-Host "Electron  : $(if($ProtoElectron){$ProtoElectron}else{$exeElectron})" -ForegroundColor Cyan
Write-Host "Navegador : $chrome -> $UrlWeb" -ForegroundColor Cyan
if (-not $ProtoElectron -and -not $exeElectron) {
  Write-Host "ERRO: nao localizei o executavel. Abra o app e rode de novo, ou use -ProtoElectron." -ForegroundColor Red; exit 1
}

$lista = @()
1..$Reps | ForEach-Object { $r = "{0:D2}" -f $_
  $lista += [pscustomobject]@{c="electron";  r=$r}
  $lista += [pscustomobject]@{c="navegador"; r=$r} }
$lista = $lista | Sort-Object { Get-Random }
$lista | ForEach-Object { "$($_.c) $($_.r)" } | Out-File (Join-Path $Saida "ordem_${App}_C1_windows.txt") -Encoding utf8

$n = 0
foreach ($it in $lista) {
  $n++; $cam = $it.c; $rep = $it.r
  $run  = "${App}_${cam}_C1_win_$rep"
  $alvo = if ($cam -eq "electron") { $ProcElectron } else { "chrome" }
  Write-Host "[$n/$($lista.Count)] $cam rep $rep  $(Get-Date -Format HH:mm)" -ForegroundColor Cyan

  Stop-Process -Name $ProcElectron,chrome -Force -ErrorAction SilentlyContinue
  $w=0; while ((Get-Process -Name $ProcElectron,chrome -ErrorAction SilentlyContinue) -and $w -lt 20) { Start-Sleep 1; $w++ }
  Start-Sleep 5

  if ($cam -eq "electron") {
    if ($ProtoElectron) { Start-Process explorer.exe -ArgumentList $ProtoElectron -ErrorAction SilentlyContinue }
    else { Start-Process $exeElectron -WindowStyle Hidden -ErrorAction SilentlyContinue }
  } else {
    Start-Process $chrome -ArgumentList "--new-window",$UrlWeb -WindowStyle Hidden -ErrorAction SilentlyContinue
  }
  Start-Sleep 60

  $ids = @((Get-Process -Name $alvo -ErrorAction SilentlyContinue).Id); $mb = 0
  if ($ids.Count -gt 0) {
    $s = (Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess,WorkingSetPrivate -ErrorAction SilentlyContinue |
          Where-Object { $ids -contains [int]$_.IDProcess } | Measure-Object -Property WorkingSetPrivate -Sum).Sum
    if ($s) { $mb = [math]::Round($s/1MB,0) }
  }
  if ($ids.Count -eq 0 -or $mb -lt $PisoMB) {
    $m = "  PULADO: $run ($($ids.Count) proc, ${mb}MB)"
    Write-Host $m -ForegroundColor Red; Add-Content $log $m
    Stop-Process -Name $ProcElectron,chrome -Force -ErrorAction SilentlyContinue; Start-Sleep 120
  } else {
    Write-Host "  ok: $($ids.Count) proc, ${mb}MB" -ForegroundColor Green
    Add-Content $log "  ok: $($ids.Count) proc, ${mb}MB -> $run"
    & $col -RunId $run -App $App -Camada $cam -Cenario C1 -Processos $alvo -Segundos $Segundos -Saida $Saida
    Stop-Process -Name $ProcElectron,chrome -Force -ErrorAction SilentlyContinue
    Write-Host "  intervalo de 2 min" -ForegroundColor DarkGray; Start-Sleep 120
  }
}
Write-Host "LOTE CONCLUIDO" -ForegroundColor Green
Add-Content $log "lote concluido $(Get-Date -Format 'o')"
