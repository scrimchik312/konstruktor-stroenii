/// Централизованная библиотека «материал → текстура» для трёхмерной
/// аксонометрии, фасадов и листов чертежей.
///
/// Идея: каждый материал стен/кровли описан одним классом
/// [MaterialTexture] с цветовой схемой и кодом процедурного паттерна
/// (кирпичная кладка, древесные волокна, газобетонные блоки, металлические
/// волны и т. п.). При выборе пользователем материала рендеринг автоматически
/// подхватывает цвет и тип паттерна — изображение собирается процедурно
/// прямо на холсте Flutter / PDF, без необходимости держать растровые
/// текстуры в assets.
///
/// **Правило для новых материалов:** при добавлении любого нового кода
/// в [WallMaterial] / [RoofMaterial] обязательно добавить запись в
/// [wallTextures] / [roofTextures]. Иначе [MaterialTextureLibrary.wall] /
/// [MaterialTextureLibrary.roof] упадут с осмысленным `assert`-ом.
library;

import 'package:flutter/painting.dart';

import 'wall_materials.dart';

/// Тип процедурного паттерна.
enum MaterialPattern {
  /// Кирпичная кладка (горизонтальные ряды + вертикальные швы).
  brick,

  /// Газобетонные / керамзитные блоки — крупная сетка.
  block,

  /// Деревянный сруб (горизонтальные «брёвна»).
  timberLog,

  /// Деревянный брус (тонкие горизонтальные линии).
  timberBeam,

  /// Каркас + плита (имитация ОСП панели).
  frame,

  /// Металлочерепица — волнистый рельеф с поперечными линиями.
  metalTile,

  /// Профлист — параллельные вертикальные рёбра.
  profileSheet,

  /// Битумная (мягкая) — мелкая случайная зернистость.
  bitumen,

  /// Керамическая черепица — крупная плитка с наклонной разбивкой.
  ceramicTile,

  /// Шифер — широкие горизонтальные волны.
  slate,

  /// Фальцевая кровля — длинные вертикальные швы.
  seam,

  /// Без паттерна — только заливка (для штукатурки и т. п.).
  flat,
}

/// Данные одной текстуры.
class MaterialTexture {
  final String key;
  final String title;
  final Color baseColor;
  final Color mortarColor; // цвет шва / акцентной линии
  final MaterialPattern pattern;

  /// Размер «плитки» паттерна в мировых метрах. Например, 0.25 м —
  /// это длина одного кирпича.
  final double tileMeters;

  /// Roughness — параметр шероховатости поверхности (PBR-fake).
  /// 0.0 = гладкое зеркало (полированный металл), 1.0 = полностью
  /// матовое (грубый кирпич). Используется в рендерере для
  /// масштабирования силы specular-блика и cool-голубизны на стенах.
  final double roughness;

  const MaterialTexture({
    required this.key,
    required this.title,
    required this.baseColor,
    required this.mortarColor,
    required this.pattern,
    required this.tileMeters,
    this.roughness = 0.85,
  });
}

/// Материалы стен.
const Map<WallMaterial, MaterialTexture> wallTextures = {
  WallMaterial.brick: MaterialTexture(
    key: 'wall_brick',
    title: 'Кирпич керамический М150',
    baseColor: Color(0xFFB35538), // тёмно-красный кирпич
    mortarColor: Color(0xFFE8E2D2), // светлый шов
    pattern: MaterialPattern.brick,
    tileMeters: 0.25,
    roughness: 0.92,
  ),
  WallMaterial.aerated: MaterialTexture(
    key: 'wall_aerated',
    title: 'Газобетон D500',
    baseColor: Color(0xFFE8E5DD),
    mortarColor: Color(0xFFB8B5AD),
    pattern: MaterialPattern.block,
    tileMeters: 0.6,
    roughness: 0.95,
  ),
  WallMaterial.expandedClay: MaterialTexture(
    key: 'wall_expanded_clay',
    title: 'Керамзитоблок',
    baseColor: Color(0xFFB1A595),
    mortarColor: Color(0xFF7C7466),
    pattern: MaterialPattern.block,
    tileMeters: 0.39,
    roughness: 0.94,
  ),
  WallMaterial.timber: MaterialTexture(
    key: 'wall_timber',
    title: 'Брус сосна',
    baseColor: Color(0xFFC59663),
    mortarColor: Color(0xFF8C5A33),
    pattern: MaterialPattern.timberBeam,
    tileMeters: 0.20,
    roughness: 0.78,
  ),
  WallMaterial.frame: MaterialTexture(
    key: 'wall_frame',
    title: 'Каркас + ОСП',
    baseColor: Color(0xFFC9A67A),
    mortarColor: Color(0xFF7B5934),
    pattern: MaterialPattern.frame,
    tileMeters: 1.25,
    roughness: 0.70,
  ),
};

