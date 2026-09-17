# Influencia360: análisis de redes sociales con redes bayesianas

Proyecto académico de Business Intelligence que genera una red social completamente ficticia con `charlatan`, explora perfiles, publicaciones, relaciones e interacciones, y emplea una red bayesiana discreta para identificar influenciadores y seguidores de valor.

## Ejecución rápida

Desde la raíz del proyecto:

```bash
Rscript run_all.R
```

La orden genera los CSV, entrena y evalúa el modelo y publica tres documentos en `docs/`:

- `index.html`: informe metodológico y ejecutivo.
- `dashboard_datos.html`: exploración interactiva de los datos iniciales.
- `dashboard_resultados.html`: ranking, red bayesiana y escenarios de inferencia.

Los resultados incluidos son reproducibles con la semilla `20260917`. Todos los nombres, organizaciones, perfiles y eventos son sintéticos; no representan personas reales.

## Estructura

```text
R/                    generación, preparación, modelado y utilidades
data/raw/             CSV simulados con charlatan
data/processed/       variables analíticas y rankings en CSV
models/               red ajustada (artefacto regenerable)
reports/              RMarkdown del informe y dashboards
docs/                 HTML listo para abrir o publicar
run_all.R              pipeline completo
```

## Dependencias principales

`charlatan`, `bnlearn`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `plotly`, `DT`, `visNetwork`, `flexdashboard`, `rmarkdown` y `knitr`.

Si faltan paquetes, instálelos una vez con:

```r
install.packages(c("charlatan", "bnlearn", "dplyr", "tidyr", "readr",
                   "ggplot2", "plotly", "DT", "visNetwork",
                   "flexdashboard", "rmarkdown", "knitr"))
```

## Alcance analítico

La red bayesiana estima asociaciones probabilísticas condicionales. En este conjunto ficticio el proceso generador es conocido, pero el modelo aprendido de datos observacionales no demuestra causalidad. Sus probabilidades deben interpretarse como apoyo para priorización y no como una decisión automática sobre personas.

