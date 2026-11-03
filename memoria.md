# memoria.md — hq-panel

> Bitácora de decisiones y cambios, **lo más nuevo arriba**. Escribí corto y con el *por qué*, no solo el qué.

---

## 2026-11-03 — Compras HQ: gateway único, catálogo maestro y pantalla `compras.html`

Plan completo y decisiones: `~/Proyectos/_auditorias/COMPRAS-HQ-plan-2026-10-29.md`. Decisión de Jose: **un solo gateway, vistas independientes por empresa**.

- **Datos (btbox, schema `compras_hq`, no expuesto a la API):** `linea` junta las compras de las 5 empresas (Freakie DTE + BEES, Kaeru, Kako por SQL local; Eatalia y Scanzano desde wzk). `item` + `alias` traducen cada descripción de factura (por NIT) a un item con su tamaño en kg, l o unidad. `mv_precio` precalcula precio por unidad base y marca atípicos (más de 5x de la mediana). Vistas: `v_item_proveedor`, `v_comparativo`, `v_ahorro`, `v_alerta_precio`.
- **Sincronización:** edge fn `compras-hq-sync` (btbox), cron `compras-hq-sync` a las 3:53 y 15:53 SV. Trae Eatalia/Scanzano desde la edge fn `compras-export` (wzk). Sin secreto compartido: wzk le pregunta a btbox si la llave que recibió es su service_role.
- **Gateway:** edge fn `compras-gateway` (btbox). El token va en el link (`?t=`); la base guarda solo su SHA-256 en `compras_hq.acceso`. Token de empresa = solo sus compras (el parámetro `empresa` se ignora). Token HQ = todas, filtro por empresa y pestaña Revisar (confirmar o corregir alias). Al confirmar se refresca `mv_precio`.
- **Tokens:** `~/.config/compras-hq/tokens.tsv` y `links.txt` en la mini (600). Nunca en git: el repo es público por GitHub Pages.
- **Pantalla:** `compras.html` (mismo estilo que `index.html`). Probada con Playwright de `~/Proyectos/provia` en iPhone 13 claro y oscuro: sin errores ni scroll horizontal; aislamiento verificado (Kaeru no ve Freakie aunque lo pida).
- **Repo público:** los lotes de semillas con NIT de proveedores viven en `~/Proyectos/_auditorias/compras_hq_semillas/`, no acá. El commit 8f80cc4 alcanzó a subir `005_semilla_lote1.sql` (NITs sin nombres, 3 de personas naturales); se borró en el siguiente commit pero sigue en el historial.
- **Ojo MCP:** `apply_migration` y DML suelto se cuelgan en sesiones remotas; todo se aplicó con `execute_sql` y los UPDATE dentro de funciones.

---

## 2026-08-18 — Se crea esta memoria (y por qué faltaba)

`hq-panel` era el único de los 8 repos **sin `CLAUDE.md` ni `memoria.md`**. Consecuencia real: una sesión de Claude que arrancó acá no tenía ritual ni contexto y tuvo que reconstruir todo desde `git log` y transcripts viejos.

Se creó junto con el rediseño del remote-control de la mini (ver `~/.claude/CLAUDE.md` y `~/Proyectos/server/bin/rc_supervisor.sh`). — *Jose + Claude, 18-ago-2026*

---

## Historial previo (reconstruido desde `git log`)

- **2026-08-09** `0a97fbf` — Banner honesto cuando el backend bloquea re-decidir (`ya_decidida`). *Criterio: el panel no simula éxito; si el backend dice que no, se muestra.*
- **2026-08-09** `5b1c66f` — Enlace venture↔idea por `idea_id`, con fallback a nombre.
- **2026-08-09** `6e43311` — Cada venture con desplegable: análisis del lab + plan a mercado + historial de eventos.
- **2026-08-09** `9e15349` — **Parseo robusto de timestamps** (Postgres nativo + ISO) para evitar `Invalid Date` y desfase horario **en Safari/iPhone**. *Es el bug recurrente de este panel: Safari es estricto con formatos de fecha que Chrome perdona.*
- **2026-08-08** `5b4a1d8` — Lab de ideas: un solo listado ordenado por % de éxito, todas expandibles y gestionables.
- **2026-08-01** `ad961ef` — Nace el panel: estático, datos vía edge function `factory-dashboard` con token.

---

## Cosas que conviene no volver a aprender por las malas

- **Safari/iOS es el navegador de verdad acá**, no Chrome. Fechas y layout se validan ahí.
- El panel **no** habla con Supabase directo: todo pasa por `factory-dashboard`. Si falta un dato, el fix suele ir en la edge function (repo `venture-factory`), no en el HTML.
- No hay build: lo que ves en `index.html` es lo que se sirve.
