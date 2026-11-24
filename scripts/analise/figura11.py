import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

K = 1.32
fs = lambda v: round(v * K, 1)
plt.rcParams.update({"font.family": "DejaVu Serif", "axes.linewidth": 0.8})

BASE = 4934.6
G8, G16 = 8192, 16384
PERFIS = [
    ("Leve",                "Um híbrido instalado e o navegador", 484.4 + 623.0),
    ("Navegador",           "Três aplicações em abas",            1219.3),
    ("Instalado",           "Três híbridos instalados",           1526.2),
    ("Instalado com folga", "Três híbridos mais o navegador",     1526.2 + 623.0),
]
br = lambda v: f"{v:,.0f}".replace(",", ".")
def brd(v, d=1):
    s = f"{v:,.{d}f}"
    return s.replace(",", "\x00").replace(".", ",").replace("\x00", ".")

fig = plt.figure(figsize=(8.0, 3.1))
ax  = fig.add_axes([0.235, 0.26, 0.405, 0.62])
axt = fig.add_axes([0.665, 0.26, 0.335, 0.62]); axt.axis("off")
axt.set_xlim(0, 1); axt.set_ylim(-0.5, len(PERFIS) - 0.5)

y = list(range(len(PERFIS)))[::-1]
for yi, (nome, desc, inc) in zip(y, PERFIS):
    ax.barh(yi, BASE, color="#c9c9c9", edgecolor="black", linewidth=0.8, height=0.52)
    ax.barh(yi, inc, left=BASE, facecolor="white", edgecolor="black",
            linewidth=0.8, hatch="///", height=0.52)

ax.set_yticks(y)
ax.set_yticklabels([f"{n}\n{d}" for n, d, _ in PERFIS], fontsize=fs(7.4), linespacing=1.45)
for lab, (nome, _, _) in zip(ax.get_yticklabels(), PERFIS):
    lab.set_ha("right")
ax.tick_params(axis="y", length=0, pad=4)

ax.set_xlim(0, 8800)
ax.set_xticks([0, 2000, 4000, 6000, 8000])
ax.tick_params(axis="x", labelsize=fs(7.4))
ax.set_xlabel("Memória projetada por máquina (MB)", fontsize=fs(7.8), labelpad=5)
ax.axvline(G8, color="black", linestyle=(0, (4, 3)), linewidth=0.9)
ax.text(G8 - 120, len(PERFIS) - 0.42, "8 GB", ha="right", va="bottom", fontsize=fs(7.4))
for s in ("top", "right", "left"):
    ax.spines[s].set_visible(False)
ax.grid(axis="x", color="#d8d8d8", linewidth=0.6)
ax.set_axisbelow(True)

COLS = [(0.26, "total"), (0.58, "acima"), (0.80, "8 GB"), (1.00, "16 GB")]
for x, h in COLS:
    axt.text(x, len(PERFIS) - 0.38, h, ha="right", va="bottom",
             fontsize=fs(7.4), style="italic")
for yi, (_, _, inc) in zip(y, PERFIS):
    tot = BASE + inc
    vals = [f"{br(tot)} MB", f"+{br(inc)}",
            f"{round(tot / G8 * 100)}%", f"{round(tot / G16 * 100)}%"]
    for (x, _), v in zip(COLS, vals):
        axt.text(x, yi, v, ha="right", va="center", fontsize=fs(7.4))

fig.legend(handles=[Patch(facecolor="#c9c9c9", edgecolor="black", linewidth=0.8,
                          label=f"linha de base do Windows 11 ({brd(BASE)} MB)"),
                    Patch(facecolor="white", edgecolor="black", linewidth=0.8,
                          hatch="///", label="acima da base")],
           loc="lower center", ncol=2, frameon=False, fontsize=fs(7.4),
           bbox_to_anchor=(0.5, -0.02), handlelength=1.9, columnspacing=2.2)

fig.savefig("fig11.png", dpi=200, bbox_inches="tight", facecolor="white")
print("ok")
