import 'dart:math' as math;

import 'package:cc_engine/cc_engine.dart';

import '../data/soil_types.dart';
import '../data/wall_materials.dart';
import '../models/client_brief.dart';
import '../models/floor_plan.dart';
import '../models/foundation.dart';
import '../models/foundation_plan.dart';
import '../models/house_project.dart';
import '../models/soil_layer.dart';
import 'composition_planner.dart';
import 'floor_plan_generator.dart';
import 'foundation_designer.dart';

/// Генератор плана фундамента: вход — проект, выход — модель
/// [FoundationPlanModel], в которой все размеры, оси и аннотации
/// получены из расчётов (`cc_engine`, [StripFootingDesigner],
/// [FoundationByTypeDesigner]) и геометрии плана 1-го этажа
/// ([FloorPlan] из [FloorPlanGenerator]).
///
/// Никаких «средних» цифр-заглушек: глубина, ширина подошвы, бетон,
/// армирование, шаг свай — всё взято из подбора по СП 22 / СП 24 / СП 63.
class FoundationPlanGenerator {
  FoundationPlanGenerator._();

  /// Возвращает `null`, если фундамент не выбран или ТЗ не заполнено
  /// настолько, чтобы определить геометрию.
  static FoundationPlanModel? generate(HouseProject project) {
    final brief = project.brief;
    final type = project.foundation.type;
    if (type == null) return null;
    if (brief.footprintWidth == null || brief.footprintLength == null) {
      return null;
    }
    final w = brief.footprintWidth!;
    final l = brief.footprintLength!;
    if (w <= 0 || l <= 0) return null;

    // 1. План 1-го этажа — нужен, чтобы понять расположение внутренних
    // несущих стен. Если ТЗ не позволяет сгенерировать план — работаем
    // только по периметру.
    final plans = FloorPlanGenerator.generate(brief);
    final firstFloor = plans.isNotEmpty ? plans.first : null;

    // 2. Расчётные параметры — нагрузки и подбор по типу.
    final calc = _computeFoundationParams(project, brief);

    // 3. Геометрия фундамента в зависимости от типа.
    final bands = <FoundationBand>[];
    FoundationSlab? slab;
    final piles = <FoundationPile>[];

    final internalWallLines = firstFloor != null
        ? _detectInternalLoadBearingWalls(firstFloor)
        : const <_WallLine>[];

    switch (type) {
      case FoundationType.strip:
        // Лента по периметру.
        bands.addAll(_perimeterBands(w, l, calc.bandThicknessM,
            kind: FoundationBandKind.external));
        // Лента под внутренними несущими стенами.
        for (final line in internalWallLines) {
          bands.add(FoundationBand(
            kind: FoundationBandKind.internal,
            x1: line.x1,
            y1: line.y1,
            x2: line.x2,
            y2: line.y2,
            thicknessM: calc.bandThicknessM,
          ));
        }
        break;
      case FoundationType.slab:
        slab = FoundationSlab(
          polygon: [
            const FoundationPoint(0, 0),
            FoundationPoint(w, 0),
            FoundationPoint(w, l),
            FoundationPoint(0, l),
          ],
          thicknessM: calc.bandThicknessM,
        );
        break;
      case FoundationType.columnar:
        // Столбы — в углах + с шагом по периметру + в пересечениях
        // с внутренними стенами.
        piles.addAll(_perimeterPiles(w, l, calc.spacingM, calc.elementDiamM));
        for (final line in internalWallLines) {
          piles.addAll(_pilesAlongLine(
              line.x1, line.y1, line.x2, line.y2, calc.spacingM, calc.elementDiamM));
        }
        // Перенумеровываем по порядку.
        for (var i = 0; i < piles.length; i++) {
          final p = piles[i];
          piles[i] = FoundationPile(
            x: p.x,
            y: p.y,
            diameterM: p.diameterM,
            label: 'Ст-${i + 1}',
          );
        }
        break;
      case FoundationType.pile:
        // Винтовые сваи: углы + по периметру + ряд под внутренними стенами.
        piles.addAll(_perimeterPiles(w, l, calc.spacingM, calc.elementDiamM));
        for (final line in internalWallLines) {
          piles.addAll(_pilesAlongLine(
              line.x1, line.y1, line.x2, line.y2, calc.spacingM, calc.elementDiamM));
        }
        for (var i = 0; i < piles.length; i++) {
          final p = piles[i];
          piles[i] = FoundationPile(
            x: p.x,
            y: p.y,
            diameterM: p.diameterM,
            label: 'СВ-${i + 1}',
          );
        }
        break;
      case FoundationType.pileWithGrillage:
        // Сваи + ростверк. Ростверк — лента по периметру и под внутренними
        // стенами (как у strip), сваи — точки под ростверком.
        bands.addAll(_perimeterBands(w, l, calc.bandThicknessM,
            kind: FoundationBandKind.grillage));
        for (final line in internalWallLines) {
          bands.add(FoundationBand(
            kind: FoundationBandKind.grillage,
            x1: line.x1,
            y1: line.y1,
            x2: line.x2,
            y2: line.y2,
            thicknessM: calc.bandThicknessM,
          ));
        }
        piles.addAll(_perimeterPiles(w, l, calc.spacingM, calc.elementDiamM));
        for (final line in internalWallLines) {
          piles.addAll(_pilesAlongLine(
              line.x1, line.y1, line.x2, line.y2, calc.spacingM, calc.elementDiamM));
        }
        for (var i = 0; i < piles.length; i++) {
          final p = piles[i];
          piles[i] = FoundationPile(
            x: p.x,
            y: p.y,
            diameterM: p.diameterM,
            label: 'С-${i + 1}',
          );
        }
        break;
    }

    // 4. Оси: буквы — горизонтальные линии (Y), цифры — вертикальные (X).
    final letterAxes = <FoundationAxis>[
      FoundationAxis(label: _letterLabel(0), position: 0),
    ];
    // Внутренние горизонтальные оси — Y-координаты внутренних
    // горизонтальных стен (тех, что параллельны оси X).
    final internalYs = <double>{};
    for (final line in internalWallLines) {
      if (line.isHorizontal) internalYs.add(line.y1);
    }
    final sortedYs = internalYs.toList()..sort();
    for (var i = 0; i < sortedYs.length; i++) {
      letterAxes.add(FoundationAxis(
        label: _letterLabel(i + 1),
        position: sortedYs[i],
      ));
    }
    letterAxes.add(FoundationAxis(
      label: _letterLabel(sortedYs.length + 1),
      position: l,
    ));

    final numericAxes = <FoundationAxis>[
      const FoundationAxis(label: '1', position: 0),
    ];
    final internalXs = <double>{};
    for (final line in internalWallLines) {
      if (line.isVertical) internalXs.add(line.x1);
    }
    final sortedXs = internalXs.toList()..sort();
    for (var i = 0; i < sortedXs.length; i++) {
      numericAxes.add(FoundationAxis(
        label: '${i + 2}',
        position: sortedXs[i],
      ));
    }
    numericAxes.add(FoundationAxis(
      label: '${sortedXs.length + 2}',
      position: w,
    ));

    // 5. Размерные цепочки.
    // С v38 — на всех 4-х сторонах (зеркально), чтобы заказчик не вертел
    // лист, чтобы прочитать размер на дальней стороне.
    final dimensionChains = <FoundationDimChain>[
      // Низ: цепочка между вертикальными осями (X).
      FoundationDimChain(
        side: FoundationDimSide.bottom,
        stops: numericAxes.map((a) => a.position).toList(),
        level: 1,
      ),
      // Низ: общий габарит.
      FoundationDimChain(
        side: FoundationDimSide.bottom,
        stops: [0, w],
        level: 2,
      ),
      // Верх: зеркало низа — оси и габарит.
      FoundationDimChain(
        side: FoundationDimSide.top,
        stops: numericAxes.map((a) => a.position).toList(),
        level: 1,
      ),
      FoundationDimChain(
        side: FoundationDimSide.top,
        stops: [0, w],
        level: 2,
      ),
      // Право: цепочка между горизонтальными осями (Y).
      FoundationDimChain(
        side: FoundationDimSide.right,
        stops: letterAxes.map((a) => a.position).toList(),
        level: 1,
      ),
      // Право: общий габарит.
      FoundationDimChain(
        side: FoundationDimSide.right,
        stops: [0, l],
        level: 2,
      ),
      // Лево: зеркало правого — оси и габарит.
      FoundationDimChain(
        side: FoundationDimSide.left,
        stops: letterAxes.map((a) => a.position).toList(),
        level: 1,
      ),
      FoundationDimChain(
        side: FoundationDimSide.left,
        stops: [0, l],
        level: 2,
      ),
    ];

    // 6. Аннотации с конкретными цифрами.
    final annotations = <FoundationAnnotation>[];
    final notes = <String>[];

    // Подпись типа фундамента — над планом.
    notes.add(calc.typeLabel);

    // Конкретные параметры — короткие строки, каждая с реальной цифрой.
    notes.addAll(calc.notes);

    // Глубина заложения / низ фундамента — на свободном поле плана как
    // отметка уровня.
    annotations.add(FoundationAnnotation(
      x: w + 0.2,
      y: l * 0.5,
      text: 'Низ фундамента: −${calc.depthM.toStringAsFixed(2)} м',
    ));

    return FoundationPlanModel(
      type: type,
      typeLabel: calc.typeLabel,
      buildingWidth: w,
      buildingLength: l,
      depthM: calc.depthM,
      footprintArea: w * l,
      bands: bands,
      slab: slab,
      piles: piles,
      horizontalAxes: letterAxes,
      verticalAxes: numericAxes,
      dimensionChains: dimensionChains,
      annotations: annotations,
      notes: notes,
      codeReferences: calc.codeReferences,
    );
  }

