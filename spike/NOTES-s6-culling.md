# S6: Frustum culling + draw path (проверено по исходникам flame_3d 0.3.0, pub-cache)

Вердикт: frustum culling ЕСТЬ и он иерархический. Критики (в т.ч. Helmholtz/Dewey) в этом пункте ошиблись.

## Факты

- `Object3D.renderTree` (lib/src/components/object_3d.dart): AABB-тест против frustum камеры.
  - `CullResult.outside` -> ранний return, поддерево пропускается целиком.
  - `CullResult.inside` -> дети пропускают собственные frustum-тесты (флаг `_ancestorFullyInside`).
  - Частичное пересечение -> дети тестируются сами; сам объект дополнительно проверяется `isVisible()`.
- `MeshComponent.isVisible` = `camera.frustum.intersectsWithAabb3(aabb)`, AABB берётся из `Surface` (считается в конструкторе).
- Draw path: `submitDraw` кладёт в пул с квадратом дистанции (без аллокаций, пул переиспользуется) ->
  `flush()` сортирует ВСЕ видимые insertion sort back-to-front (O(V^2) worst case!) -> `draw()` на каждом.
- На каждый Surface: `clearBindings` + `bindPipeline` + material.apply (5 uniform-групп + текстура) + bindGeometry + draw.
  Никакого батчинга/state-кэша. SpatialMaterial: PBR с циклом по 8 источникам света.

## Следствия для minedart

1. Component-per-chunk жизнеспособнее, чем предполагали критики: невидимые чанки почти бесплатны (1 AABB-тест).
2. Но видимые платят полный state-setup за draw; insertion sort O(V^2) на ~500+ видимых может стать заметен (проверит S3).
3. Back-to-front сортировка всего подряд — для opaque-геометрии это анти-оптимизация (ломает early-z), выключить нельзя.
4. AABB у Surface пересчитывается в конструкторе перебором всех вершин — ещё одна стоимость ремеша (замерит S1).
