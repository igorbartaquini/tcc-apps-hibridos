# =====================================================================
# Lote do cenario C1 (repouso) no Windows, ordem sorteada  -  versao 3
#
# Correcoes da v1:
#   - descobre sozinho onde o Slack esta instalado
#   - nao usa "continue", que estava disparando o modo de depuracao
#   - confere se a quantidade de processos mudou entre a verificacao e a
#     coleta, situacao que contaminou a execucao 03
#
# Novidades da v3:
#   - abre o Slack pelo protocolo slack://open, o que contorna a restricao
#     de permissao da pasta WindowsApps nas instalacoes via Microsoft Store
#   - abre os aplicativos com janela oculta do console, para o log do Slack
#     nao poluir a saida do lote
#
# Uso:  .\lote_c1.ps1 -Reps 6 -Segundos 600
# =====================================================================
param(
  [int]$Reps = 12,
  [int]$Segundos = 600,
  [int]$PisoMB = 150,
  [string]$Scripts = "C:\tcc\scripts",
  [string]$Saida   = "C:\tcc\dados"
)

[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
if (-not (Test-Path $Saida)) { New-Item -ItemType Directory -Path $Saida -Force | Out-Null }
$log = Join-Path $Saida "lote_c1_windows.log"

# --- o coletor existe? ---
$coletor = Join-Path $Scripts "coletar_windows.ps1"
if (-not (Test-Path $coletor)) {
  Write-Host "ERRO: nao encontrei $coletor" -ForegroundColor Red
  Write-Host "Copie o coletar_windows.ps1 para $Scripts e rode de novo." -ForegroundColor Yellow
  exit 1
}

# --- onde esta o Slack? ---
function Find-Slack {
  # 1) processo em execucao
  $p = Get-Process -Name slack -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p -and $p.Path) { return $p.Path }
  # 2) caminhos usuais
  $tentativas = @(
    "$env:LOCALAPPDATA\slack\slack.exe",
    "$env:LOCALAPPDATA\Programs\slack\slack.exe",
    "${env:ProgramFiles}\Slack\slack.exe",
    "${env:ProgramFiles(x86)}\Slack\slack.exe"
  )
  foreach ($t in $tentativas) { if (Test-Path $t) { return $t } }
  # 3) busca dentro do perfil
  $achado = Get-ChildItem "$env:LOCALAPPDATA" -Filter "slack.exe" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($achado) { return $achado.FullName }
  # 4) atalho do menu iniciar (funciona ate para versao da Store)
  $lnk = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Filter "Slack.lnk" -Recurse -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($lnk) { return $lnk.FullName }
  return $null
}

function Find-Chrome {
  $p = Get-Process -Name chrome -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p -and $p.Path) { return $p.Path }
  foreach ($t in @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                   "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                   "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
    if (Test-Path $t) { return $t }
  }
  return $null
}

$caminhoSlack  = Find-Slack
$caminhoChrome = Find-Chrome

Write-Host "Slack : protocolo slack://open" -ForegroundColor Cyan
if ($caminhoSlack) { Write-Host "        (instalado em $caminhoSlack)" -ForegroundColor DarkGray }
Write-Host "Chrome: $caminhoChrome" -ForegroundColor Cyan
if (-not $caminhoChrome) {
  Write-Host "ERRO: nao localizei o Chrome. Abra-o e rode de novo." -ForegroundColor Red
  exit 1
}

$procs = @{ electron = "slack"; navegador = "chrome" }

# --- monta a lista e sorteia ---
$lista = @()
foreach ($i in 1..$Reps) {
  foreach ($c in @("electron","navegador")) {
    $lista += [pscustomobject]@{ camada = $c; rep = "{0:D2}" -f $i }
  }
}
$lista = $lista | Sort-Object { Get-Random }
$lista | ForEach-Object { "$($_.camada) $($_.rep)" } |
  Out-File (Join-Path $Saida "ordem_c1_windows.txt") -Encoding utf8

$total = $lista.Count; $n = 0
foreach ($item in $lista) {
  $n++
  $cam = $item.camada; $rep = $item.rep
  $run = "slack_${cam}_C1_win_$rep"
  $alvo = $procs[$cam]
  Write-Host "[$n/$total] $cam rep $rep  $(Get-Date -Format HH:mm)" -ForegroundColor Cyan

  # limpeza: encerra tudo e espera de fato terminar
  Stop-Process -Name slack,chrome -Force -ErrorAction SilentlyContinue
  $espera = 0
  while ((Get-Process -Name slack,chrome -ErrorAction SilentlyContinue) -and $espera -lt 20) {
    Start-Sleep -Seconds 1; $espera++
  }
  Start-Sleep -Seconds 5

  if ($cam -eq "electron") {
    Start-Process "slack://open" -WindowStyle Hidden -ErrorAction SilentlyContinue
  } else {
    Start-Process $caminhoChrome -ArgumentList "--new-window","https://app.slack.com/client" -WindowStyle Hidden -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 60

  # verificacao antes de coletar
  $pids = @((Get-Process -Name $alvo -ErrorAction SilentlyContinue).Id)
  $mb = 0
  if ($pids.Count -gt 0) {
    $perf = Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess,WorkingSetPrivate -ErrorAction SilentlyContinue
    $soma = ($perf | Where-Object { $pids -contains [int]$_.IDProcess } |
             Measure-Object -Property WorkingSetPrivate -Sum).Sum
    if ($soma) { $mb = [math]::Round($soma/1MB,0) }
  }

  if ($pids.Count -eq 0 -or $mb -lt $PisoMB) {
    $msg = "  PULADO: $run  ($($pids.Count) proc, ${mb}MB). App nao abriu ou esta na tela de login."
    Write-Host $msg -ForegroundColor Red
    Add-Content $log $msg
    Stop-Process -Name slack,chrome -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 120
  }
  else {
    $antes = $pids.Count
    Add-Content $log "  ok: $antes proc, ${mb}MB. Coletando $run..."
    Write-Host "  ok: $antes proc, ${mb}MB. Coletando..." -ForegroundColor Green

    & $coletor -RunId $run -App slack -Camada $cam -Cenario C1 `
        -Processos $alvo -Segundos $Segundos -Saida $Saida

    # a arvore mudou durante a coleta?
    $depois = @((Get-Process -Name $alvo -ErrorAction SilentlyContinue).Id).Count
    if ($depois -gt ($antes * 1.3)) {
      $av = "  ATENCAO: $run comecou com $antes processos e terminou com $depois. Conferir antes de usar."
      Write-Host $av -ForegroundColor Yellow
      Add-Content $log $av
    }

    Stop-Process -Name slack,chrome -Force -ErrorAction SilentlyContinue
    Write-Host "  intervalo de 2 min" -ForegroundColor DarkGray
    Start-Sleep -Seconds 120
  }
}

Write-Host "LOTE CONCLUIDO" -ForegroundColor Green
Add-Content $log "lote concluido em $(Get-Date -Format 'o')"