  // --------------------------------------------------------------------------
  // Расчётный блок: запускает cc_engine + StripFootingDesigner /
  // FoundationByTypeDesigner и возвращает реальные числа.
  // --------------------------------------------------------------------------
  static _CalcResult _computeFoundationParams(
    HouseProject project,
    ClientBrief brief,
  ) {
    final type = project.foundation.type!;
    final w = brief.footprintWidth!;
    final l = brief.footprintLength!;

    // 1. Грунт основания.
    final soil = _soilFromBrief(brief.soilLayers);

    // 2. Глубина промерзания по региону (та же таблица, что и
    // FoundationDesignPage._freezingDepthForRegion — тождественность
    // обеспечена единой функцией).
    final freezing = freezingDepthForRegion(brief.region);

    // 3. Снеговая/ветровая нагрузка → q (кН/м²).
    final loads = _computeLoads(project);
    final q = loads.totalVerticalKnPerM2;
    final perimeter = 2 * (w + l);
    // Учитываем 1 поперечную несущую стену — как и в FoundationDesignPage.
    final wallsLength = perimeter + brief.footprintWidth!;
    final area = w * l;

    final codeRefs = <String>{
      'СП 22.13330.2016',
      'СП 20.13330.2016',
      'СП 131.13330.2020',
    };

    String typeLabel;
    final notes = <String>[];
    double bandThicknessM = 0;
    double depthM = 0;
    double spacingM = 0;
    double elementDiamM = 0;

    switch (type) {
      case FoundationType.strip:
        // Если у дома есть подвал — лента должна быть заглублена под
        // пол подвала. Высота подвала: walls.height (если задана)
        // ИЛИ staircase.floorHeight ИЛИ 2.5 м по умолчанию. Подошва
        // ленты на 0.3 м ниже пола подвала (типовое решение по
        // СП 22.13330).
        final basementMinDepthM = brief.hasBasement == true
            ? (project.walls.height ??
                    project.staircase.floorHeight ??
                    2.5) +
                0.3
            : null;
        final design = StripFootingDesigner.design(
          verticalLoadKnPerM2: q,
          footprintAreaM2: area,
          loadBearingWallsPerimeterM: wallsLength,
          soilType: soil,
          freezingDepthM: freezing,
          minimumDepthM: basementMinDepthM,
        );
        typeLabel = 'Ленточный (монолитный)';
        bandThicknessM = design.widthM;
        depthM = design.depthM;
        notes.addAll([
          'Подошва b = ${(design.widthM * 1000).toStringAsFixed(0)} мм',
          'Высота ленты h = ${(design.heightM * 1000).toStringAsFixed(0)} мм',
          'Глубина заложения d = ${design.depthM.toStringAsFixed(2)} м '
              '(df = ${freezing.toStringAsFixed(1)} м, СП 131.13330.2020)',
          'Бетон ${design.concreteClass.title} '
              '(СП 63.13330.2018)',
          'Армирование продольное: ${design.longitudinalCount}⌀'
              '${design.longitudinalDiameterMm} ${design.longitudinalClass.title}',
          'Хомуты ⌀${design.stirrupDiameterMm} ${design.stirrupClass.title}, '
              'шаг ${design.stirrupSpacingMm} мм',
          'Грунт основания: ${soil.title}, R₀ = ${soil.r0KPa} кПа',
          'Расчётная вертикальная нагрузка q = '
              '${q.toStringAsFixed(2)} кН/м² '
              '(СП 20.13330.2016, постоянная + снег + полезная)',
        ]);
        codeRefs.add('СП 63.13330.2018');
        break;
      case FoundationType.slab:
        final res = FoundationByTypeDesigner.design(
          type: type,
          verticalLoadKnPerM2: q,
          footprintWidthM: w,
          footprintLengthM: l,
          soil: soil,
          freezingDepthM: freezing,
          brief: brief,
        );
        typeLabel = 'Плитный (монолитный)';
        // Толщина плиты — извлекаем из summary («Толщина плиты h»).
        final t = _findSummaryDouble(res, 'Толщина плиты') ?? 0.20;
        bandThicknessM = t;
        depthM = t;
        for (final entry in res.summary) {
          notes.add('${entry.$1}: ${entry.$2}');
        }
        codeRefs.addAll(res.codeReferences);
        break;
      case FoundationType.pile:
        final res = FoundationByTypeDesigner.design(
          type: type,
          verticalLoadKnPerM2: q,
          footprintWidthM: w,
          footprintLengthM: l,
          soil: soil,
          freezingDepthM: freezing,
          brief: brief,
        );
        typeLabel = 'Свайный (винтовые сваи)';
        final pileCount = _findSummaryInt(res, 'Количество свай') ?? 8;
        spacingM = perimeter / pileCount;
        if (spacingM < 1.0) spacingM = 1.0;
        elementDiamM = 0.108; // СВ-108
        depthM = _findSummaryDouble(res, 'Длина сваи') ?? 2.5;
        for (final entry in res.summary) {
          notes.add('${entry.$1}: ${entry.$2}');
        }
        codeRefs.addAll(res.codeReferences);
        break;
      case FoundationType.pileWithGrillage:
        final res = FoundationByTypeDesigner.design(
          type: type,
          verticalLoadKnPerM2: q,
          footprintWidthM: w,
          footprintLengthM: l,
          soil: soil,
          freezingDepthM: freezing,
          brief: brief,
        );
        typeLabel = 'Сваи с ростверком';
        final pileCount = _findSummaryInt(res, 'Количество свай') ?? 8;
        spacingM = perimeter / pileCount;
        if (spacingM < 1.5) spacingM = 1.5;
        elementDiamM = 0.30;
        bandThicknessM = 0.40; // ростверк 400×400
        depthM = _findSummaryDouble(res, 'Длина сваи') ?? 3.0;
        for (final entry in res.summary) {
          notes.add('${entry.$1}: ${entry.$2}');
        }
        codeRefs.addAll(res.codeReferences);
        break;
      case FoundationType.columnar:
        final res = FoundationByTypeDesigner.design(
          type: type,
          verticalLoadKnPerM2: q,
          footprintWidthM: w,
          footprintLengthM: l,
          soil: soil,
          freezingDepthM: freezing,
          brief: brief,
        );
        typeLabel = 'Столбчатый (монолитный)';
        spacingM = 2.5;
        elementDiamM = 0.40; // столб 400×400
        depthM = freezing + 0.1;
        for (final entry in res.summary) {
          notes.add('${entry.$1}: ${entry.$2}');
        }
        codeRefs.addAll(res.codeReferences);
        break;
    }

    // Рекомендация Composition Planner — отдельно отражаем в ноте.
    final recommended = CompositionPlanner.recommendedFoundationType(brief);
    if (recommended != type) {
      notes.add(
        'Авторекомендация: ${recommended.title}. '
        'Текущий выбор: ${type.title}.',
      );
    }

    return _CalcResult(
      typeLabel: typeLabel,
      depthM: depthM,
      bandThicknessM: bandThicknessM,
      spacingM: spacingM,
      elementDiamM: elementDiamM,
      notes: notes,
      codeReferences: codeRefs.toList(),
    );
  }

