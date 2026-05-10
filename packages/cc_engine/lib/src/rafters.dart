import 'dart:math' as math;

import 'calc_step.dart';

/// Сорт древесины (СП 64.13330.2017, табл. 3 — расчётные сопротивления
/// сосны и ели, МПа = Н/мм²).
enum WoodGrade {
  first,
  second,
  third,
}

extension WoodGradeCalc on WoodGrade {
  /// Rи — расчётное сопротивление изгибу, Н/мм² (изгиб, растяжение
  /// вдоль волокон).
  double get ri {
    switch (this) {
      case WoodGrade.first:
        return 16;
      case WoodGrade.second:
        return 14;
      case WoodGrade.third:
        return 8.5;
    }
  }

  /// Модуль упругости, Н/мм² (≈ 10 000 для всех сортов сосны).
  double get e => 10000;

  String get label {
    switch (this) {
      case WoodGrade.first:
        return '1 сорт';
      case WoodGrade.second:
        return '2 сорт';
      case WoodGrade.third:
        return '3 сорт';
    }
  }
}

/// Результат проверки стропильной ноги / балки по СП 64.
class RafterCheckResult {
  const RafterCheckResult({
    required this.momentKnm,
    required this.sigmaNmm2,
    required this.sigmaAllowed,
    required this.deflectionMm,
    required this.deflectionLimitMm,
    required this.strengthPasses,
    required this.deflectionPasses,
    required this.steps,
  });

  final double momentKnm;
  final double sigmaNmm2;
  final double sigmaAllowed;
  final double deflectionMm;
  final double deflectionLimitMm;
  final bool strengthPasses;
  final bool deflectionPasses;
  final List<CalcStep> steps;

  bool get passes => strengthPasses && deflectionPasses;
}

/// Проверка прямоугольной деревянной балки / стропильной ноги на изгиб
/// и прогиб по СП 64.13330.2017.
class RafterCheck {
  RafterCheck._();

  /// Быстрая проверка под равномерно распределённую нагрузку q на пролёте
  /// L при сечении b×h (см). [qKnPerM] — расчётная линейная нагрузка,
  /// [qNormKnPerM] — нормативная (для прогиба).
  static RafterCheckResult computeSimple({
    required double spanM,
    required double widthMm,
    required double heightMm,
    required double qKnPerM,
    required double qNormKnPerM,
    required WoodGrade grade,
    double deflectionLimitRatio = 200, // f ≤ L/200 для стропил
  }) {
    // Момент сопротивления Wx = b·h²/6, мм³.
    final wx = widthMm * heightMm * heightMm / 6;
    // Момент инерции Ix = b·h³/12, мм⁴.
    final ix = widthMm * math.pow(heightMm, 3) / 12;
    // Максимальный момент для однопролётной балки с равномерной нагр.:
    // M = q · L² / 8. q в кН/м, L в м → M в кН·м.
    final moment = qKnPerM * spanM * spanM / 8;
    // Нормативное напряжение σ = M·10⁶ / Wx, Н/мм² (M в кН·м → ×10⁶ Н·мм).
    final sigma = moment * 1e6 / wx;
    final sigmaAllowed = grade.ri;

    // Прогиб: 5·qн·L⁴ / (384·E·I). L в мм, qн в Н/мм, E в Н/мм², I в мм⁴.
    final qNormNPerMm = qNormKnPerM; // 1 кН/м = 1 Н/мм
    final spanMm = spanM * 1000;
    final deflection = 5 *
        qNormNPerMm *
        math.pow(spanMm, 4) /
        (384 * grade.e * ix);
    final deflectionLimit = spanMm / deflectionLimitRatio;

    final steps = <CalcStep>[
      CalcStep(
        title: 'Момент сопротивления Wx',
        formula: 'Wx = b · h² / 6',
        substitution:
            'Wx = ${widthMm.toStringAsFixed(0)} · ${heightMm.toStringAsFixed(0)}² / 6 = ${wx.toStringAsFixed(0)}',
        formattedResult: 'Wx = ${wx.toStringAsFixed(0)} мм³',
        reference: 'СП 64.13330.2017 п.7.1',
      ),
      CalcStep(
        title: 'Момент Mmax',
        formula: 'M = q · L² / 8',
        substitution:
            'M = ${qKnPerM.toStringAsFixed(2)} · ${spanM.toStringAsFixed(2)}² / 8 = ${moment.toStringAsFixed(2)}',
        formattedResult: 'M = ${moment.toStringAsFixed(2)} кН·м',
        reference: 'СП 20.13330.2016 — схема нагружения',
      ),
      CalcStep(
        title: 'Нормальное напряжение σ',
        formula: 'σ = M · 10⁶ / Wx',
        substitution:
            'σ = ${moment.toStringAsFixed(2)} · 10⁶ / ${wx.toStringAsFixed(0)} = ${sigma.toStringAsFixed(1)}',
        formattedResult: 'σ = ${sigma.toStringAsFixed(1)} Н/мм²',
        reference: 'СП 64.13330.2017 формула (33)',
      ),
      CalcStep(
        title: 'Проверка прочности',
        formula: 'σ ≤ Rи',
        substitution:
            '${sigma.toStringAsFixed(1)} ≤ ${sigmaAllowed.toStringAsFixed(1)} (${grade.label})',
        formattedResult: sigma <= sigmaAllowed
            ? 'Условие выполнено'
            : 'НЕ выполнено',
        reference: 'СП 64.13330.2017 таблица 3',
      ),
      CalcStep(
        title: 'Прогиб f',
        formula: 'f = 5·qн·L⁴ / (384·E·Ix)',
        substitution:
            'f = 5 · ${qNormKnPerM.toStringAsFixed(2)} · ${spanM.toStringAsFixed(2)}⁴ · 10¹² / (384 · ${grade.e.toStringAsFixed(0)} · ${ix.toStringAsFixed(0)}) = ${deflection.toStringAsFixed(1)}',
        formattedResult: 'f = ${deflection.toStringAsFixed(1)} мм',
        reference: 'СП 20.13330.2016 прил. Д',
      ),
      CalcStep(
        title: 'Предельный прогиб',
        formula: 'f ≤ L / n',
        substitution:
            'f ≤ ${spanMm.toStringAsFixed(0)} / ${deflectionLimitRatio.toStringAsFixed(0)} = ${deflectionLimit.toStringAsFixed(1)}',
        formattedResult: deflection <= deflectionLimit
            ? 'Прогиб в норме'
            : 'Прогиб ПРЕВЫШЕН',
        reference: 'СП 20.13330.2016 табл. Д.1',
      ),
    ];

    return RafterCheckResult(
      momentKnm: moment,
      sigmaNmm2: sigma,
      sigmaAllowed: sigmaAllowed,
      deflectionMm: deflection.toDouble(),
      deflectionLimitMm: deflectionLimit,
      strengthPasses: sigma <= sigmaAllowed,
      deflectionPasses: deflection <= deflectionLimit,
      steps: steps,
    );
  }
}
