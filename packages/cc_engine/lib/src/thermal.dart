import 'calc_step.dart';

/// Климатические параметры для теплотехники по СП 50.13330.2012 с
/// учётом таблиц СП 131.13330.2020 «Строительная климатология».
class ClimateZone {
  const ClimateZone({
    required this.city,
    required this.tExtJan,
    required this.tIn,
    required this.heatingDays,
    required this.tHeatAvg,
  });

  final String city;

  /// Расчётная температура наиболее холодной пятидневки обесп. 0.92, °C.
  final double tExtJan;

  /// Расчётная температура внутреннего воздуха, °C (норм. 20 для жилья).
  final double tIn;

  /// Продолжительность отопительного периода zот, сут.
  final double heatingDays;

  /// Средняя температура отопительного периода, °C.
  final double tHeatAvg;

  /// ГСОП — градусо-сутки отопительного периода, °C·сут. Формула 5.2.
  double get gsop => (tIn - tHeatAvg) * heatingDays;
}

/// Представительные города РФ (выборка из СП 131.13330.2020).
class ClimateZones {
  ClimateZones._();

  static const moscow = ClimateZone(
    city: 'Москва',
    tExtJan: -25,
    tIn: 20,
    heatingDays: 205,
    tHeatAvg: -2.2,
  );

  static const spb = ClimateZone(
    city: 'Санкт-Петербург',
    tExtJan: -24,
    tIn: 20,
    heatingDays: 213,
    tHeatAvg: -1.3,
  );

  static const ekb = ClimateZone(
    city: 'Екатеринбург',
    tExtJan: -32,
    tIn: 20,
    heatingDays: 221,
    tHeatAvg: -5.4,
  );

  static const novosibirsk = ClimateZone(
    city: 'Новосибирск',
    tExtJan: -37,
    tIn: 20,
    heatingDays: 221,
    tHeatAvg: -8.1,
  );

  static const krasnodar = ClimateZone(
    city: 'Краснодар',
    tExtJan: -16,
    tIn: 20,
    heatingDays: 145,
    tHeatAvg: 3.0,
  );

  // Дополнительные города (СП 131.13330.2020, табл. 3.1).
  static const kazan = ClimateZone(
    city: 'Казань',
    tExtJan: -31,
    tIn: 20,
    heatingDays: 215,
    tHeatAvg: -4.7,
  );

  static const nizhnyNovgorod = ClimateZone(
    city: 'Нижний Новгород',
    tExtJan: -30,
    tIn: 20,
    heatingDays: 213,
    tHeatAvg: -3.9,
  );

  static const yakutsk = ClimateZone(
    city: 'Якутск',
    tExtJan: -52,
    tIn: 20,
    heatingDays: 252,
    tHeatAvg: -19.5,
  );

  static const sochi = ClimateZone(
    city: 'Сочи',
    tExtJan: -3,
    tIn: 20,
    heatingDays: 89,
    tHeatAvg: 7.2,
  );

  static const murmansk = ClimateZone(
    city: 'Мурманск',
    tExtJan: -27,
    tIn: 20,
    heatingDays: 281,
    tHeatAvg: -2.9,
  );

  static const vladivostok = ClimateZone(
    city: 'Владивосток',
    tExtJan: -23,
    tIn: 20,
    heatingDays: 196,
    tHeatAvg: -3.2,
  );

  static const irkutsk = ClimateZone(
    city: 'Иркутск',
    tExtJan: -36,
    tIn: 20,
    heatingDays: 240,
    tHeatAvg: -7.6,
  );

  static const all = <ClimateZone>[
    moscow,
    spb,
    ekb,
    novosibirsk,
    krasnodar,
    kazan,
    nizhnyNovgorod,
    yakutsk,
    sochi,
    murmansk,
    vladivostok,
    irkutsk,
  ];
}

/// Тип конструкции для выбора базовых значений требуемого
/// сопротивления теплопередаче (таблица 3 СП 50).
enum BuildingEnvelope {
  wall,
  roof,
  floorOverUnheated,
  window,
}

/// Слой многослойной конструкции.
class EnvelopeLayer {
  const EnvelopeLayer({
    required this.name,
    required this.thicknessMm,
    required this.lambda,
  });

  /// Материал, например «Газобетон D500».
  final String name;

  /// Толщина слоя, мм.
  final double thicknessMm;

  /// Коэффициент теплопроводности λ, Вт/(м·°C) — из СП 50 прил. С.
  final double lambda;

  /// Сопротивление теплопередаче слоя R_i = δ/λ.
  double get r => (thicknessMm / 1000.0) / lambda;
}

/// Результат теплотехнического расчёта.
class ThermalResult {
  const ThermalResult({
    required this.gsop,
    required this.rReq,
    required this.rActual,
    required this.passes,
    required this.steps,
  });

  final double gsop;

  /// Требуемое сопротивление теплопередаче, м²·°C/Вт.
  final double rReq;

  /// Фактическое сопротивление теплопередаче, м²·°C/Вт.
  final double rActual;

  /// Достаточность сопротивления (R_actual ≥ R_req).
  final bool passes;