  // --------------------------------------------------------------------------
  // Вспомогательные функции.
  // --------------------------------------------------------------------------
  /// Внутренний расчёт нагрузок: используется ТОЛЬКО как fallback, если
  /// внешний код не передал готовый `FoundationLoadsResult`. Логика
  /// идентична `FoundationLoadsPage` — иначе нагрузки на чертеже КЖ
  /// не совпадут с расчётной запиской.
  static FoundationLoadsResult _computeLoads(HouseProject project) {
    final brief = project.brief;
    final snow = SnowRegion.byId(brief.snowZone ?? 3);
    final wind = WindRegion.byId(_parseWindZone(brief.windZone));
    // RoofShape — определяется по реальному углу самого пологого ската
    // (см. FoundationLoadsPage._detectRoofShape).
    final roofShape = _detectRoofShape(project);
    final roofSlopeDeg = _worstSlope(project);
    const terrain = TerrainType.b;
    final mainFloors = brief.floors ?? 1;
    // Подвал и мансарда добавляют свой вес: подвальное перекрытие и
    // мансардное перекрытие — каждое надо учесть как ещё один уровень
    // в нагрузке. Гараж — пристройка с собственным фундаментом, в общую
    // вертикальную нагрузку основного дома НЕ включаем (он считается
    // как смежный объект).
    final basementCount = brief.hasBasement == true ? 1 : 0;
    final mansardCount = brief.hasMansard == true ? 1 : 0;
    final floors = mainFloors + basementCount + mansardCount;
    // Высота этажа из проекта: walls.height → staircase.floorHeight → 2.8.
    final ceilingHeight = project.walls.height ??
        project.staircase.floorHeight ??
        2.8;
    // Подвал ниже уровня земли — высоту не прибавляем к надземной
    // высоте здания (она важна для ветра). Мансарда добавляет 1.0 м
    // (средняя высота мансардной стенки до карниза).
    final aboveGroundFloors = mainFloors + mansardCount;
    final buildingHeight = aboveGroundFloors * ceilingHeight +
        // запас на крышу: 0.5 м для плоских, угол·0.5·B иначе
        (roofShape == RoofShape.flatOrLowSlope ? 0.5 : 2.0);
    final walls = _wallsComponents(brief);
    final floorsComp = _floorsFromProject(project);
    final roofComp = _roofFromProject(project);

    return FoundationLoadsCalculator.compute(
      snowRegion: snow,
      windRegion: wind,
      roofShape: roofShape,
      roofSlopeDegrees: roofSlopeDeg,
      windTerrain: terrain,
      buildingHeight: buildingHeight,
      wallComponents: walls,
      floorComponents: floorsComp,
      roofComponents: roofComp,
      floors: floors,
    );
  }

