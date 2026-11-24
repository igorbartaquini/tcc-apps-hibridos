#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Monta a planilha auxiliar do TCC a partir das saidas do analisar.py.

Nenhum numero e digitado aqui. Tudo vem dos arquivos CSV que o analisar.py
grava, e a aba Conferencia recalcula, com formulas de planilha, os numeros
que o artigo afirma, a partir da aba de execucoes. Se os dois nao baterem,
o erro aparece.

Uso:
  python3 planilha.py --analise <pasta com os csv> --saida <arquivo .xlsx>
"""
import argparse, os
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

FONTE = "Arial"
CAB = Font(name=FONTE, size=11, bold=True, color="FFFFFF")
TXT = Font(name=FONTE, size=11)
TIT = Font(name=FONTE, size=14, bold=True)
NOTA = Font(name=FONTE, size=10, italic=True, color="555555")
FUNDO = PatternFill("solid", fgColor="30475E")
RAIA = PatternFill("solid", fgColor="F2F5F8")
FORM = Font(name=FONTE, size=11, color="1F6F3D")
BORDA = Border(*[Side(style="thin", color="D0D7DE")] * 4)


def escreve(ws, df, titulo, nota, inicio=1):
    """Escreve um quadro com titulo, nota de origem e cabecalho fixo."""
    ws.cell(inicio, 1, titulo).font = TIT
    ws.cell(inicio + 1, 1, nota).font = NOTA
    lin0 = inicio + 3
    for j, c in enumerate(df.columns, start=1):
        cel = ws.cell(lin0, j, str(c))
        cel.font, cel.fill, cel.border = CAB, FUNDO, BORDA
        cel.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for i, (_, r) in enumerate(df.iterrows(), start=1):
        for j, c in enumerate(df.columns, start=1):
            v = r[c]
            cel = ws.cell(lin0 + i, j, None if pd.isna(v) else v)
            cel.font, cel.border = TXT, BORDA
            if i % 2 == 0:
                cel.fill = RAIA
    ws.freeze_panes = ws.cell(lin0 + 1, 1)
    for j, c in enumerate(df.columns, start=1):
        largura = max(len(str(c)), *(len(str(v)) for v in df[c].astype(str))) + 2
        ws.column_dimensions[get_column_letter(j)].width = min(max(largura, 9), 46)
    return lin0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--analise", required=True)
    p.add_argument("--dados", required=True, help="pasta dos CSV brutos, para contar as observacoes do C3")
    p.add_argument("--saida", required=True)
    a = p.parse_args()
    ler = lambda n: pd.read_csv(os.path.join(a.analise, n))

    ex = ler("tabela_por_execucao.csv")
    res = ler("tabela_resumo_camadas.csv")
    cmp_ = ler("comparacoes_estatisticas.csv")
    sw = ler("shapiro_wilk.csv")
    c3m = ler("c3_custo_marginal.csv")
    c3p = ler("c3_patamares.csv")
    disco = ler("disco_consolidado.csv")
    base = ler("linhas_de_base.csv")
    desc = ler("execucoes_descartadas.csv")

    wb = Workbook()

    # ---------------- Leia-me ----------------
    ws = wb.active
    ws.title = "Leia-me"
    ws.column_dimensions["A"].width = 112
    linhas = [
        ("Planilha auxiliar do TCC", TIT),
        ("Tendências e desafios de infraestrutura na era dos aplicativos híbridos", TXT),
        ("Igor Candido Bartaquini — Especialização em Tecnologia e Sistemas de Informação, UFABC", TXT),
        ("", TXT),
        ("O que é", TIT),
        ("Esta pasta de trabalho acompanha o artigo. Ela não substitui o texto: serve para conferir "
         "número por número e para montar gráficos da apresentação sem reabrir os dados brutos.", TXT),
        ("", TXT),
        ("De onde vêm os números", TIT),
        ("Todos saem do script analisar.py, que lê os arquivos CSV brutos de cada execução e grava "
         "as tabelas usadas no artigo. Nada foi digitado à mão nesta planilha.", TXT),
        ("Para refazer tudo do zero:  python3 analisar.py --dados <pasta dos CSV brutos> --saida <pasta>", TXT),
        ("", TXT),
        ("Abas", TIT),
        ("Execucoes — uma linha por execução medida do cenário de repouso (C1). É a base de tudo.", TXT),
        ("Tabela 8 a Tabela 12 — as mesmas tabelas que aparecem no artigo, com os mesmos números.", TXT),
        ("Shapiro-Wilk — o teste de normalidade que decidiu qual teste de comparação foi aplicado a cada par.", TXT),
        ("C3 patamares — a medição de carga acumulada, patamar a patamar.", TXT),
        ("Linhas de base e Descartes — o sistema em repouso e a única execução descartada, com o motivo.", TXT),
        ("Conferencia — recalcula, com fórmulas, os números que o artigo afirma, a partir da aba Execucoes. "
         "Se o valor recalculado não bater com o valor do artigo, a coluna Confere acusa.", TXT),
        ("", TXT),
        ("Como ler as cores", TIT),
        ("Texto preto: valor vindo do analisar.py.  Texto verde: célula calculada por fórmula dentro da planilha.", TXT),
    ]
    for i, (t, f) in enumerate(linhas, start=1):
        c = ws.cell(i, 1, t)
        c.font = f
        c.alignment = Alignment(wrap_text=True, vertical="top")

    # ---------------- Dados ----------------
    escreve(wb.create_sheet("Execucoes"), ex,
            "Execuções válidas do cenário de repouso (C1)",
            "Fonte: analisar.py, arquivo tabela_por_execucao.csv. Uma linha por execução medida. "
            "repouso_mb é a métrica principal: Private Working Set no Windows, Proportional Set Size no Ubuntu.")

    t8 = res[["so", "app", "camada", "n", "media", "mediana", "dp", "faixa"]]
    escreve(wb.create_sheet("Tabela 8 - Repouso"), t8,
            "Tabela 8 do artigo — memória em repouso por célula experimental",
            "Fonte: analisar.py, tabela_resumo_camadas.csv. n é o número de execuções válidas da célula. "
            "dp é o desvio padrão entre execuções. faixa é o intervalo do menor ao maior valor observado.")

    t9 = res[["so", "app", "camada", "pico", "residente", "proc", "cpu"]]
    escreve(wb.create_sheet("Tabela 9 - Pico e CPU"), t9,
            "Tabela 9 do artigo — pico, memória residente, processos e processamento",
            "Fonte: analisar.py, tabela_resumo_camadas.csv. residente é o Working Set total no Windows e o "
            "Resident Set Size no Ubuntu, coletado em paralelo para comparar com Thangadurai et al. (2024).")

    escreve(wb.create_sheet("Tabela 10 - Comparacoes"), cmp_,
            "Tabela 10 do artigo — comparações entre camadas",
            "Fonte: analisar.py, comparacoes_estatisticas.csv. p_ajustado já traz a correção de Benjamini-Hochberg. "
            "O tipo de efeito segue a regra de Thangadurai et al. (2024): d de Cohen quando as duas células são "
            "normais no teste de Shapiro-Wilk, delta de Cliff quando ao menos uma não é.")

    escreve(wb.create_sheet("Shapiro-Wilk"), sw,
            "Teste de normalidade por célula experimental",
            "Fonte: analisar.py, shapiro_wilk.csv. É este resultado que decide, para cada par, entre o teste t de "
            "Welch e o teste U de Mann-Whitney, pelo critério fixado antes da coleta.")

    escreve(wb.create_sheet("Tabela 11 - Custo marginal"), c3m,
            "Tabela 11 do artigo — custo marginal por aplicativo aberto (cenário C3)",
            "Fonte: analisar.py, c3_custo_marginal.csv. marginal é quanto cada aplicativo adicional acrescentou ao "
            "total do sistema, medido contra o patamar anterior e não contra a linha de base.")

    escreve(wb.create_sheet("C3 patamares"), c3p,
            "Carga acumulada, patamar a patamar",
            "Fonte: analisar.py, c3_patamares.csv. Uma linha por patamar de cada execução do cenário C3.")

    escreve(wb.create_sheet("Tabela 12 - Disco"), disco,
            "Tabela 12 do artigo — ocupação em disco",
            "Fonte: analisar.py, disco_consolidado.csv, a partir das medições de disco nos dois sistemas.")

    escreve(wb.create_sheet("Linhas de base"), base,
            "Sistema em repouso, sem nenhum aplicativo do experimento aberto",
            "Fonte: analisar.py, linhas_de_base.csv. Serve para situar o consumo dos aplicativos contra o do sistema.")

    escreve(wb.create_sheet("Descartes"), desc,
            "Execuções descartadas",
            "Fonte: analisar.py, execucoes_descartadas.csv. O descarte é declarado no artigo, na Seção 5.2.")

    # ---------------- Conferencia ----------------
    # Recalcula com formulas, a partir da aba Execucoes, os numeros que o texto
    # afirma. A coluna Confere compara o recalculo com o valor publicado.
    ws = wb.create_sheet("Conferencia")
    ws.cell(1, 1, "Conferência dos números do artigo").font = TIT
    ws.cell(2, 1, "As colunas Recalculado são fórmulas que leem a aba Execucoes. A coluna Publicado traz o valor "
                  "impresso no artigo. Confere compara as duas com tolerância de 0,1 MB.").font = NOTA
    cabs = ["Sistema", "Aplicativo", "Camada", "n recalculado", "Média recalculada (MB)",
            "Média publicada (MB)", "Confere"]
    for j, c in enumerate(cabs, start=1):
        cel = ws.cell(4, j, c)
        cel.font, cel.fill, cel.border = CAB, FUNDO, BORDA
        cel.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    ult = len(ex) + 4  # a aba Execucoes comeca o cabecalho na linha 4
    for i, (_, r) in enumerate(res.iterrows(), start=1):
        L = 4 + i
        crit = (f'Execucoes!$B$5:$B${ult},$A{L},Execucoes!$C$5:$C${ult},$B{L},'
                f'Execucoes!$D$5:$D${ult},$C{L}')
        vals = [r.so, r.app, r.camada,
                f"=COUNTIFS({crit})",
                f"=ROUND(AVERAGEIFS(Execucoes!$G$5:$G${ult},{crit}),1)",
                float(r.media),
                f'=IF(ABS(E{L}-F{L})<=0.1,"ok","CONFERIR")']
        for j, v in enumerate(vals, start=1):
            cel = ws.cell(L, j, v)
            cel.border = BORDA
            cel.font = FORM if isinstance(v, str) and v.startswith("=") else TXT
            if i % 2 == 0:
                cel.fill = RAIA
    L = 4 + len(res) + 2
    ws.cell(L, 1, "Totais").font = TIT
    ws.cell(L + 1, 1, "Execuções válidas no C1").font = TXT
    ws.cell(L + 1, 4, f"=COUNTA(Execucoes!$A$5:$A${ult})").font = FORM
    ws.cell(L + 2, 1, "Observações no C1 (soma das amostras)").font = TXT
    ws.cell(L + 2, 4, f"=SUM(Execucoes!$E$5:$E${ult})").font = FORM
    # As observacoes do C3 nao estao em nenhuma das tabelas: sao contadas aqui,
    # linha a linha, nos proprios arquivos brutos do cenario de carga acumulada.
    import glob
    obs_c3 = sum(sum(1 for _ in open(f, encoding="utf-8-sig")) - 1
                 for f in glob.glob(os.path.join(a.dados, "acumulado_*C3*.csv")))
    ws.cell(L + 3, 1, "Observações no C3").font = TXT
    ws.cell(L + 3, 4, obs_c3).font = TXT
    ws.cell(L + 3, 5, "contadas nos arquivos brutos do cenário C3 pelo planilha.py").font = NOTA
    ws.cell(L + 4, 1, "Total de observações do experimento").font = TXT
    ws.cell(L + 4, 4, f"=D{L+2}+D{L+3}").font = FORM
    for col, w in zip("ABCDEFG", [12, 14, 14, 16, 22, 22, 12]):
        ws.column_dimensions[col].width = w

    wb.save(a.saida)
    print("planilha gerada:", a.saida)


if __name__ == "__main__":
    main()
