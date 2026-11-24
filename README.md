# Custo de memória e disco de aplicativos híbridos em máquinas de usuário final

Pacote de replicação do Trabalho de Conclusão de Curso **"Tendências e desafios de
infraestrutura na era dos aplicativos híbridos"**.

Igor Candido Bartaquini · Orientador: Prof. Diogo S. Martins
Especialização em Tecnologias e Sistemas de Informação — UFABC, 2026

---

## O que foi medido

Um experimento controlado que compara **quatro camadas de execução** de aplicativos de
desktop — nativa, Electron, WebView2 e navegador — quanto ao consumo de memória,
processamento e disco da máquina do usuário final.

| | |
| --- | --- |
| Sistemas | Windows 11 (build 26200) e Ubuntu, na mesma máquina física em boot duplo |
| Hardware | Intel Core i5-7200U, 16 GB de RAM |
| Execuções válidas | 132 |
| Observações | 83.160, uma por segundo |
| Aplicativos | Outlook, Slack e Discord |

O desenho é **pareado**: toda comparação entre camadas ocorre dentro do mesmo produto.
O Outlook foi medido nas três camadas lendo a mesma conta de e-mail; os mesmos três
aplicativos foram medidos instalados e como abas de um único navegador.

## Resultados principais

No mesmo produto e na mesma tarefa, o Outlook nativo ocupou **94,3 MB** contra
**443,2 MB** na camada WebView2 e **475,9 MB** no navegador — razões de 4,7 e 5,05.

Entre as camadas híbridas o resultado se inverte conforme o número de aplicativos
abertos: com um, a versão instalada consumiu 138,5 MB a menos; a partir do segundo, as
abas de um único navegador passaram a consumir menos, chegando a 306,9 MB de vantagem
com três aplicativos no Windows. O motor de renderização é carregado uma vez por janela
de navegador e uma vez por aplicativo instalado.

## Organização

```
dados/
  c0_linha_de_base/     consumo do sistema sem aplicativos do experimento
  c1_repouso/           cada aplicativo isolado, em cada camada (249 arquivos)
  c3_carga_acumulada/   aplicativos abertos em sequência, dois braços (12 arquivos)
  disco/                ocupação em disco por alvo, nos dois sistemas
  logs/                 saída bruta dos lotes de coleta
scripts/
  coleta/               coletores de memória e disco, Windows e Linux
  lotes/                orquestração das execuções por cenário
  analise/              análise estatística, planilha auxiliar e figuras
```

Cada execução produz um par de arquivos: o `.csv` com as amostras e o `.meta.txt` com
as condições daquela execução (máquina, build do sistema, duração, processos-alvo).

### Esquema dos dados

**Cenário C1** — `timestamp, run_id, app, camada, cenario, so, n_processos,
private_ws_mb, working_set_mb, commit_mb, cpu_pct`

**Cenário C3** — `timestamp, run_id, braco, cenario, so, n_apps, app_aberto,
seg_no_patamar, mem_sistema_mb, n_processos`

**Disco** — `alvo, camada, tipo, mb, arquivos, existe, caminho`

No Windows a memória por processo é o *Private Working Set*; no Linux, o *Proportional
Set Size*. As duas não são equivalentes, e por isso a comparação entre sistemas no
trabalho é feita em razão, nunca em megabytes absolutos.

## Como reproduzir a análise

```bash
pip install pandas scipy matplotlib
python scripts/analise/analisar.py dados/
```

O script aplica a mesma sequência do estudo replicado: Shapiro-Wilk para normalidade,
depois teste t de Welch ou Mann-Whitney conforme o caso, correção de Benjamini-Hochberg
para comparações múltiplas e tamanho de efeito por d de Cohen ou delta de Cliff.

No cenário de carga acumulada, cada patamar é resumido pela média dos últimos 60
segundos, e as três execuções de cada braço, pela mediana.

## Limitações

A amostragem foi intencional: os aplicativos foram escolhidos por critério e os números
não se estendem estatisticamente a outros aplicativos. O cenário de carga acumulada teve
três repetições por braço, o que torna a inversão um resultado descritivo — com três
contra três, o menor valor-p alcançável pelo teste de Mann-Whitney bilateral é 0,10. As
medições descrevem o custo de manter os aplicativos abertos, sem incluir o custo de
usá-los.

## Nota sobre os dados

Nomes de máquina e de usuário presentes nos metadados foram substituídos por
identificadores genéricos. Nenhum valor medido foi alterado.

## Licença

Dados e scripts disponibilizados para fins de verificação e replicação acadêmica.