  static List<WeightComponent> _wallsComponents(ClientBrief brief) {
    final m = brief.wallMaterial ?? WallMaterial.aerated;
    final key = switch (m) {
      WallMaterial.brick => 'walls_brick',
      WallMaterial.aerated => 'walls_aerated',
      WallMaterial.expandedClay => 'walls_brick', // ~ плотный блок
      WallMaterial.timber => 'walls_timber',
      WallMaterial.frame => 'walls_frame',
    };
    final c = PermanentLoadCalculator.defaults[key]!;
    return [c];
  }

  /// Перекрытие — по `floorSlabs.type` и фактической толщине
  /// (логика повторяет FoundationLoadsPage._floorsFromProject).
  static List<WeightComponent> _floorsFromProject(HouseProject p) {
    const defaults = PermanentLoadCalculator.defaults;
    final h = p.floorSlabs.thickness;
    WeightComponent base;
    double? scaledKn;
    String? origin;
    switch (p.floorSlabs.type) {
      case 'monolith':
        base = defaults['floor_monolith']!;
        if (h != null) {
          scaledKn = 25.0 * h / 1000;
          origin = 'Монолит ρ=25 кН/м³ · h=${h.toStringAsFixed(0)} мм';
        }
        break;
      case 'precast':
        base = defaults['floor_precast']!;
        if (h != null) {
          scaledKn = 14.0 * h / 1000;
          origin = 'ПК ρ_eff=14 кН/м³ · h=${h.toStringAsFixed(0)} мм';
        }
        break;
      case 'metal_beams':
        base = defaults['floor_metal_beams']!;
        if (h != null) {
          scaledKn = base.loadKnPerM2 * (h / 200);
          origin = 'Стальные балки + профнастил, h=${h.toStringAsFixed(0)} мм';
        }
        break;
      case 'wood_beams':
      default:
        base = defaults['floor_timber_joists']!;
        if (h != null) {
          scaledKn = base.loadKnPerM2 * (h / 200);
          origin = 'Деревянные балки, h=${h.toStringAsFixed(0)} мм';
        }
        break;
    }
    if (scaledKn != null && origin != null) {
      return [
        WeightComponent(
          id: base.id,
          title: '${base.title} · $h мм',
          loadKnPerM2: double.parse(scaledKn.toStringAsFixed(2)),
          origin: origin,
        ),
      ];
    }
    return [base];
  }

