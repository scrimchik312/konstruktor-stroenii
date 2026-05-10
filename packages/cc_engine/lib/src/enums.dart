/// Форма скатов кровли для подбора коэффициента снеговой нагрузки.
enum RoofShape {
  /// Плоская или пологая (до ~30°).
  flatOrLowSlope,

  /// Двухскатная / вальмовая стандартной крутизны (30–60°).
  gable,

  /// Крутая кровля (>60°) — снег практически не держится.
  steep,
}

/// Тип местности для ветрового коэффициента k(ze) по СП 20.13330.2016, п. 11.1.6.
enum TerrainType {
  /// A — открытые территории, берега водоёмов.
  a,

  /// B — пригороды, лесопарковые зоны, мелкие строения.
  b,

  /// C — плотная городская застройка.
  c,
}

/// Тип грунта верхнего слоя для первичного подбора сечения фундамента.
///
/// Расчётные сопротивления `R0` приняты по СП 22.13330.2016, прил. Д
/// (табличные значения для первичной оценки).
enum FoundationSoilType {
  sandGravel(title: 'Крупнообломочный / гравийный', r0KPa: 400),
  sandCoarse(title: 'Песок крупный', r0KPa: 350),
  sandMedium(title: 'Песок средней крупности', r0KPa: 250),
  sandFine(title: 'Песок мелкий', r0KPa: 200),
  sandyLoamHard(title: 'Супесь твёрдая', r0KPa: 250),
  loamStiff(title: 'Суглинок тугопластичный', r0KPa: 200),
  loamSoft(title: 'Суглинок мягкопластичный', r0KPa: 150),
  clayHard(title: 'Глина твёрдая', r0KPa: 300),
  clayStiff(title: 'Глина полутвёрдая', r0KPa: 250),
  claySoft(title: 'Глина мягкопластичная', r0KPa: 150);

  const FoundationSoilType({required this.title, required this.r0KPa});

  /// Название на русском для UI и PDF.
  final String title;

  /// Расчётное сопротивление R0 грунта основания, кПа.
  final int r0KPa;
}

/// Класс бетона по прочности (B-класс по СП 63.13330.2018).
enum ConcreteClass {
  b15(title: 'B15 (М200)'),
  b20(title: 'B20 (М250)'),
  b25(title: 'B25 (М350)'),
  b30(title: 'B30 (М400)');

  const ConcreteClass({required this.title});
  final String title;
}

/// Класс арматуры (СП 63.13330.2018, табл. 6.14).
enum RebarClass {
  a240(title: 'A240 (гладкая, AI)'),
  a400(title: 'A400 (периодического профиля, AIII)'),
  a500(title: 'A500 (высокопрочная)');

  const RebarClass({required this.title});
  final String title;
}
