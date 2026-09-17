suppressPackageStartupMessages({
  library(charlatan)
  library(dplyr)
  library(readr)
})

set.seed(20260917)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

n_usuarios <- 650L
n_publicaciones <- 5200L

normalizar_usuario <- function(x, id) {
  limpio <- iconv(tolower(x), to = "ASCII//TRANSLIT")
  limpio <- gsub("[^a-z]", "", limpio)
  paste0(substr(limpio, 1, 14), sprintf("%04d", id))
}

usuarios <- tibble(
  usuario_id = sprintf("USR%04d", seq_len(n_usuarios)),
  nombre = ch_name(n_usuarios, locale = "en_US"),
  ocupacion = ch_job(n_usuarios, locale = "en_US"),
  organizacion = ch_company(n_usuarios, locale = "en_US"),
  pais = sample(c("Bolivia", "Perú", "Chile", "Argentina", "Colombia"),
                n_usuarios, replace = TRUE, prob = c(.38, .17, .15, .14, .16)),
  nicho = sample(c("Tecnología", "Educación", "Moda", "Deportes", "Gastronomía", "Viajes"),
                 n_usuarios, replace = TRUE),
  fecha_registro = as.Date("2018-01-01") + sample(0:3100, n_usuarios, replace = TRUE),
  latitud = round(ch_lat(n_usuarios), 5),
  longitud = round(ch_lon(n_usuarios), 5),
  atractivo_latente = rbeta(n_usuarios, 2.2, 3.0),
  actividad_latente = rbeta(n_usuarios, 2.5, 2.2),
  confianza_latente = rbeta(n_usuarios, 2.8, 2.0)
) %>%
  mutate(
    usuario = normalizar_usuario(nombre, row_number()),
    verificado = rbinom(n(), 1, plogis(-4 + 4 * atractivo_latente + 1.8 * confianza_latente)) == 1
  )

# Cada usuario sigue a una cantidad plausible de cuentas. La afinidad temática y
# el atractivo latente hacen que la red tenga comunidades e influenciadores.
relaciones_lista <- lapply(seq_len(n_usuarios), function(i) {
  cantidad <- min(n_usuarios - 1L, max(1L, rpois(1, 7 + 10 * usuarios$actividad_latente[i])))
  pesos <- 0.05 + usuarios$atractivo_latente^2 +
    0.8 * (usuarios$nicho == usuarios$nicho[i]) + 0.35 * usuarios$verificado
  pesos[i] <- 0
  destinos <- sample(seq_len(n_usuarios), cantidad, replace = FALSE, prob = pesos)
  tibble(
    seguidor_id = usuarios$usuario_id[i],
    seguido_id = usuarios$usuario_id[destinos],
    fecha_seguimiento = as.Date("2022-01-01") + sample(0:1700, cantidad, replace = TRUE)
  )
})
relaciones <- bind_rows(relaciones_lista) %>% distinct(seguidor_id, seguido_id, .keep_all = TRUE)

autor_idx <- sample(seq_len(n_usuarios), n_publicaciones, replace = TRUE,
                    prob = 0.05 + usuarios$actividad_latente)
calidad <- pmin(1, pmax(0, rbeta(n_publicaciones, 2, 2) * .55 +
                                 usuarios$atractivo_latente[autor_idx] * .45))
publicaciones <- tibble(
  publicacion_id = sprintf("PUB%06d", seq_len(n_publicaciones)),
  autor_id = usuarios$usuario_id[autor_idx],
  fecha_publicacion = as.Date("2024-01-01") + sample(0:625, n_publicaciones, replace = TRUE),
  tipo_contenido = sample(c("Imagen", "Video", "Texto", "Historia"), n_publicaciones,
                          replace = TRUE, prob = c(.32, .34, .19, .15)),
  tema = ifelse(runif(n_publicaciones) < .78, usuarios$nicho[autor_idx],
                sample(unique(usuarios$nicho), n_publicaciones, replace = TRUE)),
  calidad_contenido = round(calidad, 3),
  impresiones = pmax(20L, round(exp(4.0 + 3.4 * calidad +
                                      .65 * usuarios$verificado[autor_idx] + rnorm(n_publicaciones, 0, .65))))
)

# Se seleccionan publicaciones proporcionalmente a su calidad y exposición.
n_interacciones <- 36000L
pub_idx <- sample(seq_len(n_publicaciones), n_interacciones, replace = TRUE,
                  prob = sqrt(publicaciones$impresiones) * (0.25 + publicaciones$calidad_contenido))
actor_idx <- sample(seq_len(n_usuarios), n_interacciones, replace = TRUE,
                    prob = 0.1 + usuarios$actividad_latente)
autores_pub <- match(publicaciones$autor_id[pub_idx], usuarios$usuario_id)
misma_afinidad <- usuarios$nicho[actor_idx] == usuarios$nicho[autores_pub]

interacciones <- tibble(
  interaccion_id = sprintf("INT%07d", seq_len(n_interacciones)),
  usuario_id = usuarios$usuario_id[actor_idx],
  publicacion_id = publicaciones$publicacion_id[pub_idx],
  tipo_interaccion = vapply(seq_len(n_interacciones), function(i) {
    probs <- c(Me_gusta = .66, Comentario = .16, Compartido = .10, Guardado = .08)
    if (misma_afinidad[i]) probs <- probs + c(-.06, .025, .02, .015)
    sample(names(probs), 1, prob = probs)
  }, character(1)),
  fecha_interaccion = publicaciones$fecha_publicacion[pub_idx] + sample(0:14, n_interacciones, replace = TRUE)
) %>%
  filter(usuario_id != publicaciones$autor_id[match(publicacion_id, publicaciones$publicacion_id)]) %>%
  distinct(usuario_id, publicacion_id, tipo_interaccion, .keep_all = TRUE) %>%
  mutate(interaccion_id = sprintf("INT%07d", row_number()))

# Las variables latentes sólo controlan la simulación y no se entregan al modelo.
usuarios_csv <- usuarios %>%
  select(usuario_id, usuario, nombre, ocupacion, organizacion, pais, nicho,
         fecha_registro, latitud, longitud, verificado)

write_csv(usuarios_csv, "data/raw/usuarios.csv", na = "")
write_csv(relaciones, "data/raw/relaciones.csv", na = "")
write_csv(publicaciones, "data/raw/publicaciones.csv", na = "")
write_csv(interacciones, "data/raw/interacciones.csv", na = "")

diccionario <- tribble(
  ~archivo, ~campo, ~descripcion,
  "usuarios.csv", "usuario_id", "Clave sintética del perfil",
  "usuarios.csv", "verificado", "Indicador ficticio de verificación",
  "relaciones.csv", "seguidor_id", "Perfil que inicia la relación",
  "relaciones.csv", "seguido_id", "Perfil que recibe la relación",
  "publicaciones.csv", "calidad_contenido", "Señal simulada entre 0 y 1",
  "publicaciones.csv", "impresiones", "Exposición simulada de la publicación",
  "interacciones.csv", "tipo_interaccion", "Me gusta, comentario, compartido o guardado"
)
write_csv(diccionario, "data/raw/diccionario_datos.csv", na = "")

message("Datos generados: ", nrow(usuarios_csv), " perfiles, ", nrow(relaciones),
        " relaciones, ", nrow(publicaciones), " publicaciones y ",
        nrow(interacciones), " interacciones.")