  /// Кровля — по `roof.roofingMaterial` (та же логика, что и
  /// FoundationLoadsPage._roofFromBrief).
  static List<WeightComponent> _roofFromProject(HouseProject p) {
    const defaults = PermanentLoadCalculator.defaults;
    final m = (p.roof.roofingMaterial ?? '').toLowerCase();
    if (m.contains('soft') || m.contains('бит') || m.contains('гибк')) {
      return [defaults['roof_soft_bitumen']!];
    }
    if (m.contains('clay') || m.contains('керам')) {
      return [defaults['roof_clay_tile']!];
    }
    return [defaults['roof_metal_tile']!];
  }

  /// Минимальный из углов скатов (консервативно — больший μ для снега).
  static double _worstSlope(HouseProject p) {
    final r = p.roof;
    if (r.slopeAngles.isNotEmpty) {
      return r.slopeAngles.reduce((a, b) => a < b ? a : b);
    }
    return r.slopeAngle ?? 30;
  }

  static RoofShape _detectRoofShape(HouseProject p) {
    final slope = _worstSlope(p);
    if (slope <= 30) return RoofShape.flatOrLowSlope;
    if (slope >= 60) return RoofShape.steep;
    return RoofShape.gable;
  }

  /// Конвертирует строковую метку ветрового района («II», «4», «iv»)
  /// в индекс таблицы [WindRegion] (0…7).
  static int _parseWindZone(String? raw) {
    if (raw == null) return 2;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 2;
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    const roman = {
      'iа': 0, 'ia': 0, '1а': 0, '1a': 0,
      'i': 1, '1': 1,
      'ii': 2, '2': 2,
      'iii': 3, '3': 3,
      'iv': 4, '4': 4,
      'v': 5, '5': 5,
      'vi': 6, '6': 6,
      'vii': 7, '7': 7,
    };
    return roman[s] ?? 2;
  }

