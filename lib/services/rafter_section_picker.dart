import 'package:cc_engine/cc_engine.dart';

import '../models/house_project.dart';

/// Подбор сечения стропильной ноги по фактическим нагрузкам проекта
/// (СП 20.13330.2016 «Нагрузки и воздействия» + СП 64.13330.2017
/// «Деревянные конструкции»).
///
/// Используется в нескольких местах:
///   • `RaftersExplanationPdf` — пояснительная записка с расчётом;
///   • `pdf_additional_plans._paintRaftersSection` — лист КД-2.1
///     с разрезом стропильной системы.
///
/// До v43 на листе КД-2.1 сечение выбиралось простым сравнением
/// «полупролёт ≤ 4.5 → 50×150» — без учёта снегового района,
/// угла ската и веса кровли. Теперь оба места используют один
/// и тот же подбор.
class RafterSectionPicker {
  RafterSectionPicker._();

  /// Подобрать минимально возможное сечение из стандартного ряда
  /// 50×150, 50×200, 50×250, 75×250, 100×250 (мм). Если ничего не
  /// подходит — возвращаем 100×250 (предельный для индивидуального
  /// строительства; больший пролёт требует фермы или клееной балки).
  static const _stockSections = <List<double>>[
    [50, 150],
    [50, 200],
    [50, 250],
    [75, 250],
    [100, 250],
  ];

  /// Sg — нормативный вес снегового покрова (кН/м²) по СП 20 табл.10.1.
  static double snowSgPerZone(int? zone) {
    switch (zone ?? 3) {
      case 1:
        return 1.0;
      case 2:
        return 1.2;
      case 3:
        return 1.8;
      case 4:
        return 2.4;
      case 5:
        return 3.2;
      case 6:
        return 4.0;
      case 7:
        return 4.8;
      case 8:
        return 5.6;
      default:
        return 1.8;
    }
  }

  /// w0 — нормативное ветровое давление (кН/м²) по СП 20 табл.11.1.
  static double windW0PerZone(String? zone) {
    switch (zone) {
      case 'Iа':
        return 0.17;
      case 'I':
        return 0.23;
      case 'II':
        return 0.30;
      case 'III':
        return 0.38;
      case 'IV':
        return 0.48;
      case 'V':
        return 0.60;
      case 'VI':
        return 0.73;
      case 'VII':
        return 0.85;
      default:
        return 0.30;
    }
  }

  /// μ — коэффициент перехода нагрузки на покрытие (СП 20 п.10.4).
  static double snowMu(double angleDeg) {
    if (angleDeg <= 30) return 1.0;
    if (angleDeg >= 60) return 0.0;
    return (60 - angleDeg) / 30;
  }

  /// Шаг стропил (м) — типичные значения для разных кровельных
  /// материалов, СП 17.13330.2017.
  static double rafterStep(String? roofingMaterial) {
    switch (roofingMaterial) {
      case 'tile':
        return 0.9;
      case 'metal':
      case 'corrugated':
        return 0.6;
      case 'soft':
        return 0.6;
      case 'slate':
        return 0.7;
      default:
        return 0.6;
    }
  }

  /// Постоянная нагрузка g (кН/м²): кровля + обрешётка + нога + утеплитель.
  static double permanentLoadKnPerM2(String? roofingMaterial) {
    double roofingKn;
    switch (roofingMaterial) {
      case 'metal':
        roofingKn = 0.05;
        break;
      case 'tile':
        roofingKn = 0.45;
        break;
      case 'soft':
        roofingKn = 0.10;
        break;
      case 'corrugated':
        roofingKn = 0.06;
        break;
      case 'slate':
        roofingKn = 0.18;
        break;
      default:
        roofingKn = 0.10;
    }
    const sheathingKn = 0.10;
    const rafterSelfKn = 0.12;
    const insulationKn = 0.07;
    return roofingKn + sheathingKn + rafterSelfKn + insulationKn;
  }

  /// Угол ската — из проекта или дефолт по типу.
  static double slopeAngle(HouseProject project) {
    final fromRoof = project.roof.slopeAngle;
    if (fromRoof != null) return fromRoof;
    final t = project.roof.type;
    switch (t) {
      case 'mansard':
        return 45.0;
      case 'shed':
        return 15.0;
      case 'flat':
        return 2.0;
      case 'gable':
      case 'hip':
      default:
        return 30.0;
    }
  }

  /// Полупролёт стропильной ноги (м).
  static double span(HouseProject project, double footprintWidth) {
    final t = project.roof.type;
    switch (t) {
      case 'shed':
        return footprintWidth;
      case 'flat':
        return footprintWidth / 2;
      case 'mansard':
      case 'gable':
      case 'hip':
      default:
        return footprintWidth / 2;
    }
  }

