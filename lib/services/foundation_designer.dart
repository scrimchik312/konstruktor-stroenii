import 'dart:math' as math;

import 'package:cc_engine/cc_engine.dart';

import '../data/wall_materials.dart';
import '../models/client_brief.dart';
import '../models/foundation.dart';

/// Упрощённые упрощённые расчёты для всех типов фундамента, кроме ленточного
/// (для него используем существующий [StripFootingDesigner]). Назначение —
/// дать пользователю числовые результаты, соответствующие его выбору, не
/// привязываясь к ленте по умолчанию. Для ИЖС достаточно: глубина/толщина,
/// количество элементов, типовое армирование, ссылка на СП. Глубокий
/// расчёт по СП 22/24/50-101 — задача следующих итераций.
class FoundationByTypeDesigner {
  FoundationByTypeDesigner._();

  static FoundationByTypeResult design({
    required FoundationType type,
    required double verticalLoadKnPerM2,
    required double footprintWidthM,
    required double footprintLengthM,
    required FoundationSoilType soil,
    required double freezingDepthM,
    required ClientBrief brief,
  }) {
    switch (type) {
      case FoundationType.strip:
        // Лента считается основным StripFootingDesigner-ом отдельно.
        return FoundationByTypeResult(
          type: type,
          steps: const [],
          summary: const [],
          codeReferences: const ['СП 22.13330.2016', 'СП 63.13330.2018'],
        );
      case FoundationType.slab:
        return _slab(
          q: verticalLoadKnPerM2,
          width: footprintWidthM,
          length: footprintLengthM,
          soil: soil,
        );
      case FoundationType.pile:
        return _screwPile(
          q: verticalLoadKnPerM2,
          width: footprintWidthM,
          length: footprintLengthM,
          soil: soil,
          freezing: freezingDepthM,
          brief: brief,
        );
      case FoundationType.pileWithGrillage:
        return _boredPileGrillage(
          q: verticalLoadKnPerM2,
          width: footprintWidthM,
          length: footprintLengthM,
          soil: soil,
          freezing: freezingDepthM,
        );
      case FoundationType.columnar:
        return _columnar(
          q: verticalLoadKnPerM2,
          width: footprintWidthM,
          length: footprintLengthM,
          soil: soil,
          freezing: freezingDepthM,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Плитный фундамент (СП 22.13330.2016 + СП 50-101 + СП 63.13330.2018)
  // ---------------------------------------------------------------------------
  static FoundationByTypeResult _slab({
    required double q,
    required double width,
    required double length,
    required FoundationSoilType soil,
  }) {
    final area = width * length;
    final nTotal = q * area; // кН
    final pAvg = nTotal / area; // кН/м² = кПа (равно q)
    final r = soil.r0KPa.toDouble();
    final maxSpan = math.max(width, length);
    // Толщина плиты: эмпирика по СП 50-101 ~ (1/35..1/25) пролёта, не менее 200 мм.
    final tFromSpan = maxSpan / 30; // м
    final thicknessM = math.max(0.20, _round(tFromSpan, 0.05));
    // Армирование — два уровня сетки ⌀12 А500С с шагом 200 мм.
    return FoundationByTypeResult(
      type: FoundationType.slab,
      summary: [
        ('Площадь плиты A', '${area.toStringAsFixed(1)} м²'),
        ('Полная нагрузка N', '${nTotal.toStringAsFixed(0)} кН'),
        ('Среднее давление p', '${pAvg.toStringAsFixed(1)} кПа'),
        ('R0 грунта основания', '${r.toStringAsFixed(0)} кПа'),
        ('Толщина плиты h', '${(thicknessM * 1000).toStringAsFixed(0)} мм'),
        ('Армирование', '2 сетки ⌀12 А500С, шаг 200 мм'),
        ('Бетон', 'B25 W6 F150'),
        (
          'Подушка',
          'песок средней крупности 100 мм + щебень 100 мм с трамбовкой'
        ),
      ],
      steps: [
        CalcStep(
          title: 'Площадь плиты',
          formula: 'A = B · L',
          substitution:
              'A = $width · $length = ${area.toStringAsFixed(2)} м²',
          formattedResult: '${area.toStringAsFixed(2)} м²',
          reference: 'СП 22.13330.2016, п. 5.10 (плитные фундаменты)',
        ),
        CalcStep(
          title: 'Среднее давление под подошвой',
          formula: 'p = q (равномерно распределённая нагрузка)',
          substitution:
              'p = q = ${q.toStringAsFixed(2)} кПа = ${q.toStringAsFixed(2)} кН/м²',
          formattedResult: '${pAvg.toStringAsFixed(1)} кПа',
          reference: 'СП 22.13330.2016, п. 5.5',
        ),
        CalcStep(
          title: 'Проверка несущей способности грунта',
          formula: 'p ≤ R',
          substitution: '${pAvg.toStringAsFixed(1)} кПа '
              '${pAvg <= r ? '≤' : '>'} '
              '${r.toStringAsFixed(0)} кПа',
          formattedResult: pAvg <= r
              ? 'Условие выполнено — плита допустима'
              : 'Условие НЕ выполнено — увеличить площадь или ставить '
                  'свайный/комбинированный вариант',
          reference: 'СП 22.13330.2016, п. 5.6',
          note: pAvg <= r
              ? null
              : 'Нагрузка превышает R0 грунта; для жилого ИЖС редко, '
                  'обычно следствие очень слабого основания.',
        ),
        CalcStep(
          title: 'Толщина плиты',
          formula: 'h ≥ max(200 мм; L/30)',
          substitution: 'h ≥ max(200; ${(maxSpan * 1000 / 30).toStringAsFixed(0)}) '
              'мм = ${(thicknessM * 1000).toStringAsFixed(0)} мм',
          formattedResult: '${(thicknessM * 1000).toStringAsFixed(0)} мм',
          reference: 'СП 50-101-2004, п. 5.5',
        ),
      ],
      codeReferences: const [
        'СП 22.13330.2016 «Основания зданий и сооружений»',
        'СП 50-101-2004 «Проектирование и устройство оснований…»',
        'СП 63.13330.2018 «Бетонные и железобетонные конструкции»',
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Винтовые сваи (СП 24.13330.2021)
  // ---------------------------------------------------------------------------
  static FoundationByTypeResult _screwPile({
    required double q,
    required double width,
    required double length,
    required FoundationSoilType soil,
    required double freezing,
    required ClientBrief brief,
  }) {
    final area = width * length;
    final nTotal = q * area; // кН
    // Типовая несущая способность винтовой сваи 108×3 длиной 2.5 м в
    // супесчаных/суглинистых грунтах: ~25-30 кН (СП 24.13330.2021, табл. Б.2).
    // Возьмём расчётное Fd = 30 кН.
    const fdPerPile = 30.0; // кН
    final n = (nTotal / fdPerPile).ceil().clamp(8, 100);
    // Минимальная длина — на 0.5 м ниже глубины промерзания.
    final pileLengthM = math.max(2.5, freezing + 0.5);
    final perimeter = 2 * (width + length);
    // Шаг свай по периметру + 1 поперечный ряд.
    final pileSpacing = perimeter / (n - 4); // 4 угловые
    return FoundationByTypeResult(
      type: FoundationType.pile,
      summary: [
        ('Площадь застройки A', '${area.toStringAsFixed(1)} м²'),
        ('Полная нагрузка N', '${nTotal.toStringAsFixed(0)} кН'),
        ('Несущая способность одной сваи Fd', '${fdPerPile.toStringAsFixed(0)} кН'),
        ('Количество свай n', '$n'),
        ('Тип сваи', '108 × 3 мм, лопасть ⌀300 (СВ-108)'),
        ('Длина сваи', '${pileLengthM.toStringAsFixed(1)} м'),
        ('Шаг свай по периметру', '~${pileSpacing.toStringAsFixed(1)} м'),
        (
          'Обвязка',
          brief.wallMaterial == WallMaterial.brick
              ? 'двутавр №20 + анкеры'
              : 'двутавр №16 / швеллер №20 + сварка'
        ),
      ],
      steps: [
        CalcStep(
          title: 'Полная вертикальная нагрузка',
          formula: 'N = q · A',
          substitution:
              'N = ${q.toStringAsFixed(2)} · ${area.toStringAsFixed(2)} = '
              '${nTotal.toStringAsFixed(0)} кН',
          formattedResult: '${nTotal.toStringAsFixed(0)} кН',
          reference: 'СП 20.13330.2016',
        ),
        CalcStep(
          title: 'Количество свай',
          formula: 'n = ⌈N / Fd⌉',
          substitution:
              'n = ⌈${nTotal.toStringAsFixed(0)} / ${fdPerPile.toStringAsFixed(0)}⌉ = $n',
          formattedResult: '$n шт.',
          reference: 'СП 24.13330.2021, п. 7.1.10',
        ),
        CalcStep(
          title: 'Длина сваи',
          formula: 'L ≥ df + 0.5 м',
          substitution:
              'L ≥ ${freezing.toStringAsFixed(1)} + 0.5 = ${pileLengthM.toStringAsFixed(1)} м',
          formattedResult: '${pileLengthM.toStringAsFixed(1)} м',
          reference: 'СП 24.13330.2021, п. 8.10 (заглубление ниже '
              'глубины промерзания)',
        ),
      ],
      codeReferences: const [
        'СП 24.13330.2021 «Свайные фундаменты»',
        'СП 22.13330.2016 «Основания зданий и сооружений»',
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Буронабивные сваи с ростверком (СП 24.13330.2021)
  // ---------------------------------------------------------------------------
  static FoundationByTypeResult _boredPileGrillage({
    required double q,
    required double width,
    required double length,
    required FoundationSoilType soil,
    required double freezing,
  }) {
    final area = width * length;
    final nTotal = q * area; // кН
    // Буронабивная свая ⌀300, длина 4 м, в плотных суглинках — Fd ~ 220 кН
    // (СП 24.13330.2021, п. 7.2.3, формула 7.5).
    const fdPerPile = 220.0;
    final n = (nTotal / fdPerPile).ceil().clamp(6, 60);
    final perimeter = 2 * (width + length);
    final spacing = perimeter / (n - 4);
    final pileLengthM = math.max(3.0, freezing + 1.5);
    return FoundationByTypeResult(
      type: FoundationType.pileWithGrillage,
      summary: [
        ('Площадь застройки A', '${area.toStringAsFixed(1)} м²'),
        ('Полная нагрузка N', '${nTotal.toStringAsFixed(0)} кН'),
        ('Несущая способность Fd', '${fdPerPile.toStringAsFixed(0)} кН'),
        ('Количество свай n', '$n'),
        ('Диаметр сваи', '⌀300 мм'),
        ('Длина сваи', '${pileLengthM.toStringAsFixed(1)} м'),
        ('Шаг свай', '~${spacing.toStringAsFixed(1)} м'),
        ('Ростверк', 'монолитная лента 400 × 500 мм, B25, ⌀12 А500С (4 нитки)'),
      ],
      steps: [
        CalcStep(
          title: 'Полная вертикальная нагрузка',
          formula: 'N = q · A',
          substitution:
              'N = ${q.toStringAsFixed(2)} · ${area.toStringAsFixed(2)} = '
              '${nTotal.toStringAsFixed(0)} кН',
          formattedResult: '${nTotal.toStringAsFixed(0)} кН',
          reference: 'СП 20.13330.2016',
        ),
        CalcStep(
          title: 'Количество свай',
          formula: 'n = ⌈N / Fd⌉',
          substitution:
              'n = ⌈${nTotal.toStringAsFixed(0)} / ${fdPerPile.toStringAsFixed(0)}⌉ = $n',
          formattedResult: '$n шт.',
          reference: 'СП 24.13330.2021, п. 7.1.10',
        ),
        CalcStep(
          title: 'Длина сваи',
          formula: 'L ≥ df + 1.5 м (заглубление в плотный слой)',
          substitution:
              'L ≥ ${freezing.toStringAsFixed(1)} + 1.5 = ${pileLengthM.toStringAsFixed(1)} м',
          formattedResult: '${pileLengthM.toStringAsFixed(1)} м',
          reference: 'СП 24.13330.2021, п. 8.10',
        ),
      ],
      codeReferences: const [
        'СП 24.13330.2021 «Свайные фундаменты»',
        'СП 22.13330.2016 «Основания зданий и сооружений»',
        'СП 63.13330.2018 «Бетонные и железобетонные конструкции» (ростверк)',
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Столбчатый фундамент (СП 22.13330.2016)
  // ---------------------------------------------------------------------------
  static FoundationByTypeResult _columnar({
    required double q,
    required double width,
    required double length,
    required FoundationSoilType soil,
    required double freezing,
  }) {
    final area = width * length;
    final nTotal = q * area;
    // Размещаем столбы с шагом ~3 м по периметру + углы.
    final perimeter = 2 * (width + length);
    final n = math.max(6, (perimeter / 3).ceil() + 4);
    final loadPerColumn = nTotal / n;
    final r = soil.r0KPa.toDouble();
    final aRequired = loadPerColumn / r; // м²
    final aSide = math.sqrt(aRequired);
    final sideM = math.max(0.6, _round(aSide, 0.1));
    final depthM = math.max(0.8, freezing + 0.2);
    return FoundationByTypeResult(
      type: FoundationType.columnar,
      summary: [
        ('Количество столбов n', '$n'),
        ('Нагрузка на столб N1', '${loadPerColumn.toStringAsFixed(1)} кН'),
        ('R0 грунта', '${r.toStringAsFixed(0)} кПа'),
        ('Размер подушки', '${sideM.toStringAsFixed(2)} × ${sideM.toStringAsFixed(2)} м'),
        ('Высота столба над землёй', '0.30 м (цоколь)'),
        ('Глубина заложения', '${depthM.toStringAsFixed(1)} м (df + 0.2)'),
        ('Армирование столба', '4 ⌀12 А500С + хомуты ⌀6 шаг 200'),
        ('Бетон', 'B20'),
      ],
      steps: [
        CalcStep(
          title: 'Количество столбов',
          formula: 'n ≈ P / 3 + угловые',
          substitution:
              'n ≈ ${perimeter.toStringAsFixed(1)} / 3 + 4 = $n',
          formattedResult: '$n шт.',
          reference: 'СП 22.13330.2016, п. 5.6',
        ),
        CalcStep(
          title: 'Нагрузка на 1 столб',
          formula: 'N1 = N / n',
          substitution:
              'N1 = ${nTotal.toStringAsFixed(0)} / $n = ${loadPerColumn.toStringAsFixed(1)} кН',
          formattedResult: '${loadPerColumn.toStringAsFixed(1)} кН',
          reference: 'СП 22.13330.2016',
        ),
        CalcStep(
          title: 'Размер подошвы столба',
          formula: 'A = N1 / R, b = √A',
          substitution:
              'A = ${loadPerColumn.toStringAsFixed(1)} / ${r.toStringAsFixed(0)} = '
              '${aRequired.toStringAsFixed(2)} м², b = '
              '${aSide.toStringAsFixed(2)} м → принимаем '
              '${sideM.toStringAsFixed(2)} м',
          formattedResult: '${sideM.toStringAsFixed(2)} м',
          reference: 'СП 22.13330.2016, п. 5.6',
        ),
      ],
      codeReferences: const [
        'СП 22.13330.2016 «Основания зданий и сооружений»',
        'СП 63.13330.2018 «Бетонные и железобетонные конструкции»',
      ],
    );
  }

  static double _round(double v, double step) =>
      (v / step).round() * step;
}

/// Результат упрощённого расчёта по выбранному типу фундамента.
class FoundationByTypeResult {
  const FoundationByTypeResult({
    required this.type,
    required this.steps,
    required this.summary,
    required this.codeReferences,
  });

  final FoundationType type;
  final List<CalcStep> steps;

  /// Итоговые строки «параметр — значение» для блока «Подобранные параметры».
  final List<(String, String)> summary;

  /// Список нормативных документов, по которым велся расчёт.
  final List<String> codeReferences;
}