  /// Маппинг между типом грунта в техническом задании (SoilType) и
  /// FoundationSoilType в cc_engine — соответствует
  /// foundation_design_page._soilFromBrief.
  static FoundationSoilType _soilFromBrief(List<SoilLayer> layers) {
    if (layers.isEmpty || layers.first.type == null) {
      return FoundationSoilType.loamStiff;
    }
    switch (layers.first.type!) {
      case SoilType.sand:
        return FoundationSoilType.sandMedium;
      case SoilType.sandyLoam:
        return FoundationSoilType.sandyLoamHard;
      case SoilType.loam:
        return FoundationSoilType.loamStiff;
      case SoilType.clay:
        return FoundationSoilType.clayStiff;
      case SoilType.peat:
        return FoundationSoilType.loamSoft;
      case SoilType.rock:
        return FoundationSoilType.sandGravel;
    }
  }

  /// Грубая оценка нормативной глубины промерзания по региону. Полностью
  /// соответствует функции в `foundation_design_page.dart`.
  static double freezingDepthForRegion(String? region) {
    if (region == null) return 1.4;
    final r = region.toLowerCase();
    if (r.contains('мурманск') ||
        r.contains('архангельск') ||
        r.contains('сургут')) {
      return 2.0;
    }
    if (r.contains('новосибирск') ||
        r.contains('екатеринбург') ||
        r.contains('пермь') ||
        r.contains('омск') ||
        r.contains('тюмень')) {
      return 1.8;
    }
    if (r.contains('москва') ||
        r.contains('казань') ||
        r.contains('челябинск') ||
        r.contains('самара')) {
      return 1.4;
    }
    if (r.contains('ростов') ||
        r.contains('волгоград') ||
        r.contains('краснодар') ||
        r.contains('сочи')) {
      return 0.8;
    }
    return 1.4;
  }

