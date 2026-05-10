/// Один весовой компонент постоянной нагрузки (слой кровли, перекрытия,
/// стена по материалу).
///
/// Поля обдуманно простые: вычислитель нагрузки суммирует `loadKnPerM2`
/// и показывает источник значения через `origin`.
class WeightComponent {
  const WeightComponent({
    required this.id,
    required this.title,
    required this.loadKnPerM2,
    required this.origin,
  });

  /// Стабильный ключ компонента (например, `walls_brick`).
  final String id;

  /// Название на русском для UI/PDF.
  final String title;

  /// Нагрузка компонента, кН/м².
  final double loadKnPerM2;

  /// Откуда взято значение — обычно ссылка на СП / справочник.
  final String origin;
}
