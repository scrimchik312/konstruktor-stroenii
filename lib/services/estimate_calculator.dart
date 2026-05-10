import 'dart:math' as math;

import '../data/price_catalog.dart';
import '../data/region_price_factors.dart';
import '../data/unit_conversions.dart';
import '../data/wall_materials.dart';
import '../models/estimate.dart';
import '../models/foundation.dart';
import '../models/house_project.dart';
import 'material_volumes.dart';

/// Расчёт «полной» сметы на ИЖС-проект.
///
/// Делает три вещи:
///   1) Достаёт из проекта все нужные **объёмы работ (ВОР)**:
///      • объём бетона/арматуры/опалубки по типу фундамента;
///      • объём кладки и количество блоков/кирпича по материалу стен;
///      • площадь перекрытий и стропильной системы;
///      • площадь кровли с поправкой на уклон;
///      • количество окон/дверей и площадь отделки.
///   2) Берёт **базовые цены** из [kPriceCatalog] и применяет
///      пользовательские правки (`priceOverrides`).
///   3) Применяет **региональный коэффициент** из
///      [regionFactorFor]. Регион определяется по `brief.region`.
///
/// Если данных проекта недостаточно (например, пользователь ещё не
/// указал материал стен) — соответствующий раздел остаётся пустым,
/// а смета выдаст ровно то, что можно посчитать корректно.
class EstimateCalculator {
  EstimateCalculator._();

  /// Главная точка входа — посчитать смету по проекту.
  static Estimate compute(HouseProject project) {
    final brief = project.brief;
    final overrides = project.priceOverrides;
    final unitOverrides = project.unitOverrides;
    final region = brief.region ?? '';
    final regionFactor = regionFactorFor(brief.region);

    final volumes = MaterialVolumes.compute(project);

    final rows = <EstimateRow>[
      ..._foundationRows(
          project, volumes, overrides, regionFactor, unitOverrides),
      ..._wallsRows(project, volumes, overrides, regionFactor, unitOverrides),
      ..._slabsRows(project, volumes, overrides, regionFactor, unitOverrides),
      ..._roofRows(project, volumes, overrides, regionFactor, unitOverrides),
      ..._engineeringRows(project, overrides, regionFactor, unitOverrides),
      ..._finishingRows(
          project, volumes, overrides, regionFactor, unitOverrides),
    ];

    return Estimate(
      rows: rows,
      region: region,
      regionFactor: regionFactor,
    );
  }

