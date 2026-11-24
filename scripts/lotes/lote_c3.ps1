# =====================================================================
# Cenario C3, carga acumulada (Windows)
# Mede a memoria TOTAL DO SISTEMA enquanto os aplicativos sao abertos
# um a um, com cinco minutos de patamar em cada.
#
# Dois bracos:
#   desktop   = Slack (Electron) + Discord (Electron) + Outlook novo (WebView2)
#   navegador = os mesmos tres como abas do Chrome
#
#   .\lote_c3.ps1 -Conferir
#   .\lote_c3.ps1 -Braco desktop   -Reps 3
#   .\lote_c3.ps1 -Braco navegador -Reps 3
# =====================================================================
param(
  [switch]$Conferir,
  [ValidateSet("desktop","navegador")][string]$Braco = "desktop",
  [int]$Reps       = 3,
  [int]$SegBase    = 180,
  [int]$SegPatamar = 300,
  [int]$PisoMB     = 80,
  [string]$Saida   = "C:\tcc\dados"
)

[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$inv = [Globalization.CultureInfo]::InvariantCulture
function N1 { param($v) ([double]$v).ToString("0.#", $inv) }

if (-not (Test-Path $Saida)) { New-Item -ItemType Directory $Saida -Force | Out-Null }
$log = Join-Path $Saida "lote_c3_windows.log"

$chrome = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") |
          Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Write-Host "ERRO: Chrome nao encontrado" -ForegroundColor Red; exit 1 }

# Outlook novo, aplicativo da Microsoft Store
$alvoOlk = $null
$pkg = Get-AppxPackage *OutlookForWindows* -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) {
  try {
    $appId = (Get-AppxPackageManifest $pkg).Package.Applications.Application.Id | Select-Object -First 1
    $alvoOlk = "shell:AppsFolder\$($pkg.PackageFamilyName)!$appId"
  } catch { }
}
if (-not $alvoOlk) { Write-Host "ERRO: nao localizei o pacote do Outlook novo." -ForegroundColor Red; exit 1 }

# Discord, instalacao convencional
$exeDiscord = $null
$pr = Get-Process -Name Discord -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pr -and $pr.Path) { $exeDiscord = $pr.Path }
if (-not $exeDiscord) {
  $exeDiscord = Get-ChildItem "$env:LOCALAPPDATA\Discord" -Filter "Discord.exe" -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $exeDiscord) {
  Write-Host "ERRO: nao achei Discord.exe. Abra o Discord uma vez e rode de novo." -ForegroundColor Red; exit 1
}

# ordem fixa de entrada, igual nos dois bracos
$apps = @(
  @{ nome='slack';   url='https://app.slack.com/client' },
  @{ nome='discord'; url='https://discord.com/app' },
  @{ nome='outlook'; url='https://outlook.live.com/mail/0/' }
)

