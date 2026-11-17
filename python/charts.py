"""
Графики для проекта «Анализ маркетплейса Olist на SQL».

Скрипт подключается к PostgreSQL, читает материализованные представления
(sql/setup/materialized_views.sql) и сохраняет PNG-графики в images/charts/.

Запуск (из корня репозитория):
    pip install -r requirements.txt
    python python/charts.py

Параметры подключения берутся из переменных окружения, а если их нет —
из значений по умолчанию ниже. Поменяй их под свою базу.
Пароль в файле не хранится: если переменная PGPASSWORD не задана,
скрипт спросит его при запуске.
"""

import os
from getpass import getpass
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle
from sqlalchemy import URL, create_engine


# Подключение к базе
DB_USER = os.getenv("PGUSER", "postgres")
DB_PASSWORD = os.getenv("PGPASSWORD", "")
DB_HOST = os.getenv("PGHOST", "localhost")
DB_PORT = os.getenv("PGPORT", "5432")
DB_NAME = os.getenv("PGDATABASE", "olist")

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "images" / "charts"

SOURCE = "Данные: Olist (Kaggle), 2016–2018 · расчёт: PostgreSQL"


# Палитра
SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
NEUTRAL = "#d6d4cc"

BLUE = "#2a78d6"
ORANGE = "#eb6834"
AQUA = "#1baf7a"
VIOLET = "#6250d6"
RED = "#e34948"
NAVY = "#184f95"


def ramp(name: str, colors: list[str]) -> LinearSegmentedColormap:
    return LinearSegmentedColormap.from_list(name, colors)


SEQ_AQUA = ramp("seq_aqua", ["#f1faf6", "#c9eedf", "#94dcc2", "#5cc6a0",
                             "#1baf7a", "#138a60", "#0d6647", "#08432f"])
SEQ_VIOLET = ramp("seq_violet", ["#f5f3fd", "#dcd7f8", "#bcb3f1", "#9b8ee9",
                                 "#7b6ae0", "#6250d6", "#4a3aa7", "#2f2470"])

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica Neue", "Inter", "Arial", "DejaVu Sans"],
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "font.size": 11,
    "text.color": TEXT,
    "axes.labelcolor": TEXT_2,
    "axes.edgecolor": GRID,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "xtick.labelcolor": TEXT_2,
    "ytick.labelcolor": TEXT_2,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "legend.frameon": False,
    "legend.fontsize": 10.5,
})


# Общие элементы оформления
def load(view: str) -> pd.DataFrame:
    """Читает материализованное представление целиком."""
    return pd.read_sql(f"SELECT * FROM {view}", ENGINE)


def header(fig, title: str, subtitle: str, accent: str) -> None:
    """Заголовок, подзаголовок и цветная метка над графиком."""
    w, h = fig.get_size_inches()
    fig.add_artist(Rectangle((0.06 - 0.16 / w, 0.968 - 0.33 / h), 0.06 / w, 0.33 / h,
                             transform=fig.transFigure, color=accent, linewidth=0))
    fig.text(0.06, 0.968, title, fontsize=18, fontweight="bold", va="top", color=TEXT)
    fig.text(0.06, 0.905, subtitle, fontsize=11.5, va="top", color=TEXT_2)


def footer(fig, note: str = "") -> None:
    text = SOURCE + (f"   ·   {note}" if note else "")
    fig.text(0.06, 0.02, text, fontsize=9, color=MUTED, va="bottom")


def clean(ax, grid_axis: str | None = "y") -> None:
    if grid_axis:
        ax.grid(axis=grid_axis)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)


