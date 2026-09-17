suppressPackageStartupMessages({
  library(bnlearn)
  library(dplyr)
  library(tidyr)
  library(readr)
})

set.seed(20260917)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("models", recursive = TRUE, showWarnings = FALSE)

usuarios <- read_csv("data/raw/usuarios.csv", show_col_types = FALSE)
relaciones <- read_csv("data/raw/relaciones.csv", show_col_types = FALSE)
publicaciones <- read_csv("data/raw/publicaciones.csv", show_col_types = FALSE)
interacciones <- read_csv("data/raw/interacciones.csv", show_col_types = FALSE)

entrantes <- relaciones %>% count(seguido_id, name = "seguidores")
salientes <- relaciones %>% count(seguidor_id, name = "seguidos")
pares <- relaciones %>%
  inner_join(relaciones, by = c("seguidor_id" = "seguido_id", "seguido_id" = "seguidor_id")) %>%
  count(seguidor_id, name = "vinculos_reciprocos")

actividad_posts <- publicaciones %>%
  group_by(autor_id) %>%
  summarise(publicaciones = n(), calidad_media = mean(calidad_contenido),
            impresiones = sum(impresiones), .groups = "drop")

recibidas <- interacciones %>%
  left_join(publicaciones %>% select(publicacion_id, autor_id), by = "publicacion_id") %>%
  count(autor_id, tipo_interaccion, name = "n") %>%
  pivot_wider(names_from = tipo_interaccion, values_from = n, values_fill = 0)

emitidas <- interacciones %>% count(usuario_id, name = "interacciones_emitidas")

perfiles <- usuarios %>%
  left_join(entrantes, by = c("usuario_id" = "seguido_id")) %>%
  left_join(salientes, by = c("usuario_id" = "seguidor_id")) %>%
  left_join(pares, by = c("usuario_id" = "seguidor_id")) %>%
  left_join(actividad_posts, by = c("usuario_id" = "autor_id")) %>%
  left_join(recibidas, by = c("usuario_id" = "autor_id")) %>%
  left_join(emitidas, by = "usuario_id") %>%
  mutate(across(c(seguidores, seguidos, vinculos_reciprocos, publicaciones, impresiones,
                  Me_gusta, Comentario, Compartido, Guardado, interacciones_emitidas),
                ~replace_na(.x, 0)),
         calidad_media = replace_na(calidad_media, 0),
         antiguedad_dias = as.integer(as.Date("2026-09-17") - as.Date(fecha_registro)),
         interacciones_recibidas = Me_gusta + Comentario + Compartido + Guardado,
         tasa_engagement = 100 * interacciones_recibidas / pmax(impresiones, 1),
         reciprocidad = vinculos_reciprocos / pmax(seguidos, 1),
         centralidad = seguidores / pmax(max(seguidores), 1),
         score_influencia = 100 * (.28 * percent_rank(log1p(seguidores)) +
                                    .24 * percent_rank(log1p(impresiones)) +
                                    .22 * percent_rank(tasa_engagement) +
                                    .16 * percent_rank(calidad_media) +
                                    .10 * verificado),
         score_seguidor = 100 * (.45 * percent_rank(interacciones_emitidas) +
                                  .30 * percent_rank(reciprocidad) +
                                  .25 * percent_rank(seguidos)))

discretizar <- function(x) {
  cortes <- quantile(x, probs = c(1/3, 2/3), na.rm = TRUE, type = 8)
  factor(ifelse(x <= cortes[1], "Bajo", ifelse(x <= cortes[2], "Medio", "Alto")),
         levels = c("Bajo", "Medio", "Alto"))
}

datos_bn <- perfiles %>%
  transmute(
    antiguedad = discretizar(antiguedad_dias),
    frecuencia = discretizar(publicaciones),
    calidad_contenido = discretizar(calidad_media),
    tasa_engagement = discretizar(tasa_engagement),
    alcance = discretizar(impresiones),
    centralidad = discretizar(centralidad),
    reciprocidad = discretizar(reciprocidad),
    actividad_seguidor = discretizar(interacciones_emitidas),
    verificado = factor(ifelse(verificado, "Si", "No"), levels = c("No", "Si")),
    potencial_influencia = discretizar(score_influencia),
    calidad_seguidor = discretizar(score_seguidor)
  )

# bnlearn requiere data.frame base y no admite niveles declarados sin casos.
# Esto ocurre, por ejemplo, cuando muchos perfiles tienen reciprocidad cero.
datos_bn <- as.data.frame(droplevels(datos_bn))

# La orientación respeta el tiempo y evita que los objetivos sean causas de sus
# propios predictores. La estructura restante se aprende con hill climbing/BIC.
objetivos <- c("potencial_influencia", "calidad_seguidor")
predictores <- setdiff(names(datos_bn), objetivos)
blacklist <- expand.grid(from = objetivos, to = predictores, stringsAsFactors = FALSE)
blacklist <- bind_rows(blacklist, tibble(from = "potencial_influencia", to = "calidad_seguidor"),
                       tibble(from = "calidad_seguidor", to = "potencial_influencia"))

