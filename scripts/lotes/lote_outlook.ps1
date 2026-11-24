# =====================================================================
# Lote do cenario C1 (repouso) para o Outlook no Windows
# Tres camadas na mesma caixa postal:
#   nativo     = Outlook Desktop Classic   (processo OUTLOOK)
#   webview2   = Outlook novo              (olk + msedgewebview2, filtrado)
#   navegador  = Outlook na web no Chrome  (processo chrome)
#
# Exemplos:
#   .\lote_outlook.ps1 -Conferir            prova as tres camadas em 6 min
#   .\lote_outlook.ps1 -Reps 8 -Segundos 600
# =====================================================================
param(
  [switch]$Conferir,
  [int]$Reps      = 8,
  [int]$Segundos  = 600,
  [int]$Aquecer   = 90,
  [int]$PisoMB    = 80,
  [string]$UrlWeb = "https://outlook.live.com/mail/0/",
  [string]$ExeClassic = "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE",
  [string]$Scripts = "C:\tcc\scripts",
  [string]$Saida   = "C:\tcc\dados"
)

[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$col = Join-Path $Scripts "coletar_windows.ps1"
if (-not (Test-Path $col))        { Write-Host "ERRO: falta $col" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $ExeClassic)) { Write-Host "ERRO: nao achei o Outlook classico em $ExeClassic" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Saida)) { New-Item -ItemType Directory $Saida -Force | Out-Null }
$log = Join-Path $Saida "lote_outlook_C1_windows.log"

$chrome = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") |
          Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Write-Host "ERRO: Chrome nao encontrado" -ForegroundColor Red; exit 1 }

# Descobre como abrir o Outlook novo, que e aplicativo da Microsoft Store
$alvoOlk = $null
$pkg = Get-AppxPackage *OutlookForWindows* -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) {
  try {
    $appId = (Get-AppxPackageManifest $pkg).Package.Applications.Application.Id | Select-Object -First 1
    $alvoOlk = "shell:AppsFolder\$($pkg.PackageFamilyName)!$appId"
  } catch { }
}
if (-not $alvoOlk) {
  Write-Host "ERRO: nao localizei o pacote do Outlook novo." -ForegroundColor Red
  Write-Host "Pacotes com 'utlook' no nome, para diagnostico:" -ForegroundColor Yellow
  Get-AppxPackage | Where-Object { $_.Name -like "*utlook*" } |
    Select-Object Name, PackageFamilyName | Format-Table -AutoSize
  Write-Host "Me mande essa lista." -ForegroundColor Yellow
  exit 1
}

Write-Host "Classico  : $ExeClassic"            -ForegroundColor Cyan
Write-Host "Novo      : $alvoOlk"               -ForegroundColor Cyan
Write-Host "Navegador : $chrome -> $UrlWeb"     -ForegroundColor Cyan
Write-Host "Execucoes : $($Reps * 3) de $Segundos s" -ForegroundColor Cyan

# ---------------------------------------------------------------
# Mesma logica de arvore do coletor, para a conferencia previa
# ---------------------------------------------------------------
function Arvore {
  param([string[]]$Nomes, [string]$Filtro = "")
  $arv = @{}
  $todos = Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,CommandLine -ErrorAction SilentlyContinue
  if (-not $todos) { return $arv }
  $filhos = @{}; $raizes = New-Object System.Collections.Generic.List[int]
  foreach ($p in $todos) {
    $pai = [int]$p.ParentProcessId
    if (-not $filhos.ContainsKey($pai)) { $filhos[$pai] = New-Object System.Collections.Generic.List[int] }
    $filhos[$pai].Add([int]$p.ProcessId)
    $nome = $p.Name -replace '\.exe$',''
    foreach ($a in $Nomes) {
      if ($nome -ieq $a) {
        if ([string]::IsNullOrWhiteSpace($Filtro)) { $raizes.Add([int]$p.ProcessId) }
        elseif ($p.CommandLine -and $p.CommandLine -like "*$Filtro*") { $raizes.Add([int]$p.ProcessId) }
        break
      }
    }
  }
  $fila = New-Object System.Collections.Generic.Queue[int]
  foreach ($r in $raizes) { if (-not $arv.ContainsKey($r)) { $arv[$r] = $true; $fila.Enqueue($r) } }
  while ($fila.Count -gt 0) {
    $at = $fila.Dequeue()
    if ($filhos.ContainsKey($at)) {
      foreach ($f in $filhos[$at]) { if (-not $arv.ContainsKey($f)) { $arv[$f] = $true; $fila.Enqueue($f) } }
    }
  }
  return $arv
}