def save(fig, name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    fig.savefig(path, dpi=200, pad_inches=0.1)
    plt.close(fig)
    print(f"  сохранён {path.relative_to(ROOT)}")


# 1. Когортный анализ
def chart_cohorts() -> None:
    df = load("mv_cohort_retention")
    df["cohort_month"] = pd.to_datetime(df["cohort_month"])
    sizes = df[df["month_idx"] == 0].set_index("cohort_month")["active_customers"]
    df = df[(df["cohort_month"] >= "2017-01-01") & (df["month_idx"] >= 1)]

    pivot = df.pivot(index="cohort_month", columns="month_idx", values="retention_pct")
    pivot = pivot.reindex(columns=range(1, 13))
    data = pivot.to_numpy(dtype=float)
    vmax = np.nanpercentile(data, 98)

    fig = plt.figure(figsize=(12, 9.5))
    ax = fig.add_axes([0.16, 0.06, 0.69, 0.76])
    cax = fig.add_axes([0.875, 0.30, 0.015, 0.35])

    im = ax.imshow(data, cmap=SEQ_AQUA, vmin=0, vmax=vmax, aspect="auto")
    for i in range(data.shape[0]):
        for j in range(data.shape[1]):
            v = data[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=8.5,
                        color="#ffffff" if v > vmax * 0.55 else TEXT_2)

    ax.set_xticks(np.arange(-0.5, 12, 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(pivot.index), 1), minor=True)
    ax.grid(which="minor", color=SURFACE, linewidth=2)
    ax.tick_params(which="both", length=0)
    for s in ax.spines.values():
        s.set_visible(False)

    ax.set_xticks(range(12), [str(m) for m in range(1, 13)])
    ax.xaxis.tick_top()
    ax.xaxis.set_label_position("top")
    ax.set_xlabel("Месяцев после первой покупки", labelpad=8)
    ax.set_yticks(range(len(pivot.index)), [f"{d:%Y-%m}" for d in pivot.index], fontsize=10)
    for i, d in enumerate(pivot.index):
        ax.text(-0.62, i, f"{int(sizes.get(d, 0)):,}".replace(",", " "), ha="right", va="center",
                fontsize=8.5, color=MUTED)
    ax.tick_params(axis="y", pad=48)
    ax.set_ylabel("Когорта · клиентов в ней", labelpad=8)

    cb = fig.colorbar(im, cax=cax)
    cb.outline.set_visible(False)
    cb.ax.tick_params(length=0, labelcolor=TEXT_2)
    cb.set_label("вернулись, %", color=TEXT_2)

    header(fig, "Удержание клиентов по когортам",
           "Доля клиентов когорты, сделавших заказ в N-й месяц после первого, %", AQUA)
    footer(fig)
    save(fig, "cohort_retention.png")


# 2. Аномалии выручки
def chart_revenue_anomalies(state: str = "SP") -> None:
    df = load("mv_revenue_anomalies")
    df = df[df["customer_state"] == state].copy()
    df["order_date"] = pd.to_datetime(df["order_date"])
    df = df.sort_values("order_date").reset_index(drop=True)
    last_sale = df.loc[df["daily_revenue"] > 0, "order_date"].max()
    df = df[df["order_date"] <= last_sale]

    d = df["order_date"]
    rev = df["daily_revenue"].astype(float) / 1000
    avg = df["moving_avg_7"].astype(float) / 1000
    std = df["moving_std_30"].astype(float) / 1000
    lo, hi = (avg - 2 * std).clip(lower=0), avg + 2 * std

    fig = plt.figure(figsize=(14, 7))
    ax = fig.add_axes([0.06, 0.17, 0.92, 0.65])

    ax.fill_between(d, lo, hi, color=BLUE, alpha=0.10, linewidth=0, label="Коридор нормы (±2σ)")
    ax.plot(d, rev, color="#9fb7d6", linewidth=0.9, label="Выручка за день")
    ax.plot(d, avg, color=NAVY, linewidth=2, label="Среднее за 7 дней")

    spikes = (df["day_type"] == "spike").to_numpy()
    drops = (df["day_type"] == "drop").to_numpy()
    ax.vlines(d[spikes], avg[spikes], rev[spikes], color=ORANGE, linewidth=1.2, alpha=0.7)
    ax.vlines(d[drops], rev[drops], avg[drops], color=VIOLET, linewidth=1.2, alpha=0.7)
    ax.scatter(d[spikes], rev[spikes], s=70, color=ORANGE, edgecolor=SURFACE,
               linewidth=1.8, zorder=4, label=f"Всплеск ({spikes.sum()} дн.)")
    ax.scatter(d[drops], rev[drops], s=70, color=VIOLET, marker="v", edgecolor=SURFACE,
               linewidth=1.8, zorder=4, label=f"Провал ({drops.sum()} дн.)")

    top = rev.idxmax()
    ax.annotate(f"{df.loc[top, 'order_date']:%d.%m.%Y}\n{rev[top]:.0f} тыс. BRL",
                xy=(df.loc[top, "order_date"], rev[top]), xytext=(14, -4),
                textcoords="offset points", fontsize=10.5, fontweight="bold", color=TEXT, va="top")

    ax.set_ylim(bottom=0)
    ax.margins(x=0.01)
    ax.set_ylabel("Тыс. BRL")
    clean(ax)
    ax.legend(loc="upper left", ncols=5, bbox_to_anchor=(0, -0.07), handlelength=1.6)

    header(fig, f"Дневная выручка и аномалии: штат {state}",
           "Аномалия — день, когда выручка вышла за коридор «7-дневное среднее ± 2 ст. отклонения за 30 дней»",
           ORANGE)
    footer(fig)
    save(fig, f"revenue_anomalies_{state.lower()}.png")


# 3. Оценки доставки
BASKET_LABELS = {
    "1_early_8plus": "Раньше\nна 8+ дней",
    "2_early_0_7": "Раньше на 0–7\nили в срок",
    "3_late_1_3": "Опоздание\n1–3 дня",
    "4_late_4_7": "Опоздание\n4–7 дней",
    "5_late_8plus": "Опоздание\n8+ дней",
}


def chart_delivery_score() -> None:
    df = load("mv_delivery_score").sort_values("basket").reset_index(drop=True)
    low = df["low_score_pct"].astype(float)
    high = df["high_score_pct"].astype(float)
    mid = 100 - low - high
    avg = df["avg_score"].astype(float)
    x = np.arange(len(df))

    fig = plt.figure(figsize=(12, 8.6))
    ax_top = fig.add_axes([0.12, 0.64, 0.84, 0.16])
    ax = fig.add_axes([0.12, 0.17, 0.84, 0.44], sharex=ax_top)

    ax_top.plot(x, avg, color=TEXT, linewidth=2, zorder=2)
    ax_top.scatter(x, avg, s=90, color=SURFACE, edgecolor=TEXT, linewidth=2, zorder=3)
    for xi, v in zip(x, avg):
        ax_top.annotate(f"{v:.1f}", (xi, v), xytext=(0, 11), textcoords="offset points",
                        ha="center", fontsize=11, fontweight="bold")
    ax_top.set_ylim(1, 5.8)
    ax_top.set_yticks([1, 3, 5])
    ax_top.set_ylabel("Средняя\nоценка", rotation=0, ha="right", va="center", labelpad=12)
    ax_top.tick_params(labelbottom=False)
    ax_top.spines["bottom"].set_visible(False)
    clean(ax_top)

    w = 0.62
    segs = [(low, ORANGE, "Оценки 1–2", "#ffffff"),
            (mid, NEUTRAL, "Оценки 3–4", TEXT_2),
            (high, BLUE, "Оценка 5", "#ffffff")]
    bottom = np.zeros(len(df))
    for vals, color, label, txt in segs:
        ax.bar(x, vals, w, bottom=bottom, color=color, edgecolor=SURFACE, linewidth=2, label=label)
        for xi, b, v in zip(x, bottom, vals):
            if v >= 6:
                ax.text(xi, b + v / 2, f"{v:.0f}%", ha="center", va="center",
                        fontsize=10.5, fontweight="bold", color=txt)
        bottom += vals.to_numpy()

    ax.set_xticks(x, [BASKET_LABELS.get(b, b) for b in df["basket"]])
    for xi, n in zip(x, df["orders"]):
        ax.text(xi, -0.22, f"{int(n):,} заказов".replace(",", " "),
                transform=ax.get_xaxis_transform(), ha="center", fontsize=9.5, color=MUTED)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(decimals=0))
    ax.set_ylabel("Структура\nоценок", rotation=0, ha="right", va="center", labelpad=12)
    ax.spines["left"].set_visible(False)
    clean(ax)
    handles, labels = ax.get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper left", ncols=3, bbox_to_anchor=(0.055, 0.875))

    header(fig, "Чем сильнее опоздание, тем ниже оценка",
           "Средняя оценка и структура оценок по группам задержки доставки", ORANGE)
    footer(fig)
    save(fig, "delivery_score.png")


