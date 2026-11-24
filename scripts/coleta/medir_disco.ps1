# =====================================================================
# Medicao de disco (QP4) no Windows, tudo num comando
# Gera C:\tcc\dados\disco_windows.csv com uma linha por alvo.
#
# Rode como Administrador, depois de ter usado cada aplicativo pelo
# menos uma vez, para o cache ja existir.
#
#   .\medir_disco.ps1
# =====================================================================
param([string]$Saida = "C:\tcc\dados")

[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$inv = [Globalization.CultureInfo]::InvariantCulture
if (-not (Test-Path $Saida)) { New-Item -ItemType Directory $Saida -Force | Out-Null }
$arq = Join-Path $Saida "disco_windows.csv"

$res = New-Object System.Collections.Generic.List[object]

function Medir {
  param([string]$Alvo, [string]$Camada, [string]$Tipo, [string]$Caminho)
  if ([string]::IsNullOrWhiteSpace($Caminho) -or -not (Test-Path -LiteralPath $Caminho)) {
    $res.Add([pscustomobject]@{ alvo=$Alvo; camada=$Camada; tipo=$Tipo; mb="0"; arquivos=0; existe="nao"; caminho=$Caminho })
    return
  }
  $itens = Get-ChildItem -LiteralPath $Caminho -Recurse -Force -File -ErrorAction SilentlyContinue
  $soma  = ($itens | Measure-Object -Property Length -Sum).Sum
  if (-not $soma) { $soma = 0 }
  $res.Add([pscustomobject]@{
    alvo     = $Alvo
    camada   = $Camada
    tipo     = $Tipo
    mb       = ([math]::Round($soma/1MB,2)).ToString("0.##", $inv)
    arquivos = @($itens).Count
    existe   = "sim"
    caminho  = $Caminho
  })
}

# Resolve a pasta de instalacao de um aplicativo da Microsoft Store
function LojaInstalado { param([string]$Padrao)
  $p = Get-AppxPackage $Padrao -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { return $p.InstallLocation } else { return "" }
}
# Resolve a pasta de dados e cache de um aplicativo da Microsoft Store
function LojaDados { param([string]$Padrao)
  $p = Get-AppxPackage $Padrao -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { return (Join-Path "$env:LOCALAPPDATA\Packages" $p.PackageFamilyName) } else { return "" }
}

Write-Host "Medindo disco. Pode levar alguns minutos." -ForegroundColor Cyan

# ---------- 1. instaladores baixados ----------
Get-ChildItem "C:\tcc\instaladores" -File -ErrorAction SilentlyContinue | ForEach-Object {
  $res.Add([pscustomobject]@{
    alvo=$_.Name; camada="instalador"; tipo="instalador"
    mb=([math]::Round($_.Length/1MB,2)).ToString("0.##",$inv)
    arquivos=1; existe="sim"; caminho=$_.FullName })
}

# ---------- 2. motor compartilhado ----------
# Numero central da QP4: o runtime do WebView2 e instalado uma vez e
# atendido a todos os aplicativos que o usam.
Write-Host "  runtime WebView2..." -ForegroundColor DarkGray
Medir "webview2_runtime" "compartilhado" "instalado" "C:\Program Files (x86)\Microsoft\EdgeWebView\Application"
Medir "chrome"           "compartilhado" "instalado" "C:\Program Files\Google\Chrome\Application"

# ---------- 3. instalado por aplicativo ----------
Write-Host "  instalado..." -ForegroundColor DarkGray
Medir "slack"            "electron" "instalado" (LojaInstalado "*SlackDesktop*")
Medir "slack_appdata"    "electron" "instalado" "$env:LOCALAPPDATA\slack"
Medir "discord"          "electron" "instalado" "$env:LOCALAPPDATA\Discord"
Medir "outlook_novo"     "webview2" "instalado" (LojaInstalado "*OutlookForWindows*")
Medir "outlook_classico" "nativo"   "instalado" "C:\Program Files\Microsoft Office\root\Office16"

# ---------- 4. perfil e cache por aplicativo ----------
Write-Host "  perfil e cache..." -ForegroundColor DarkGray
Medir "slack"            "electron"  "perfil_cache" (LojaDados "*SlackDesktop*")
Medir "slack_roaming"    "electron"  "perfil_cache" "$env:APPDATA\Slack"
Medir "discord"          "electron"  "perfil_cache" "$env:APPDATA\discord"
Medir "outlook_novo"     "webview2"  "perfil_cache" (LojaDados "*OutlookForWindows*")
Medir "outlook_classico" "nativo"    "perfil_cache" "$env:LOCALAPPDATA\Microsoft\Outlook"
Medir "chrome_perfil"    "navegador" "perfil_cache" "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"

$res | Export-Csv -LiteralPath $arq -NoTypeInformation -Encoding UTF8
Write-Host ""
$res | Format-Table alvo, camada, tipo, mb, arquivos, existe -AutoSize
Write-Host "Gravado em $arq" -ForegroundColor Green
Write-Host ""
Write-Host "Confira: linha com existe=sim e arquivos=0 significa pasta protegida." -ForegroundColor Yellow
Write-Host "Nesse caso rode de novo como Administrador." -ForegroundColor Yellow