/// ID кровельного материала из [_RoofingOption.id] в `roof_page.dart`.
/// Используются строковые ключи, чтобы не плодить ещё один enum.
const Map<String, MaterialTexture> roofTextures = {
  'metal_tile': MaterialTexture(
    key: 'roof_metal_tile',
    title: 'Металлочерепица',
    baseColor: Color(0xFF7C2929),
    mortarColor: Color(0xFF3A0F0F),
    pattern: MaterialPattern.metalTile,
    tileMeters: 0.40,
    roughness: 0.25,
  ),
  'soft': MaterialTexture(
    key: 'roof_soft',
    title: 'Мягкая (битумная)',
    baseColor: Color(0xFF555048),
    mortarColor: Color(0xFF2E2A22),
    pattern: MaterialPattern.bitumen,
    tileMeters: 0.10,
    roughness: 0.88,
  ),
  'ceramic': MaterialTexture(
    key: 'roof_ceramic',
    title: 'Керамическая черепица',
    baseColor: Color(0xFFB16A2A),
    mortarColor: Color(0xFF6E3F12),
    pattern: MaterialPattern.ceramicTile,
    tileMeters: 0.33,
    roughness: 0.65,
  ),
  'slate': MaterialTexture(
    key: 'roof_slate',
    title: 'Шифер',
    baseColor: Color(0xFFB6B3AD),
    mortarColor: Color(0xFF6B6862),
    pattern: MaterialPattern.slate,
    tileMeters: 0.50,
    roughness: 0.72,
  ),
  'seam': MaterialTexture(
    key: 'roof_seam',
    title: 'Фальцевая',
    baseColor: Color(0xFF4D5A66),
    mortarColor: Color(0xFF1F2730),
    pattern: MaterialPattern.seam,
    tileMeters: 0.50,
    roughness: 0.18,
  ),
  // Дефолт, если идентификатор не распознан.
  'default': MaterialTexture(
    key: 'roof_default',
    title: 'Кровля (по умолчанию)',
    baseColor: Color(0xFF7C5A4A),
    mortarColor: Color(0xFF3F2D24),
    pattern: MaterialPattern.metalTile,
    tileMeters: 0.40,
    roughness: 0.30,
  ),
};

/// Удобный класс-фасад над двумя картами выше.
class MaterialTextureLibrary {
  MaterialTextureLibrary._();

  /// Возвращает текстуру для стенового материала [m] (или дефолт, если
  /// `m == null`).
  static MaterialTexture wall([WallMaterial? m]) {
    if (m == null) return wallTextures[WallMaterial.aerated]!;
    final t = wallTextures[m];
    assert(t != null,
        'Не задана текстура для WallMaterial.${m.name}. '
        'Добавь её в lib/data/material_textures.dart → wallTextures.');
    return t!;
  }

  /// Возвращает текстуру для кровельного материала по строковому id
  /// (как в `_RoofingOption`, см. `roof_page.dart`).
  static MaterialTexture roof([String? id]) {
    if (id == null) return roofTextures['default']!;
    return roofTextures[id] ?? roofTextures['default']!;
  }
}
