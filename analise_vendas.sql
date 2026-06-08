-- ============================================================================
--  Analise de vendas de bicicletas (2013 a 2016)
--  Reproducao das transformacoes e medidas em SQL (dialeto PostgreSQL)
--
--  O projeto foi feito em Power BI com tratamento no Power Query.
--  Este arquivo mostra a mesma logica escrita em SQL: criar as tabelas,
--  limpar os dados, unir os periodos, montar a tabela de calendario e
--  reproduzir as metricas que no Power BI eram medidas DAX.
--
--  Ordem de execucao:
--    1. Tabelas de origem (staging)
--    2. Limpeza e padronizacao
--    3. Bases consolidadas (append via UNION ALL)
--    4. Tabela de calendario
--    5. Analises (reproduzem as medidas DAX)
-- ============================================================================


-- ============================================================================
-- 1. TABELAS DE ORIGEM (staging)
--    Quatro arquivos: vendas e fabricacao, cada um em dois periodos.
--    Nos arquivos de 2013-2014, pais e produto vinham juntos numa coluna so.
-- ============================================================================

CREATE TABLE stg_sales_2013_2014 (
    segment          TEXT,
    country_product  TEXT,        -- "Germany,Carretera" -> sera separado
    discount_band    TEXT,
    units_sold       NUMERIC,
    sale_price       NUMERIC,
    gross_sales      NUMERIC,
    discounts        NUMERIC,
    sales            NUMERIC,
    profit           NUMERIC,
    date             DATE,
    month_number     INT,
    month_name       TEXT,
    year             INT
);

CREATE TABLE stg_sales_2015_2016 (
    segment        TEXT,
    country        TEXT,
    product        TEXT,
    discount_band  TEXT,
    units_sold     NUMERIC,
    sale_price     NUMERIC,
    gross_sales    NUMERIC,
    discounts      NUMERIC,
    sales          NUMERIC,
    profit         NUMERIC,
    date           DATE,
    month_number   INT,
    month_name     TEXT,
    year           INT
);

CREATE TABLE stg_manufacturing_2013_2014 (
    segment              TEXT,
    country_product      TEXT,
    units_sold           NUMERIC,
    manufacturing_price  NUMERIC,
    cogs                 NUMERIC,
    date                 DATE,
    month_number         INT,
    month_name           TEXT,
    year                 INT
);

CREATE TABLE stg_manufacturing_2015_2016 (
    segment              TEXT,
    country              TEXT,
    product              TEXT,
    units_sold           NUMERIC,
    manufacturing_price  NUMERIC,
    cogs                 NUMERIC,
    date                 DATE,
    month_number         INT,
    month_name           TEXT,
    year                 INT
);

-- A carga dos dados (COPY a partir dos CSV tratados, ou import direto) entra aqui.
-- Ex.: \copy stg_sales_2013_2014 FROM 'sales_2013_2014.csv' CSV HEADER;


-- ============================================================================
-- 2. FUNCAO DE LIMPEZA
--    Padroniza segmentos e paises corrigindo os erros de digitacao que
--    geravam categorias duplicadas. Usada em todas as bases.
-- ============================================================================

-- Segmento: junta as variacoes escritas errado no nome certo
--   Chanel Partners -> Channel Partners
--   Enter&rise / Enterrise -> Enterprise
--   Governmemt -> Government
--   Smal Business -> Small Business
-- Pais:
--   FrancE -> France

-- Expressao reaproveitada nas views abaixo via CASE.


-- ============================================================================
-- 3. BASES CONSOLIDADAS (append via UNION ALL)
--    Resultado: uma view de vendas e uma de fabricacao cobrindo 2013 a 2016,
--    ja com pais e produto separados e os textos padronizados.
-- ============================================================================

CREATE VIEW vendas AS
WITH base AS (
    -- periodo 2013-2014: separar country_product pela virgula
    SELECT
        segment,
        TRIM(SPLIT_PART(country_product, ',', 1)) AS country,
        TRIM(SPLIT_PART(country_product, ',', 2)) AS product,
        units_sold, sales, profit, date, year
    FROM stg_sales_2013_2014
    UNION ALL
    -- periodo 2015-2016: pais e produto ja vem separados
    SELECT
        segment, country, TRIM(product) AS product,
        units_sold, sales, profit, date, year
    FROM stg_sales_2015_2016
)
SELECT
    CASE segment
        WHEN 'Chanel Partners' THEN 'Channel Partners'
        WHEN 'Enter&rise'      THEN 'Enterprise'
        WHEN 'Enterrise'       THEN 'Enterprise'
        WHEN 'Governmemt'      THEN 'Government'
        WHEN 'Smal Business'   THEN 'Small Business'
        ELSE segment
    END AS segment,
    CASE country WHEN 'FrancE' THEN 'France' ELSE country END AS country,
    product,
    units_sold,
    sales,
    profit,
    date,
    year
