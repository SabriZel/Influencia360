suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

usuarios_qc <- read_csv("data/raw/usuarios.csv", show_col_types = FALSE)
relaciones_qc <- read_csv("data/raw/relaciones.csv", show_col_types = FALSE)
publicaciones_qc <- read_csv("data/raw/publicaciones.csv", show_col_types = FALSE)
interacciones_qc <- read_csv("data/raw/interacciones.csv", show_col_types = FALSE)

controles <- tibble(
  control = c(
    "Clave única de usuarios", "Clave única de publicaciones",
    "Clave única de interacciones", "Relaciones sin duplicados",
    "Seguidores con usuario válido", "Seguidos con usuario válido",
    "Autores con usuario válido", "Interacciones con usuario válido",
    "Interacciones con publicación válida", "Sin auto-seguimientos",
    "Calidad de contenido entre 0 y 1", "Impresiones positivas"
  ),
  aprobado = c(
    !anyDuplicated(usuarios_qc$usuario_id),
    !anyDuplicated(publicaciones_qc$publicacion_id),
    !anyDuplicated(interacciones_qc$interaccion_id),
    !anyDuplicated(relaciones_qc[c("seguidor_id", "seguido_id")]),
    all(relaciones_qc$seguidor_id %in% usuarios_qc$usuario_id),
    all(relaciones_qc$seguido_id %in% usuarios_qc$usuario_id),
    all(publicaciones_qc$autor_id %in% usuarios_qc$usuario_id),
    all(interacciones_qc$usuario_id %in% usuarios_qc$usuario_id),
    all(interacciones_qc$publicacion_id %in% publicaciones_qc$publicacion_id),
    all(relaciones_qc$seguidor_id != relaciones_qc$seguido_id),
    all(dplyr::between(publicaciones_qc$calidad_contenido, 0, 1)),
    all(publicaciones_qc$impresiones > 0)
  )
)

write_csv(controles, "data/processed/control_calidad.csv")
if (!all(controles$aprobado)) {
  stop("Fallaron controles de calidad: ",
       paste(controles$control[!controles$aprobado], collapse = "; "))
}
message("Control de calidad: ", nrow(controles), " de ", nrow(controles), " pruebas aprobadas.")

