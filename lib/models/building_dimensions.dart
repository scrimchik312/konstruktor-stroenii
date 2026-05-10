/// Единый источник истины для габаритов здания.
///
/// До v68.11 расчёт высоты этажа, цоколя, глубины фундамента и кровли
/// дублировался в трёх местах:
///   * [Building3DGenerator.generate] — для on-screen 3D и аксонометрии
///     PDF (через `Building3DRenderer`).
///   * `PdfBuilder._elevation` — для разрезов и фасадов.
///   * `PdfBuilder._foundationPreview` — для штампа на КЖ-1 и таблицы
///     фундамента.
///
/// При расхождении значений (например, для `slab` фундамента
/// генератор отдавал `plinthHeight = 0.0`, а `_elevation` — `0.20`) на
/// разрезе цоколь был, а на аксонометрии исчезал. Теперь оба
/// потребителя берут данные из одного объекта [BuildingDimensions], и
/// соответственно цифры на всех листах совпадают.
///
/// Класс — чисто-функциональный: создаётся через [BuildingDimensions.of]
/// один раз для проекта, не хранит ссылок на объекты UI.
library;

import 'dart:math' as math;

import 'foundation.dart';
import 'house_project.dart';
import '../services/roof_plan_geometry.dart';

class BuildingDimensions {
  /// Кол-во надземных этажей (без подвала и без мансарды).
  final int floors;

  /// Признак наличия мансарды (отдельный жилой этаж под скатом).
  final bool hasMansard;

  /// Признак наличия подвала (заглублённый этаж ниже уровня земли).
  final bool hasBasement;

  /// Высота этажа в свету, м (СП 55.13330.2017 — не менее 2.5 м).
  final double floorHeight;

  /// Высота подвального этажа, м (если `hasBasement == true`,
  /// иначе 0). Берётся равной [floorHeight] или 2.5 м минимум.
  final double basementHeight;

  /// Глубина фундамента (от пола 1-го этажа / пола подвала вниз), м.
  /// Согласована с подобранным типом и сечением:
  ///   * `slab`     → толщина плиты, ≥ 0.20 м;
  ///   * `strip`    → 0.80 м (типовая глубина для ИЖС);
  ///   * `pile`     → 2.50 м (длина винтовой сваи);
  ///   * `pileWithGrillage` → 3.00 м;
  ///   * `columnar` → 1.50 м.
  final double foundationDepth;

  /// Высота цоколя над уровнем земли, м. Для slab = 0.20 (цокольная
  /// обвязка), strip = 0.40, pile/columnar = 0.50 (открытое подполье).
  /// Если есть подвал — добавляется +1.00 м, чтобы цокольные окна
  /// подвала оказались над землёй (СП 50-101.2004).
  final double plinthHeight;

  /// Высота конька кровли над верхом стен, м.
  final double roofHeight;

  /// Уклон кровли в градусах.
  final double slopeDeg;

  /// Тип кровли (плоская / односкатная / двускатная / вальмовая / мансардная).
  final RoofShape roofShape;

  /// Толщина наружной стены, м.
  final double wallThicknessM;

  /// Толщина перекрытия, м.
  final double slabThicknessM;

  /// Тип фундамента (для согласования с КЖ).
  final FoundationType foundationType;

  const BuildingDimensions({
    required this.floors,
    required this.hasMansard,
    required this.hasBasement,
    required this.floorHeight,
    required this.basementHeight,
    required this.foundationDepth,
    required this.plinthHeight,
    required this.roofHeight,
    required this.slopeDeg,
    required this.roofShape,
    required this.wallThicknessM,
    required this.slabThicknessM,
    required this.foundationType,
  });

  /// Габариты здания на основе проекта и пятна (W×L в метрах).
  ///
  /// Для разрезов и фасадов передавайте размеры [FloorPlan]; для
  /// 3D-модели — `brief.footprintWidth/Length`. Это два разных пятна
  /// (план может быть L/T-формы), но высоты и глубины — общие.
  factory BuildingDimensions.of(
    HouseProject project, {
    required double widthM,
    required double lengthM,
  }) {
    final brief = project.brief;
    final floors = brief.floors ?? 1;
    final hasMansard = brief.hasMansard == true;
    final hasBasement = brief.hasBasement == true;

    // Высота этажа в свету: walls.height (если задана) →
    // staircase.floorHeight → 2.8 м (СП 55.13330.2017).
    final floorHeight = project.walls.height ??
        project.staircase.floorHeight ??
        2.8;

    final wallThickness =
        (project.walls.thickness ?? 400.0) / 1000.0;
    final slabThickness =
        (project.floorSlabs.thickness ?? 220.0) / 1000.0;

    // Тип и глубина фундамента + цоколь.
    final foundationType =
        project.foundation.type ?? FoundationType.strip;
    final maxSpan = math.max(widthM, lengthM);
    double depth;
    double plinthBase;
    switch (foundationType) {
      case FoundationType.slab:
        // Плита: толщина ≥ 0.20 м, или span/30 (округлено вверх).
        depth = math.max(0.20, _round05(maxSpan / 30));
        plinthBase = 0.20; // цокольная обвязка
        break;
      case FoundationType.strip:
        depth = 0.80;
        plinthBase = 0.40;
        break;
      case FoundationType.pile:
        depth = 2.50;
        plinthBase = 0.50;
        break;
      case FoundationType.pileWithGrillage:
        depth = 3.00;
        plinthBase = 0.50;
        break;
      case FoundationType.columnar:
        depth = 1.50;
        plinthBase = 0.50;
        break;
    }

    // Подвал: высота не менее 2.5 м (СП 54.13330), цоколь поднимается
    // на +1.0 м, чтобы цокольные окна оказались над землёй.
    final basementHeight = hasBasement ? math.max(floorHeight, 2.5) : 0.0;
    final plinthHeight =
        hasBasement ? plinthBase + 1.0 : plinthBase;
    final foundationDepth = hasBasement
        ? math.max(depth, basementHeight + 0.6)
        : depth;

    final slopeDeg = project.roof.slopeAngle ?? 30.0;
    final roofShape = RoofShape.fromTypeId(project.roof.type);
    final shortSide = math.min(widthM, lengthM);
    double roofHeight;
    switch (roofShape) {
      case RoofShape.flat:
        roofHeight = 0.30;
        break;
      case RoofShape.shed:
        roofHeight = shortSide * math.tan(slopeDeg * math.pi / 180.0);
        break;
      case RoofShape.gable:
      case RoofShape.hip:
      case RoofShape.mansard:
        roofHeight =
            (shortSide / 2) * math.tan(slopeDeg * math.pi / 180.0);
        break;
    }
    roofHeight = roofHeight.clamp(0.30, 5.00).toDouble();

    return BuildingDimensions(
      floors: floors,
      hasMansard: hasMansard,
      hasBasement: hasBasement,
      floorHeight: floorHeight,
      basementHeight: basementHeight,
      foundationDepth: foundationDepth,
      plinthHeight: plinthHeight,
      roofHeight: roofHeight,
      slopeDeg: slopeDeg,
      roofShape: roofShape,
      wallThicknessM: wallThickness,
      slabThicknessM: slabThickness,
      foundationType: foundationType,
    );
  }
}

double _round05(double v) => (v * 20).ceilToDouble() / 20;
