-- Compras HQ — vistas de comparación (base del gateway y del panel)
-- Solo alias con tamaño conocido y proveedores de insumos. Precios sin IVA por unidad base.

-- 0) Líneas atípicas: precio más de 5x arriba o abajo de la mediana del item (12 meses).
--    Casi siempre es una cantidad mal capturada. Se excluyen de todo y quedan para revisión.
create or replace view compras_hq.v_precio_atipico as
with med as (
  select item_id, percentile_cont(0.5) within group (order by precio_base) mediana
  from compras_hq.v_precio where base_por_unidad is not null and fecha >= current_date - 365
  group by item_id
)
select v.*, m.mediana, round((v.precio_base / nullif(m.mediana, 0))::numeric, 2) veces_mediana
from compras_hq.v_precio v join med m using (item_id)
where v.base_por_unidad is not null and v.fecha >= current_date - 365
  and (v.precio_base > 5 * m.mediana or v.precio_base < 0.2 * m.mediana);

-- 1) Por empresa × item × proveedor (vista de cada empresa) --------------------------
create or replace view compras_hq.v_item_proveedor as
with p as (
  select v.* from compras_hq.v_precio v
  left join compras_hq.proveedor pr on pr.nit = v.proveedor_key
  where v.base_por_unidad is not null and v.fecha >= current_date - 365
    and not coalesce(pr.excluir_comparacion, false)
    and not exists (select 1 from compras_hq.v_precio_atipico x where x.linea_id = v.linea_id)
)
select empresa, item_id, item, categoria, unidad_base, proveedor_key, max(proveedor) proveedor,
       count(*) compras_12m,
       round(sum(monto_sin_iva), 2) gasto_12m,
       round(sum(cantidad_base), 3) cantidad_12m,
       round(sum(monto_sin_iva) filter (where fecha >= current_date - 90), 2) gasto_90d,
       round(sum(cantidad_base) filter (where fecha >= current_date - 90), 3) cantidad_90d,
       round((percentile_cont(0.5) within group (order by precio_base))::numeric, 4) precio_mediano_12m,
       round((percentile_cont(0.5) within group (order by precio_base) filter (where fecha >= current_date - 90))::numeric, 4) precio_mediano_90d,
       round(((array_agg(precio_base order by fecha desc, linea_id desc))[1])::numeric, 4) ultimo_precio,
       max(fecha) ultima_compra
from p
group by empresa, item_id, item, categoria, unidad_base, proveedor_key;

-- 2) Comparativo HQ: cada proveedor contra el mejor precio del item (todas las empresas) --
create or replace view compras_hq.v_comparativo as
with base as (
  select item_id, item, categoria, unidad_base, proveedor_key, max(proveedor) proveedor,
         string_agg(distinct empresa, ',' order by empresa) empresas,
         sum(compras_12m) compras_12m, sum(gasto_12m) gasto_12m,
         -- precio de referencia: mediana 90 días si hay, si no la de 12 meses
         min(coalesce(precio_mediano_90d, precio_mediano_12m)) precio_ref,
         max(ultima_compra) ultima_compra
  from compras_hq.v_item_proveedor
  group by item_id, item, categoria, unidad_base, proveedor_key
)
select b.*,
       min(precio_ref) over (partition by item_id) mejor_precio,
       first_value(proveedor) over (partition by item_id order by precio_ref) mejor_proveedor,
       round(100 * (precio_ref / nullif(min(precio_ref) over (partition by item_id), 0) - 1), 1) dif_pct,
       count(*) over (partition by item_id) proveedores_item
from base b;

-- 3) Ahorro potencial por empresa e item (últimos 90 días al mejor precio observado) ----
create or replace view compras_hq.v_ahorro as
with mejor as (select distinct item_id, mejor_precio, mejor_proveedor, proveedores_item from compras_hq.v_comparativo)
select ip.empresa, ip.item_id, ip.item, ip.categoria, ip.unidad_base,
       sum(ip.gasto_90d) gasto_90d, sum(ip.cantidad_90d) cantidad_90d,
       round(sum(ip.gasto_90d) / nullif(sum(ip.cantidad_90d), 0), 4) precio_pagado_90d,
       m.mejor_precio, m.mejor_proveedor, m.proveedores_item,
       round(sum(ip.gasto_90d) - sum(ip.cantidad_90d) * m.mejor_precio, 2) ahorro_90d,
       round(100 * (sum(ip.gasto_90d) / nullif(sum(ip.cantidad_90d), 0) / nullif(m.mejor_precio, 0) - 1), 1) sobreprecio_pct
from compras_hq.v_item_proveedor ip
join mejor m using (item_id)
where ip.gasto_90d > 0
group by ip.empresa, ip.item_id, ip.item, ip.categoria, ip.unidad_base, m.mejor_precio, m.mejor_proveedor, m.proveedores_item;

-- 4) Alertas de alza: última compra vs mediana de 90 días del mismo proveedor ----------
create or replace view compras_hq.v_alerta_precio as
select empresa, item_id, item, unidad_base, proveedor_key, proveedor, ultima_compra, ultimo_precio,
       precio_mediano_90d,
       round(100 * (ultimo_precio / nullif(precio_mediano_90d, 0) - 1), 1) alza_pct
from compras_hq.v_item_proveedor
where precio_mediano_90d is not null and ultima_compra >= current_date - 30
  and ultimo_precio > precio_mediano_90d * 1.08;
