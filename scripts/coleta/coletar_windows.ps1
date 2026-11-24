# =====================================================================
# Coleta de memoria e CPU no Windows 11  -  versao 3
# TCC - Tendencias e desafios de infraestrutura na era dos apps hibridos
#
# Correcao da v1: $pid e variavel automatica reservada do PowerShell e nao
# pode ser usada como variavel de laco. Renomeada para $procId.
#
# Correcao da v2: quando a arvore tinha um unico processo, o PowerShell
# desembrulhava o HashSet e devolvia um Int32, provocando o erro
# "does not contain a method named 'Contains'". Agora a funcao devolve
# sempre uma colecao e a filtragem usa uma tabela de busca.
#
# Metrica principal: Private Working Set, somado na arvore de processos.
# Auxiliares: Working Set total e Commit Size. Taxa: 1 amostra por segundo.
#
# Exemplo:
#   .\coletar_windows.ps1 -RunId teste -App slack -Camada electron `
#       -Cenario C1 -Processos slack -Segundos 120
# =====================================================================

param(
  [Parameter(Mandatory=$true)][string]$RunId,
  [Parameter(Mandatory=$true)][string]$App,
  [Parameter(Mandatory=$true)][string]$Camada,
  [Parameter(Mandatory=$true)][string]$Cenario,
  [Parameter(Mandatory=$true)][string[]]$Processos,
  [int]$Segundos = 600,
  [string]$Saida = "C:\tcc\dados",
  # Opcional. Quando preenchido, um processo raiz so entra na arvore se a
  # linha de comando dele contiver este texto. Serve para o WebView2, que e
  # um runtime compartilhado: sem o filtro, processos de outros aplicativos
  # entrariam na medicao. Para o Outlook novo use -Contem "Olk".
  [string]$Contem = ""
)

$ErrorActionPreference = "Continue"

# Forca ponto como separador decimal. Em sistemas em portugues o padrao e
# virgula, o que quebraria o CSV ao dividir cada numero em duas colunas.
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function N2 { param($v) ([double]$v).ToString("0.##", $inv) }

if (-not (Test-Path $Saida)) { New-Item -ItemType Directory -Path $Saida -Force | Out-Null }
$arquivo = Join-Path $Saida "$RunId.csv"
$meta    = Join-Path $Saida "$RunId.meta.txt"

# ------------------------------------------------------------------
# Monta a arvore de processos a partir dos nomes alvo
# ------------------------------------------------------------------
# Devolve SEMPRE uma tabela (hashtable) com os PIDs como chaves. Tabela nao e
# desembrulhada pelo PowerShell, diferente de HashSet e de array, por isso
# funciona igual com um processo ou com cinquenta.
function Get-ArvoreProcessos {
  param([string[]]$Nomes, [string]$Filtro = "")

  $arvore = @{}

  if ([string]::IsNullOrWhiteSpace($Filtro)) {
    $todos = Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name -ErrorAction SilentlyContinue
  } else {
    $todos = Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,CommandLine -ErrorAction SilentlyContinue
  }
  if (-not $todos) { return $arvore }

  $filhosDe = @{}
  $raizes   = New-Object System.Collections.Generic.List[int]

  foreach ($proc in $todos) {
    $paiId = [int]$proc.ParentProcessId
    if (-not $filhosDe.ContainsKey($paiId)) {
      $filhosDe[$paiId] = New-Object System.Collections.Generic.List[int]
    }
    $filhosDe[$paiId].Add([int]$proc.ProcessId)

    $nomeLimpo = $proc.Name -replace '\.exe$',''
    foreach ($alvo in $Nomes) {
      if ($nomeLimpo -ieq $alvo) {
        if ([string]::IsNullOrWhiteSpace($Filtro)) {
          $raizes.Add([int]$proc.ProcessId)
        } elseif ($proc.CommandLine -and $proc.CommandLine -like "*$Filtro*") {
          $raizes.Add([int]$proc.ProcessId)
        }
        break
      }
    }
  }

  $fila = New-Object System.Collections.Generic.Queue[int]
  foreach ($r in $raizes) {
    if (-not $arvore.ContainsKey($r)) { $arvore[$r] = $true; $fila.Enqueue($r) }
  }

  while ($fila.Count -gt 0) {
    $atual = $fila.Dequeue()
    if ($filhosDe.ContainsKey($atual)) {
      foreach ($f in $filhosDe[$atual]) {
        if (-not $arvore.ContainsKey($f)) { $arvore[$f] = $true; $fila.Enqueue($f) }
      }
    }
  }
  return $arvore
}

# ------------------------------------------------------------------
# Diagnostico antes de comecar
# ------------------------------------------------------------------
Write-Host "Verificando processos alvo..." -ForegroundColor Cyan
$teste = Get-ArvoreProcessos -Nomes $Processos -Filtro $Contem
if ($teste.Count -eq 0) {
  Write-Host ""
  Write-Host "NENHUM PROCESSO ENCONTRADO com os nomes: $($Processos -join ', ')" -ForegroundColor Red
  Write-Host "O aplicativo esta aberto? Confira o nome real com:" -ForegroundColor Yellow
  Write-Host "   Get-Process | Select-Object -Unique Name | Sort-Object Name" -ForegroundColor Yellow
  Write-Host "Coleta cancelada." -ForegroundColor Red
  exit 1
}
Write-Host "  $($teste.Count) processos na arvore. Iniciando." -ForegroundColor Green