  // ─── ФУНДАМЕНТ ──────────────────────────────────────────────────
  static List<EstimateRow> _foundationRows(
    HouseProject project,
    MaterialVolumes vol,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final type = project.foundation.type;
    if (type == null) return out;

    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    if (w <= 0 || l <= 0) return out;
    final perimeter = 2 * (w + l);
    final footprint = w * l;

    switch (type) {
      case FoundationType.strip:
      case FoundationType.pileWithGrillage:
        if (vol.concreteVolumeM3 > 0) {
          out.add(_makeRow(
            'foundation_concrete_b25',
            quantity: vol.concreteVolumeM3,
            note: 'периметр ${perimeter.toStringAsFixed(1)} м · '
                'сечение ленты ~0.4×1.0 м (СП 22.13330.2016)',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          // Арматура — 90 кг/м³ бетона.
          out.add(_makeRow(
            'foundation_rebar_a500c',
            quantity: vol.rebarMassKg / 1000,
            note: 'расход 90 кг/м³ бетона (типовой ИЖС, СП 63.13330.2018)',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          // Опалубка — периметр × высота × 2 стороны.
          final formworkArea = perimeter * 1.0 * 2;
          out.add(_makeRow(
            'foundation_formwork',
            quantity: formworkArea,
            note: 'периметр × высота × 2 стороны',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          // ПГС подушка под лентой.
          final padArea = perimeter * 0.5; // 0.5 м шире ленты
          out.add(_makeRow(
            'foundation_sand_gravel_pad',
            quantity: padArea * 0.2, // 200 мм
            note: 'подушка 200 мм под лентой',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          out.add(_makeRow(
            'foundation_waterproofing',
            quantity: perimeter * 1.0,
            note: 'обмазка боковых граней ленты',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          out.add(_makeRow(
            'foundation_work_strip',
            quantity: vol.concreteVolumeM3,
            note: 'устройство ленты — по объёму бетона',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
        }
        if (type == FoundationType.pileWithGrillage) {
          // Прибавим оценку буронабивных свай: ~ 1 свая на 2.5 м периметра.
          final pileCount = (perimeter / 2.5).ceil() + 4;
          out.add(_makeRow(
            'foundation_bored_pile_d300',
            quantity: pileCount * 3.0,
            note: '$pileCount свай Ø300 × 3 м (по периметру с шагом 2.5 м)',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
        }
        break;

      case FoundationType.slab:
        out.add(_makeRow(
          'foundation_concrete_b25',
          quantity: vol.concreteVolumeM3,
          note: 'плита ${footprint.toStringAsFixed(1)} м² × '
              'толщина ~0.3 м (СП 22.13330)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'foundation_rebar_a500c',
          quantity: vol.rebarMassKg / 1000,
          note: 'двухсетчатое армирование Ø12, расход 90 кг/м³',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'foundation_sand_gravel_pad',
          quantity: footprint * 0.3,
          note: 'подушка 300 мм под плитой',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'foundation_waterproofing',
          quantity: footprint * 1.1,
          note: 'нижняя гидроизоляция плиты',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'foundation_work_slab',
          quantity: vol.concreteVolumeM3,
          note: 'устройство монолитной плиты',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;

      case FoundationType.columnar:
        if (vol.concreteVolumeM3 > 0) {
          out.add(_makeRow(
            'foundation_concrete_b25',
            quantity: vol.concreteVolumeM3,
            note: 'столбы 0.4×0.4×1.6 м по периметру',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
          out.add(_makeRow(
            'foundation_rebar_a500c',
            quantity: vol.rebarMassKg / 1000,
            note: 'каркасы Ø10 + хомуты Ø6',
            overrides: overrides,
            regionFactor: regionFactor,
            unitOverrides: unitOverrides,
          ));
        }
        break;

      case FoundationType.pile:
        // Винтовые сваи — без бетона.
        final pileCount = (perimeter / 2.5).ceil() + 4;
        out.add(_makeRow(
          'foundation_screw_pile_d108',
          quantity: pileCount.toDouble(),
          note: '$pileCount свай по периметру с шагом 2.5 м',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
    }
    return out;
  }

  // ─── СТЕНЫ ──────────────────────────────────────────────────────
  static List<EstimateRow> _wallsRows(
    HouseProject project,
    MaterialVolumes vol,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final brief = project.brief;
    final mat = WallMaterial.fromName(project.walls.material) ??
        brief.wallMaterial;
    if (mat == null || vol.wallVolumeM3 <= 0) return out;

    // Внутренние перегородки — оценочно, +30 % к площади наружных стен.
    final partitionsArea = vol.wallAreaM2 * 0.3;
    const partitionsThicknessM = 0.1; // 100 мм для внутренних
    final partitionsVolume = partitionsArea * partitionsThicknessM;

    switch (mat) {
      case WallMaterial.brick:
        // Кладка → штук кирпича: ~400 шт/м³ для одинарного полнотелого.
        final bricks = (vol.wallVolumeM3 + partitionsVolume) * 400;
        out.add(_makeRow(
          'wall_brick_solid',
          quantity: bricks,
          note: 'V = ${(vol.wallVolumeM3 + partitionsVolume).toStringAsFixed(1)} м³ '
              '× 400 шт/м³ (одинарный полнотелый, ГОСТ 530)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_masonry_mortar',
          quantity: (vol.wallVolumeM3 + partitionsVolume) * 0.25,
          note: 'расход 0.25 м³ раствора на 1 м³ кладки',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_masonry_mesh',
          quantity: vol.wallAreaM2 * 0.25,
          note: 'сетка через 4 ряда кладки (~25 % площади)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_work_masonry',
          quantity: vol.wallVolumeM3 + partitionsVolume,
          note: 'кладка по объёму',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;

      case WallMaterial.aerated:
        out.add(_makeRow(
          'wall_aerated_d500',
          quantity: vol.wallVolumeM3 + partitionsVolume,
          note: 'по объёму кладки',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_masonry_mortar',
          quantity: (vol.wallVolumeM3 + partitionsVolume) * 0.05,
          note: 'клей-пена для блоков, 0.05 м³ на 1 м³',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_work_masonry',
          quantity: vol.wallVolumeM3 + partitionsVolume,
          note: 'кладка блоков по объёму',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;

      case WallMaterial.expandedClay:
        out.add(_makeRow(
          'wall_expanded_clay_block',
          quantity: vol.wallVolumeM3 + partitionsVolume,
          note: 'по объёму кладки',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_masonry_mortar',
          quantity: (vol.wallVolumeM3 + partitionsVolume) * 0.18,
          note: 'раствор М100, 0.18 м³ на 1 м³ кладки',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_masonry_mesh',
          quantity: vol.wallAreaM2 * 0.20,
          note: 'сетка через 3 ряда (~20 % площади)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_work_masonry',
          quantity: vol.wallVolumeM3 + partitionsVolume,
          note: 'кладка по объёму',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;

      case WallMaterial.timber:
        out.add(_makeRow(
          'wall_timber_150',
          quantity: vol.wallVolumeM3,
          note: 'брус по объёму стен',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_work_timber',
          quantity: vol.wallVolumeM3,
          note: 'сборка стен из бруса',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;

      case WallMaterial.frame:
        // Стойки 50×150 + обвязка → ~0.04 м³ пиломатериала на 1 м² стены.
        final frameLumber = vol.wallAreaM2 * 0.04;
        out.add(_makeRow(
          'wall_frame_lumber_50x150',
          quantity: frameLumber,
          note: 'стойки + обвязка, 0.04 м³ на 1 м² стены',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_osb_12',
          quantity: vol.wallAreaM2 * 2,
          note: 'OSB-3 12 мм с обеих сторон каркаса',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_mineral_wool_100',
          quantity: vol.insulationAreaM2,
          note: 'утеплитель 150 мм в каркас (1.5 слоя × 100 мм)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_vapor_barrier',
          quantity: vol.wallAreaM2,
          note: 'изнутри по утеплителю',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_wind_membrane',
          quantity: vol.wallAreaM2,
          note: 'снаружи по утеплителю',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'wall_work_frame',
          quantity: vol.wallAreaM2,
          note: 'сборка каркаса по площади',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
    }
    return out;
  }

  // ─── ПЕРЕКРЫТИЯ ─────────────────────────────────────────────────
  static List<EstimateRow> _slabsRows(
    HouseProject project,
    MaterialVolumes vol,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    if (w <= 0 || l <= 0) return out;
    final footprint = w * l;
    final floors = (brief.floors ?? 1).clamp(1, 5);
    // Перекрытий: floors (ceiling каждого этажа). Если есть мансарда — +1.
    final slabCount = floors + (brief.hasMansard == true ? 0 : 0);
    final totalSlabArea = footprint * slabCount;
    if (totalSlabArea <= 0) return out;

    final slabType = project.floorSlabs.type;
    if (slabType == null) {
      // Тип не выбран — общий комплекс деревянное по балкам по умолчанию.
      out.add(_makeRow(
        'slab_wood_beam',
        quantity: totalSlabArea * 0.025,
        note: 'тип не задан — оценка как деревянное (0.025 м³/м²)',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      out.add(_makeRow(
        'slab_floor_sheathing',
        quantity: totalSlabArea,
        note: 'обшивка перекрытий',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      out.add(_makeRow(
        'slab_work_wood_beams',
        quantity: totalSlabArea,
        note: 'устройство по балкам',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      return out;
    }

    switch (slabType) {
      case 'monolith':
        final thicknessM = (project.floorSlabs.thickness ?? 200) / 1000.0;
        final concreteVol = totalSlabArea * thicknessM;
        out.add(_makeRow(
          'slab_monolith_concrete',
          quantity: concreteVol,
          note: '${totalSlabArea.toStringAsFixed(1)} м² × '
              '${thicknessM.toStringAsFixed(2)} м',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_monolith_rebar',
          quantity: concreteVol * 0.10,
          note: 'двойная сетка Ø12 — 100 кг/м³',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_work_monolith',
          quantity: totalSlabArea,
          note: 'устройство монолита по площади',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
      case 'precast':
        out.add(_makeRow(
          'slab_precast_pk',
          quantity: totalSlabArea,
          note: 'плиты ПК на этажи $slabCount × ${footprint.toStringAsFixed(1)} м²',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_work_precast',
          quantity: totalSlabArea,
          note: 'монтаж плит',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
      case 'wood_beams':
        out.add(_makeRow(
          'slab_wood_beam',
          quantity: totalSlabArea * 0.025,
          note: 'балки 100×200 с шагом 600 мм (~0.025 м³/м²)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_floor_sheathing',
          quantity: totalSlabArea,
          note: 'обшивка по балкам',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_work_wood_beams',
          quantity: totalSlabArea,
          note: 'устройство по балкам',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
      case 'metal_beams':
        // Двутавр 20Б1 ~21 кг/м, шаг 1.2 м → ~17.5 кг/м² → 0.0175 т/м².
        out.add(_makeRow(
          'slab_metal_beam',
          quantity: totalSlabArea * 0.0175,
          note: 'двутавр 20Б1 с шагом 1.2 м (~17.5 кг/м²)',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        out.add(_makeRow(
          'slab_floor_sheathing',
          quantity: totalSlabArea,
          note: 'обшивка по балкам',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
        break;
    }
    return out;
  }

  // ─── КРОВЛЯ ─────────────────────────────────────────────────────
  static List<EstimateRow> _roofRows(
    HouseProject project,
    MaterialVolumes vol,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final roof = project.roof;
    if (vol.roofAreaM2 <= 0 || roof.type == null) return out;

    final isFlat = roof.type == 'flat';
    if (!isFlat) {
      // Стропила — 0.04 м³/м² кровли (50×200 с шагом 600).
      out.add(_makeRow(
        'roof_rafter_lumber',
        quantity: vol.roofAreaM2 * 0.04,
        note: 'стропила 50×200, шаг 600 мм',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      // Обрешётка — 0.015 м³/м².
      out.add(_makeRow(
        'roof_lathing',
        quantity: vol.roofAreaM2 * 0.015,
        note: 'обрешётка 25×100, шаг 350 мм',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      out.add(_makeRow(
        'roof_underlay_membrane',
        quantity: vol.roofAreaM2,
        note: 'плёнка по площади ската',
        overrides: overrides,
        regionFactor: regionFactor,
        unitOverrides: unitOverrides,
      ));
      // Утеплитель только если есть мансарда (тёплое подкровельное).
      if (project.brief.hasMansard == true) {
        out.add(_makeRow(
          'roof_insulation_200',
          quantity: vol.roofAreaM2,
          note: 'утеплитель 200 мм в скаты',
          overrides: overrides,
          regionFactor: regionFactor,
          unitOverrides: unitOverrides,
        ));
      }
    }

    // Покрытие.
    final material = roof.roofingMaterial;
    String coverId;
    String coverNote;
    switch (material) {
      case 'tile':
      case 'clay':
        coverId = 'roof_clay_tile';
        coverNote = 'натуральная керамическая черепица';
        break;
      case 'soft':
      case 'bitumen':
        coverId = 'roof_soft_tile';
        coverNote = 'гибкая (битумная) черепица';
        break;
      case 'profiled':
      case 'corrugated':
        coverId = 'roof_corrugated_sheet';
        coverNote = 'профлист C20';
        break;
      case 'metal':
      default:
        coverId = 'roof_metal_tile';
        coverNote = 'металлочерепица';
        break;
    }
    out.add(_makeRow(
      coverId,
      quantity: vol.roofAreaM2,
      note: coverNote,
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));

    out.add(_makeRow(
      isFlat ? 'roof_work_flat' : 'roof_work_pitched',
      quantity: vol.roofAreaM2,
      note: isFlat ? 'устройство плоской' : 'устройство скатной',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    return out;
  }

  // ─── ИНЖЕНЕРНЫЕ СИСТЕМЫ ─────────────────────────────────────────
  static List<EstimateRow> _engineeringRows(
    HouseProject project,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    final floors = (brief.floors ?? 1).clamp(1, 5);
    final totalArea = w * l * floors;
    if (totalArea <= 0) return out;

    out.add(_makeRow(
      'eng_electrical',
      quantity: totalArea,
      note: 'на ${totalArea.toStringAsFixed(1)} м² общей',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'eng_heating_radiator',
      quantity: totalArea,
      note: 'радиаторное отопление, ${totalArea.toStringAsFixed(1)} м²',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'eng_ventilation',
      quantity: totalArea,
      note: 'приточно-вытяжная',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    // Сантехника — по комнатам с водой (кухни + санузлы).
    final kitchens = brief.rooms['kitchen'] ?? 1;
    final bathrooms = (brief.rooms['bathroom'] ?? 0) +
        (brief.rooms['toilet'] ?? 0);
    final waterPoints = math.max(2, kitchens * 2 + bathrooms * 3);
    out.add(_makeRow(
      'eng_water_supply',
      quantity: waterPoints.toDouble(),
      note: '$kitchens кухня(и) + $bathrooms санузел(ов) → $waterPoints точек',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    return out;
  }

  // ─── ОТДЕЛКА И ПРОЁМЫ ───────────────────────────────────────────
  static List<EstimateRow> _finishingRows(
    HouseProject project,
    MaterialVolumes vol,
    Map<String, double> overrides,
    double regionFactor,
    Map<String, String> unitOverrides,
  ) {
    final out = <EstimateRow>[];
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    final floors = (brief.floors ?? 1).clamp(1, 5);
    final totalArea = w * l * floors;
    if (totalArea <= 0) return out;

    final wallSurface = vol.wallAreaM2 + vol.wallAreaM2 * 0.6; // + перегородки
    out.add(_makeRow(
      'finish_plaster',
      quantity: wallSurface,
      note: 'наружные + внутренние стены',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'finish_putty',
      quantity: wallSurface + totalArea, // + потолки
      note: 'стены + потолки',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'finish_paint',
      quantity: wallSurface + totalArea,
      note: 'стены + потолки',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'finish_screed',
      quantity: totalArea,
      note: 'стяжка по площади полов',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    // Ламинат: 80 % площади. Плитка: 20 % (санузлы, кухни).
    out.add(_makeRow(
      'finish_floor_laminate',
      quantity: totalArea * 0.8,
      note: '~80 % полов — ламинат',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'finish_floor_tile',
      quantity: totalArea * 0.2,
      note: '~20 % полов — плитка (санузлы, кухня, прихожая)',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));

    // Окна — 12 % от наружной площади стены = vol.wallAreaM2 / 0.88 * 0.12.
    final outerWallTotal = vol.wallAreaM2 / 0.88; // нетто/(1-0.12)
    final windowArea = outerWallTotal * 0.12;
    out.add(_makeRow(
      'finish_window_pvc',
      quantity: windowArea,
      note: '12 % от площади наружных стен',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));

    // Двери внутренние — по числу комнат с дверями.
    final roomsWithDoor = (brief.rooms['bedroom'] ?? 0) +
        (brief.rooms['bathroom'] ?? 0) +
        (brief.rooms['toilet'] ?? 0) +
        (brief.rooms['kitchen'] ?? 0) +
        (brief.rooms['wardrobe'] ?? 0) +
        (brief.rooms['office'] ?? 0);
    final intDoors = math.max(3, roomsWithDoor);
    out.add(_makeRow(
      'finish_door_internal',
      quantity: intDoors.toDouble(),
      note: '$roomsWithDoor комнат с дверью',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));
    out.add(_makeRow(
      'finish_door_entry',
      quantity: 1,
      note: 'входная дверь',
      overrides: overrides,
      regionFactor: regionFactor,
      unitOverrides: unitOverrides,
    ));

    return out;
  }

  // ─── helpers ────────────────────────────────────────────────────
  static EstimateRow _makeRow(
    String id, {
    required double quantity,
    required Map<String, double> overrides,
    required double regionFactor,
    Map<String, String> unitOverrides = const {},
    String? note,
  }) {
    final item = findPriceItem(id);
    if (item == null) {
      throw StateError('Unknown price item id: $id');
    }
    // Применяем выбранную пользователем единицу измерения, если она
    // задана и валидна. Количество и цена пересчитываются через
    // factor так, чтобы итог по строке (qty × price) оставался
    // **физически тем же** (целостность сметы).
    final variant = findUnitVariant(item.id, unitOverrides[item.id]);
    final factor = (variant != null && variant.unit != item.unit)
        ? variant.perBase
        : 1.0;
    final displayUnit = variant?.unit ?? item.unit;
    final displayQty = quantity * factor;
    final displayBasePrice = factor == 0 ? item.basePrice : item.basePrice / factor;
    return EstimateRow(
      itemId: item.id,
      section: item.section,
      kind: item.kind,
      title: item.title,
      unit: displayUnit,
      baseUnit: item.unit,
      unitFactor: factor,
      quantity: _round(displayQty),
      basePrice: displayBasePrice,
      overridePrice: overrides[item.id],
      regionFactor: regionFactor,
      quantityNote: note,
      source: item.source,
    );
  }

  /// Округление количества до 2 знаков (для штук — до целого).
  static double _round(double v) {
    if (v >= 100) return double.parse(v.toStringAsFixed(0));
    if (v >= 10) return double.parse(v.toStringAsFixed(1));
    return double.parse(v.toStringAsFixed(2));
  }
}