  static double? _findSummaryDouble(
      FoundationByTypeResult res, String key) {
    for (final entry in res.summary) {
      if (entry.$1.contains(key)) {
        final raw = entry.$2;
        // Парсим первое число из строки.
        final m = RegExp(r'(-?\d+[.,]?\d*)').firstMatch(raw);
        if (m == null) continue;
        final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        if (v == null) continue;
        if (raw.contains('мм')) return v / 1000;
        return v;
      }
    }
    return null;
  }

  static int? _findSummaryInt(FoundationByTypeResult res, String key) {
    for (final entry in res.summary) {
      if (entry.$1.contains(key)) {
        final m = RegExp(r'(\d+)').firstMatch(entry.$2);
        if (m != null) return int.tryParse(m.group(1)!);
      }
    }
    return null;
  }

  /// Буквенная маркировка осей: А, Б, В, Г, Д, Е, Ж, З, И, К, Л.
  static String _letterLabel(int index) {
    const letters = ['А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З', 'И', 'К', 'Л'];
    if (index < letters.length) return letters[index];
    return 'А${index - letters.length + 1}';
  }

  // --------------------------------------------------------------------------
  // Геометрия: ленты по периметру и расстановка свай.
  // --------------------------------------------------------------------------
  static List<FoundationBand> _perimeterBands(
    double w,
    double l,
    double thickness, {
    required FoundationBandKind kind,
  }) {
    return [
      // Верх (Y=0)
      FoundationBand(
        kind: kind,
        x1: 0,
        y1: 0,
        x2: w,
        y2: 0,
        thicknessM: thickness,
      ),
      // Низ (Y=l)
      FoundationBand(
        kind: kind,
        x1: 0,
        y1: l,
        x2: w,
        y2: l,
        thicknessM: thickness,
      ),
      // Лево (X=0)
      FoundationBand(
        kind: kind,
        x1: 0,
        y1: 0,
        x2: 0,
        y2: l,
        thicknessM: thickness,
      ),
      // Право (X=w)
      FoundationBand(
        kind: kind,
        x1: w,
        y1: 0,
        x2: w,
        y2: l,
        thicknessM: thickness,
      ),
    ];
  }

  static List<FoundationPile> _perimeterPiles(
    double w,
    double l,
    double spacing,
    double diameter,
  ) {
    final piles = <FoundationPile>[];
    // По 4 стенам — равномерно с шагом ≈ [spacing], плюс обязательно
    // углы.
    void distribute(
      double x1,
      double y1,
      double x2,
      double y2,
    ) {
      final dx = x2 - x1;
      final dy = y2 - y1;
      final lengthM = _hyp(dx, dy);
      if (lengthM == 0) return;
      final n = (lengthM / spacing).ceil().clamp(1, 100);
      for (var i = 0; i <= n; i++) {
        final t = i / n;
        piles.add(FoundationPile(
          x: x1 + dx * t,
          y: y1 + dy * t,
          diameterM: diameter,
        ));
      }
    }

    distribute(0, 0, w, 0); // верх
    distribute(w, 0, w, l); // право
    distribute(w, l, 0, l); // низ
    distribute(0, l, 0, 0); // лево

    // Дедупликация по координате (углы попадают дважды).
    final unique = <FoundationPile>[];
    for (final p in piles) {
      final dup = unique.any((q) =>
          (q.x - p.x).abs() < 0.01 && (q.y - p.y).abs() < 0.01);
      if (!dup) unique.add(p);
    }
    return unique;
  }

  static List<FoundationPile> _pilesAlongLine(
    double x1,
    double y1,
    double x2,
    double y2,
    double spacing,
    double diameter,
  ) {
    final lengthM = _hyp(x2 - x1, y2 - y1);
    if (lengthM == 0) return const [];
    final n = (lengthM / spacing).ceil().clamp(1, 100);
    final piles = <FoundationPile>[];
    // Без концевых точек (они попадают в periphery).
    for (var i = 1; i < n; i++) {
      final t = i / n;
      piles.add(FoundationPile(
        x: x1 + (x2 - x1) * t,
        y: y1 + (y2 - y1) * t,
        diameterM: diameter,
      ));
    }
    return piles;
  }

  static double _hyp(double a, double b) => math.sqrt(a * a + b * b);

