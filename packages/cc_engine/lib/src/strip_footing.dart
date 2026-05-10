import 'dart:math' as math;

import 'calc_step.dart';
import 'enums.dart';

/// Результат подбора ленточного фундамента.
///
/// Содержит геометрию (ширина/высота/глубина заложения), материалы
/// (класс бетона, класс арматуры) и журнал шагов расчёта.
class StripFootingDesign {
  const StripFootingDesign({
    required this.widthM,
    required this.heightM,
    required this.depthM,
    required this.concreteClass,
    required this.longitudinalClass,
    required this.longitudinalDiameterMm,
    required this.longitudinalCount,
    required this.stirrupClass,
    required this.stirrupDiameterMm,
    required this.stirrupSpacingMm,
    required this.steps,
  });

  final double widthM;
  final double heightM;
  final double depthM;
  final ConcreteClass concreteClass;
  final RebarClass longitudinalClass;
  final int longitudinalDiameterMm;
  final int longitudinalCount;
  final RebarClass stirrupClass;
  final int stirrupDiameterMm;
  final int stirrupSpacingMm;
  final List<CalcStep> steps;
}

/// Подбор монолитного ленточного фундамента (упрощённо, для ИЖС).
class StripFootingDesigner {
  StripFootingDesigner._();

  static StripFootingDesign design({
    required double verticalLoadKnPerM2,
    required double footprintAreaM2,
    required double loadBearingWallsPerimeterM,
    required FoundationSoilType soilType,
    required double freezingDepthM,
    /// Минимальная глубина заложения подошвы (м), требуемая по
    /// архитектуре. Пример: при наличии подвала с высотой 2.5 м
    /// подошва ленты должна быть ниже пола подвала ≥ 0.3 м,
    /// т. е. depthMinM = 2.8.
    double? minimumDepthM,
    String? loadOrigin,
    String? footprintOrigin,
    String? wallsOrigin,
    String? soilOrigin,
    String? freezingOrigin,
  }) {
    final r0 = soilType.r0KPa.toDouble();
    final totalLoadKn = verticalLoadKnPerM2 * footprintAreaM2;
    final loadPerMeterLinealKn = totalLoadKn / loadBearingWallsPerimeterM;

    // Требуемая ширина подошвы, м
    final requiredWidthM = loadPerMeterLinealKn / r0;
    // Округляем до стандартных 300 / 400 / 500 / 600 мм
    final widthM = _roundFootingWidth(requiredWidthM);

    // Высота ленты — принимаем 2·ширины, но не меньше 400 мм.
    final heightM = math.max(0.4, widthM * 2);

    // Глубина заложения — не меньше df + 10 см для защиты от пучения.
    // Если есть архитектурное требование (например, подвал) — берём
    // более глубокое значение.
    final baseDepthM = math.max(freezingDepthM + 0.1, 1.0);
    final depthM = math.max(baseDepthM, minimumDepthM ?? 0.0);

    // Подбор бетона по нагрузке (упрощённо).
    final concreteClass = _concreteByLoad(verticalLoadKnPerM2);

    // Продольная арматура: 4⌀12 для малой нагрузки, 6⌀14 для высокой.
    final heavyLoad = verticalLoadKnPerM2 > 30;
    final longitudinalDiameter = heavyLoad ? 14 : 12;
    final longitudinalCount = heavyLoad ? 6 : 4;

    // Поперечная (хомуты): ⌀8 A240 с шагом 200 мм.
    const stirrupDiameter = 8;
    const stirrupSpacing = 200;

    final steps = <CalcStep>[
      CalcStep(
        title: 'Расчётное сопротивление основания R0',
        formula: 'R0 — табличное по СП 22',
        substitution: 'Грунт: ${soilType.title} ⇒ R0 = ${r0.toStringAsFixed(0)} кПа',
        formattedResult: 'R0 = ${r0.toStringAsFixed(0)} кПа',
        reference: 'СП 22.13330.2016, прил. Д',
        inputs: [
          CalcInput(
            symbol: 'грунт',
            value: soilType.title,
            origin: soilOrigin ?? 'Из ТЗ, верхний слой',
          ),
        ],
      ),
      CalcStep(
        title: 'Площадь застройки A',
        formula: 'A = L · B',
        substitution: 'A = ${footprintAreaM2.toStringAsFixed(1)} м²',
        formattedResult: 'A = ${footprintAreaM2.toStringAsFixed(1)} м²',
        inputs: [
          CalcInput(
            symbol: 'A',
            value: '${footprintAreaM2.toStringAsFixed(1)} м²',
            origin: footprintOrigin ?? 'Из ТЗ: габариты пятна',
          ),
        ],
      ),
      CalcStep(
        title: 'Длина несущих стен L',
        formula: 'L = периметр + внутренние',
        substitution: 'L = ${loadBearingWallsPerimeterM.toStringAsFixed(1)} м',
        formattedResult: 'L = ${loadBearingWallsPerimeterM.toStringAsFixed(1)} м',
        inputs: [
          CalcInput(
            symbol: 'L',
            value: '${loadBearingWallsPerimeterM.toStringAsFixed(1)} м',
            origin: wallsOrigin ?? 'По пятну + 1 поперечная',
          ),
        ],
      ),
      CalcStep(
        title: 'Суммарная вертикальная нагрузка N',
        formula: 'N = q · A',
        substitution:
            'N = ${verticalLoadKnPerM2.toStringAsFixed(2)} · ${footprintAreaM2.toStringAsFixed(1)}',
        formattedResult: 'N = ${totalLoadKn.toStringAsFixed(1)} кН',
        inputs: [
          CalcInput(
            symbol: 'q',
            value: '${verticalLoadKnPerM2.toStringAsFixed(2)} кН/м²',
            origin: loadOrigin ?? 'С предыдущего экрана',
          ),
        ],
      ),
      CalcStep(
        title: 'Нагрузка на погонный метр ленты q_L',
        formula: 'q_L = N / L',
        substitution:
            'q_L = ${totalLoadKn.toStringAsFixed(1)} / ${loadBearingWallsPerimeterM.toStringAsFixed(1)}',
        formattedResult: 'q_L = ${loadPerMeterLinealKn.toStringAsFixed(1)} кН/м',
      ),
      CalcStep(
        title: 'Требуемая ширина подошвы b',
        formula: 'b = q_L / R0',
        substitution:
            'b = ${loadPerMeterLinealKn.toStringAsFixed(1)} / ${r0.toStringAsFixed(0)} = ${requiredWidthM.toStringAsFixed(3)} м',
        formattedResult:
            'b(тр) = ${requiredWidthM.toStringAsFixed(3)} м → b = ${widthM.toStringAsFixed(2)} м',
        note: 'Принят типовой размер с округлением вверх до 50 мм',
      ),
      CalcStep(
        title: 'Проверка давления под подошвой',
        formula: 'p = q_L / b ≤ R0',
        substitution:
            'p = ${loadPerMeterLinealKn.toStringAsFixed(1)} / ${widthM.toStringAsFixed(2)} = ${(loadPerMeterLinealKn / widthM).toStringAsFixed(1)} кПа',
        formattedResult: (loadPerMeterLinealKn / widthM) <= r0
            ? 'p ≤ R0 — выполняется'
            : 'p > R0 — увеличить ширину!',
        reference: 'СП 22.13330.2016, п. 5.6.7',
      ),
      CalcStep(
        title: 'Глубина заложения d',
        formula: 'd = df + 0.1 м (защита от морозного пучения)',
        substitution: 'd = ${freezingDepthM.toStringAsFixed(1)} + 0.1 м',
        formattedResult: 'd = ${depthM.toStringAsFixed(2)} м',
        reference: 'СП 22.13330.2016, п. 5.5.3',
        inputs: [
          CalcInput(
            symbol: 'df',
            value: '${freezingDepthM.toStringAsFixed(1)} м',
            origin: freezingOrigin ?? 'По СП 131.13330.2020 для региона',
          ),
        ],
      ),
      CalcStep(
        title: 'Высота ленты h',
        formula: 'h = 2·b, но ≥ 400 мм',
        substitution:
            'h = 2 · ${widthM.toStringAsFixed(2)} = ${(widthM * 2).toStringAsFixed(2)} м',
        formattedResult: 'h = ${heightM.toStringAsFixed(2)} м',
      ),
      CalcStep(
        title: 'Класс бетона',
        formula: 'По таблице СП 63.13330.2018',
        substitution:
            'Нагрузка ${verticalLoadKnPerM2.toStringAsFixed(1)} кН/м² ⇒ ${concreteClass.title}',
        formattedResult: concreteClass.title,
        reference: 'СП 63.13330.2018, табл. 6.7',
      ),
      CalcStep(
        title: 'Продольная арматура',
        formula: 'Конструктивное требование Ø и количество',
        substitution:
            '$longitudinalCount⌀$longitudinalDiameter мм ${heavyLoad ? 'A500' : 'A400'}',
        formattedResult:
            '$longitudinalCount⌀$longitudinalDiameter ${heavyLoad ? 'A500' : 'A400'}',
        reference: 'СП 63.13330.2018, п. 10.3.5',
      ),
      const CalcStep(
        title: 'Поперечная арматура (хомуты)',
        formula: 'Конструктивно',
        substitution:
            '⌀$stirrupDiameter мм A240 с шагом $stirrupSpacing мм',
        formattedResult:
            '⌀$stirrupDiameter A240, шаг $stirrupSpacing мм',
        reference: 'СП 63.13330.2018, п. 10.3.10',
      ),
    ];

    return StripFootingDesign(
      widthM: widthM,
      heightM: heightM,
      depthM: depthM,
      concreteClass: concreteClass,
      longitudinalClass: heavyLoad ? RebarClass.a500 : RebarClass.a400,
      longitudinalDiameterMm: longitudinalDiameter,
      longitudinalCount: longitudinalCount,
      stirrupClass: RebarClass.a240,
      stirrupDiameterMm: stirrupDiameter,
      stirrupSpacingMm: stirrupSpacing,
      steps: steps,
    );
  }

  static double _roundFootingWidth(double required) {
    // Ряд типовых ширин ленты: 300, 400, 500, 600, 800, 1000 мм.
    for (final w in const [0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.2]) {
      if (required <= w) return w;
    }
    return 1.5; // экстремальный случай
  }

  static ConcreteClass _concreteByLoad(double qKnPerM2) {
    if (qKnPerM2 <= 15) return ConcreteClass.b15;
    if (qKnPerM2 <= 25) return ConcreteClass.b20;
    if (qKnPerM2 <= 40) return ConcreteClass.b25;
    return ConcreteClass.b30;
  }
}
