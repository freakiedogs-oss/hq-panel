-- Compras HQ — clasificación de proveedores, clave de proveedor y vista de precios

-- Proveedores que no son de insumos (alquiler, comisiones, bancos, equipo): no se comparan
alter table compras_hq.proveedor add column if not exists tipo text
  check (tipo in ('insumos','servicio','arrendamiento','financiero','activo_fijo','intercompania'));
alter table compras_hq.proveedor add column if not exists excluir_comparacion boolean not null default false;

-- Clave de proveedor: NIT, o el nombre cuando la línea no trae NIT (Excel de Scanzano)
alter table compras_hq.linea add column if not exists proveedor_key text
  generated always as (coalesce(proveedor_nit, 'n:' || lower(btrim(coalesce(proveedor_nombre, ''))))) stored;
create index if not exists linea_key_desc_idx on compras_hq.linea (proveedor_key, descripcion_norm);

-- alias.proveedor_nit guarda esa misma clave (NIT o 'n:nombre')
comment on column compras_hq.alias.proveedor_nit is 'Clave de proveedor: NIT en dígitos, o n:<nombre> si la línea no trae NIT';

-- Proponer/actualizar un alias y crear el item si no existe --------------------------
create or replace function compras_hq.proponer(
  p_key text, p_desc text, p_item text, p_categoria text, p_dimension text,
  p_base numeric, p_notas text default null, p_origen text default 'ia')
returns bigint
language plpgsql
security definer
set search_path to 'compras_hq', 'public', 'pg_temp'
as $$
declare v_item bigint;
begin
  insert into compras_hq.item (nombre, categoria, dimension)
  values (p_item, p_categoria, p_dimension)
  on conflict ((lower(nombre))) do nothing;
  select id into v_item from compras_hq.item where lower(nombre) = lower(p_item);

  insert into compras_hq.alias (proveedor_nit, descripcion_norm, item_id, base_por_unidad, origen, notas)
  values (p_key, public.norm_desc(p_desc), v_item, p_base, p_origen, p_notas)
  on conflict (proveedor_nit, descripcion_norm) do update
     set item_id = excluded.item_id, base_por_unidad = excluded.base_por_unidad,
         origen = excluded.origen, notas = excluded.notas, updated_at = now()
   where compras_hq.alias.estado <> 'confirmado';   -- lo confirmado por una persona no se pisa
  return v_item;
end;
$$;

-- Precio por unidad base, por línea ------------------------------------------------
create or replace view compras_hq.v_precio as
select l.id linea_id, l.empresa, l.fecha, l.tipo_dte, l.proveedor_key, l.proveedor_nit,
       coalesce(p.nombre, l.proveedor_nombre) proveedor, l.descripcion, l.cantidad, l.unidad,
       l.monto_sin_iva, a.item_id, i.nombre item, i.categoria, i.unidad_base,
       a.base_por_unidad, a.estado alias_estado,
       l.cantidad * a.base_por_unidad cantidad_base,
       l.monto_sin_iva / nullif(l.cantidad * a.base_por_unidad, 0) precio_base
from compras_hq.linea l
join compras_hq.alias a on a.proveedor_nit = l.proveedor_key and a.descripcion_norm = l.descripcion_norm
join compras_hq.item i on i.id = a.item_id
left join compras_hq.proveedor p on p.nit = l.proveedor_nit
where not l.anulada
  and coalesce(l.tipo_dte, '') not in ('05', '06')
  and a.estado <> 'rechazado'
  and l.cantidad > 0 and l.monto_sin_iva > 0;
