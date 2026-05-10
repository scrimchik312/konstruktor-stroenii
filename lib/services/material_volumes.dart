import 'dart:math' as math;

import '../models/floor_plan.dart';
import '../models/foundation.dart';
import '../models/foundation_plan.dart';
import '../models/house_project.dart';

/// Расчётные объёмы основных материалов на дом.
///
/// Все значения — это упрощённые «строительные» оценки для спецификации
/// (для ТЭП и сметы). Точные значения определяются рабочей документацией;
/// здесь — те же формулы, что используют ИЖС-сметчики:
///   * бетон: суммарный объём лент/плиты/свай;
///   * арматура: 90 кг/м³ бетона (типовой расход для ИЖС, СП 63);
///   * стены: периметр × высота этажа × этажность × толщина;
///   * крыша: пятно × коэффициент 1/cos(угол);
///   * утеплитель: периметр × высота × толщина (если каркас).
class MaterialVolumes {
  final double concreteVolumeM3;
  final double rebarMassKg;

  /// Объём НАРУЖНЫХ стен (несущих + забирка цоколя), м³.
  /// «Стеновой» материал в спецификации идёт сюда.
  final double wallVolumeM3;

  /// Чистая площадь наружных стен (за вычетом окон/дверей), м².
  final double wallAreaM2;

  /// Объём ВНУТРЕННИХ перегородок, м³ — отдельная позиция в
  /// спецификации, не должен совпадать с наружными.
  final double partitionVolumeM3;

  /// Площадь внутренних перегородок, м² (с учётом проёмов −12%).
  final double partitionAreaM2;

  final double roofAreaM2;
  final double insulationAreaM2;
  final double insulationVolumeM3;

  /// Перечень фактически используемых диаметров арматуры (мм).
  /// Для ИЖС-фундаментов — Ø10–14 (рабочая) и Ø6–8 (хомуты).
  final List<int> rebarDiametersMm;

  const MaterialVolumes({
    required this.concreteVolumeM3,
    required this.rebarMassKg,
    required this.wallVolumeM3,
    required this.wallAreaM2,
    required this.partitionVolumeM3,
    required this.partitionAreaM2,
    required this.roofAreaM2,
    required this.insulationAreaM2,
    required this.insulationVolumeM3,
    required this.rebarDiametersMm,
  });

