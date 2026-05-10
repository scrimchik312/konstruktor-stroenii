import '../data/soil_types.dart';
import '../data/wall_materials.dart';
import '../models/client_brief.dart';
import '../models/foundation.dart';
import '../models/foundation_design.dart';
import '../models/foundation_rationale.dart';
import '../models/roof_design.dart';
import '../models/soil_layer.dart';
import '../models/staircase_design.dart';
import '../models/walls_design.dart';

/// Результат подбора состава сооружения по техническому заданию.
///
/// Это «рекомендация» — то, что приложение предложит клиенту автоматически
/// и проектировщику в качестве отправной точки.
class CompositionPlan {
  final FoundationDesign foundation;
  final FoundationRationale foundationRationale;
  final WallsDesign walls;
  final RoofDesign roof;
  final StaircaseDesign staircase;
  final bool includesStaircase;
  final bool includesGarage;
  final bool includesTerrace;
  final bool includesBalcony;
  final bool includesOriel;
  final bool includesDoubleHeight;
  final bool includesBasement;
  final bool includesMansard;

  CompositionPlan({
    required this.foundation,
    required this.foundationRationale,
    required this.walls,
    required this.roof,
    required this.staircase,
    required this.includesStaircase,
    required this.includesGarage,
    required this.includesTerrace,
    required this.includesBalcony,
    required this.includesOriel,
    required this.includesDoubleHeight,
    required this.includesBasement,
    required this.includesMansard,
  });
}

/// Результат выбора фундамента вместе с обоснованием.
class _FoundationPick {
  final FoundationDesign design;
  final FoundationRationale rationale;
  const _FoundationPick(this.design, this.rationale);
}

/// Движок правил «техническое задание → состав сооружения».
///
/// Сейчас правила примитивные и иллюстративные. Когда мы будем углубляться
/// в нормативы (СП 22.13330.2016 «Основания зданий и сооружений», СП 50.13330.2024
/// «Тепловая защита» и т. п.), их можно усиливать без изменения остальных
/// слоёв приложения.
class CompositionPlanner {
  /// Рекомендованный тип фундамента по слоям грунта и параметрам здания
  /// (СП 22.13330.2016, СП 24.13330.2021, СП 50-101). Возвращает только сам тип —
  /// без deviceа/ростверка, чтобы UI выбора типа мог показывать стрелку
  /// на «лучшем» варианте, не привязываясь к остальным подвыборам.
  static FoundationType recommendedFoundationType(ClientBrief brief) =>
      _planFoundation(brief).design.type!;

  /// Рекомендованный фундамент целиком (тип + устройство + материал ростверка)
  /// с обоснованием по СП — для использования при автоплане и в подсказках.
  static ({FoundationDesign design, FoundationRationale rationale})
      recommendedFoundation(ClientBrief brief) {
    final pick = _planFoundation(brief);
    return (design: pick.design, rationale: pick.rationale);
  }

  static CompositionPlan plan(ClientBrief brief) {
    final pick = _planFoundation(brief);
    final walls = _planWalls(brief);
    final roof = _planRoof(brief);
    final staircase = StaircaseDesign(
      type: brief.requiresStaircase ? 'marsh' : null,
    );

    return CompositionPlan(
      foundation: pick.design,
      foundationRationale: pick.rationale,
      walls: walls,
      roof: roof,
      staircase: staircase,
      includesStaircase: brief.requiresStaircase,
      includesGarage: brief.hasGarage == true,
      includesTerrace: brief.hasTerrace == true,
      includesBalcony: brief.hasBalcony == true,
      includesOriel: brief.hasOriel == true,
      includesDoubleHeight: brief.hasDoubleHeight == true,
      includesBasement: brief.hasBasement == true,
      includesMansard: brief.hasMansard == true,
    );
  }