FROM base;

CREATE VIEW fabricacao AS
WITH base AS (
    SELECT
        segment,
        TRIM(SPLIT_PART(country_product, ',', 1)) AS country,
        TRIM(SPLIT_PART(country_product, ',', 2)) AS product,
        units_sold, cogs, date, year
    FROM stg_manufacturing_2013_2014
    UNION ALL
    SELECT
        segment, country, TRIM(product) AS product,
        units_sold, cogs, date, year
    FROM stg_manufacturing_2015_2016
)
SELECT
    CASE segment
        WHEN 'Chanel Partners' THEN 'Channel Partners'
        WHEN 'Enter&rise'      THEN 'Enterprise'
        WHEN 'Enterrise'       THEN 'Enterprise'
        WHEN 'Governmemt'      THEN 'Government'
        WHEN 'Smal Business'   THEN 'Small Business'
        ELSE segment
    END AS segment,
    CASE country WHEN 'FrancE' THEN 'France' ELSE country END AS country,
    product, units_sold, cogs, date, year
FROM base;


-- ============================================================================
-- 4. TABELA DE CALENDARIO
--    No Power BI ela era o centro do Star Schema. Em SQL, geramos uma tabela
--    de datas continua de jan/2013 a dez/2016 para servir de eixo de tempo.
-- ============================================================================

CREATE TABLE calendario AS
SELECT
    d::date                              AS date,
    EXTRACT(YEAR  FROM d)::int           AS ano,
    EXTRACT(MONTH FROM d)::int           AS mes_numero,
    TO_CHAR(d, 'TMMonth')                AS mes_nome,
    EXTRACT(QUARTER FROM d)::int         AS trimestre
FROM generate_series('2013-01-01'::date, '2016-12-01'::date, '1 month') AS d;


-- ============================================================================
-- 5. ANALISES (reproduzem as medidas DAX do projeto)
-- ============================================================================

-- 5.1 Indicadores gerais (Total_Sales, Total_Profit, Margem)
--     Esperado: vendas ~237,96 mi | lucro ~35,16 mi | margem ~15%
SELECT
    SUM(sales)                       AS total_vendas,
    SUM(profit)                      AS lucro_total,
    SUM(profit) / SUM(sales)         AS margem
FROM vendas;

-- 5.2 Vendas por ano + quantos meses cada ano cobre
--     Atencao: 2013 tem apenas 4 meses (set a dez), por isso nao se compara
--     de igual para igual com 2014, 2015 e 2016.
SELECT
    year                             AS ano,
    COUNT(DISTINCT date)             AS meses_cobertos,
    SUM(sales)                       AS vendas
FROM vendas
GROUP BY year
ORDER BY year;

-- 5.3 Crescimento ano a ano (reproduz a medida YoY)
--     Compara cada ano com o anterior usando LAG.
SELECT
    ano,
    vendas,
    LAG(vendas) OVER (ORDER BY ano)  AS vendas_ano_anterior,
    ROUND(
        (vendas - LAG(vendas) OVER (ORDER BY ano))
        / LAG(vendas) OVER (ORDER BY ano) * 100, 1
    )                                AS variacao_pct
FROM (
    SELECT year AS ano, SUM(sales) AS vendas
    FROM vendas GROUP BY year
) t
ORDER BY ano;

-- 5.4 Por segmento: vendas, lucro, margem e participacao
--     Aqui aparece o achado principal: Enterprise opera no prejuizo,
--     enquanto Channel Partners e o segmento mais eficiente em margem.
SELECT
    segment,
    SUM(sales)                                          AS vendas,
    SUM(profit)                                         AS lucro,
    SUM(units_sold)                                     AS unidades,
    ROUND(SUM(profit) / SUM(sales) * 100, 1)            AS margem_pct,
    ROUND(SUM(profit) / SUM(SUM(profit)) OVER () * 100, 1) AS pct_do_lucro
FROM vendas
GROUP BY segment
ORDER BY lucro DESC;

-- 5.5 Vendas por pais
SELECT country AS pais, SUM(sales) AS vendas
FROM vendas
GROUP BY country
ORDER BY vendas DESC;

-- 5.6 Vendas por produto
SELECT product AS produto, SUM(sales) AS vendas
FROM vendas
GROUP BY product
ORDER BY vendas DESC;

-- 5.7 Custo de fabricacao por ano (reproduz Total_COGS)
SELECT year AS ano, SUM(cogs) AS custo_total
FROM fabricacao
GROUP BY year
ORDER BY ano;
