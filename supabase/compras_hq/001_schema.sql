-- Compras HQ — esquema base (proyecto btboxlwfqcbrdfrlnwln)
-- 2-nov-2026. Plan: ~/Proyectos/_auditorias/COMPRAS-HQ-plan-2026-10-29.md
--
-- Un solo gateway, vistas independientes por empresa. Este schema junta las líneas de
-- compra de las 5 empresas en solo lectura respecto de los ERPs: nunca escribe en
-- public/kaeru/kako ni en Eatalia. No está expuesto a PostgREST; lo leen las edge
-- functions con service_role por medio de RPCs public.compras_hq_* que validan el rol.
--
-- Reglas del MCP en sesiones remotas: sin DROP/DELETE/UPDATE sueltos (ver memoria).

create schema if not exists compras_hq;

-- Empresas -------------------------------------------------------------------
create table if not exists compras_hq.empresa (
  id        text primary key,            -- freakie | kaeru | kako | eatalia | scanzano
  nombre    text not null,
  proyecto  text not null,               -- ref de Supabase donde vive su ERP
  activo    boolean not null default true
);

-- Unidades: códigos CAT-014 de Hacienda + texto libre de los ERPs -----------------
-- dimension: masa (base kg), volumen (base l), conteo (base u), otra (sin conversión)
create table if not exists compras_hq.unidad (
  codigo     text primary key,           -- '36', 'lb', 'libra', ...
  nombre     text not null,
  dimension  text not null check (dimension in ('masa','volumen','conteo','otra')),
  a_base     numeric                     -- cuántas unidades base vale 1 de esta unidad
);

-- Proveedores, uno por NIT ------------------------------------------------------
create table if not exists compras_hq.proveedor (
  nit         text primary key,          -- solo dígitos
  nombre      text not null,
  nombres     text[] not null default '{}',
  notas       text,
  created_at  timestamptz not null default now()
);

-- Items maestros: el mismo insumo para todas las empresas -----------------------
create table if not exists compras_hq.item (
  id          bigserial primary key,
  nombre      text not null,
  categoria   text,
  dimension   text not null check (dimension in ('masa','volumen','conteo')),
  unidad_base text generated always as (case dimension when 'masa' then 'kg' when 'volumen' then 'l' else 'u' end) stored,
  especificacion text,                   -- calidad / marca / presentación de referencia
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists item_nombre_key on compras_hq.item (lower(nombre));

-- Alias: cómo una descripción de factura (por NIT) se vuelve un item -------------
-- base_por_unidad = cuántas unidades base del item trae 1 unidad facturada.
--   Ej: "PAPA SAZONADA 30LB" facturada por unidad → item Papa sazonada (masa) → 13.608 kg
create table if not exists compras_hq.alias (
  id               bigserial primary key,
  proveedor_nit    text not null,
  descripcion_norm text not null,
  item_id          bigint not null references compras_hq.item(id),
  base_por_unidad  numeric check (base_por_unidad is null or base_por_unidad > 0),
  origen           text not null default 'ia' check (origen in ('unidad','regex','ia','tenant','manual')),
  estado           text not null default 'propuesto' check (estado in ('propuesto','confirmado','rechazado')),
  notas            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (proveedor_nit, descripcion_norm)
);
create index if not exists alias_item_idx on compras_hq.alias (item_id);

-- Líneas de compra de las 5 empresas (hecho central) -----------------------------
create table if not exists compras_hq.linea (
  id                bigserial primary key,
  empresa           text not null references compras_hq.empresa(id),
  fuente            text not null,       -- dte | bees | scanzano | eatalia
  fuente_id         text not null,       -- id de la línea en su ERP
  documento_id      text,                -- id de la factura en su ERP
  fecha             date not null,
  tipo_dte          text,                -- 01 FCF (precio con IVA), 03 CCF, 05 NC, 14 FSE
  proveedor_nit     text,
  proveedor_nombre  text,
  descripcion       text not null,
  descripcion_norm  text not null,
  cantidad          numeric,
  unidad            text,                -- código CAT-014 o texto del ERP
  precio_unitario   numeric,
  monto             numeric,             -- monto de la línea tal como viene
  monto_sin_iva     numeric,             -- normalizado: FCF gravada / 1.13
  producto_ref      text,                -- producto del ERP, si está mapeado allá
  producto_nombre   text,
  anulada           boolean not null default false,
  ingresado_at      timestamptz not null default now(),
  unique (empresa, fuente, fuente_id)
);
create index if not exists linea_fecha_idx on compras_hq.linea (fecha);
create index if not exists linea_alias_idx on compras_hq.linea (proveedor_nit, descripcion_norm);
create index if not exists linea_empresa_fecha_idx on compras_hq.linea (empresa, fecha);

alter table compras_hq.empresa   enable row level security;
alter table compras_hq.unidad    enable row level security;
alter table compras_hq.proveedor enable row level security;
alter table compras_hq.item      enable row level security;
alter table compras_hq.alias     enable row level security;
alter table compras_hq.linea     enable row level security;

-- Semillas ---------------------------------------------------------------------
insert into compras_hq.empresa (id, nombre, proyecto) values
  ('freakie',  'Freakie Dogs',  'btboxlwfqcbrdfrlnwln'),
  ('kaeru',    'Kaeru Chan',    'btboxlwfqcbrdfrlnwln'),
  ('kako',     'Kako Cakes',    'btboxlwfqcbrdfrlnwln'),
  ('eatalia',  'Eatalia',       'wzkqaxgsqgbokkmxarbd'),
  ('scanzano', 'Scanzano',      'wzkqaxgsqgbokkmxarbd')
on conflict (id) do nothing;

insert into compras_hq.unidad (codigo, nombre, dimension, a_base) values
  -- CAT-014 Hacienda
  ('22','Galón','volumen',3.78541), ('23','Litro','volumen',1), ('26','Mililitro','volumen',0.001),
  ('30','Tonelada','masa',1000), ('32','Quintal','masa',45.359237), ('33','Arroba','masa',11.33980925),
  ('34','Kilogramo','masa',1), ('36','Libra','masa',0.45359237), ('38','Onza','masa',0.028349523),
  ('39','Gramo','masa',0.001), ('40','Miligramo','masa',0.000001),
  ('55','Millar','conteo',1000), ('57','Ciento','conteo',100), ('58','Docena','conteo',12),
  ('59','Unidad','conteo',1), ('99','Otra','otra',null),
  -- texto libre de los ERPs
  ('lb','Libra','masa',0.45359237), ('libra','Libra','masa',0.45359237), ('libras','Libra','masa',0.45359237),
  ('kg','Kilogramo','masa',1), ('kilogramo','Kilogramo','masa',1), ('25 kg','Saco 25 kg','masa',25),
  ('quintal','Quintal','masa',45.359237), ('g','Gramo','masa',0.001), ('gramos','Gramo','masa',0.001),
  ('oz','Onza','masa',0.028349523), ('ml','Mililitro','volumen',0.001), ('l','Litro','volumen',1),
  ('lt','Litro','volumen',1), ('litro','Litro','volumen',1), ('galon','Galón','volumen',3.78541),
  ('galón','Galón','volumen',3.78541), ('galones','Galón','volumen',3.78541),
  ('unidad','Unidad','conteo',1), ('unid','Unidad','conteo',1), ('un','Unidad','conteo',1),
  ('docena','Docena','conteo',12), ('ciento','Ciento','conteo',100), ('millar','Millar','conteo',1000),
  ('otro','Otra','otra',null)
on conflict (codigo) do nothing;