function MemSistemaMB {
  $o = Get-CimInstance Win32_OperatingSystem
  [math]::Round(($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1024, 1)
}
function NProcAlvo {
  if ($Braco -eq "desktop") {
    @(Get-Process -Name slack,Discord,olk,msedgewebview2 -ErrorAction SilentlyContinue).Count
  } else {
    @(Get-Process -Name chrome -ErrorAction SilentlyContinue).Count
  }
}
function Fechar {
  Get-Process -Name slack,Discord,olk,chrome -ErrorAction SilentlyContinue |
    ForEach-Object { try { $null = $_.CloseMainWindow() } catch { } }
  $w = 0
  while ((Get-Process -Name slack,Discord,olk,chrome -ErrorAction SilentlyContinue) -and $w -lt 25) { Start-Sleep 1; $w++ }
  Stop-Process -Name slack,Discord,olk,msedgewebview2,chrome -Force -ErrorAction SilentlyContinue
  $w = 0
  while ((Get-Process -Name slack,Discord,olk,chrome -ErrorAction SilentlyContinue) -and $w -lt 20) { Start-Sleep 1; $w++ }
  Start-Sleep 8
}
function Abrir { param([int]$Indice, [string]$Modo)
  $a = $apps[$Indice]
  if ($Modo -eq "desktop") {
    switch ($a.nome) {
      "slack"   { Start-Process explorer.exe -ArgumentList "slack://open" -ErrorAction SilentlyContinue }
      "discord" { Start-Process $exeDiscord -ErrorAction SilentlyContinue }
      "outlook" { Start-Process explorer.exe -ArgumentList $alvoOlk -ErrorAction SilentlyContinue }
    }
  } else {
    # a primeira abre a janela, as seguintes entram como aba na mesma janela
    if ($Indice -eq 0) { Start-Process $chrome -ArgumentList "--new-window",$a.url -ErrorAction SilentlyContinue }
    else               { Start-Process $chrome -ArgumentList "--new-tab",$a.url   -ErrorAction SilentlyContinue }
  }
}

# ---------------------------------------------------------------
# Conferencia: abre os tres em cada braco, mede e fecha. Nao grava.
# ---------------------------------------------------------------
if ($Conferir) {
  Write-Host ""
  Write-Host "=== CONFERENCIA DO C3 ===" -ForegroundColor Yellow
  Write-Host "Nao grava dado. Leva cerca de 6 minutos." -ForegroundColor Yellow
  $falhou = 0
  foreach ($modo in @("desktop","navegador")) {
    $Braco = $modo
    Write-Host ""
    Write-Host "[$modo] fechando tudo..." -ForegroundColor Cyan
    Fechar
    $base = MemSistemaMB
    Write-Host "  base do sistema: $base MB" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $apps.Count; $i++) {
      Abrir $i $modo
      Start-Sleep 45
      $m = MemSistemaMB
      $np = NProcAlvo
      $delta = $m - $base
      if ($np -eq 0 -or $delta -lt $PisoMB) {
        Write-Host ("  FALHOU {0}: {1} proc, +{2} MB sobre a base" -f $apps[$i].nome, $np, (N1 $delta)) -ForegroundColor Red
        $falhou++
      } else {
        Write-Host ("  OK     {0}: {1} proc, sistema em {2} MB, +{3} MB sobre a base" -f `
          $apps[$i].nome, $np, (N1 $m), (N1 $delta)) -ForegroundColor Green
      }
      $base = $m
    }
    Fechar
  }
  Write-Host ""
  if ($falhou -eq 0) {
    Write-Host "OS DOIS BRACOS PASSARAM. Pode soltar o lote:" -ForegroundColor Green
    Write-Host "   .\lote_c3.ps1 -Braco desktop   -Reps 3" -ForegroundColor Green
    Write-Host "   .\lote_c3.ps1 -Braco navegador -Reps 3" -ForegroundColor Green
  } else {
    Write-Host "$falhou passo(s) falharam. Me mande esta saida." -ForegroundColor Red
  }
  exit 0
}

# ---------------------------------------------------------------
# Lote
# ---------------------------------------------------------------
$porExec = $SegBase + ($apps.Count * $SegPatamar) + 130
Write-Host "Braco: $Braco  |  $Reps execucoes  |  cerca de $([math]::Round($Reps*$porExec/60)) minutos" -ForegroundColor Cyan

foreach ($r in 1..$Reps) {
  $rep = "{0:D2}" -f $r
  $run = "acumulado_${Braco}_C3_win_$rep"
  $arq = Join-Path $Saida "$run.csv"

  if (Test-Path $arq) { Write-Host "[$r/$Reps] $run ja existe, pulando" -ForegroundColor DarkYellow; continue }

  Write-Host "[$r/$Reps] $Braco rep $rep  $(Get-Date -Format HH:mm)" -ForegroundColor Cyan
  Fechar

  "timestamp,run_id,braco,cenario,so,n_apps,app_aberto,seg_no_patamar,mem_sistema_mb,n_processos" |
    Out-File -FilePath $arq -Encoding utf8

  # patamar zero: sistema sem nenhum aplicativo do experimento
  for ($t = 0; $t -lt $SegBase; $t++) {
    "{0},{1},{2},C3,Windows,0,nenhum,{3},{4},{5}" -f `
      (Get-Date -Format 'o'), $run, $Braco, $t, (N1 (MemSistemaMB)), (NProcAlvo) | Add-Content $arq
    Start-Sleep 1
  }
  # Media dos ultimos 60 segundos do patamar. O cast explicito evita que o
  # Measure-Object receba texto em vez de numero.
  $baseMB = (Import-Csv $arq | Select-Object -Last 60 |
             ForEach-Object { [double]$_.mem_sistema_mb } | Measure-Object -Average).Average
  Write-Host ("  base do sistema: {0} MB" -f (N1 $baseMB)) -ForegroundColor DarkGray

  for ($i = 0; $i -lt $apps.Count; $i++) {
    $nome = $apps[$i].nome
    Abrir $i $Braco
    Write-Host "  abriu $nome ($($i+1) de $($apps.Count)), patamar de $SegPatamar s" -ForegroundColor Gray
    for ($t = 0; $t -lt $SegPatamar; $t++) {
      "{0},{1},{2},C3,Windows,{3},{4},{5},{6},{7}" -f `
        (Get-Date -Format 'o'), $run, $Braco, ($i+1), $nome, $t, (N1 (MemSistemaMB)), (NProcAlvo) |
        Add-Content $arq
      Start-Sleep 1
    }
    $fim = (Import-Csv $arq | Select-Object -Last 60 |
            ForEach-Object { [double]$_.mem_sistema_mb } | Measure-Object -Average).Average
    Write-Host ("    patamar {0}: {1} MB, {2} processos, +{3} MB sobre a base" -f `
      ($i+1), (N1 $fim), (NProcAlvo), (N1 ($fim - $baseMB))) -ForegroundColor DarkGray
  }

  Fechar
  Add-Content $log "  ok: $run (base $(N1 $baseMB) MB)"
  Write-Host "  pronto: $arq" -ForegroundColor Green
  Start-Sleep 120
}

Write-Host "LOTE C3 CONCLUIDO: braco $Braco" -ForegroundColor Green
Add-Content $log "lote c3 $Braco concluido $(Get-Date -Format 'o')"