  /// Считает объёмы материалов на основе текущего проекта.
  static MaterialVolumes compute(
    HouseProject project, {
    FoundationPlanModel? foundationPlan,
    List<FloorPlan>? floorPlans,
  }) {
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    // Этажность: основные этажи + мансарда + подвал. Раньше учитывались
    // только основные этажи, из-за чего объёмы стен и площади
    // отделки не покрывали верхний/нижний уровень. Гараж пристройкой —
    // учитывается отдельно (см. ниже).
    final mainFloors = (brief.floors ?? 1).clamp(1, 5);
    final hasMansard = brief.hasMansard == true;
    final hasBasement = brief.hasBasement == true;
    final hasGarage = brief.hasGarage == true;
    // «Стеновых» этажей — для умножения площади наружных стен и
    // перегородок: основные + мансарда (стены мансарды по фронтонам и
    // короткие до карниза в среднем 1.2 м, что эквивалентно ~0.5 этажа,
    // но для упрощения сметной оценки берём полный этаж — типичный
    // подход у ИЖС-сметчиков, расход материалов с запасом).
    final wallFloors =
        mainFloors + (hasMansard ? 1 : 0) + (hasBasement ? 1 : 0);
    final perimeter = 2 * (w + l);
    final footprint = w * l;
    // Гараж — пристройка. Для оценки: типовая площадь 18 м² (один авто),
    // 36 м² (два авто). Пользователь не задаёт размеры гаража отдельно;
    // берём 20 м² на каждый машиноместо (по умолчанию 1 м/м).
    const garageFootprint = 20.0; // м²
    const garagePerim = 18.0; // м (4.5 × 6 м габарит)
    final garageWalls = hasGarage ? garagePerim : 0.0;

    // 1) Бетон фундамента.
    var concreteM3 = 0.0;
    var rebarDiameters = <int>{};
    final foundationType = project.foundation.type;
    final fp = foundationPlan;
    if (fp != null) {
      switch (fp.type) {
        case FoundationType.strip:
        case FoundationType.pileWithGrillage:
          // Сумма (длина × ширина × высота) лент.
          // Высота ленты ≈ глубина заложения для strip, 0.4 м для ростверка.
          final bandHeight = fp.type == FoundationType.strip ? fp.depthM : 0.4;
          for (final b in fp.bands) {
            final dx = b.x2 - b.x1;
            final dy = b.y2 - b.y1;
            final len = math.sqrt(dx * dx + dy * dy);
            concreteM3 += len * b.thicknessM * bandHeight;
          }
          // Сваи в составе ростверка (буронабивные).
          if (fp.type == FoundationType.pileWithGrillage) {
            for (final p in fp.piles) {
              final r = p.diameterM / 2;
              concreteM3 += math.pi * r * r * fp.depthM;
            }
          }
          rebarDiameters.addAll([12, 8]);
          break;
        case FoundationType.slab:
          final slabT = fp.slab?.thicknessM ?? 0.3;
          concreteM3 += footprint * slabT;
          rebarDiameters.addAll([12, 14]);
          break;
        case FoundationType.columnar:
          for (final p in fp.piles) {
            final side = p.diameterM;
            // Столб квадратного сечения side×side, высотой depthM.
            concreteM3 += side * side * fp.depthM;
          }
          rebarDiameters.addAll([10, 6]);
          break;
        case FoundationType.pile:
          // Винтовые сваи — без бетона, только обвязка двутавром.
          break;
      }
    } else if (foundationType != null) {
      // Грубая оценка без плана.
      switch (foundationType) {
        case FoundationType.strip:
          concreteM3 = perimeter * 0.4 * 1.5; // 400 мм × 1.5 м глубина
          rebarDiameters.addAll([12, 8]);
          break;
        case FoundationType.slab:
          concreteM3 = footprint * 0.30;
          rebarDiameters.addAll([12, 14]);
          break;
        case FoundationType.pileWithGrillage:
          concreteM3 = perimeter * 0.4 * 0.4 + footprint * 0.05;
          rebarDiameters.addAll([12, 8]);
          break;
        case FoundationType.columnar:
          concreteM3 = math.max(8, perimeter / 2) * 0.4 * 0.4 * 1.6;
          rebarDiameters.addAll([10, 6]);
          break;
        case FoundationType.pile:
          break;
      }
    }

    // 2) Арматура — 90 кг/м³ бетона типовой расход для ИЖС
    // (СП 63.13330.2018, ВСН 32-77 для индивидуальных домов).
    final rebarKg = concreteM3 * 90;

    // 3) Стены — V = периметр × высота этажа × этажность × толщина.
    //
    // Этажность для стен (`wallFloors`) включает основные этажи,
    // подвал (если выбран) и мансарду (если выбрана). Гараж — пристройка
    // высотой 1 этаж, добавляется отдельно.
    final wallH = project.walls.height ?? 2.8;
    final wallT = (project.walls.thickness ?? 380) / 1000;
    final wallAreaSingle =
        perimeter * wallH * wallFloors + garageWalls * wallH;
    final wallVol = wallAreaSingle * wallT;
    // Площадь оконных проёмов вычитается ~12% от наружной стены (типовой
    // показатель остеклённости для жилых). У подвала остекление ~5 %,
    // у гаража 0 — но для упрощения берём общий коэффициент 0.88.
    final netWallArea = wallAreaSingle * 0.88;

    // 3a) Перегородки — внутренние стены. Если есть планы этажей —
    //     суммируем длину всех границ комнат, исключаем периметр (наружные
    //     стены) и делим на 2 (общие стены между комнатами учитываются
    //     дважды). Если планов нет — оцениваем как ~60 % от наружного
    //     периметра на каждый этаж (СП 54.13330: для типовой планировки
    //     отношение длины перегородок к периметру наружных стен ≈ 0.5–0.7).
    // Толщина внутренней несущей стены берётся из `WallsDesign`:
    // для кирпича 510 мм — 380 мм (1.5 кирпича); для прочих — 150 мм.
    // Это критично для спецификаций: 380 мм перегородки требуют почти
    // 2.5× больше материала, чем 150 мм блок.
    final partitionThicknessM = project.walls.partitionThicknessM;
    double partitionLen = 0;
    if (floorPlans != null && floorPlans.isNotEmpty) {
      for (final plan in floorPlans) {
        var totalRoomPerimeter = 0.0;
        for (final r in plan.rooms) {
          if (r.kind == PlanRoomKind.staircase ||
              r.kind == PlanRoomKind.free) continue;
          totalRoomPerimeter += 2 * (r.width + r.height);
        }
        // Периметр пятна — это наружные стены, их вычитаем.
        final outerP = 2 * (plan.width + plan.height);
        // Делим на 2: каждая внутренняя стена общая для двух комнат.
        final inner = math.max(0.0, (totalRoomPerimeter - outerP) / 2);
        partitionLen += inner;
      }
    }
    if (partitionLen <= 0) {
      // Нет планов — типовая оценка: 0.6 × наружный периметр на этаж.
      // Подвал и мансарда тоже имеют свои перегородки.
      partitionLen = perimeter * 0.6 * wallFloors;
    }
    final partitionAreaSingle = partitionLen * wallH;
    final partitionVol = partitionAreaSingle * partitionThicknessM;
    // Дверные проёмы перегородок — ~10 % площади.
    final partitionArea = partitionAreaSingle * 0.90;

    // 4) Крыша — пятно × коэффициент по уклону. Используем средний из
    // углов скатов (если задано). Для плоской — площадь = пятно.
    // К пятну прибавляем гараж (если он одного уровня и крыт общей
    // кровлей — типовой случай).
    final roofFootprint = footprint + (hasGarage ? garageFootprint : 0);
    var roofArea = roofFootprint;
    final roof = project.roof;
    if (roof.type != null && roof.type != 'flat') {
      double angle = 30; // по умолчанию
      if (roof.slopeAngles.isNotEmpty) {
        angle = roof.slopeAngles.reduce((a, b) => a + b) /
            roof.slopeAngles.length;
      } else if (roof.slopeAngle != null) {
        angle = roof.slopeAngle!;
      }
      final cosA = math.cos(angle * math.pi / 180);
      if (cosA > 0.1) {
        roofArea = roofFootprint / cosA;
      } else {
        roofArea = roofFootprint * 1.4;
      }
      // +5% на свесы.
      roofArea *= 1.05;
    }

    // 5) Утеплитель — для каркасных стен внутри стены. Толщина по СП 50
    // обычно 150-200 мм для ср. полосы (берём 150 мм = 0.15).
    var insulVol = 0.0;
    var insulArea = 0.0;
    if ((project.walls.material ?? brief.wallMaterial?.name) == 'frame') {
      insulArea = netWallArea;
      insulVol = netWallArea * 0.15;
    }

    // Если арматура для типа фундамента не определена — используем
    // типовой набор для ИЖС.
    if (rebarDiameters.isEmpty && concreteM3 > 0) {
      rebarDiameters.addAll([12, 8]);
    }

    final sortedDiameters = rebarDiameters.toList()..sort();

    return MaterialVolumes(
      concreteVolumeM3: concreteM3,
      rebarMassKg: rebarKg,
      wallVolumeM3: wallVol,
      wallAreaM2: netWallArea,
      partitionVolumeM3: partitionVol,
      partitionAreaM2: partitionArea,
      roofAreaM2: roofArea,
      insulationAreaM2: insulArea,
      insulationVolumeM3: insulVol,
      rebarDiametersMm: sortedDiameters,
    );
  }
}
