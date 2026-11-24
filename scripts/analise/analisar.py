#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Analise dos dados do TCC "Tendencias e desafios de infraestrutura na era dos
aplicativos hibridos" - Igor Candido Bartaquini, UFABC, 2026.

Reproduz, a partir dos arquivos brutos de coleta, todas as tabelas e figuras
do capitulo de resultados.

A sequencia estatistica segue Thangadurai et al. (2024):
  Shapiro-Wilk -> teste t (dados normais) ou Mann-Whitney U (nao normais)
  -> correcao de Benjamini-Hochberg -> tamanho de efeito
     (d de Cohen para dados normais, delta de Cliff para nao normais).

Uso:
    python3 analisar.py --dados ./dados --saida ./resultados

Dependencias: pandas, numpy, scipy, matplotlib.
"""
import argparse, glob, os, sys
import numpy as np
import pandas as pd
from scipy import stats
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

COL_TEXTO = 6          # timestamp,run_id,app,camada,cenario,so
DESCARTES = {
    "slack_electron_C1_linux_1":
        "execucao de validacao do instrumento: 120 amostras em vez de 600 e "
        "separador decimal anterior a correcao de localidade",
}

# ----------------------------------------------------------------------
# 1. Leitura, com reparo de arquivos gravados com virgula decimal
# ----------------------------------------------------------------------
def ler_coleta(caminho):
    """Le um CSV de coleta. Repara linhas em que a virgula decimal dividiu
    cada numero em duas colunas. Devolve (DataFrame, linhas_reparadas)."""
    linhas = [l for l in open(caminho, encoding="utf-8-sig").read().splitlines() if l.strip()]
    cab = linhas[0].split(",")
    nc, nnum = len(cab), len(cab) - COL_TEXTO - 1
    dados, reparadas = [], 0
    for l in linhas[1:]:
        c = l.split(",")
        if len(c) == nc:
            dados.append(c); continue
        reparadas += 1
        cauda, faltam, saida, i = c[COL_TEXTO+1:], len(c[COL_TEXTO+1:]) - nnum, [], 0
        while i < len(cauda):
            if faltam > 0 and i+1 < len(cauda) and cauda[i+1].isdigit() and len(cauda[i+1]) <= 2:
                saida.append(cauda[i] + "." + cauda[i+1]); i += 2; faltam -= 1
            else:
                saida.append(cauda[i]); i += 1
        nova = c[:COL_TEXTO+1] + saida
        if len(nova) == nc:
            dados.append(nova)
    d = pd.DataFrame(dados, columns=cab)
    for col in cab[COL_TEXTO:]:
        d[col] = pd.to_numeric(d[col], errors="coerce")
    return d, reparadas

# ----------------------------------------------------------------------
# 2. Tamanhos de efeito
# ----------------------------------------------------------------------
def cliff(x, y):
    """Delta de Cliff: probabilidade de um valor de x superar um de y, menos
    a probabilidade inversa. Vale 1 em modulo quando nao ha sobreposicao."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    maior = sum((xi > y).sum() for xi in x)
    menor = sum((xi < y).sum() for xi in x)
    return (maior - menor) / (len(x) * len(y))