function MemMB { param($arv)
  if ($arv.Count -eq 0) { return 0 }
  $s = (Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess,WorkingSetPrivate -ErrorAction SilentlyContinue |
        Where-Object { $arv.ContainsKey([int]$_.IDProcess) } | Measure-Object -Property WorkingSetPrivate -Sum).Sum
  if ($s) { return [math]::Round($s/1MB,0) } else { return 0 }
}

function Fechar {
  # Pede o fechamento normal primeiro. Matar o Outlook classico oito vezes
  # seguidas marcaria o arquivo de dados como sujo e a abertura seguinte
  # viria com a tela de recuperacao, que estragaria a medicao.
  Get-Process -Name OUTLOOK,olk,chrome -ErrorAction SilentlyContinue | ForEach-Object {
    try { $null = $_.CloseMainWindow() } catch { }
  }
  $w = 0
  while ((Get-Process -Name OUTLOOK,olk,chrome -ErrorAction SilentlyContinue) -and $w -lt 30) { Start-Sleep 1; $w++ }

  # O que nao saiu sozinho em trinta segundos vai a forca.
  Stop-Process -Name OUTLOOK,olk,msedgewebview2,chrome -Force -ErrorAction SilentlyContinue
  $w = 0
  while ((Get-Process -Name OUTLOOK,olk,chrome -ErrorAction SilentlyContinue) -and $w -lt 20) { Start-Sleep 1; $w++ }
  Start-Sleep 5
}

function Abrir { param([string]$Camada)
  switch ($Camada) {
    "nativo"    { Start-Process $ExeClassic -ErrorAction SilentlyContinue }
    "webview2"  { Start-Process explorer.exe -ArgumentList $alvoOlk -ErrorAction SilentlyContinue }
    "navegador" { Start-Process $chrome -ArgumentList "--new-window",$UrlWeb -ErrorAction SilentlyContinue }
  }
}
function Alvos { param([string]$Camada)
  switch ($Camada) {
    "nativo"    { return @{ nomes = @("OUTLOOK");              filtro = ""    } }
    "webview2"  { return @{ nomes = @("olk","msedgewebview2"); filtro = "Olk" } }
    "navegador" { return @{ nomes = @("chrome");               filtro = ""    } }
  }
}

