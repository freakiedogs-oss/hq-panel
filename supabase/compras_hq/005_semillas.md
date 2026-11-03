# Semillas de items y alias (lotes 1 a 3) — 2-nov-2026

El SQL exacto de los lotes **no va en este repo**: es público (GitHub Pages) y los lotes usan
NIT de proveedores, algunos de personas naturales. Las copias viven en la mini:

    ~/Proyectos/_auditorias/compras_hq_semillas/

Formato de cada lote:

    select compras_hq.proponer_prefijo(clave_proveedor, prefijo_descripcion, item, categoria,
                                       dimension, base_por_unidad, nota)

- `dimension`: masa (kg), volumen (l) o conteo (u).
- `base_por_unidad`: cuántas unidades base trae 1 unidad facturada; null = falta el tamaño.
- Todo entra como `propuesto`. Se confirma o corrige desde la pantalla Revisar del panel.

Resultado al 2-nov-2026: 86% del gasto en insumos de 12 meses mapeado a un item
(Freakie 90, Scanzano 88, Eatalia 70, Kaeru 68, Kako 50) y 76% con tamaño conocido.