  // --------------------------------------------------------------------------
  // Внутренние несущие стены — детектируются по плану 1-го этажа.
  //
  // Стена считается «несущей через всё здание», если она:
  //  • параллельна одной из осей (горизонтальная или вертикальная),
  //  • её начало совпадает с одним наружным краем, а конец — с другим
  //    (т. е. она тянется от одной стены до противоположной).
  // --------------------------------------------------------------------------
  static List<_WallLine> _detectInternalLoadBearingWalls(FloorPlan plan) {
    const eps = 0.02;
    final hLines = <double>{}; // Y-координаты горизонтальных внутренних стен
    final vLines = <double>{}; // X-координаты вертикальных внутренних стен

    // Внутренние ребра комнат, совпадающие с краями других комнат, дают
    // нам кандидатов на стены. Берём только те Y/X, которые встречаются
    // у разных комнат, исключая 0 и width/height (это наружные стены).
    final ys = <double>[];
    final xs = <double>[];
    for (final r in plan.rooms) {
      if (r.kind == PlanRoomKind.staircase) continue;
      ys.add(r.y);
      ys.add(r.y + r.height);
      xs.add(r.x);
      xs.add(r.x + r.width);
    }

    bool isExternal(double v, double size) =>
        v.abs() < eps || (v - size).abs() < eps;

    for (final y in ys) {
      if (isExternal(y, plan.height)) continue;
      // Проверим, что есть комната, у которой нижний край = y, и комната,
      // у которой верхний край = y, и совокупно они покрывают всю
      // ширину плана.
      if (_spansFullWidth(plan, y, eps)) hLines.add(_quant(y));
    }
    for (final x in xs) {
      if (isExternal(x, plan.width)) continue;
      if (_spansFullHeight(plan, x, eps)) vLines.add(_quant(x));
    }

    final result = <_WallLine>[];
    for (final y in hLines) {
      result.add(_WallLine(0, y, plan.width, y));
    }
    for (final x in vLines) {
      result.add(_WallLine(x, 0, x, plan.height));
    }
    return result;
  }

  static bool _spansFullWidth(FloorPlan plan, double y, double eps) {
    // Накапливаем интервалы по X на двух «сторонах» от y.
    final above = <(double, double)>[];
    final below = <(double, double)>[];
    for (final r in plan.rooms) {
      if (r.kind == PlanRoomKind.staircase) continue;
      if ((r.y + r.height - y).abs() < eps) {
        above.add((r.x, r.x + r.width));
      }
      if ((r.y - y).abs() < eps) {
        below.add((r.x, r.x + r.width));
      }
    }
    return _coversInterval(above, 0, plan.width, eps) &&
        _coversInterval(below, 0, plan.width, eps);
  }

  static bool _spansFullHeight(FloorPlan plan, double x, double eps) {
    final left = <(double, double)>[];
    final right = <(double, double)>[];
    for (final r in plan.rooms) {
      if (r.kind == PlanRoomKind.staircase) continue;
      if ((r.x + r.width - x).abs() < eps) {
        left.add((r.y, r.y + r.height));
      }
      if ((r.x - x).abs() < eps) {
        right.add((r.y, r.y + r.height));
      }
    }
    return _coversInterval(left, 0, plan.height, eps) &&
        _coversInterval(right, 0, plan.height, eps);
  }

  static bool _coversInterval(
      List<(double, double)> intervals, double from, double to, double eps) {
    if (intervals.isEmpty) return false;
    final sorted = [...intervals]..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = from;
    for (final iv in sorted) {
      if (iv.$1 > cursor + eps) return false;
      if (iv.$2 > cursor) cursor = iv.$2;
    }
    return (cursor - to).abs() < eps;
  }

  static double _quant(double v) => (v * 100).round() / 100;
}

class _CalcResult {
  final String typeLabel;
  final double depthM;
  final double bandThicknessM;
  final double spacingM;
  final double elementDiamM;
  final List<String> notes;
  final List<String> codeReferences;

  _CalcResult({
    required this.typeLabel,
    required this.depthM,
    required this.bandThicknessM,
    required this.spacingM,
    required this.elementDiamM,
    required this.notes,
    required this.codeReferences,
  });
}

class _WallLine {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const _WallLine(this.x1, this.y1, this.x2, this.y2);

  bool get isHorizontal => (y2 - y1).abs() < 0.01;
  bool get isVertical => (x2 - x1).abs() < 0.01;
}