# 4. Категории с наибольшей долей низких оценок при опоздании
def chart_delivery_categories() -> None:
    df = load("mv_delivery_low_score_category").sort_values("low_score_pct").reset_index(drop=True)
    pct = df["low_score_pct"].astype(float)
    y = np.arange(len(df))

    fig = plt.figure(figsize=(11, 5.4))
    ax = fig.add_axes([0.25, 0.10, 0.62, 0.68])

    ax.barh(y, 100, height=0.55, color="#f1efe9")
    ax.barh(y, pct, height=0.55, color=RED)
    for yi, p, n in zip(y, pct, df["late_orders"]):
        ax.text(p - 1.5, yi, f"{p:.0f}%", ha="right", va="center", color="#ffffff",
                fontsize=11, fontweight="bold")
        ax.text(101.5, yi, f"{int(n)} опозданий", ha="left", va="center", color=MUTED, fontsize=9.5)

    ax.set_yticks(y, df["category"], fontsize=11)
    ax.set_xlim(0, 100)
    ax.set_xticks([])
    for s in ("left", "bottom"):
        ax.spines[s].set_visible(False)
    clean(ax, grid_axis=None)

    header(fig, "Где опоздание бьёт по оценке сильнее всего",
           "Доля оценок 1–2 среди опоздавших заказов · категории со 100+ такими заказами", RED)
    footer(fig)
    save(fig, "delivery_categories.png")


