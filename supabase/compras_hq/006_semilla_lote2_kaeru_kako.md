# Lote 2 (Kaeru y Kako) — aplicado el 2-nov-2026 por execute_sql

Mismo formato que 005: `compras_hq.proponer_prefijo(clave, prefijo, item, categoría, dimensión, base, nota)`.
El SQL exacto quedó en el transcript de la sesión. Lo que hizo:

- 12 proveedores marcados como activo_fijo o servicio (equipo de cocina, remodelación, redes, software).
- 68 alias de insumos: pollo Pricesmart (muslo y pechuga por kg), miso, panceta Calleja y Axel Ramces,
  cervezas, Ramune, gyoza, takoyaki, katsuobushi 100 g, kombu, soya Kikkoman 5 gal, ajonjolí, mirin,
  harina de arroz, taro, Kewpie, verduras de Emanuel (kale, cebolla, jengibre, zanahoria, pimienta, piña),
  huevo Nutriaves (cartón 30), tahini, fresa, bolsa kraft, salmón, lácteos Pricesmart (sin tamaño),
  crema Versatie, gas Zeta Gas, bandeja de pastel, harinas El Roble (saco 50 lb), azúcar, azúcar glas,
  whip topping, hielo, matcha, aguacate, tapioca.
- Los que no traen tamaño quedaron con base null y nota "falta el tamaño".