# ---------------------------------------------------------------
# Modo conferencia: abre cada camada uma vez, mede, fecha e sai.
# Nao grava dado nenhum. Serve para provar que o lote vai funcionar
# antes de gastar cinco horas nele.
# ---------------------------------------------------------------
if ($Conferir) {
  Write-Host ""
  Write-Host "=== CONFERENCIA DAS TRES CAMADAS ===" -ForegroundColor Yellow
  Write-Host "Nao grava dado. Leva cerca de $([math]::Round((3*($Aquecer+45))/60)) minutos." -ForegroundColor Yellow
  Write-Host ""
  $falhou = 0
  foreach ($cam in @("nativo","webview2","navegador")) {
    Write-Host "[$cam] fechando tudo e abrindo..." -ForegroundColor Cyan
    Fechar
    Abrir $cam
    Start-Sleep $Aquecer
    $a = Alvos $cam
    $arv = Arvore -Nomes $a.nomes -Filtro $a.filtro
    $mb  = MemMB $arv
    if ($arv.Count -eq 0) {
      Write-Host "  FALHOU: nenhum processo. A camada nao abriu." -ForegroundColor Red
      $falhou++
    } elseif ($mb -lt $PisoMB) {
      Write-Host "  FALHOU: $($arv.Count) proc mas so ${mb}MB, abaixo do piso de ${PisoMB}MB." -ForegroundColor Red
      $falhou++
    } else {
      Write-Host "  OK: $($arv.Count) processos, ${mb}MB" -ForegroundColor Green
      Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $arv.ContainsKey([int]$_.Id) } |
        Group-Object ProcessName | Sort-Object Count -Descending |
        ForEach-Object { Write-Host ("      {0,-22} {1}" -f $_.Name, $_.Count) -ForegroundColor DarkGray }
    }
  }
  Fechar
  Write-Host ""
  if ($falhou -eq 0) {
    Write-Host "AS TRES CAMADAS PASSARAM. Pode soltar o lote." -ForegroundColor Green
    Write-Host "   .\lote_outlook.ps1 -Reps 8 -Segundos 600" -ForegroundColor Green
  } else {
    Write-Host "$falhou camada(s) falharam. NAO solte o lote ainda." -ForegroundColor Red
    Write-Host "Me mande essa saida que eu corrijo." -ForegroundColor Yellow
  }
  exit 0
}

# ---------------------------------------------------------------
# Sorteia a ordem, para a variacao da maquina nao cair toda numa camada
# ---------------------------------------------------------------
$lista = @()
1..$Reps | ForEach-Object {
  $r = "{0:D2}" -f $_
  foreach ($c in @("nativo","webview2","navegador")) {
    $lista += [pscustomobject]@{ c = $c; r = $r }
  }
}
$lista = $lista | Sort-Object { Get-Random }
$lista | ForEach-Object { "$($_.c) $($_.r)" } |
  Out-File (Join-Path $Saida "ordem_outlook_C1_windows.txt") -Encoding utf8

$n = 0
foreach ($it in $lista) {
  $n++; $cam = $it.c; $rep = $it.r
  $run = "outlook_${cam}_C1_win_$rep"

  if (Test-Path (Join-Path $Saida "$run.csv")) {
    Write-Host "[$n/$($lista.Count)] $run ja existe, pulando" -ForegroundColor DarkYellow
    continue
  }

  Write-Host "[$n/$($lista.Count)] $cam rep $rep  $(Get-Date -Format HH:mm)" -ForegroundColor Cyan
  Fechar

  $a = Alvos $cam
  $nomes = $a.nomes; $filtro = $a.filtro

  Abrir $cam
  Start-Sleep $Aquecer

  $arv = Arvore -Nomes $nomes -Filtro $filtro
  $mb  = MemMB $arv

  if ($arv.Count -eq 0 -or $mb -lt $PisoMB) {
    $m = "  PULADO: $run ($($arv.Count) proc, ${mb}MB, piso ${PisoMB}MB)"
    Write-Host $m -ForegroundColor Red
    Add-Content $log $m
    Fechar
    Start-Sleep 120
  } else {
    Write-Host "  ok: $($arv.Count) proc, ${mb}MB" -ForegroundColor Green
    Add-Content $log "  ok: $($arv.Count) proc, ${mb}MB -> $run"
    & $col -RunId $run -App outlook -Camada $cam -Cenario C1 `
           -Processos $nomes -Contem $filtro -Segundos $Segundos -Saida $Saida
    Fechar
    Write-Host "  intervalo de 2 min" -ForegroundColor DarkGray
    Start-Sleep 120
  }
}

Write-Host "LOTE CONCLUIDO" -ForegroundColor Green
Add-Content $log "lote concluido $(Get-Date -Format 'o')"