idx_train <- sample(seq_len(nrow(datos_bn)), floor(.80 * nrow(datos_bn)))
train <- as.data.frame(datos_bn[idx_train, , drop = FALSE])
test <- as.data.frame(datos_bn[-idx_train, , drop = FALSE])

red_train <- hc(train, score = "bde", iss = 10, blacklist = blacklist, restart = 20, perturb = 5)
ajuste_train <- bn.fit(red_train, train, method = "bayes", iss = 10)

pred_inf <- predict(ajuste_train, node = "potencial_influencia", data = test, method = "bayes-lw")
pred_seg <- predict(ajuste_train, node = "calidad_seguidor", data = test, method = "bayes-lw")
metricas <- tibble(
  objetivo = c("Potencial de influencia", "Calidad como seguidor"),
  exactitud = c(mean(pred_inf == test$potencial_influencia),
                mean(pred_seg == test$calidad_seguidor)),
  n_entrenamiento = nrow(train),
  n_prueba = nrow(test),
  metodo = "Hill climbing + BDe; parámetros Bayes/Dirichlet"
)

red_final <- hc(datos_bn, score = "bde", iss = 10, blacklist = blacklist,
                restart = 30, perturb = 5)
ajuste_final <- bn.fit(red_final, datos_bn, method = "bayes", iss = 10)
saveRDS(list(red = red_final, ajuste = ajuste_final, niveles = lapply(datos_bn, levels)),
        "models/red_bayesiana.rds")

prob_inf <- predict(ajuste_final, node = "potencial_influencia", data = datos_bn,
                    method = "bayes-lw", prob = TRUE)
prob_seg <- predict(ajuste_final, node = "calidad_seguidor", data = datos_bn,
                    method = "bayes-lw", prob = TRUE)
mat_inf <- t(attr(prob_inf, "prob"))
mat_seg <- t(attr(prob_seg, "prob"))

perfiles_salida <- perfiles %>%
  mutate(clase_influencia = as.character(datos_bn$potencial_influencia),
         clase_seguidor = as.character(datos_bn$calidad_seguidor),
         prob_influencia_alta = mat_inf[, "Alto"],
         prob_seguidor_alta = mat_seg[, "Alto"])

ranking_influenciadores <- perfiles_salida %>%
  arrange(desc(prob_influencia_alta), desc(score_influencia)) %>%
  mutate(posicion = row_number()) %>%
  select(posicion, usuario_id, usuario, nombre, pais, nicho, verificado, seguidores,
         publicaciones, impresiones, tasa_engagement, score_influencia,
         clase_influencia, prob_influencia_alta)

ranking_seguidores <- perfiles_salida %>%
  arrange(desc(prob_seguidor_alta), desc(score_seguidor)) %>%
  mutate(posicion = row_number()) %>%
  select(posicion, usuario_id, usuario, nombre, pais, nicho, seguidos,
         interacciones_emitidas, reciprocidad, score_seguidor,
         clase_seguidor, prob_seguidor_alta)

arcos <- as_tibble(arcs(red_final)) %>% rename(origen = from, destino = to)
fortalezas <- arc.strength(red_final, datos_bn, criterion = "x2") %>%
  as_tibble() %>% rename(origen = from, destino = to, p_value = strength)
arcos <- arcos %>% left_join(fortalezas, by = c("origen", "destino"))

set.seed(20260917)
escenarios <- tibble(
  escenario = c("Base", "Alcance, engagement y centralidad altos",
                "Alcance bajo y engagement alto", "Perfil verificado y contenido alto"),
  prob_influencia_alta = c(
    cpquery(ajuste_final, potencial_influencia == "Alto", TRUE, method = "lw", n = 50000),
    cpquery(ajuste_final, potencial_influencia == "Alto",
            list(alcance = "Alto", tasa_engagement = "Alto", centralidad = "Alto"),
            method = "lw", n = 50000),
    cpquery(ajuste_final, potencial_influencia == "Alto",
            list(alcance = "Bajo", tasa_engagement = "Alto"), method = "lw", n = 50000),
    cpquery(ajuste_final, potencial_influencia == "Alto",
            list(verificado = "Si", calidad_contenido = "Alto"), method = "lw", n = 50000)
  )
)

write_csv(perfiles_salida, "data/processed/perfiles_analiticos.csv")
write_csv(ranking_influenciadores, "data/processed/ranking_influenciadores.csv")
write_csv(ranking_seguidores, "data/processed/ranking_seguidores.csv")
write_csv(arcos, "data/processed/arcos_red_bayesiana.csv")
write_csv(metricas, "data/processed/metricas_modelo.csv")
write_csv(escenarios, "data/processed/escenarios_inferencia.csv")

message("Modelo generado con ", nrow(arcos), " arcos; exactitud influencia = ",
        round(metricas$exactitud[1], 3), ".")
