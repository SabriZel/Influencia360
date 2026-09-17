options(stringsAsFactors = FALSE)

local_lib <- file.path(getwd(), ".Rlib")
if (dir.exists(local_lib)) .libPaths(c(local_lib, .libPaths()))

required <- c(
  "charlatan", "bnlearn", "dplyr", "tidyr", "readr", "ggplot2",
  "plotly", "DT", "visNetwork", "flexdashboard", "rmarkdown", "knitr"
)
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Faltan paquetes: ", paste(missing, collapse = ", "),
       ". Consulte README.md para instalarlos.")
}

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("models", recursive = TRUE, showWarnings = FALSE)
dir.create("docs", recursive = TRUE, showWarnings = FALSE)

source("R/01_generar_datos.R", encoding = "UTF-8")
source("R/02_validar_datos.R", encoding = "UTF-8")
source("R/02_modelar_red_bayesiana.R", encoding = "UTF-8")

reports <- c(
  "reports/informe_proyecto.Rmd",
  "reports/dashboard_datos.Rmd",
  "reports/dashboard_resultados.Rmd"
)
outputs <- c("index.html", "dashboard_datos.html", "dashboard_resultados.html")

for (i in seq_along(reports)) {
  rmarkdown::render(
    input = reports[i],
    output_file = outputs[i],
    output_dir = normalizePath("docs", mustWork = TRUE),
    knit_root_dir = normalizePath(getwd()),
    envir = new.env(parent = globalenv()),
    quiet = TRUE
  )
  message("Generado: docs/", outputs[i])
}

message("Pipeline completo. Abra docs/index.html")
