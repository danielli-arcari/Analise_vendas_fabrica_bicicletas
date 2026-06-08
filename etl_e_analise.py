"""
ETL e analise das vendas de bicicletas (2013 a 2016)
Etapas:
    1. Ler os 4 arquivos de origem (vendas e fabricacao, em dois periodos)
    2. Separar Pais e Produto nos arquivos de 2013-2014 (vinham numa coluna so)
    3. Padronizar nomes de coluna
    4. Corrigir erros de digitacao em segmentos e paises
    5. Unir os periodos (append) em duas bases unicas
    6. Salvar as bases tratadas em CSV
    7. Calcular os indicadores e gerar os graficos da analise
"""

from pathlib import Path
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# Todos os arquivos ficam na mesma pasta deste script

PASTA = Path(__file__).resolve().parent
BRUTOS = PASTA
TRATADOS = PASTA
IMAGENS = PASTA


# 1. Leitura

def ler(nome):
    return pd.read_excel(BRUTOS / nome, sheet_name=0)

sales_13 = ler("Base_de_dados_2013_2014_-_Sales.xlsx")
sales_15 = ler("Base_de_dados_2015_2016_-_Sales.xlsx")
manuf_13 = ler("Base_de_dados_2013_2014_-_Manufacturing.xlsx")
manuf_15 = ler("Base_de_dados_2015_2016_-_Manufacturing.xlsx")


# 2. Separar Pais e Produto nos arquivos de 2013-2014

def separar_pais_produto(df):
    partes = df["Country,Product"].str.split(",", n=1, expand=True)
    df["Country"] = partes[0].str.strip()
    df["Product"] = partes[1].str.strip()
    return df.drop(columns=["Country,Product"])

sales_13 = separar_pais_produto(sales_13)
manuf_13 = separar_pais_produto(manuf_13)


# 3. Padronizar nomes de coluna

for df in (sales_13, sales_15, manuf_13, manuf_15):
    df.columns = [c.strip() for c in df.columns]


# 4. Corrigir erros de digitacao

CORRECAO_SEGMENTO = {
    "Chanel Partners": "Channel Partners",
    "Enter&rise": "Enterprise",
    "Enterrise": "Enterprise",
    "Governmemt": "Government",
    "Smal Business": "Small Business",
}
CORRECAO_PAIS = {"FrancE": "France"}

for df in (sales_13, sales_15, manuf_13, manuf_15):
    df["Segment"] = df["Segment"].replace(CORRECAO_SEGMENTO)
    df["Country"] = df["Country"].replace(CORRECAO_PAIS)
    df["Product"] = df["Product"].astype(str).str.strip()


# 5. Unir os periodos (append)

vendas = pd.concat([sales_13, sales_15], ignore_index=True)
fabricacao = pd.concat([manuf_13, manuf_15], ignore_index=True)
vendas["Date"] = pd.to_datetime(vendas["Date"])

print(f"Vendas tratadas:     {len(vendas)} linhas")
print(f"Fabricacao tratada:  {len(fabricacao)} linhas")


# 6. Salvar bases tratadas

vendas.to_csv(TRATADOS / "vendas_tratadas.csv", index=False, encoding="utf-8-sig")
fabricacao.to_csv(TRATADOS / "fabricacao_tratada.csv", index=False, encoding="utf-8-sig")


# 7. Analise

total_vendas = vendas["Sales"].sum()
total_lucro = vendas["Profit"].sum()
margem = total_lucro / total_vendas

print("\n=== Indicadores gerais ===")
print(f"Total de vendas: R$ {total_vendas:,.0f}")
print(f"Lucro total:     R$ {total_lucro:,.0f}")
print(f"Margem de lucro: {margem:.1%}")

# Vendas por ano (atencao: 2013 tem apenas 4 meses de dados)
por_ano = vendas.groupby("Year")["Sales"].sum()
meses_por_ano = vendas.groupby("Year")["Date"].apply(lambda s: s.dt.month.nunique())
print("\n=== Vendas por ano (meses cobertos) ===")
for ano in por_ano.index:
    print(f"{ano}: R$ {por_ano[ano]:,.0f}  ({meses_por_ano[ano]} meses)")