# 5. ABC/XYZ
def chart_abc_xyz() -> None:
    df = load("mv_abc_xyz")
    abc = ["A", "B", "C"]
    xyz = ["X", "Y", "Z", "N/A"]
    share = df.pivot(index="abc", columns="xyz", values="revenue_share_pct").reindex(index=abc, columns=xyz)
    sellers = df.pivot(index="abc", columns="xyz", values="sellers").reindex(index=abc, columns=xyz)
    data = share.to_numpy(dtype=float)
    top = np.nanmax(data)

    fig = plt.figure(figsize=(11, 7))
    ax = fig.add_axes([0.19, 0.08, 0.78, 0.68])
    ax.imshow(np.nan_to_num(data), cmap=SEQ_VIOLET, vmin=0, vmax=top, aspect="auto")

    for i in range(len(abc)):
        for j in range(len(xyz)):
            v, n = data[i, j], sellers.iat[i, j]
            if np.isnan(v):
                ax.text(j, i, "—", ha="center", va="center", color=MUTED, fontsize=14)
                continue
            dark = v > top * 0.45
            ax.text(j, i - 0.1, f"{v:.1f}%", ha="center", va="center", fontsize=17,
                    fontweight="bold", color="#ffffff" if dark else TEXT)
            ax.text(j, i + 0.2, f"{int(n)} продавцов", ha="center", va="center", fontsize=9.5,
                    color="#ffffff" if dark else TEXT_2)

    ax.set_xticks(range(4), ["X · стабильные", "Y · умеренные", "Z · нестабильные", "N/A · 1 месяц"],
                  fontsize=10.5)
    ax.xaxis.tick_top()
    ax.set_yticks(range(3), ["A · 80% выручки", "B · следующие 15%", "C · последние 5%"], fontsize=10.5)
    ax.set_xticks(np.arange(-0.5, 4, 1), minor=True)
    ax.set_yticks(np.arange(-0.5, 3, 1), minor=True)
    ax.grid(which="minor", color=SURFACE, linewidth=4)
    ax.tick_params(which="both", length=0)
    for s in ax.spines.values():
        s.set_visible(False)

    header(fig, "ABC/XYZ-матрица продавцов",
           "Доля в общей выручке и число продавцов: ABC — вклад в выручку, XYZ — стабильность по месяцам",
           VIOLET)
    footer(fig)
    save(fig, "abc_xyz.png")


# 6. Анализ корзины
def chart_product_pairs(top: int = 15, min_reliable: int = 10) -> None:
    df = load("mv_product_pairs").sort_values("lift", ascending=False).head(top)
    df = df.iloc[::-1].reset_index(drop=True)  # самый большой lift сверху
    lift = df["lift"].astype(float)
    reliable = (df["n_pair"] >= min_reliable).to_numpy()
    y = np.arange(len(df))

    fig = plt.figure(figsize=(12, 8.5))
    ax = fig.add_axes([0.33, 0.14, 0.60, 0.68])

    colors = np.where(reliable, AQUA, NEUTRAL)
    ax.hlines(y, 1, lift, color=colors, linewidth=2.5)
    sizes = 40 + df["n_pair"].astype(float) * 6
    ax.scatter(lift, y, s=sizes, color=colors, edgecolor=SURFACE, linewidth=2, zorder=3)
    for yi, l, n, r in zip(y, lift, df["n_pair"], reliable):
        ax.annotate(f"{l:.1f}  ·  {int(n)} заказов", (l, yi), xytext=(14, 0), textcoords="offset points",
                    va="center", fontsize=9.5, color=TEXT if r else MUTED,
                    fontweight="bold" if r else "normal")

    ax.axvline(1, color=MUTED, linewidth=1, linestyle=(0, (3, 3)))
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(mticker.FixedLocator([1, 2, 5, 10, 20]))
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"{v:g}"))
    ax.xaxis.set_minor_locator(mticker.NullLocator())
    ax.set_xlim(0.9, lift.max() * 2.4)
    ax.set_xlabel("Lift (логарифмическая шкала)")
    ax.set_yticks(y, df["pair"], fontsize=10)
    ax.spines["left"].set_visible(False)
    clean(ax, grid_axis="x")

    fig.legend(handles=[
        Line2D([], [], marker="o", linestyle="", markersize=10, color=AQUA, label=f"{min_reliable}+ заказов"),
        Line2D([], [], marker="o", linestyle="", markersize=10, color=NEUTRAL,
               label=f"меньше {min_reliable} — статистически ненадёжно"),
    ], loc="lower left", ncols=2, bbox_to_anchor=(0.055, 0.045))

    header(fig, f"Какие категории покупают вместе: топ-{top} пар по lift",
           "Во сколько раз чаще пара встречается в одном заказе, чем случайно · размер точки — число заказов",
           AQUA)
    footer(fig)
    save(fig, "product_pairs.png")


