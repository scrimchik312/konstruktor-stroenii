/// Снеговые и ветровые районы РФ по СП 20.13330.2016, прил. Е.
///
/// Индекс — это номер района (для снега: 1…8; для ветра: Ia, I…VII).
/// Хранится также «римское» обозначение и расчётное значение.
library;

class SnowRegion {
  const SnowRegion._({
    required this.id,
    required this.title,
    required this.sgKPa,
  });

  /// Номер района (1…8).
  final int id;

  /// Метка для UI («I район», «II район» …).
  final String title;

  /// Нормативное значение снеговой нагрузки на грунт Sg, кПа.
  final double sgKPa;

  /// Короткий алиас для удобства использования в UI.
  double get sg => sgKPa;

  static const _table = <SnowRegion>[
    SnowRegion._(id: 1, title: 'I снеговой район', sgKPa: 0.8),
    SnowRegion._(id: 2, title: 'II снеговой район', sgKPa: 1.2),
    SnowRegion._(id: 3, title: 'III снеговой район', sgKPa: 1.5),
    SnowRegion._(id: 4, title: 'IV снеговой район', sgKPa: 2.0),
    SnowRegion._(id: 5, title: 'V снеговой район', sgKPa: 2.5),
    SnowRegion._(id: 6, title: 'VI снеговой район', sgKPa: 3.0),
    SnowRegion._(id: 7, title: 'VII снеговой район', sgKPa: 3.5),
    SnowRegion._(id: 8, title: 'VIII снеговой район', sgKPa: 4.0),
  ];

  /// Получить запись по номеру района (защитно: зажимает в допустимый диапазон).
  static SnowRegion byId(int id) {
    final clamped = id.clamp(1, _table.length);
    return _table[clamped - 1];
  }

  /// Все районы (для селекторов).
  static List<SnowRegion> all() => List.unmodifiable(_table);
}

class WindRegion {
  const WindRegion._({
    required this.id,
    required this.title,
    required this.w0KPa,
  });

  /// Внутренний идентификатор (0 = Iа, 1 = I, …, 7 = VII).
  final int id;

  /// Метка для UI.
  final String title;

  /// Нормативное значение ветрового давления w0, кПа.
  final double w0KPa;

  /// Короткий алиас для удобства использования в UI.
  double get w0 => w0KPa;

  static const _table = <WindRegion>[
    WindRegion._(id: 0, title: 'Iа ветровой район', w0KPa: 0.17),
    WindRegion._(id: 1, title: 'I ветровой район', w0KPa: 0.23),
    WindRegion._(id: 2, title: 'II ветровой район', w0KPa: 0.30),
    WindRegion._(id: 3, title: 'III ветровой район', w0KPa: 0.38),
    WindRegion._(id: 4, title: 'IV ветровой район', w0KPa: 0.48),
    WindRegion._(id: 5, title: 'V ветровой район', w0KPa: 0.60),
    WindRegion._(id: 6, title: 'VI ветровой район', w0KPa: 0.73),
    WindRegion._(id: 7, title: 'VII ветровой район', w0KPa: 0.85),
  ];

  static WindRegion byId(int id) {
    final clamped = id.clamp(0, _table.length - 1);
    return _table[clamped];
  }

  static List<WindRegion> all() => List.unmodifiable(_table);
}
