-- Compras HQ — precios precalculados (reemplaza la lectura en vivo de 007)
-- Motivo: con filtro por empresa, el anti-join contra v_precio_atipico se recalculaba por
-- fila y el gateway se cortaba por timeout. Ahora todo lee mv_precio (≈30 ms).
-- Se refresca al final de compras-hq-sync y al confirmar un alias.

create materialized view if not exists compras_hq.mv_precio as
with med as (
  select item_id, percentile_cont(0.5) within group (order by precio_base) mediana
  from compras_hq.v_precio where base_por_unidad is not null and fecha >= current_date - 365
  group by item_id
)
select v.*, m.mediana,
       coalesce(v.base_por_unidad is not null and (v.precio_base > 5 * m.mediana or v.precio_base < 0.2 * m.mediana), false) atipico
from compras_hq.v_precio v left join med m using (item_id)
where v.fecha >= current_date - 400;
create unique index if not exists mv_precio_linea_key on compras_hq.mv_precio (linea_id);
create index if not exists mv_precio_emp_item_idx on compras_hq.mv_precio (empresa, item_id);

create or replace function compras_hq.refrescar()
returns void language plpgsql security definer set search_path to 'compras_hq', 'pg_temp' as $$
begin
  refresh materialized view concurrently compras_hq.mv_precio;
end;
$$;

create or replace function public.compras_hq_refrescar()
returns void language plpgsql security definer set search_path to 'compras_hq', 'pg_temp' as $$
begin
  if not compras_hq._es_servicio() then raise exception 'solo service_role'; end if;
  perform compras_hq.refrescar();
end;
$$;

-- Versión vigente de v_item_proveedor (la de 007 quedó reemplazada)
create or replace view compras_hq.v_item_proveedor as
with p as (
  select v.* from compras_hq.mv_precio v
  left join compras_hq.proveedor pr on pr.nit = v.proveedor_key
  where v.base_por_unidad is not null and v.fecha >= current_date - 365
    and not coalesce(pr.excluir_comparacion, false)
    and not v.atipico
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

-- Otras piezas aplicadas el 2-nov (por execute_sql) que no tienen archivo propio:
--   compras_hq.clasificar_proveedores(jsonb) — marca proveedores de servicio/alquiler/etc.
--   compras_hq.proponer_prefijo(...)          — alias por prefijo de descripción
--   compras_hq.sync_log + public.compras_hq_sync_reciente / compras_hq_log_sync / compras_hq_hay_remotas