def cohen_d(x, y):
    """d de Cohen com desvio padrao combinado."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    nx, ny = len(x), len(y)
    s = np.sqrt(((nx-1)*x.var(ddof=1) + (ny-1)*y.var(ddof=1)) / (nx+ny-2))
    return (x.mean() - y.mean()) / s if s else 0.0

def rotulo_cliff(d):
    a = abs(d)
    return "desprezivel" if a < 0.147 else "pequeno" if a < 0.330 else "medio" if a < 0.474 else "grande"

def rotulo_cohen(d):
    a = abs(d)
    return "desprezivel" if a < 0.2 else "pequeno" if a < 0.5 else "medio" if a < 0.8 else "grande"

def benjamini_hochberg(p):
    """Devolve os valores de p ajustados pelo procedimento de Benjamini e
    Hochberg (1995), na mesma ordem em que foram recebidos."""
    p = np.asarray(p, float); m = len(p)
    ordem = np.argsort(p)
    ajust = np.empty(m)
    anterior = 1.0
    for pos in range(m-1, -1, -1):
        i = ordem[pos]
        anterior = min(anterior, p[i] * m / (pos + 1))
        ajust[i] = anterior
    return ajust

# ----------------------------------------------------------------------
# 3. Cenario de repouso (C1)
# ----------------------------------------------------------------------
def por_execucao(pasta):
    reg, desc, reparos = [], [], 0
    for a in sorted(glob.glob(os.path.join(pasta, "*_C1_*.csv"))):
        run = os.path.basename(a)[:-4]
        d, r = ler_coleta(a); reparos += r
        if run in DESCARTES:
            desc.append(dict(run=run, amostras=len(d), motivo=DESCARTES[run])); continue
        col  = "pss_mb" if "pss_mb" in d.columns else "private_ws_mb"
        col2 = "rss_mb" if "rss_mb" in d.columns else "working_set_mb"
        d = d.reset_index(drop=True); d["seg"] = d.index
        est = d[d.seg >= 60]                       # descarta o 1o minuto
        reg.append(dict(
            run=run, so=d["so"].iloc[0], app=d["app"].iloc[0], camada=d["camada"].iloc[0],
            amostras=len(d), n_proc=int(d["n_processos"].max()),
            repouso_mb=round(est[col].median(), 1), media_mb=round(est[col].mean(), 1),
            pico_mb=round(d[col].max(), 1), residente_mb=round(est[col2].median(), 1),
            cpu_pct=round(d["cpu_pct"].mean(), 2),
            inclinacao_mb_min=round(np.polyfit(est["seg"]/60.0, est[col], 1)[0], 2)))
    return pd.DataFrame(reg), pd.DataFrame(desc), reparos

def comparacoes(ex, normal):
    linhas = []
    for (so, app), g in ex.groupby(["so", "app"]):
        cams = sorted(g.camada.unique())
        for i in range(len(cams)):
            for j in range(i+1, len(cams)):
                a = g[g.camada == cams[i]].repouso_mb.values
                b = g[g.camada == cams[j]].repouso_mb.values
                ambos_normais = normal[(so, app, cams[i])] and normal[(so, app, cams[j])]
                if ambos_normais:
                    _, p = stats.ttest_ind(a, b, equal_var=False)
                    teste, ef, rot, nome_ef = "t de Welch", cohen_d(a, b), None, "d de Cohen"
                    rot = rotulo_cohen(ef)
                else:
                    _, p = stats.mannwhitneyu(a, b, alternative="two-sided")
                    teste, ef, nome_ef = "Mann-Whitney", cliff(a, b), "delta de Cliff"
                    rot = rotulo_cliff(ef)
                linhas.append(dict(
                    so=so, app=app, camada_a=cams[i], camada_b=cams[j],
                    n_a=len(a), n_b=len(b),
                    media_a=round(a.mean(), 1), media_b=round(b.mean(), 1),
                    dif_mb=round(b.mean()-a.mean(), 1),
                    razao=round(b.mean()/a.mean(), 2),
                    teste=teste, p=p, efeito_tipo=nome_ef,
                    efeito=round(ef, 3), magnitude=rot,
                    faixas=("sobrepostas" if (max(a) >= min(b) and max(b) >= min(a)) else "separadas")))
    pr = pd.DataFrame(linhas)
    pr["p_ajustado"] = benjamini_hochberg(pr.p.values)
    pr["significativo_5pct"] = np.where(pr.p_ajustado < 0.05, "sim", "nao")
    return pr.sort_values(["so", "app", "camada_a", "camada_b"]).reset_index(drop=True)

# ----------------------------------------------------------------------
# 4. Cenario de carga acumulada (C3)
# ----------------------------------------------------------------------
def patamares(pasta):
    reg = []
    for a in sorted(glob.glob(os.path.join(pasta, "acumulado_*.csv"))):
        d = pd.read_csv(a, encoding="utf-8-sig")
        d["mem_sistema_mb"] = pd.to_numeric(d["mem_sistema_mb"], errors="coerce")
        est, app = {}, {}
        for n, g in d.groupby("n_apps"):
            g = g.sort_values("seg_no_patamar")
            est[int(n)] = g["mem_sistema_mb"].tail(60).mean()   # ultimos 60 s do patamar
            app[int(n)] = g["app_aberto"].iloc[0]
        nmax = max(est)
        for k in range(1, nmax+1):
            reg.append(dict(so=d["so"].iloc[0], run=d["run_id"].iloc[0], braco=d["braco"].iloc[0],
                            ordem=k, app=app[k], base=round(est[0],1),
                            acumulado=round(est[k]-est[0],1), marginal=round(est[k]-est[k-1],1),
                            total=round(est[nmax]-est[0],1), n_apps=nmax))
    return pd.DataFrame(reg)

# ----------------------------------------------------------------------
# 5. Figuras
# ----------------------------------------------------------------------
def preparar_matplotlib():
    plt.rcParams.update({
        "font.family":"serif","font.serif":["DejaVu Serif"],"font.size":9,
        "axes.titlesize":10,"axes.labelsize":9,"axes.linewidth":0.6,"axes.edgecolor":"#333333",
        "xtick.major.width":0.6,"ytick.major.width":0.6,"legend.frameon":False,"legend.fontsize":8.5,
        "figure.dpi":300,"savefig.dpi":300,"savefig.bbox":"tight"})

EST = {"nativo":    dict(facecolor="white",   hatch="////",       edgecolor="black"),
       "webview2":  dict(facecolor="#bfbfbf", hatch="\\\\\\\\",   edgecolor="black"),
       "electron":  dict(facecolor="white",   hatch="////",       edgecolor="black"),
       "navegador": dict(facecolor="#595959", hatch="",           edgecolor="black")}

def grade(ax):
    ax.grid(axis="y", color="#d9d9d9", linewidth=0.5, zorder=0); ax.set_axisbelow(True)
    for s in ("top","right"): ax.spines[s].set_visible(False)

def figura_outlook(res, saida):
    g = res[res.app=="outlook"].set_index("camada").loc[["nativo","webview2","navegador"]]
    fig, ax = plt.subplots(figsize=(4.6,3.3)); x = np.arange(3)
    rot = ["nativo\n(Win32)\n1 processo","WebView2\n(Outlook novo)\n10 processos",
           "navegador\n(Outlook web)\n14 processos"]
    for i,(cam,r) in enumerate(g.iterrows()):
        ax.bar(x[i], r.media, width=0.6, linewidth=0.8, zorder=3, **EST[cam])
        ax.errorbar(x[i], r.media, yerr=[[r.media-r.minimo],[r.maximo-r.media]], fmt="none",
                    ecolor="black", elinewidth=0.8, capsize=3, capthick=0.8, zorder=4)
        ax.text(x[i], r.maximo+16, f"{r.media:.0f}", ha="center", va="bottom", fontsize=9.5)
    ax.set_xticks(x); ax.set_xticklabels(rot, fontsize=8); ax.set_xlim(-0.6,2.6)
    ax.set_ylabel("Memória privada em repouso (MB)"); ax.set_ylim(0,580); grade(ax)
    fig.savefig(os.path.join(saida,"fig1_outlook_tres_camadas.png")); plt.close(fig)

def figura_dois_sistemas(res, saida):
    fig, axes = plt.subplots(1,2, figsize=(6.6,3.0))
    for ax, so, met in zip(axes, ["Windows","Linux"], ["Private Working Set","PSS"]):
        d = res[(res.so==so) & (res.app.isin(["slack","discord"]))]
        apps, cams, x, w = ["slack","discord"], ["electron","navegador"], np.arange(2), 0.33
        for j, cam in enumerate(cams):
            vals, lo, hi = [], [], []
            for ap in apps:
                r = d[(d.app==ap)&(d.camada==cam)].iloc[0]
                vals.append(r.media); lo.append(r.media-r.minimo); hi.append(r.maximo-r.media)
            pos = x + (j-0.5)*(w+0.02)
            ax.bar(pos, vals, width=w, linewidth=0.8, zorder=3,
                   label="Electron" if cam=="electron" else "Navegador", **EST[cam])
            ax.errorbar(pos, vals, yerr=[lo,hi], fmt="none", ecolor="black",
                        elinewidth=0.8, capsize=3, capthick=0.8, zorder=4)
            for p,v,h in zip(pos, vals, hi):
                ax.text(p, v+h+10, f"{v:.0f}", ha="center", va="bottom", fontsize=8)
        ax.set_xticks(x); ax.set_xticklabels(["Slack","Discord"])
        ax.set_title(f"{so}  ·  {met}", fontsize=9); ax.set_ylim(0,820); grade(ax)
        if so=="Windows": ax.set_ylabel("Memória em repouso (MB)")
    axes[0].legend(loc="upper left")
    fig.savefig(os.path.join(saida,"fig2_electron_navegador_dois_sistemas.png")); plt.close(fig)

def figura_acumulado(pat, saida):
    fig, axes = plt.subplots(1,2, figsize=(6.8,3.2)); linhas=[]
    for ax, so in zip(axes, ["Windows","Linux"]):
        p = pat[pat.so==so]; na = int(p.n_apps.iloc[0])
        for braco, mk, ls, cor, mfc in [("desktop","s","-","black","white"),
                                        ("navegador","o","--","#595959","#595959")]:
            gg = p[p.braco==braco].groupby("ordem")["acumulado"]
            med, lo, hi = gg.median(), gg.min(), gg.max()
            ln, = ax.plot(med.index, med.values, marker=mk, markersize=5, linewidth=2, linestyle=ls,
                          color=cor, markerfacecolor=mfc, markeredgecolor=cor, markeredgewidth=1.4,
                          zorder=3, label=("Desktop, um motor por aplicativo" if braco=="desktop"
                                           else "Navegador, motor compartilhado"))
            ax.fill_between(med.index, lo.values, hi.values, color=cor, alpha=0.13, linewidth=0, zorder=2)
            if so=="Windows": linhas.append(ln)
            ax.annotate(f"{med.iloc[-1]:.0f}", (na, med.iloc[-1]), textcoords="offset points",
                        xytext=(7,-3), ha="left", va="center", fontsize=8.5, color=cor)
        ax.set_xticks(range(0,na+1)); ax.set_xlim(-0.12, na+0.62)
        ax.set_xlabel("Aplicativos abertos simultaneamente")
        ax.set_title(f"{so}, {na} aplicativos", fontsize=9); ax.set_ylim(0,1750); grade(ax)
        if so=="Windows": ax.set_ylabel("Memória do sistema acima da base (MB)")
    fig.legend(handles=linhas, loc="lower center", ncol=2, bbox_to_anchor=(0.5,-0.11))
    fig.savefig(os.path.join(saida,"fig3_carga_acumulada.png")); plt.close(fig)

def figura_disco(disco, saida):
    # O ponto de equilibrio e uma analise do Windows, unico sistema com motor
    # de renderizacao compartilhado pelo proprio sistema operacional.
    d_win = disco[disco.so == "Windows"] if "so" in disco.columns else disco
    def mb(alvo, tipo="instalado"):
        l = d_win[(d_win.alvo == alvo) & (d_win.tipo == tipo)]
        if len(l) == 0:
            raise SystemExit(f"disco: alvo '{alvo}' ({tipo}) nao encontrado")
        if len(l) > 1:
            raise SystemExit(f"disco: alvo '{alvo}' ({tipo}) aparece {len(l)} vezes; "
                             "deixe apenas o arquivo disco_consolidado.csv na pasta de dados")
        return float(l.mb.iloc[0])
    RT, WV = mb("webview2_runtime"), mb("outlook_novo")
    SL, DC = mb("slack"), mb("discord")
    n = np.arange(1,7)
    fig, ax = plt.subplots(figsize=(4.9,3.3))
    ax.plot(n, RT+n*WV, marker="o", markersize=5, linewidth=2, color="#595959",
            markerfacecolor="#595959", markeredgecolor="#595959", zorder=4,
            label=f"WebView2: {RT:.0f} MB de motor, uma vez, + {WV:.0f} MB por aplicativo")
    ax.plot(n, n*SL, marker="s", markersize=5, linewidth=2, linestyle="--", color="black",
            markerfacecolor="white", markeredgecolor="black", markeredgewidth=1.4, zorder=4,
            label=f"Electron porte Slack: {SL:.0f} MB por aplicativo")
    ax.plot(n, n*DC, marker="^", markersize=5, linewidth=2, linestyle=":", color="black",
            markerfacecolor="black", markeredgecolor="black", zorder=4,
            label=f"Electron porte Discord: {DC:.0f} MB por aplicativo")
    for val,nome in ((DC,"Discord"),(SL,"Slack")):
        xq = RT/(val-WV)
        ax.axvline(xq, color="#aaaaaa", linewidth=0.8, zorder=1)
        ax.text(xq, 90, f"{xq:.1f}".replace(".",","), ha="center", va="bottom", fontsize=8,
                color="#555555", bbox=dict(facecolor="white", edgecolor="none", pad=1.0))
    ax.set_xlabel("Aplicativos híbridos instalados na máquina")
    ax.set_ylabel("Ocupação em disco (MB)")
    ax.set_xticks(n); ax.set_ylim(0,3700); grade(ax)
    ax.legend(loc="upper center", bbox_to_anchor=(0.46,-0.19), ncol=1)
    fig.savefig(os.path.join(saida,"fig4_equilibrio_disco.png")); plt.close(fig)
    return RT, WV, SL, DC

# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Analise dos dados do experimento.")
    ap.add_argument("--dados", default="./dados")
    ap.add_argument("--saida", default="./resultados")
    a = ap.parse_args()
    os.makedirs(a.saida, exist_ok=True)
    fig_dir = os.path.join(a.saida, "figuras"); os.makedirs(fig_dir, exist_ok=True)
    preparar_matplotlib()

    print("1. Cenario de repouso")
    ex, desc, reparos = por_execucao(a.dados)
    ex.to_csv(f"{a.saida}/tabela_por_execucao.csv", index=False)
    desc.to_csv(f"{a.saida}/execucoes_descartadas.csv", index=False)
    print(f"   {len(ex)} execucoes validas, {len(desc)} descartadas, {reparos} linhas reparadas")
    print(f"   {ex.amostras.sum():,} observacoes")

    res = ex.groupby(["so","app","camada"]).agg(
        n=("run","count"), media=("repouso_mb","mean"), mediana=("repouso_mb","median"),
        dp=("repouso_mb","std"), minimo=("repouso_mb","min"), maximo=("repouso_mb","max"),
        pico=("pico_mb","max"), residente=("residente_mb","mean"),
        proc=("n_proc","max"), cpu=("cpu_pct","mean")).round(1).reset_index()
    res["faixa"] = res.apply(lambda r: f"{r.minimo:.0f} a {r.maximo:.0f}", axis=1)
    res.to_csv(f"{a.saida}/tabela_resumo_camadas.csv", index=False)

    print("2. Shapiro-Wilk")
    norm, mapa = [], {}
    for (so,app,cam), g in ex.groupby(["so","app","camada"]):
        W, p = stats.shapiro(g.repouso_mb)
        mapa[(so,app,cam)] = p > 0.05
        norm.append(dict(so=so, app=app, camada=cam, n=len(g), W=round(W,4), p=round(p,4),
                         normal=("sim" if p>0.05 else "nao")))
    pd.DataFrame(norm).to_csv(f"{a.saida}/shapiro_wilk.csv", index=False)
    print(f"   normais: {sum(mapa.values())} de {len(mapa)}")

    print("3. Comparacoes par a par")
    comp = comparacoes(ex, mapa)
    comp.to_csv(f"{a.saida}/comparacoes_estatisticas.csv", index=False)
    print(f"   {len(comp)} comparacoes, {(comp.significativo_5pct=='sim').sum()} significativas apos Benjamini-Hochberg")

    print("4. Carga acumulada")
    pat = patamares(a.dados)
    if len(pat):
        pat.to_csv(f"{a.saida}/c3_patamares.csv", index=False)
        marg = pat.groupby(["so","braco","ordem","app"])["marginal"].agg(
            mediana="median", media="mean", minimo="min", maximo="max").round(1).reset_index()
        marg.to_csv(f"{a.saida}/c3_custo_marginal.csv", index=False)
        print(f"   {pat.run.nunique()} execucoes, {int(pat.groupby('run').size().sum())} patamares")

    print("5. Linhas de base")
    base = []
    for pat_arq, so in ((f"{a.dados}/baseline_win_*.csv","Windows"), (f"{a.dados}/baseline_linux_*.csv","Linux")):
        for arq in glob.glob(pat_arq):
            b = pd.read_csv(arq, encoding="utf-8-sig")
            for c in ["memoria_em_uso_mb","memoria_total_mb","n_processos"]:
                b[c] = pd.to_numeric(b[c], errors="coerce")
            base.append(dict(so=so, amostras=len(b), media=round(b.memoria_em_uso_mb.mean(),1),
                             minimo=round(b.memoria_em_uso_mb.min(),1),
                             maximo=round(b.memoria_em_uso_mb.max(),1),
                             total=round(b.memoria_total_mb.iloc[0],0),
                             processos=round(b.n_processos.mean())))
    if base:
        pd.DataFrame(base).to_csv(f"{a.saida}/linhas_de_base.csv", index=False)
        for r in base: print(f"   {r['so']}: {r['media']} MB em uso, {r['processos']} processos")

    print("6. Disco")
    disco = None
    # Prefere o arquivo consolidado e conferido. So recorre aos brutos se ele
    # nao existir, porque os brutos podem conter medidas que foram corrigidas
    # depois (ver Secao 5.8 do artigo).
    consolidado = os.path.join(a.dados, "disco_consolidado.csv")
    arqs = [consolidado] if os.path.exists(consolidado) else sorted(glob.glob(f"{a.dados}/disco_*.csv"))
    if arqs:
        disco = pd.concat([pd.read_csv(x) for x in arqs], ignore_index=True)
        disco["mb"] = pd.to_numeric(disco["mb"], errors="coerce")
        chaves = ["so","alvo","tipo"] if "so" in disco.columns else ["alvo","tipo"]
        dup = disco[disco.duplicated(chaves, keep=False)]
        if len(dup):
            print("   AVISO: alvos repetidos em disco; a analise usa a primeira ocorrencia:")
            for _, r in dup.iterrows():
                print(f"      {r.alvo} / {r.tipo} = {r.mb}")
        disco.to_csv(f"{a.saida}/disco_consolidado.csv", index=False)

    print("7. Figuras")
    figura_outlook(res, fig_dir)
    figura_dois_sistemas(res, fig_dir)
    if len(pat): figura_acumulado(pat, fig_dir)
    if disco is not None and "webview2_runtime" in set(disco.alvo):
        RT,WV,SL,DC = figura_disco(disco, fig_dir)
        eq = pd.DataFrame([{"contra":"Slack","equilibrio_apps":round(RT/(SL-WV),2)},
                           {"contra":"Discord","equilibrio_apps":round(RT/(DC-WV),2)}])
        eq.to_csv(f"{a.saida}/disco_ponto_equilibrio.csv", index=False)
        print(f"   equilibrio: {RT/(SL-WV):.2f} contra Slack, {RT/(DC-WV):.2f} contra Discord")
    print(f"\nPronto. Tabelas e figuras em {a.saida}")

if __name__ == "__main__":
    main()