  static _FoundationPick _planFoundation(ClientBrief brief) {
    final layers = brief.soilLayers;
    final floors = brief.floors ?? 1;
    final heavyWalls = brief.wallMaterial == WallMaterial.brick ||
        brief.wallMaterial == WallMaterial.expandedClay;

    final hasPeatOnTop = _hasPeatInTop(layers);
    final peatThickness = _peatThicknessOnTop(layers);
    final bearing = _bearingLayer(layers);
    final weakBearing = bearing != null &&
        bearing.deformationModulus != null &&
        bearing.deformationModulus! < 5; // МПа, «слабый» грунт

    final items = <RationaleItem>[];
    items.add(_inputsRationale(brief, bearing));

    if (hasPeatOnTop) {
      // СП 22.13330.2016 п. 6.4: при заторфованном основании возможны
      // три варианта:
      //  1) торф ≤ 1.0 м и под ним прочный слой → выторфовка с заменой
      //     песчаной подушкой (200-300 мм); тип фундамента — плита.
      //  2) торф 1.0-2.0 м и под ним прочный слой → плита с песчаной
      //     подушкой увеличенной толщины ИЛИ буронабивные сваи с
      //     ростверком (выбор по экономике).
      //  3) торф > 2.0 м или под ним слабый слой → буронабивные сваи на
      //     прочный несущий горизонт (СП 24.13330.2021).
      final underPeatStrong = bearing != null &&
          bearing.type != SoilType.peat &&
          !(bearing.deformationModulus != null &&
              bearing.deformationModulus! < 8); // «прочный» по СП 22 п. 5.6
      if (peatThickness > 0 && peatThickness <= 1.0 && underPeatStrong) {
        items.add(RationaleItem(
          text: 'Торф мощностью ${peatThickness.toStringAsFixed(1)} м '
              '(≤ 1.0 м) подстилается прочным грунтом '
              '(${bearing.type?.name ?? 'песок/глина'}). '
              'По СП 22.13330.2016 п. 6.4 допускается выторфовка с заменой '
              'на песчаную подушку 300 мм с послойной трамбовкой и '
              'устройство монолитной железобетонной плиты.',
          codeReference: 'СП 22.13330.2016, п. 6.4; п. 5.10',
        ));
        return _FoundationPick(
          FoundationDesign(
            type: FoundationType.slab,
            device: FoundationDevice.monolithic,
          ),
          FoundationRationale(items: items),
        );
      }
      // Толщина > 2 м либо подстилающий слой слабый — однозначно сваи.
      items.add(RationaleItem(
        text: 'В верхних слоях присутствует торф мощностью '
            '${peatThickness.toStringAsFixed(1)} м — слабый биогенный грунт. '
            '${underPeatStrong ? 'Толщина торфяного слоя > 1 м' : 'Подстилающий слой также слабый'}, '
            'поэтому опирание поверхностных фундаментов недопустимо. '
            'Рекомендуются буронабивные сваи с монолитным ростверком, '
            'погружённые ниже торфяного горизонта.',
        codeReference: 'СП 22.13330.2016, п. 6.4 «Заторфованные грунты»; '
            'СП 24.13330.2021 «Свайные фундаменты»',
      ));
      _appendGroundwaterRationale(items, brief);
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.pileWithGrillage,
          device: FoundationDevice.boredPile,
          grillageMaterial: GrillageMaterial.monolithic,
        ),
        FoundationRationale(items: items),
      );
    }
    if (weakBearing) {
      items.add(RationaleItem(
        text: 'Модуль деформации несущего слоя '
            'E = ${bearing.deformationModulus!.toStringAsFixed(1)} МПа < 5 МПа — '
            'грунт считается слабым, опирание поверхностных фундаментов приведёт '
            'к недопустимым осадкам. Передаём нагрузку на более плотные слои '
            'буронабивными сваями.',
        codeReference:
            'СП 22.13330.2016, п. 5.5 (оценка деформационных свойств); '
                'СП 24.13330.2021',
      ));
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.pileWithGrillage,
          device: FoundationDevice.boredPile,
          grillageMaterial: GrillageMaterial.monolithic,
        ),
        FoundationRationale(items: items),
      );
    }
    final bearingType = bearing?.type ?? brief.soilType;
    if (bearingType == SoilType.rock) {
      items.add(const RationaleItem(
        text: 'Несущий слой — скальный грунт. Он имеет высокую несущую '
            'способность и слабо деформируется — рационально опирать здание '
            'точечно через столбчатые опоры.',
        codeReference: 'СП 22.13330.2016, п. 5.6 «Скальные грунты»',
      ));
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.columnar,
          device: FoundationDevice.monolithic,
        ),
        FoundationRationale(items: items),
      );
    }
    if (bearingType == SoilType.clay && (floors >= 2 || heavyWalls)) {
      items.add(RationaleItem(
        text: 'Несущий слой — глина при этажности $floors '
            'и ${heavyWalls ? 'тяжёлых' : 'стандартных'} стенах. '
            'Глинистые грунты склонны к неравномерным осадкам и пучинистости. '
            'Плитный фундамент равномерно распределяет нагрузку и снижает осадки.',
        codeReference: 'СП 22.13330.2016, п. 5.7 «Пылевато-глинистые '
            'грунты»; СП 22.13330.2016, п. 5.10 (плитные фундаменты)',
      ));
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.slab,
          device: FoundationDevice.monolithic,
        ),
        FoundationRationale(items: items),
      );
    }
    if (heavyWalls && floors >= 2) {
      items.add(RationaleItem(
        text: 'Тяжёлые каменные стены при $floors этажах дают высокую '
            'погонную нагрузку на основание. Широкое распределение этой нагрузки обеспечивает '
            'ленточный монолитный фундамент под всеми несущими стенами.',
        codeReference: 'СП 15.13330.2020 «Каменные и армокаменные '
            'конструкции»; СП 22.13330.2016',
      ));
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.strip,
          device: FoundationDevice.monolithic,
        ),
        FoundationRationale(items: items),
      );
    }
    if (brief.wallMaterial == WallMaterial.frame ||
        brief.wallMaterial == WallMaterial.timber) {
      items.add(const RationaleItem(
        text: 'Лёгкие стены (каркас/брус) дают малую нагрузку на основание. '
            'Винтовые сваи экономичнее ленты и не требуют мокрых процессов на площадке.',
        codeReference: 'СП 24.13330.2021 «Свайные фундаменты»; '
            'СП 64.13330.2017 «Деревянные конструкции»',
      ));
      return _FoundationPick(
        FoundationDesign(
          type: FoundationType.pile,
          device: FoundationDevice.screwPile,
        ),
        FoundationRationale(items: items),
      );
    }
    items.add(const RationaleItem(
      text: 'Нет специфических факторов (торф / слабый грунт / скала / '
          'тяжёлые стены). По умолчанию рекомендуется ленточный монолитный '
          'фундамент мелкого заложения под несущими стенами.',
      codeReference: 'СП 22.13330.2016 «Основания зданий и сооружений»',
    ));
    _appendGroundwaterRationale(items, brief);
    return _FoundationPick(
      FoundationDesign(
        type: FoundationType.strip,
        device: FoundationDevice.monolithic,
      ),
      FoundationRationale(items: items),
    );
  }

  /// Добавляет в обоснование пункт про учёт УГВ (если он задан).
  /// СП 22.13330.2016 п. 5.5.5 + п. 6.1.7:
  ///   • УГВ выше 1.5 м → нужна гидроизоляция оклеечная и дренаж;
  ///   • УГВ выше глубины промерзания → пучинистость грунта повышена,
  ///     ленту нужно либо заглублять ниже промерзания, либо
  ///     устраивать утеплённую отмостку;
  ///   • УГВ глубже 3 м → дополнительных мер не требуется.
  static void _appendGroundwaterRationale(
    List<RationaleItem> items,
    ClientBrief brief,
  ) {
    final ugv = brief.groundwaterLevelM;
    if (ugv == null) return;
    String text;
    if (ugv < 1.5) {
      text = 'УГВ ${ugv.toStringAsFixed(1)} м (выше 1.5 м от поверхности) — '
          'высокий. Необходимы оклеечная гидроизоляция боковых поверхностей '
          'фундамента, дренаж по периметру (СП 22.13330.2016 п. 6.1.7) и '
          'песчаная подушка с послойной трамбовкой.';
    } else if (ugv < 3.0) {
      text = 'УГВ ${ugv.toStringAsFixed(1)} м — средний. Требуется обмазочная '
          'гидроизоляция фундамента и устройство отмостки шириной не менее 1 м.';
    } else {
      text = 'УГВ ${ugv.toStringAsFixed(1)} м (глубже 3 м) — не оказывает '
          'влияния на фундамент мелкого заложения, дополнительные меры по '
          'водопонижению не требуются.';
    }
    items.add(RationaleItem(
      text: text,
      codeReference: 'СП 22.13330.2016, п. 5.5.5; п. 6.1.7',
    ));
  }

  /// Вводная сводка: что мы взяли за исходные данные.
  static RationaleItem _inputsRationale(
    ClientBrief brief,
    SoilLayer? bearing,
  ) {
    final parts = <String>[];
    parts.add('Этажность: ${brief.floors ?? 1}');
    if (brief.hasMansard == true) parts.add('мансарда');
    if (brief.hasBasement == true) parts.add('подвал');
    if (brief.wallMaterial != null) {
      parts.add('стены — ${brief.wallMaterial!.title.toLowerCase()}');
    }
    if (bearing?.type != null) {
      parts.add('несущий слой — ${bearing!.type!.title.toLowerCase()}');
    } else if (brief.soilType != null) {
      parts.add('грунт — ${brief.soilType!.title.toLowerCase()}');
    }
    return RationaleItem(
      text: 'Исходные данные: ${parts.join(', ')}.',
      codeReference: 'СП 47.13330.2016 «Инженерные изыскания для строительства»',
    );
  }

  /// Есть ли торф в верхних ~3 м (ориентировочная проверка).
  static bool _hasPeatInTop(List<SoilLayer> layers) {
    var depth = 0.0;
    for (final l in layers) {
      if (depth > 3) break;
      if (l.type == SoilType.peat) return true;
      depth += l.thickness ?? 0;
    }
    return false;
  }

  /// Суммарная мощность торфа в верхних слоях (от поверхности до первого
  /// неторфяного слоя). Если торф залегает не сверху — возвращает 0.
  static double _peatThicknessOnTop(List<SoilLayer> layers) {
    var sum = 0.0;
    for (final l in layers) {
      if (l.type == SoilType.peat) {
        sum += l.thickness ?? 0;
      } else {
        // Дошли до неторфяного слоя — прерываемся.
        if (sum > 0) break;
      }
    }
    return sum;
  }

  /// Несущий слой: первый сверху «non-weak» слой (не торф и не текучий).
  static SoilLayer? _bearingLayer(List<SoilLayer> layers) {
    for (final l in layers) {
      if (l.type == null) continue;
      if (l.type == SoilType.peat) continue;
      final il = l.liquidityIndex;
      if (il != null && il > 0.75) continue;
      return l;
    }
    return layers.isEmpty ? null : layers.first;
  }

  static WallsDesign _planWalls(ClientBrief brief) {
    final material = brief.wallMaterial;
    if (material == null) return WallsDesign();
    final thickness = _defaultThickness(material);
    return WallsDesign(
      material: material.name,
      thickness: thickness,
      height: 3.0,
    );
  }

  static double _defaultThickness(WallMaterial m) {
    switch (m) {
      case WallMaterial.brick:
        return 510;
      case WallMaterial.aerated:
        return 400;
      case WallMaterial.expandedClay:
        return 400;
      case WallMaterial.timber:
        return 200;
      case WallMaterial.frame:
        return 200;
    }
  }

  static RoofDesign _planRoof(ClientBrief brief) {
    final hasMansard = brief.hasMansard == true;
    return RoofDesign(
      type: hasMansard ? 'mansard' : 'gable',
      slopeAngle: hasMansard ? 45 : 30,
      roofingMaterial: 'metal',
    );
  }
}