  final List<CalcStep> steps;
}

/// Теплотехнический расчёт ограждающей конструкции по СП 50.13330.2024.
class ThermalCalculator {
  ThermalCalculator._();

  /// Коэффициенты a, b из таблицы 3 СП 50 для жилых зданий.
  /// R_req = a · Dd + b, где Dd = ГСОП.
  static double _reqR(BuildingEnvelope e, double gsop) {
    double a, b;
    switch (e) {
      case BuildingEnvelope.wall:
        a = 0.00035;
        b = 1.4;
        break;
      case BuildingEnvelope.roof:
        a = 0.00050;
        b = 2.2;
        break;
      case BuildingEnvelope.floorOverUnheated:
        a = 0.00045;
        b = 1.9;
        break;
      case BuildingEnvelope.window:
        a = 0.00005;
        b = 0.3;
        break;
    }
    return a * gsop + b;
  }

  static String _envLabel(BuildingEnvelope e) {
    switch (e) {
      case BuildingEnvelope.wall:
        return 'наружная стена';
      case BuildingEnvelope.roof:
        return 'покрытие/чердак';
      case BuildingEnvelope.floorOverUnheated:
        return 'перекрытие над неотапливаемым';
      case BuildingEnvelope.window:
        return 'светопрозрачная конструкция';
    }
  }

  /// Выполняет расчёт для указанной конструкции в заданном климате.
  static ThermalResult compute({
    required ClimateZone climate,
    required BuildingEnvelope envelope,
    required List<EnvelopeLayer> layers,
    double alphaIn = 8.7, // Вт/(м²·°C), таблица 4 СП 50 — для стен.
    double alphaOut = 23.0,
  }) {
    final gsop = climate.gsop;
    final rReq = _reqR(envelope, gsop);

    // Термическое сопротивление слоя + граничные.
    final rLayers = layers.fold<double>(0, (p, l) => p + l.r);
    final rActual = 1 / alphaIn + rLayers + 1 / alphaOut;

    final steps = <CalcStep>[
      CalcStep(
        title: 'ГСОП (градусо-сутки отоп. периода)',
        formula: 'Dd = (tв − tот) · zот',
        substitution:
            'Dd = (${climate.tIn.toStringAsFixed(0)} − ${climate.tHeatAvg.toStringAsFixed(1)}) · ${climate.heatingDays.toStringAsFixed(0)} = ${gsop.toStringAsFixed(0)}',
        formattedResult: 'Dd = ${gsop.toStringAsFixed(0)} °C·сут',
        reference: 'СП 50.13330.2012 п.5.2, формула (5.2)',
      ),
      CalcStep(
        title: 'Требуемое R₀ для ${_envLabel(envelope)}',
        formula: 'R₀^тр = a · Dd + b',
        substitution:
            'R₀^тр = ${_a(envelope).toStringAsFixed(5)} · ${gsop.toStringAsFixed(0)} + ${_b(envelope).toStringAsFixed(2)} = ${rReq.toStringAsFixed(2)}',
        formattedResult: 'R₀^тр = ${rReq.toStringAsFixed(2)} м²·°C/Вт',
        reference: 'СП 50.13330.2012 таблица 3',
      ),
      for (final l in layers)
        CalcStep(
          title: 'R слоя «${l.name}»',
          formula: 'R = δ / λ',
          substitution:
              'R = ${(l.thicknessMm / 1000).toStringAsFixed(3)} / ${l.lambda.toStringAsFixed(3)} = ${l.r.toStringAsFixed(3)}',
          formattedResult: 'R = ${l.r.toStringAsFixed(3)} м²·°C/Вт',
          reference: 'СП 50.13330.2012 формула (Е.6)',
        ),
      CalcStep(
        title: 'Фактическое R₀ конструкции',
        formula: 'R₀ = 1/αв + ΣRi + 1/αн',
        substitution:
            'R₀ = 1/${alphaIn.toStringAsFixed(1)} + ${rLayers.toStringAsFixed(3)} + 1/${alphaOut.toStringAsFixed(1)} = ${rActual.toStringAsFixed(2)}',
        formattedResult: 'R₀ = ${rActual.toStringAsFixed(2)} м²·°C/Вт',
        reference: 'СП 50.13330.2012 формула (Е.6)',
      ),
    ];

    return ThermalResult(
      gsop: gsop,
      rReq: rReq,
      rActual: rActual,
      passes: rActual >= rReq,
      steps: steps,
    );
  }

  static double _a(BuildingEnvelope e) => switch (e) {
        BuildingEnvelope.wall => 0.00035,
        BuildingEnvelope.roof => 0.00050,
        BuildingEnvelope.floorOverUnheated => 0.00045,
        BuildingEnvelope.window => 0.00005,
      };

  static double _b(BuildingEnvelope e) => switch (e) {
        BuildingEnvelope.wall => 1.4,
        BuildingEnvelope.roof => 2.2,
        BuildingEnvelope.floorOverUnheated => 1.9,
        BuildingEnvelope.window => 0.3,
      };
}