queda_15 = (por_ano[2015] - por_ano[2014]) / por_ano[2014]
var_16 = (por_ano[2016] - por_ano[2015]) / por_ano[2015]
print(f"Variacao 2014 -> 2015: {queda_15:.1%}")
print(f"Variacao 2015 -> 2016: {var_16:+.1%}")

# Por segmento
seg = vendas.groupby("Segment").agg(
    Vendas=("Sales", "sum"),
    Lucro=("Profit", "sum"),
    Unidades=("Units Sold", "sum"),
)
seg["Margem"] = seg["Lucro"] / seg["Vendas"]
seg["%_do_lucro"] = seg["Lucro"] / total_lucro
seg["%_das_unidades"] = seg["Unidades"] / seg["Unidades"].sum()
seg = seg.sort_values("Lucro", ascending=False)
print("\n=== Por segmento ===")
print(seg.to_string())

# Por pais e por produto
print("\n=== Vendas por pais ===")
print(vendas.groupby("Country")["Sales"].sum().sort_values(ascending=False).to_string())
print("\n=== Vendas por produto ===")
print(vendas.groupby("Product")["Sales"].sum().sort_values(ascending=False).to_string())


# ---------------------------------------------------------------------------
# 8. Graficos para o README
# ---------------------------------------------------------------------------
AZUL = "#0D1B3E"
ROSA = "#E8006F"
CINZA = "#9AA3B2"

def milhoes(x, pos):
    return f"{x/1e6:.0f}M"

# Grafico 1: vendas por ano
fig, ax = plt.subplots(figsize=(8, 4.5))
cores = [CINZA if ano == 2013 else AZUL for ano in por_ano.index]
ax.bar(por_ano.index.astype(str), por_ano.values, color=cores)
ax.set_title("Vendas por ano (2013 com apenas 4 meses de dados)", fontsize=12, color=AZUL, weight="bold")
ax.yaxis.set_major_formatter(mticker.FuncFormatter(milhoes))
ax.set_ylabel("Vendas")
for i, v in enumerate(por_ano.values):
    ax.text(i, v, f"R$ {v/1e6:.1f}M", ha="center", va="bottom", fontsize=9)
ax.spines[["top", "right"]].set_visible(False)
plt.tight_layout()
plt.savefig(IMAGENS / "vendas_por_ano.png", dpi=130)
plt.close()

# Grafico 2: lucro e margem por segmento
seg_plot = seg.sort_values("Lucro")
fig, ax = plt.subplots(figsize=(8, 4.5))
cores = [ROSA if v < 0 else AZUL for v in seg_plot["Lucro"].values]
ax.barh(seg_plot.index, seg_plot["Lucro"].values, color=cores)
ax.set_title("Lucro por segmento (Enterprise opera no prejuizo)", fontsize=12, color=AZUL, weight="bold")
ax.xaxis.set_major_formatter(mticker.FuncFormatter(milhoes))
ax.set_xlabel("Lucro")
for i, (lucro, m) in enumerate(zip(seg_plot["Lucro"].values, seg_plot["Margem"].values)):
    ax.text(lucro, i, f"  {m:.0%}", va="center", fontsize=9,
            ha="left" if lucro >= 0 else "right")
ax.axvline(0, color="#333", linewidth=0.8)
ax.spines[["top", "right"]].set_visible(False)
plt.tight_layout()
plt.savefig(IMAGENS / "lucro_por_segmento.png", dpi=130)
plt.close()

# Grafico 3: vendas por produto
prod = vendas.groupby("Product")["Sales"].sum().sort_values()
fig, ax = plt.subplots(figsize=(8, 4.5))
ax.barh(prod.index, prod.values, color=AZUL)
ax.set_title("Vendas por produto", fontsize=12, color=AZUL, weight="bold")
ax.xaxis.set_major_formatter(mticker.FuncFormatter(milhoes))
ax.spines[["top", "right"]].set_visible(False)
plt.tight_layout()
plt.savefig(IMAGENS / "vendas_por_produto.png", dpi=130)
plt.close()

print("\nGraficos salvos em /imagens.")
print("Bases tratadas salvas em /dados/tratados.")