# 7. Распределение времени доставки по регионам
REGIONS = {
    "Southeast": ("Юго-Восток", BLUE),
    "South": ("Юг", AQUA),
    "Central-West": ("Центр-Запад", "#eda100"),
    "Northeast": ("Северо-Восток", ORANGE),
    "North": ("Север", "#e87ba4"),
}


def chart_delivery_time(max_days: int = 60) -> None:
    df = load("mv_delivery_time_dest")
    df["delivery_time"] = df["delivery_time"].astype(float)
    df["share"] = df["share"].astype(float)

    stats = {}
    for region, g in df.groupby("region"):
        g = g.sort_values("delivery_time")
        cum = g["share"].cumsum()
        stats[region] = {
            "median": g.loc[cum >= 0.5, "delivery_time"].iloc[0],
            "p90": g.loc[cum >= 0.9, "delivery_time"].iloc[0],
            "late": g.loc[g["delivery_time"] > 30, "share"].sum() * 100,
        }
    order = sorted(stats, key=lambda r: stats[r]["median"])
    ymax = df.loc[df["delivery_time"] <= max_days, "share"].max() * 100 * 1.1

    fig = plt.figure(figsize=(12, 8.5))
    n = len(order)
    top, bottom, gap = 0.80, 0.11, 0.012
    h = (top - bottom - gap * (n - 1)) / n
    days = np.arange(0, max_days + 1)

    for k, region in enumerate(order):
        name, color = REGIONS.get(region, (region, MUTED))
        g = df[df["region"] == region].set_index("delivery_time")["share"]
        y = g.reindex(days, fill_value=0).to_numpy() * 100

        ax = fig.add_axes([0.20, top - (k + 1) * h - k * gap, 0.62, h])
        ax.fill_between(days, y, color=color, alpha=0.25, linewidth=0)
        ax.plot(days, y, color=color, linewidth=2)
        st = stats[region]
        ax.axvline(st["median"], color=TEXT, linewidth=1.2, linestyle=(0, (3, 2)))
        ax.set_xlim(0, max_days)
        ax.set_ylim(0, ymax)
        ax.set_yticks([])
        for sp in ("left", "top", "right"):
            ax.spines[sp].set_visible(False)
        ax.tick_params(length=0)
        if k < n - 1:
            ax.tick_params(labelbottom=False)
        else:
            ax.set_xlabel("Дней от покупки до доставки")
        ax.grid(axis="x")
        ax.set_axisbelow(True)

        ax.text(-0.02, 0.35, name, transform=ax.transAxes, ha="right", va="center",
                fontsize=12.5, fontweight="bold", color=TEXT)
        ax.text(1.02, 0.55, f"медиана {st['median']:.0f} дн.", transform=ax.transAxes,
                ha="left", va="center", fontsize=10.5, fontweight="bold", color=TEXT)
        ax.text(1.02, 0.22, f"90% — за {st['p90']:.0f} дн.\nдольше 30 дн.: {st['late']:.1f}%",
                transform=ax.transAxes, ha="left", va="center", fontsize=9, color=TEXT_2)

    header(fig, "Сколько ждут доставку в разных регионах Бразилии",
           "Распределение доставленных заказов по сроку доставки, доля внутри региона · "
           "пунктир — медиана", BLUE)
    footer(fig, f"по оси X — до {max_days} дней, более долгие доставки не показаны")
    save(fig, "delivery_time_regions.png")