  /// Подобрать сечение стропил, прошедшее проверку по прочности и
  /// прогибу в текущих условиях (снеговой/ветровой районы из
  /// `brief`, угол из `roof`, ширина из `brief.footprintWidth`).
  ///
  /// Возвращает результат [RafterPickResult] со всеми промежуточными
  /// величинами (для отрисовки на чертеже и подписи).
  static RafterPickResult pickFor(HouseProject project) {
    final width = project.brief.footprintWidth ?? 8.0;
    final spanM = span(project, width);
    final angleDeg = slopeAngle(project);
    final roofingMaterial = project.roof.roofingMaterial;
    final stepM = rafterStep(roofingMaterial);
    final permKn = permanentLoadKnPerM2(roofingMaterial);
    final snowZone = project.brief.snowZone ?? 3;
    final sg = snowSgPerZone(snowZone);
    final mu = snowMu(angleDeg);
    final s0 = sg * mu;
    const gfPermanent = 1.1;
    const gfSnow = 1.4;
    final qDesignKnPerM2 = gfPermanent * permKn + gfSnow * s0;
    final qKnPerM = qDesignKnPerM2 * stepM;
    final qNormKnPerM = (permKn + s0) * stepM;

    double widthMm = 50;
    double heightMm = 150;
    RafterCheckResult? result;
    for (final s in _stockSections) {
      widthMm = s[0];
      heightMm = s[1];
      result = RafterCheck.computeSimple(
        spanM: spanM,
        widthMm: widthMm,
        heightMm: heightMm,
        qKnPerM: qKnPerM,
        qNormKnPerM: qNormKnPerM,
        grade: WoodGrade.second,
      );
      if (result.passes) break;
    }
    final reactionKn = qKnPerM * spanM / 2;
    return RafterPickResult(
      spanM: spanM,
      angleDeg: angleDeg,
      stepM: stepM,
      widthMm: widthMm,
      heightMm: heightMm,
      snowZone: snowZone,
      snowSgKnPerM2: sg,
      snowS0KnPerM2: s0,
      permKnPerM2: permKn,
      qDesignKnPerM2: qDesignKnPerM2,
      qKnPerM: qKnPerM,
      qNormKnPerM: qNormKnPerM,
      momentKnm: result?.momentKnm ?? 0,
      sigmaNmm2: result?.sigmaNmm2 ?? 0,
      deflectionMm: result?.deflectionMm ?? 0,
      reactionKn: reactionKn,
      passes: result?.passes ?? false,
    );
  }
}

/// Результат подбора стропильного сечения.
class RafterPickResult {
  const RafterPickResult({
    required this.spanM,
    required this.angleDeg,
    required this.stepM,
    required this.widthMm,
    required this.heightMm,
    required this.snowZone,
    required this.snowSgKnPerM2,
    required this.snowS0KnPerM2,
    required this.permKnPerM2,
    required this.qDesignKnPerM2,
    required this.qKnPerM,
    required this.qNormKnPerM,
    required this.momentKnm,
    required this.sigmaNmm2,
    required this.deflectionMm,
    required this.reactionKn,
    required this.passes,
  });

  /// Пролёт стропильной ноги, м.
  final double spanM;

  /// Угол ската, градусы.
  final double angleDeg;

  /// Шаг стропил, м.
  final double stepM;

  /// Подобранное сечение, мм.
  final double widthMm;
  final double heightMm;

  /// Снеговой район.
  final int snowZone;

  /// Sg — нормативный вес снегового покрова, кН/м².
  final double snowSgKnPerM2;

  /// S0 = Sg · μ — снеговая на покрытие, кН/м².
  final double snowS0KnPerM2;

  /// Постоянная нагрузка g, кН/м².
  final double permKnPerM2;

  /// Расчётная нагрузка q (с учётом γf), кН/м².
  final double qDesignKnPerM2;

  /// Линейная расчётная нагрузка q на одну стропилу, кН/м.
  final double qKnPerM;

  /// Линейная нормативная нагрузка q на одну стропилу, кН/м (для прогиба).
  final double qNormKnPerM;

  /// Изгибающий момент Mmax, кН·м.
  final double momentKnm;

  /// Нормальное напряжение σ, Н/мм².
  final double sigmaNmm2;

  /// Прогиб f, мм.
  final double deflectionMm;

  /// Опорная реакция R = q·L/2, кН.
  final double reactionKn;

  /// Прошёл ли по прочности и прогибу.
  final bool passes;

  /// Текстовое обозначение сечения (например, «Ц 50×200»).
  String get sectionLabel =>
      'Ц ${widthMm.toStringAsFixed(0)}×${heightMm.toStringAsFixed(0)}';
}