# Mostra o nome de cada processo capturado, para conferir antes de gastar
# dez minutos coletando a arvore errada.
Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $teste.ContainsKey([int]$_.Id) } |
  Group-Object ProcessName |
  Sort-Object Count -Descending |
  ForEach-Object { Write-Host ("    {0,-24} {1}" -f $_.Name, $_.Count) -ForegroundColor DarkGray }

@"
run_id=$RunId
app=$App
camada=$Camada
cenario=$Cenario
so=Windows 11
so_build=$((Get-CimInstance Win32_OperatingSystem).BuildNumber)
processos_alvo=$($Processos -join ',')
filtro_linha_comando=$Contem
processos_encontrados=$($teste.Count)
duracao_s=$Segundos
inicio=$(Get-Date -Format 'o')
maquina=$env:COMPUTERNAME
cpu=$((Get-CimInstance Win32_Processor).Name)
ram_total_mb=$([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1MB))
"@ | Out-File -FilePath $meta -Encoding utf8

"timestamp,run_id,app,camada,cenario,so,n_processos,private_ws_mb,working_set_mb,commit_mb,cpu_pct" |
  Out-File -FilePath $arquivo -Encoding utf8

$nucleos     = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$cpuAnterior = @{}
$primeira    = $true
$zerados     = 0

Write-Host "Coletando $RunId por $Segundos segundos..." -ForegroundColor Cyan

for ($i = 0; $i -lt $Segundos; $i++) {
  $t0 = Get-Date
  $arvore = Get-ArvoreProcessos -Nomes $Processos -Filtro $Contem

  $privWS = 0; $ws = 0; $commit = 0; $cpuPct = 0

  if ($arvore.Count -gt 0) {
    $perf = Get-CimInstance Win32_PerfRawData_PerfProc_Process `
              -Property IDProcess,WorkingSetPrivate,WorkingSet,PrivateBytes -ErrorAction SilentlyContinue |
            Where-Object { $arvore.ContainsKey([int]$_.IDProcess) }

    if ($perf) {
      $s1 = ($perf | Measure-Object -Property WorkingSetPrivate -Sum).Sum
      $s2 = ($perf | Measure-Object -Property WorkingSet        -Sum).Sum
      $s3 = ($perf | Measure-Object -Property PrivateBytes      -Sum).Sum
      if ($s1) { $privWS = $s1 }
      if ($s2) { $ws     = $s2 }
      if ($s3) { $commit = $s3 }
    }

    $cpuTotal = 0.0
    $cpuAtual = @{}
    $indice = @{}
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) { $indice[$p.Id] = $p }
    foreach ($procId in @($arvore.Keys)) {
      if ($indice.ContainsKey($procId)) {
        try {
          $seg = $indice[$procId].TotalProcessorTime.TotalSeconds
          $cpuAtual[$procId] = $seg
          if ($cpuAnterior.ContainsKey($procId)) { $cpuTotal += ($seg - $cpuAnterior[$procId]) }
        } catch { }
      }
    }
    $cpuAnterior = $cpuAtual
    if (-not $primeira) { $cpuPct = [math]::Round(($cpuTotal / $nucleos) * 100, 2) }
    $primeira = $false
  }

  if ($privWS -eq 0) { $zerados++ }

  $linha = "{0},{1},{2},{3},{4},Windows,{5},{6},{7},{8},{9}" -f `
    (Get-Date -Format 'o'), $RunId, $App, $Camada, $Cenario, $arvore.Count,
    (N2 ($privWS/1MB)), (N2 ($ws/1MB)), (N2 ($commit/1MB)), (N2 $cpuPct)
  Add-Content -Path $arquivo -Value $linha

  if ($i -eq 4 -and $zerados -ge 4) {
    Write-Host "AVISO: cinco amostras zeradas. Rode o PowerShell como Administrador." -ForegroundColor Red
  }
  if ($i % 30 -eq 0 -and $i -gt 0) {
    Write-Host ("  {0}s  -  {1} processos  -  {2} MB" -f $i, $arvore.Count, [math]::Round($privWS/1MB,0)) -ForegroundColor DarkGray
  }

  $espera = 1000 - ((Get-Date) - $t0).TotalMilliseconds
  if ($espera -gt 0) { Start-Sleep -Milliseconds $espera }
}

Add-Content -Path $meta -Value "fim=$(Get-Date -Format 'o')"
Add-Content -Path $meta -Value "amostras_zeradas=$zerados"

if ($zerados -gt ($Segundos * 0.1)) {
  Write-Host "ATENCAO: $zerados amostras zeradas de $Segundos. Descarte esta execucao." -ForegroundColor Red
} else {
  Write-Host "Pronto: $arquivo" -ForegroundColor Green
}