# 8. Кривая Лоренца по выручке продавцов
def chart_lorenz() -> None:
    df = load("mv_lorenz").sort_values("cum_sellers")
    x = np.concatenate([[0.0], df["cum_sellers"].astype(float).to_numpy()])
    y = np.concatenate([[0.0], df["cum_revenue"].astype(float).to_numpy()])
    gini = 1 - np.sum((x[1:] - x[:-1]) * (y[1:] + y[:-1]))

    def share_at(q: float) -> float:
        """Доля выручки, которую дают первые q продавцов (от мелких к крупным)."""
        return float(np.interp(q, x, y))

    fig = plt.figure(figsize=(10, 10))
    ax = fig.add_axes([0.12, 0.09, 0.80, 0.74])

    ax.plot([0, 1], [0, 1], color=MUTED, linewidth=1.2, linestyle=(0, (4, 3)))
    ax.fill_between(x, y, x, color=VIOLET, alpha=0.12, linewidth=0)
    ax.plot(x, y, color=VIOLET, linewidth=2.5)
    ax.text(0.52, 0.56, "линия равенства", rotation=45, rotation_mode="anchor",
            transform=ax.transData, fontsize=9.5, color=MUTED, ha="center")

    for q, text_fn, offset in [
        (0.8, lambda v: f"80% продавцов\nдают {v * 100:.0f}% выручки", (-150, 40)),
        (0.9, lambda v: f"топ-10% продавцов\nдают {(1 - v) * 100:.0f}% выручки", (-175, 55)),
    ]:
        v = share_at(q)
        ax.scatter([q], [v], s=70, color=VIOLET, edgecolor=SURFACE, linewidth=2, zorder=4)
        ax.annotate(text_fn(v), (q, v), xytext=offset, textcoords="offset points",
                    fontsize=10.5, fontweight="bold", color=TEXT,
                    arrowprops=dict(arrowstyle="-", color=MUTED, lw=1))

    ax.text(0.04, 0.93, f"{gini:.2f}", transform=ax.transAxes, fontsize=34,
            fontweight="bold", color=VIOLET, va="top")
    ax.text(0.04, 0.80, "коэффициент Джини\n0 — все равны, 1 — всё у одного", transform=ax.transAxes,
            fontsize=10, color=TEXT_2, va="top")

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.xaxis.set_major_formatter(mticker.PercentFormatter(1.0, decimals=0))
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(1.0, decimals=0))
    ax.set_xlabel("Накопленная доля продавцов (от самых мелких к крупным)")
    ax.set_ylabel("Накопленная доля выручки")
    ax.set_aspect("equal")
    clean(ax, grid_axis="both")

    header(fig, "Насколько выручка сосредоточена у крупных продавцов",
           "Кривая Лоренца: чем сильнее кривая провисает под диагональ, тем выше неравенство", VIOLET)
    footer(fig)
    save(fig, "lorenz_sellers.png")


# Основной процесс
def main() -> None:
    print("Строю графики...")
    chart_cohorts()
    chart_revenue_anomalies()
    chart_delivery_score()
    chart_delivery_categories()
    chart_abc_xyz()
    chart_product_pairs()
    chart_delivery_time()
    chart_lorenz()
    print("Готово.")


ENGINE = None

if __name__ == "__main__":
    import sys
    from sqlalchemy import text
    from sqlalchemy.exc import OperationalError

    password = DB_PASSWORD
    while not password:
        password = getpass(f"Введи пароль PostgreSQL для пользователя {DB_USER} "
                           f"(символы не отображаются) и нажми Enter: ")
        if not password:
            print("Пароль пустой, попробуй ещё раз.")

    ENGINE = create_engine(URL.create(
        "postgresql+psycopg2",
        username=DB_USER, password=password,
        host=DB_HOST, port=int(DB_PORT), database=DB_NAME,
    ))
    try:
        with ENGINE.connect() as conn:
            conn.execute(text("SELECT 1"))
    except OperationalError as e:
        print("\nНе удалось подключиться к базе:")
        print(" ", str(e.orig).strip().splitlines()[0])
        print(f"\nПараметры: пользователь={DB_USER}, база={DB_NAME}, хост={DB_HOST}:{DB_PORT}")
        print("Проверь пароль и название базы (как в pgAdmin).")
        sys.exit(1)
    main()
