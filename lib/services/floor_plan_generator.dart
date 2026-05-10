import 'dart:math' as math;

import '../data/rooms_catalog.dart';
import '../data/wall_materials.dart';
import '../models/building_footprint.dart';
import '../models/client_brief.dart';
import '../models/floor_plan.dart';
import '../models/layout_scheme.dart';
import 'furniture/placement_engine.dart';

/// Генератор схематических планов этажей по техническому заданию.
///
/// Алгоритм:
///   1. Разворачиваем состав комнат («Спальня: 3» → три комнаты с типовыми
///      площадями).
///   2. Распределяем по этажам:
///        — 1-й этаж: общественная зона + прихожая (если её нет в техническом задании,
///          добавляется автоматически);
///        — 2..N этажи: приватная зона.
///      Если этажность > 1 (или есть мансарда/подвал) — на КАЖДЫЙ этаж
///      добавляется лестничный проём фиксированной площади.
///   3. Резервируем минимум 20 % площади пятна под свободную зону. Если
///      рассчитанные комнаты не помещаются в 80 % — масштабируем их вниз.
///      Остаток до 100 % забивается псевдо-комнатой «Свободная зона»,
///      чтобы slice-and-dice не «съедал» дырки между комнатами.
///   4. Slice-and-dice укладка: рекурсивно режем длинную сторону пятна
///      пропорционально весам.
class FloorPlanGenerator {
  /// Типовые площади помещений, м² (для частного дома).
  static const Map<RoomKind, double> _typicalArea = {
    RoomKind.bedroom: 14,
    RoomKind.bathroom: 5,
    RoomKind.kitchen: 12,
    RoomKind.livingRoom: 25,
    RoomKind.study: 12,
    RoomKind.hallway: 8,
    RoomKind.boilerRoom: 6,
    RoomKind.storage: 4,
    RoomKind.wardrobe: 4,
  };

  static const Set<RoomKind> _publicZone = {
    RoomKind.livingRoom,
    RoomKind.kitchen,
    RoomKind.hallway,
    RoomKind.boilerRoom,
    RoomKind.storage,
  };

  /// Минимальная доля свободного пространства от площади этажа.
  static const double _minFreeShare = 0.20;

  /// Типовые размеры лестничного проёма — фиксированы, чтобы
  /// лестница была в одном и том же месте на всех этажах (в реальности
  /// лестничный марш проходит через перекрытие в фиксированной точке).
  static const double _staircaseStripWidth = 3.0; // мин. ширина марша
  static const double _staircaseDepth = 4.0;

  /// Генерация плана этажей.
  ///
  /// [ceilingHeight] — высота этажа в метрах. Если задана и > 3.3 м,
  /// в комнатах с пролётом > 6 м автоматически расставляются колонны
  /// (СП 63.13330.2018). Если null или ≤ 3.3 м — колонны не нужны.
  static List<FloorPlan> generate(
    ClientBrief brief, {
    double? ceilingHeight,
    BuildingFootprint? footprint,
  }) {
    final width = brief.footprintWidth;
    final length = brief.footprintLength;
    if (width == null || length == null || width <= 0 || length <= 0) {
      return const [];
    }
    final floors = brief.floors ?? 1;
    final hasMansard = brief.hasMansard == true;
    // Manual override активен только если ХОТЯ БЫ ОДИН этаж имеет
    // непустую запись с положительным счётчиком. Иначе (карта только
    // из пустых под-карт — например, после неудачной попытки
    // включить ручной режим) — fallback к auto-распределению из
    // [brief.rooms], чтобы не игнорировать состав, указанный
    // пользователем.
    final hasManualOverride = brief.floorRooms.values
        .any((m) => m.values.any((v) => v > 0));
    final List<List<_RoomReq>> perFloor;
    final List<_RoomReq>? mansardRooms;
    if (hasManualOverride) {
      // Ручное распределение по этажам (п.8 handoff v37). Каждый этаж
      // получает ровно те комнаты, что указал пользователь.
      perFloor = <List<_RoomReq>>[];
      for (var f = 1; f <= floors; f++) {
        final raw = brief.floorRooms[ClientBrief.floorKey(f)] ?? const {};
        perFloor.add(_expandRoomsFromMap(raw));
      }
      // Без auto-_enforce/_ensureGround*: пользователь несёт
      // ответственность сам. Только клэмп санузлов — это безусловное
      // санитарное правило.
      for (final list in perFloor) {
        _enforceBathroomSizeRule(list);
      }
      if (hasMansard) {
        final raw =
            brief.floorRooms[ClientBrief.floorKey(0, mansard: true)] ??
                const {};
        mansardRooms = _expandRoomsFromMap(raw);
        _enforceBathroomSizeRule(mansardRooms);
      } else {
        mansardRooms = null;
      }
    } else {
      // Авто-распределение из общего списка комнат.
      final rooms = _withDefaults(_expandRooms(brief), brief);
      _enforceBathroomSizeRule(rooms);
      perFloor = _distributeByFloors(rooms, floors, brief: brief);
      // При этажности ≥3 на первом этаже должны быть: 1 кухня, 1 гостиная,
      // 1 санузел и 1 спальня — даже если пользователь не указал эти
      // комнаты в брифе или их распределили наверх.
      if (floors >= 3 && perFloor.isNotEmpty) {
        _ensureGroundFloorMandatoryRooms(perFloor);
      }
      mansardRooms = null;
    }
    final needsStaircase = brief.requiresStaircase;

    final plans = <FloorPlan>[];
    // П.9 v40: параметризованная генерация. Если задан planSeed,
    // перемешиваем порядок комнат внутри каждого этажа детерминированно
    // от seed — получится «другой вариант» того же ТЗ. Перемешиваются
    // только non-anchor комнаты; кухня/гостиная/санузел/прихожая
    // сохраняют приоритет (попадают в банк раньше «обычных»),
    // чтобы сохранить общую логику расстановки.
    final planSeed = brief.planSeed;
    void shuffleNonAnchors(List<_RoomReq> rs, math.Random rng) {
      // Anchors: bathroom/kitchen/livingRoom/boilerRoom — позиция важна
      // (мокрые точки и инженерные узлы у стояков). Остальные — спальни,
      // кладовые, кабинеты — можно перемешивать.
      final anchors = <_RoomReq>[];
      final others = <_RoomReq>[];
      for (final r in rs) {
        if (r.kind == RoomKind.bathroom ||
            r.kind == RoomKind.kitchen ||
            r.kind == RoomKind.livingRoom ||
            r.kind == RoomKind.boilerRoom) {
          anchors.add(r);
        } else {
          others.add(r);
        }
      }
      others.shuffle(rng);
      // Также перемешать anchors по типу — это меняет, какая стена
      // достанется кухне (правая/левая) при равной площади.
      anchors.shuffle(rng);
      rs
        ..clear()
        ..addAll([...anchors, ...others]);
    }

    for (var i = 0; i < perFloor.length; i++) {
      final floorRooms = perFloor[i];

      // Прихожая как отдельная комната больше не нужна — её роль играет начало
      // магистрального коридора.
      floorRooms.removeWhere((r) => r.kind == RoomKind.hallway);

      // Перемешиваем по seed (если задан).
      if (planSeed != null) {
        // Свой rng на каждый этаж, чтобы 1 и 2 этажи отличались.
        shuffleNonAnchors(floorRooms, math.Random(planSeed * 31 + i));
      }

      final layout = _layoutFloor(
        floorRooms,
        width,
        length,
        needsStaircase: needsStaircase,
        isFirstFloor: i == 0,
        scheme: brief.schemeForFloor(ClientBrief.floorKey(i + 1)),
      );
      // Правило 4: жилые помещения (спальни, гостиная) — на южной/юго-
      // восточной стороне. В нашей системе координат «юг» = низ плана
      // (WallSide.bottom). Свапаем roomKindName между парами комнат
      // близкой площади, если высокоприоритетная (жилая) сейчас на
      // севере, а низкоприоритетная (санузел/кладовая/котельная) — на
      // юге. Геометрия не меняется, только ярлыки.
      _postProcessSouthOrientation(layout, width, length);
      // Правило 7 — кухня ближе ко входу. Только на 1-м этаже, т. к.
      // вход в дом расположен только на нём.
      if (i == 0) {
        _postProcessKitchenNearEntry(layout, width, length);
      }
      // Правило 15 — кухня и гостиная рядом (или объединены).
      // Только на 1-м этаже: гостиная зона на первом, и эргономика
      // питания требует короткой связи между мокрыми точками
      // (СП 55.13330.2017 — функциональное зонирование).
      if (i == 0) {
        _postProcessKitchenLivingAdjacency(layout);
      }
      // Правило 8 — спальни не делят общую стену.
      _postProcessBedroomSeparation(layout, width, length);
      // Правило 16 — гардеробная рядом со спальней. Гардеробная
      // должна примыкать к спальне (доступ через спальню или общий
      // блок), это типовая планировочная связка для ИЖС.
      _postProcessWardrobeNearBedroom(layout);
      // Правило 9 — техпомещение (котельная) должно быть на наружном
      // контуре, чтобы получить отдельный вход с улицы (СП 60.13330,
      // СП 281.1325800.2016, п. 4.3 — котельная газовая обязательно
      // с обособленным наружным выходом).
      if (i == 0) {
        _postProcessBoilerRoomToOuter(layout, width, length);
      }
      // Правило 12 — модульная привязка габаритов к шагу
      // строительных материалов. Для каркаса (SIP/панели/стойки)
      // координаты слайсов снаппятся к 0.6 м (стандартная ширина
      // OSB-листа и шаг каркасных стоек). Для блочных/брусовых стен —
      // к 0.3 м (полублока). Каменные стены работают и так.
      _postProcessFrameModular(layout, width, length, brief.wallMaterial);
      final openings = _planOpenings(
        layout,
        width,
        length,
        isFirstFloor: i == 0,
        brief: brief,
      );
      final attachments = _planAttachments(
        brief: brief,
        rooms: layout,
        openings: openings,
        width: width,
        length: length,
        isFirstFloor: i == 0,
      );
      // Финальный пост-процессинг (п. 6 v44):
      //  • не более одного помещения с лейблом «Коридор» на этаж —
      //    лишние переименовываем в «Холл»;
      //  • любое помещение, помеченное санузлом (по kind или roomKindName),
      //    не должно быть больше 15 м² — даже если что-то ускользнуло
      //    от _enforceBathroomSizeRule на этапе площадей, на этом шаге
      //    мы режем геометрию.
      _postProcessSingleCorridor(layout);
      _postProcessBathroomCap(layout);
      final columns = _generateColumns(layout, ceilingHeight: ceilingHeight);
      plans.add(FloorPlan(
        floorLabel: 'Этаж ${i + 1}',
        width: width,
        height: length,
        rooms: layout,
        openings: openings,
        attachments: attachments,
        columns: columns,
      ));
    }

    if (hasMansard) {
      // Мансарда — отдельный «этаж». При ручном распределении используем
      // переданные комнаты (если их нет — мансарда остаётся пустой со
      // свободной зоной).
      final mansardList =
          mansardRooms ?? const <_RoomReq>[];
      final mansardWorking = List<_RoomReq>.from(mansardList)
        ..removeWhere((r) => r.kind == RoomKind.hallway);
      if (planSeed != null) {
        shuffleNonAnchors(mansardWorking,
            math.Random(planSeed * 31 + perFloor.length));
      }
      final layout = _layoutFloor(
        mansardWorking,
        width,
        length,
        needsStaircase: needsStaircase,
        isFirstFloor: false,
        scheme: brief.schemeForFloor(
          ClientBrief.floorKey(0, mansard: true),
        ),
      );
      _postProcessSouthOrientation(layout, width, length);
      // Мансарда — не первый этаж, кухню к входу не привязываем.
      _postProcessBedroomSeparation(layout, width, length);
      _postProcessWardrobeNearBedroom(layout);
      _postProcessFrameModular(layout, width, length, brief.wallMaterial);
      final openings = _planOpenings(
        layout,
        width,
        length,
        isFirstFloor: false,
        brief: brief,
      );
      _postProcessSingleCorridor(layout);
      _postProcessBathroomCap(layout);
      final columns = _generateColumns(layout, ceilingHeight: ceilingHeight);
      plans.add(FloorPlan(
        floorLabel: 'Мансарда',
        width: width,
        height: length,
        rooms: layout,
        openings: openings,
        columns: columns,
      ));
    }
    // Phase-1: автоматическая расстановка мебели в распознанных
    // комнатах (bedroom/livingRoom/kitchen/bathroom/...). Если у
    // комнаты не выставлен `roomKindName`, расстановщик её пропускает,
    // поэтому это безопасно для всех существующих сценариев.
    final withFurniture = <FloorPlan>[];
    for (final p in plans) {
      withFurniture.add(placeFurnitureForPlan(p));
    }
    // Phase-3b §17.2.1. Если задан полигональный footprint — обрезаем
    // комнаты/проёмы/колонны по контуру. Прямоугольный footprint
    // (или его отсутствие) оставляет план как есть.
    if (footprint != null && _isPolygonal(footprint, width, length)) {
      return [
        for (final p in withFurniture) _clipPlanToFootprint(p, footprint),
      ];
    }
    return withFurniture;
  }

  /// Является ли `footprint` нетривиально-полигональным (не равен
  /// прямоугольнику `width × length`).
  static bool _isPolygonal(
    BuildingFootprint footprint,
    double width,
    double length,
  ) {
    if (footprint.outline.length != 4) return true;
    final b = footprint.bbox;
    if ((b.width - width).abs() > 1e-3) return true;
    if ((b.height - length).abs() > 1e-3) return true;
    final corners = {
      (b.minX, b.minY),
      (b.maxX, b.minY),
      (b.maxX, b.maxY),
      (b.minX, b.maxY),
    };
    final got = {for (final p in footprint.outline) (p.x, p.y)};
    return !got.containsAll(corners);
  }

  /// Обрезка плана `plan` по полигональному пятну `footprint`:
  ///   * комнаты, чей геометрический центр оказался ВНЕ полигона —
  ///     удаляются (в L/T/U-формах это комнаты внутри выреза);
  ///   * проёмы, чей середина не лежит на/внутри полигона —
  ///     удаляются (внешние окна со срезанной стены);
  ///   * колонны вне полигона — удаляются;
  ///   * к плану цепляется `footprint`, чтобы рендер `_paintPlan`
  ///     отрисовал контур по нему.
  /// Топология сохранившихся комнат не меняется — мы НЕ ужимаем их
  /// прямоугольники, чтобы не ломать связи дверей и положение мебели.
  static FloorPlan _clipPlanToFootprint(
    FloorPlan plan,
    BuildingFootprint footprint,
  ) {
    bool insideFp(double x, double y) {
      // Учёт допуска: точки на самой границе полигона трактуем как
      // «внутри», иначе проёмы строго на наружной стене будут
      // отбрасываться.
      const eps = 1e-2;
      return footprint.contains(Vec2(x, y)) ||
          footprint.contains(Vec2(x - eps, y - eps)) ||
          footprint.contains(Vec2(x + eps, y + eps)) ||
          footprint.contains(Vec2(x - eps, y + eps)) ||
          footprint.contains(Vec2(x + eps, y - eps));
    }

    final newRooms = <PlanRoom>[
      for (final r in plan.rooms)
        if (insideFp(r.x + r.width / 2, r.y + r.height / 2)) r,
    ];
    final newOpenings = <PlanOpening>[
      for (final op in plan.openings)
        if (insideFp(
          op.side.isHorizontal ? op.x + op.length / 2 : op.x,
          op.side.isHorizontal ? op.y : op.y + op.length / 2,
        ))
          op,
    ];
    final newColumns = <PlanColumn>[
      for (final c in plan.columns)
        if (insideFp(c.x, c.y)) c,
    ];
    return plan.copyWith(
      rooms: newRooms,
      openings: newOpenings,
      columns: newColumns,
      footprint: footprint,
    );
  }

  /// Пост-обработка слоя комнат: оставляем не более одного помещения
  /// с лейблом, начинающимся на «Коридор». Лишние переименовываем
  /// в «Холл», что подразумевает «расширенный участок коридорной зоны»
  /// и не считается отдельным магистральным коридором (требование
  /// пользователя п. 6 — один коридор на этаж).
  static void _postProcessSingleCorridor(List<PlanRoom> rooms) {
    var seenCorridor = false;
    for (var i = 0; i < rooms.length; i++) {
      final r = rooms[i];
      if (r.kind != PlanRoomKind.free) continue;
      final lower = r.label.toLowerCase();
      if (!lower.startsWith('коридор')) continue;
      if (!seenCorridor) {
        seenCorridor = true;
        continue;
      }
      rooms[i] = PlanRoom(
        label: 'Холл',
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        area: r.area,
        kind: r.kind,
        roomKindName: r.roomKindName,
      );
    }
  }

  /// Пост-обработка слоя комнат: ни один санузел не может быть больше
  /// _bathroomMaxArea (15 м²) — жёсткое санитарно-планировочное
  /// требование (СП 55.13330.2017, п. 6.2 — санитарный узел не должен
  /// «съедать» жилой объём). Если PlanRoom больше — режем геометрию,
  /// освобождённую часть превращаем в «Холл» (свободная зона).
  static void _postProcessBathroomCap(List<PlanRoom> rooms) {
    final originalLen = rooms.length;
    final extras = <PlanRoom>[];
    for (var i = 0; i < originalLen; i++) {
      final r = rooms[i];
      final isBath = r.kind == PlanRoomKind.room &&
          r.roomKindName == RoomKind.bathroom.name;
      if (!isBath) continue;
      if (r.area <= _bathroomMaxArea + 0.01) continue;
      // Сохраняем пропорции санузла — режем подобно (sqrt-scale).
      final scale = _bathroomMaxArea / r.area;
      final linScale = math.sqrt(scale);
      final newW = r.width * linScale;
      final newH = r.height * linScale;
      final newArea = newW * newH;
      rooms[i] = PlanRoom(
        label: r.label,
        x: r.x,
        y: r.y,
        width: newW,
        height: newH,
        area: newArea,
        kind: r.kind,
        roomKindName: r.roomKindName,
      );
      // Освобождённое пространство — две прилегающие полосы (справа и
      // снизу от уменьшенного санузла), помечаем «Холл», чтобы план не
      // имел дырки и при этом не выглядел как ещё один коридор.
      final dW = r.width - newW;
      final dH = r.height - newH;
      if (dW > 0.2) {
        extras.add(PlanRoom(
          label: 'Холл',
          x: r.x + newW,
          y: r.y,
          width: dW,
          height: newH,
          area: dW * newH,
          kind: PlanRoomKind.free,
        ));
      }
      if (dH > 0.2) {
        extras.add(PlanRoom(
          label: 'Холл',
          x: r.x,
          y: r.y + newH,
          width: r.width,
          height: dH,
          area: r.width * dH,
          kind: PlanRoomKind.free,
        ));
      }
    }
    rooms.addAll(extras);
  }

  /// Правило 4: жилые помещения (спальни и гостиная) — на южной стороне
  /// (нижний край плана, [WallSide.bottom]). Свапаем `roomKindName` /
  /// `label` между парами комнат **близкой площади** (±25 %), если
  /// низкоприоритетная (санузел/котельная/кладовая) сейчас на южной
  /// стене, а высокоприоритетная (гостиная/спальня) — нет.
  ///
  /// Геометрия комнат не меняется — только их функциональное назначение.
  /// Это безопасно: окна, двери, площадь и материал отделки расставляются
  /// в `_planOpenings` уже после этого пост-процессинга по новому
  /// `roomKindName`.
  static void _postProcessSouthOrientation(
    List<PlanRoom> rooms,
    double planW,
    double planH,
  ) {
    if (rooms.isEmpty) return;

    int southPreference(String? roomKindName) {
      if (roomKindName == null) return 0;
      if (roomKindName == RoomKind.livingRoom.name) return 100;
      if (roomKindName == RoomKind.bedroom.name) return 80;
      if (roomKindName == RoomKind.study.name) return 50;
      if (roomKindName == RoomKind.kitchen.name) return 30;
      if (roomKindName == RoomKind.hallway.name) return 0;
      if (roomKindName == RoomKind.storage.name) return -60;
      if (roomKindName == RoomKind.wardrobe.name) return -40;
      if (roomKindName == RoomKind.bathroom.name) return -80;
      if (roomKindName == RoomKind.boilerRoom.name) return -100;
      return 0;
    }

    bool isSouthOuter(PlanRoom r) =>
        _isOuterWall(r, WallSide.bottom, planW, planH);

    bool sameAreaCompatible(PlanRoom a, PlanRoom b) {
      if (a.kind != PlanRoomKind.room) return false;
      if (b.kind != PlanRoomKind.room) return false;
      if (a.roomKindName == b.roomKindName) return false;
      final maxA = math.max(a.area, b.area);
      final minA = math.min(a.area, b.area);
      if (maxA <= 0) return false;
      return minA / maxA >= 0.75; // площади должны быть близкими (±25%)
    }

    // Итеративный обмен: повторяем пока есть улучшения. Ограничение
    // числа итераций защищает от бесконечного цикла на патологических
    // вводах.
    for (var iter = 0; iter < 6; iter++) {
      var swapped = false;
      for (var i = 0; i < rooms.length; i++) {
        for (var j = i + 1; j < rooms.length; j++) {
          final a = rooms[i];
          final b = rooms[j];
          if (!sameAreaCompatible(a, b)) continue;
          final aSouth = isSouthOuter(a);
          final bSouth = isSouthOuter(b);
          if (aSouth == bSouth) continue;
          final aPref = southPreference(a.roomKindName);
          final bPref = southPreference(b.roomKindName);
          // Свап нужен, если сейчас на юге сидит менее приоритетная.
          final shouldSwap = (aSouth && aPref < bPref) ||
              (bSouth && bPref < aPref);
          if (!shouldSwap) continue;
          // Обмениваем только roomKindName и label — координаты,
          // размер и kind (room/free/staircase) сохраняются.
          rooms[i] = a.copyWith(
            label: b.label,
            roomKindName: b.roomKindName,
          );
          rooms[j] = b.copyWith(
            label: a.label,
            roomKindName: a.roomKindName,
          );
          swapped = true;
        }
      }
      if (!swapped) break;
    }
  }

  /// Правило 7 — кухня по возможности ближе ко входу. После
  /// `_postProcessSouthOrientation` ярлыки кухни/спален/санузлов уже
  /// сидят «по ориентации»; теперь свапаем `kitchen` с любой не-жилой
  /// комнатой близкой площади (±30 %), которая ближе к
  /// предсказанному входу. Жилые (livingRoom/bedroom) НЕ трогаем,
  /// чтобы не сломать правило 4.
  static void _postProcessKitchenNearEntry(
    List<PlanRoom> rooms,
    double planW,
    double planH,
  ) {
    final entry = _predictEntryRoom(rooms, planW, planH);
    if (entry == null) return;
    final ex = entry.x + entry.width / 2;
    final ey = entry.y + entry.height / 2;
    double distToEntry(PlanRoom r) {
      final rx = r.x + r.width / 2;
      final ry = r.y + r.height / 2;
      final dx = rx - ex;
      final dy = ry - ey;
      return math.sqrt(dx * dx + dy * dy);
    }

    var kitchenIdx = -1;
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].roomKindName == RoomKind.kitchen.name) {
        kitchenIdx = i;
        break;
      }
    }
    if (kitchenIdx < 0) return;
    final kitchen = rooms[kitchenIdx];
    final kDist = distToEntry(kitchen);

    int bestIdx = -1;
    double bestDist = kDist;
    for (var i = 0; i < rooms.length; i++) {
      if (i == kitchenIdx) continue;
      final r = rooms[i];
      if (r.kind != PlanRoomKind.room) continue;
      final n = r.roomKindName;
      if (n == null) continue;
      if (n == RoomKind.kitchen.name) continue;
      // Не трогаем жилые (правило 4).
      if (n == RoomKind.livingRoom.name) continue;
      if (n == RoomKind.bedroom.name) continue;
      // Площади должны быть близкими (±30 %).
      final maxA = math.max(r.area, kitchen.area);
      final minA = math.min(r.area, kitchen.area);
      if (maxA <= 0 || minA / maxA < 0.7) continue;
      final d = distToEntry(r);
      if (d + 0.5 < bestDist) {
        // +0.5 м — чтобы не свапать ради микроулучшения и не пинг-понговать
        // с другими правилами.
        bestIdx = i;
        bestDist = d;
      }
    }
    if (bestIdx < 0) return;
    final candidate = rooms[bestIdx];
    rooms[kitchenIdx] = kitchen.copyWith(
      label: candidate.label,
      roomKindName: candidate.roomKindName,
    );
    rooms[bestIdx] = candidate.copyWith(
      label: kitchen.label,
      roomKindName: kitchen.roomKindName,
    );
  }

  /// Правило 8 — спальни не делят общую стену между собой
  /// (звукоизоляция). Если две спальни имеют общую стену длиной
  /// ≥ `_minSharedWallForDoor`, пытаемся свапнуть одну из них с
  /// не-спальней близкой площади, у которой нет смежной спальни.
  static void _postProcessBedroomSeparation(
    List<PlanRoom> rooms,
    double planW,
    double planH,
  ) {
    bool sharesWithOtherBedroom(int idx) {
      for (var k = 0; k < rooms.length; k++) {
        if (k == idx) continue;
        if (rooms[k].roomKindName != RoomKind.bedroom.name) continue;
        final sw = _sharedWall(rooms[idx], rooms[k]);
        if (sw != null && sw.length >= _minSharedWallForDoor) return true;
      }
      return false;
    }

    for (var iter = 0; iter < 4; iter++) {
      var swapped = false;
      for (var i = 0; i < rooms.length && !swapped; i++) {
        if (rooms[i].roomKindName != RoomKind.bedroom.name) continue;
        for (var j = i + 1; j < rooms.length && !swapped; j++) {
          if (rooms[j].roomKindName != RoomKind.bedroom.name) continue;
          final sw = _sharedWall(rooms[i], rooms[j]);
          if (sw == null) continue;
          if (sw.length < _minSharedWallForDoor) continue;
          // Спальни i и j соседствуют. Ищем кандидата на обмен с j.
          for (var k = 0; k < rooms.length; k++) {
            if (k == i || k == j) continue;
            final c = rooms[k];
            if (c.kind != PlanRoomKind.room) continue;
            final n = c.roomKindName;
            if (n == null) continue;
            // Свап с не-спальней. Жилые комнаты (livingRoom) и
            // санузлы — допустимы; спальню обменивать на спальню
            // бессмысленно.
            if (n == RoomKind.bedroom.name) continue;
            // Кандидат не должен сам граничить с другой спальней
            // (иначе после свапа у нас получится та же конфликтная
            // пара).
            if (sharesWithOtherBedroom(k)) continue;
            final maxA = math.max(c.area, rooms[j].area);
            final minA = math.min(c.area, rooms[j].area);
            if (maxA <= 0 || minA / maxA < 0.7) continue;
            final rj = rooms[j];
            final rk = rooms[k];
            rooms[j] = rj.copyWith(
              label: rk.label,
              roomKindName: rk.roomKindName,
            );
            rooms[k] = rk.copyWith(
              label: rj.label,
              roomKindName: rj.roomKindName,
            );
            swapped = true;
            break;
          }
        }
      }
      if (!swapped) break;
    }
  }

  /// Правило 9 — техпомещение (котельная) должно быть на наружном
  /// контуре, чтобы получить отдельный вход с улицы. Если котельная
  /// сейчас «зажата» внутри плана — свапаем её `roomKindName/label`
  /// с любой не-жилой комнатой близкой площади (±30 %), которая
  /// уже на внешнем контуре. Жилые (livingRoom/bedroom/kitchen) НЕ
  /// трогаются — у них свои нормативные требования.
  static void _postProcessBoilerRoomToOuter(
    List<PlanRoom> rooms,
    double planW,
    double planH,
  ) {
    var boilerIdx = -1;
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].roomKindName == RoomKind.boilerRoom.name) {
        boilerIdx = i;
        break;
      }
    }
    if (boilerIdx < 0) return;
    final boiler = rooms[boilerIdx];
    if (_hasOuterWall(boiler, planW, planH)) return; // уже OK

    int bestIdx = -1;
    double bestArea = double.infinity;
    for (var i = 0; i < rooms.length; i++) {
      if (i == boilerIdx) continue;
      final r = rooms[i];
      if (r.kind != PlanRoomKind.room) continue;
      final n = r.roomKindName;
      if (n == null) continue;
      if (n == RoomKind.boilerRoom.name) continue;
      // Не свапаем с жилыми — у них свои правила (4, 7) и
      // СП-нормативы.
      if (n == RoomKind.livingRoom.name) continue;
      if (n == RoomKind.bedroom.name) continue;
      if (n == RoomKind.kitchen.name) continue;
      if (n == RoomKind.study.name) continue;
      if (!_hasOuterWall(r, planW, planH)) continue;
      // Площади должны быть близкими (±30 %).
      final maxA = math.max(r.area, boiler.area);
      final minA = math.min(r.area, boiler.area);
      if (maxA <= 0 || minA / maxA < 0.7) continue;
      // Среди подходящих кандидатов берём **минимальный по площади**:
      // это, как правило, кладовая или санузел, которые не сильно
      // пострадают, если их «толкнуть» внутрь плана.
      if (r.area < bestArea) {
        bestIdx = i;
        bestArea = r.area;
      }
    }
    if (bestIdx < 0) return;
    final candidate = rooms[bestIdx];
    rooms[boilerIdx] = boiler.copyWith(
      label: candidate.label,
      roomKindName: candidate.roomKindName,
    );
    rooms[bestIdx] = candidate.copyWith(
      label: boiler.label,
      roomKindName: boiler.roomKindName,
    );
  }

  /// Правило 15 — кухня и гостиная должны быть рядом или объединены
  /// (стена общего длиной ≥ [_minSharedWallForDoor]). Это и
  /// функциональное зонирование (СП 55.13330.2017 — общая зона
  /// кухня/столовая/гостиная), и эргономика (короткая «треугольная»
  /// связь между сервировкой и зоной приёма пищи).
  ///
  /// Если кухня и гостиная сейчас не смежны, ищем кандидата на обмен:
  ///   1) c кухней — комнату ±40 % площади, которая граничит с гостиной;
  ///   2) если не вышло, c гостиной — комнату ±40 %, которая граничит
  ///      с кухней.
  /// В кандидаты допускаются спальни (правило 8 ниже починит, если
  /// возникнут смежные спальни) и кабинеты; санузлы и котельная
  /// исключены (правило 3 и правило 9). Меняем ярлык/тип, геометрия
  /// не меняется.
  static void _postProcessKitchenLivingAdjacency(List<PlanRoom> rooms) {
    var livingIdx = -1;
    var kitchenIdx = -1;
    for (var i = 0; i < rooms.length; i++) {
      final n = rooms[i].roomKindName;
      if (n == RoomKind.livingRoom.name && livingIdx < 0) livingIdx = i;
      if (n == RoomKind.kitchen.name && kitchenIdx < 0) kitchenIdx = i;
    }
    if (livingIdx < 0 || kitchenIdx < 0) return;
    final living = rooms[livingIdx];
    final kitchen = rooms[kitchenIdx];
    final sw0 = _sharedWall(living, kitchen);
    if (sw0 != null && sw0.length >= _minSharedWallForDoor) return;

    bool eligible(String? n) {
      if (n == null) return false;
      if (n == RoomKind.kitchen.name) return false;
      if (n == RoomKind.livingRoom.name) return false;
      if (n == RoomKind.bathroom.name) return false;
      if (n == RoomKind.boilerRoom.name) return false;
      if (n == RoomKind.wardrobe.name) return false;
      return true; // bedroom, study, hallway, storage — допустимы
    }

    bool tryDirection({required bool moveKitchen}) {
      final pivotIdx = moveKitchen ? kitchenIdx : livingIdx;
      final neighbourIdx = moveKitchen ? livingIdx : kitchenIdx;
      final pivot = rooms[pivotIdx];
      final neighbour = rooms[neighbourIdx];
      int bestIdx = -1;
      double bestSharedLen = 0;
      for (var i = 0; i < rooms.length; i++) {
        if (i == kitchenIdx || i == livingIdx) continue;
        final c = rooms[i];
        if (c.kind != PlanRoomKind.room) continue;
        if (!eligible(c.roomKindName)) continue;
        final maxA = math.max(c.area, pivot.area);
        final minA = math.min(c.area, pivot.area);
        if (maxA <= 0 || minA / maxA < 0.6) continue;
        final sw = _sharedWall(c, neighbour);
        if (sw == null || sw.length < _minSharedWallForDoor) continue;
        if (sw.length > bestSharedLen) {
          bestSharedLen = sw.length;
          bestIdx = i;
        }
      }
      if (bestIdx < 0) return false;
      final candidate = rooms[bestIdx];
      rooms[pivotIdx] = pivot.copyWith(
        label: candidate.label,
        roomKindName: candidate.roomKindName,
      );
      rooms[bestIdx] = candidate.copyWith(
        label: pivot.label,
        roomKindName: pivot.roomKindName,
      );
      return true;
    }

    if (tryDirection(moveKitchen: true)) return;
    tryDirection(moveKitchen: false);
  }

  /// Правило 16 — гардеробная (`RoomKind.wardrobe`) должна примыкать
  /// к спальне (общая стена ≥ [_minSharedWallForDoor]). Это типовая
  /// планировочная связка для ИЖС: проход в гардеробную идёт через
  /// спальню или общий «спальный блок».
  ///
  /// Если у гардеробной сейчас нет смежной спальни, ищем кандидата
  /// близкой площади (±30 %) среди не-спален, который сам граничит
  /// со спальней, и обмениваем ярлыки (как в правилах 7/8/9/15).
  static void _postProcessWardrobeNearBedroom(List<PlanRoom> rooms) {
    bool hasBedroomNeighbor(int idx) {
      for (var k = 0; k < rooms.length; k++) {
        if (k == idx) continue;
        if (rooms[k].roomKindName != RoomKind.bedroom.name) continue;
        final sw = _sharedWall(rooms[idx], rooms[k]);
        if (sw != null && sw.length >= _minSharedWallForDoor) return true;
      }
      return false;
    }

    for (var iter = 0; iter < 4; iter++) {
      var swapped = false;
      for (var i = 0; i < rooms.length && !swapped; i++) {
        if (rooms[i].roomKindName != RoomKind.wardrobe.name) continue;
        if (hasBedroomNeighbor(i)) continue;
        for (var k = 0; k < rooms.length && !swapped; k++) {
          if (k == i) continue;
          final c = rooms[k];
          if (c.kind != PlanRoomKind.room) continue;
          final n = c.roomKindName;
          if (n == null) continue;
          // Не свапаем со спальней — потеряем спальню. Не трогаем
          // кухню/гостиную (правило 15) и котельную (правило 9).
          // Санузлы тоже не трогаем — у них свои правила связности
          // (вход только из коридора/спальни). Ярлык «гардеробная»
          // ставим на маленький соседний слот: storage / hallway /
          // study / другая мелкая.
          if (n == RoomKind.bedroom.name) continue;
          if (n == RoomKind.kitchen.name) continue;
          if (n == RoomKind.livingRoom.name) continue;
          if (n == RoomKind.boilerRoom.name) continue;
          if (n == RoomKind.wardrobe.name) continue;
          if (n == RoomKind.bathroom.name) continue;
          // Кандидат должен сам граничить со спальней.
          if (!hasBedroomNeighbor(k)) continue;
          // Слот кандидата должен быть пригоден под гардеробную:
          // ≥ 3 м² (минимум для прохода и шкафа), ≤ 8 м² (иначе
          // комната «велика» и её жалко отдавать под гардеробную).
          if (c.area < 3 || c.area > 8) continue;
          final ri = rooms[i];
          final rk = rooms[k];
          rooms[i] = ri.copyWith(
            label: rk.label,
            roomKindName: rk.roomKindName,
          );
          rooms[k] = rk.copyWith(
            label: ri.label,
            roomKindName: ri.roomKindName,
          );
          swapped = true;
        }
      }
      if (!swapped) break;
    }
  }

  /// Правило 12 — модульная привязка габаритов к шагу строительных
  /// материалов. Для каркасных стен (SIP/панели/стойки) шаг 0.6 м —
  /// кратность ширине OSB-листа и шагу каркасных стоек. Для
  /// блочных/брусовых — 0.3 м (полублока/бруса 100 мм). Каменные
  /// (кирпич/керамзит) — без снэппинга, у них и так гибкий шаг.
  ///
  /// Алгоритм:
  ///   1. Собираем все уникальные X- и Y-координаты слайсов (стен между
  ///      комнатами).
  ///   2. Снэппим каждую внутреннюю координату к ближайшему кратному
  ///      шага. Внешний контур (0 и planW/H) и координаты лестницы не
  ///      трогаем — они задают пятно/ядро.
  ///   3. Применяем снэп ко всем комнатам и пересчитываем `area`.
  ///
  /// Если снэп выводит координату из допустимого окна (между соседями),
  /// для этой координаты снэп пропускается — лучше слегка нестандартный
  /// шаг, чем сломанная адъяцентность.
  static void _postProcessFrameModular(
    List<PlanRoom> rooms,
    double planW,
    double planH,
    WallMaterial? material,
  ) {
    if (material == null) return;
    double? step;
    switch (material) {
      case WallMaterial.frame:
        step = 0.6;
      case WallMaterial.timber:
        step = 0.3;
      case WallMaterial.aerated:
      case WallMaterial.expandedClay:
        step = 0.3;
      case WallMaterial.brick:
        step = null;
    }
    if (step == null || step <= 0) return;
    if (rooms.isEmpty) return;
    const eps = 0.05;
    final stepV = step;

    final xs = <double>{};
    final ys = <double>{};
    for (final r in rooms) {
      xs.add(r.x);
      xs.add(r.x + r.width);
      ys.add(r.y);
      ys.add(r.y + r.height);
    }

    // Координаты, которые НЕ снэппим: внешний контур (0, planW/H) и
    // координаты лестницы — она занимает фиксированную позицию.
    final lockedX = <double>{0, planW};
    final lockedY = <double>{0, planH};
    for (final r in rooms) {
      if (r.kind != PlanRoomKind.staircase) continue;
      lockedX.add(r.x);
      lockedX.add(r.x + r.width);
      lockedY.add(r.y);
      lockedY.add(r.y + r.height);
    }

    bool isLocked(Set<double> locked, double v) {
      for (final l in locked) {
        if ((v - l).abs() < eps) return true;
      }
      return false;
    }

    double? snapped(double v, Set<double> sortedAxis) {
      // Снэп к ближайшему кратному шагу.
      final n = (v / stepV).round();
      final s = n * stepV;
      // Не должен выходить за внешний контур.
      if (s < 0 || s > planW + eps && sortedAxis == xs) return null;
      // Минимально близко к исходному значению (не более 0.5*step).
      if ((s - v).abs() > stepV / 2 + eps) return null;
      return s;
    }

    final xMap = <double, double>{};
    for (final v in xs) {
      if (isLocked(lockedX, v)) {
        xMap[v] = v;
        continue;
      }
      final s = snapped(v, xs);
      xMap[v] = s ?? v;
    }
    final yMap = <double, double>{};
    for (final v in ys) {
      if (isLocked(lockedY, v)) {
        yMap[v] = v;
        continue;
      }
      final s = snapped(v, ys);
      yMap[v] = s ?? v;
    }

    double mapX(double v) {
      // Берём «точное» значение из карты по близости.
      double best = v;
      double bestD = double.infinity;
      xMap.forEach((k, mapped) {
        final d = (v - k).abs();
        if (d < bestD) {
          bestD = d;
          best = mapped;
        }
      });
      return best;
    }

    double mapY(double v) {
      double best = v;
      double bestD = double.infinity;
      yMap.forEach((k, mapped) {
        final d = (v - k).abs();
        if (d < bestD) {
          bestD = d;
          best = mapped;
        }
      });
      return best;
    }

    for (var i = 0; i < rooms.length; i++) {
      final r = rooms[i];
      // Лестницу не снэппим — она тогда «съедет» с проёма перекрытия.
      if (r.kind == PlanRoomKind.staircase) continue;
      final newX = mapX(r.x);
      final newY = mapY(r.y);
      final newRight = mapX(r.x + r.width);
      final newBottom = mapY(r.y + r.height);
      final newW = newRight - newX;
      final newH = newBottom - newY;
      // Если снэп схлопнул комнату до отрицательной/нулевой ширины —
      // оставляем оригинал, чтобы не получить мусорную геометрию.
      if (newW <= 0.5 || newH <= 0.5) continue;
      rooms[i] = r.copyWith(
        x: newX,
        y: newY,
        width: newW,
        height: newH,
        area: newW * newH,
      );
    }
  }

  /// Предсказывает, какая `free`/`hallway`-зона будет выбрана в
  /// `_planOpenings` под входную дверь — для правила 7. Логика
  /// совпадает с шагом 3 в `_planOpenings`.
  static PlanRoom? _predictEntryRoom(
    List<PlanRoom> rooms,
    double planW,
    double planH,
  ) {
    final cx = planW / 2;
    final cy = planH / 2;
    double centralDist(PlanRoom r) {
      final rx = r.x + r.width / 2;
      final ry = r.y + r.height / 2;
      final dx = rx - cx;
      final dy = ry - cy;
      return math.sqrt(dx * dx + dy * dy);
    }

    PlanRoom? entryRoom;
    var bestDist = double.infinity;
    var bestIsHallway = false;
    for (final r in rooms) {
      final isHallway = r.roomKindName == RoomKind.hallway.name;
      final isFree = r.kind == PlanRoomKind.free;
      if (!isHallway && !isFree) continue;
      if (!_hasOuterWall(r, planW, planH)) continue;
      final d = centralDist(r);
      final betterStatus = isHallway && !bestIsHallway;
      final equalStatus = isHallway == bestIsHallway;
      if (entryRoom == null ||
          betterStatus ||
          (equalStatus && d < bestDist)) {
        entryRoom = r;
        bestDist = d;
        bestIsHallway = isHallway;
      }
    }
    return entryRoom;
  }

  /// Расставляет колонны в комнатах с пролётом > 6 м, если высота этажа
  /// > 3.3 м (СП 63.13330.2018, табл. 7.1: при больших пролётах плиты
  /// перекрытия требуют дополнительной опоры).
  ///
  /// Алгоритм:
  ///   • [ceilingHeight] ≤ 3.3 м или null → колонны не нужны.
  ///   • Для каждой комнаты с w > 6 или h > 6:
  ///       - если w > 6: поделить пролёт по X на N+1 равных частей,
  ///         где N = ceil(w/6) - 1; поставить N колонн вдоль центра по Y;
  ///       - если h > 6: то же по Y;
  ///       - если оба > 6: создать сетку колонн.
  ///   • Сторона колонны 0.4 м (квадратная ж/б), маркировка «К».
  static List<PlanColumn> _generateColumns(
    List<PlanRoom> rooms, {
    double? ceilingHeight,
  }) {
    if (ceilingHeight == null || ceilingHeight <= 3.3) return const [];
    const double maxSpan = 6.0;
    const double colSize = 0.4;
    final out = <PlanColumn>[];
    var idx = 1;
    for (final r in rooms) {
      // Не ставим колонны в технических зонах: лестница, свободная зона
      // (коридор/прихожая/служебка) и в санузле — там колонна не уместна.
      if (r.kind == PlanRoomKind.staircase || r.kind == PlanRoomKind.free) {
        continue;
      }
      if (r.roomKindName == RoomKind.bathroom.name) {
        continue;
      }
      final w = r.width;
      final h = r.height;
      if (w <= maxSpan && h <= maxSpan) continue;
      final nx = w > maxSpan ? (w / maxSpan).ceil() - 1 : 1;
      final ny = h > maxSpan ? (h / maxSpan).ceil() - 1 : 1;
      // Регулярная сетка: nx × ny колонн внутри комнаты.
      for (var ix = 1; ix <= nx; ix++) {
        for (var iy = 1; iy <= ny; iy++) {
          // Если нет необходимости разбивать одну ось, ставим колонны
          // ровно по центру.
          final cx = nx == 1 && w <= maxSpan
              ? r.x + w / 2
              : r.x + (w * ix) / (nx + 1);
          final cy = ny == 1 && h <= maxSpan
              ? r.y + h / 2
              : r.y + (h * iy) / (ny + 1);
          out.add(PlanColumn(
            x: cx,
            y: cy,
            sizeM: colSize,
            label: 'К${idx++}',
          ));
        }
      }
    }
    return out;
  }

  /// Разворачивает `Map<RoomKind.name, count>` в плоский список запросов.
  static List<_RoomReq> _expandRoomsFromMap(Map<String, int> raw) {
    final out = <_RoomReq>[];
    for (final k in RoomKind.values.where((e) => e.userSelectable)) {
      final n = raw[k.name] ?? 0;
      for (var i = 0; i < n; i++) {
        out.add(_RoomReq(
          kind: k,
          label: n == 1 ? k.title : '${k.title} ${i + 1}',
          area: _typicalArea[k] ?? 10,
        ));
      }
    }
    return out;
  }

  static List<_RoomReq> _expandRooms(ClientBrief brief) {
    final out = <_RoomReq>[];
    for (final k in RoomKind.values.where((e) => e.userSelectable)) {
      final n = brief.rooms[k.name] ?? 0;
      for (var i = 0; i < n; i++) {
        out.add(_RoomReq(
          kind: k,
          label: n == 1 ? k.title : '${k.title} ${i + 1}',
          area: _typicalArea[k] ?? 10,
        ));
      }
    }
    return out;
  }

  /// Если пользователь не указал ни одной жилой комнаты — добавляем
  /// типовой состав по этажности.
  ///
  /// 1-этажный дом: 1 спальня + 1 кухня + 1 санузел + 1 гостиная
  /// (либо «квартира-студия», если выбрана схема [LayoutScheme.studio] —
  /// гостиная и кухня объединяются в один объём, хранятся раздельно,
  /// а в раскладке [_placeStudio] склеиваются).
  ///
  /// 2-этажный дом: 2 спальни (1 на каждом этаже) + 2 санузла +
  /// 1 кухня + 1 гостиная.
  ///
  /// 3+ этажей: дополнительно по 1 спальне на каждый этаж сверх второго.
  static List<_RoomReq> _withDefaults(
    List<_RoomReq> rooms,
    ClientBrief brief,
  ) {
    final hasResidential = rooms.any(
      (r) =>
          r.kind == RoomKind.bedroom ||
          r.kind == RoomKind.livingRoom ||
          r.kind == RoomKind.kitchen,
    );
    if (hasResidential) return rooms;
    final floors = (brief.floors ?? 1).clamp(1, 5);
    final defaults = <_RoomReq>[];
    if (floors == 1) {
      defaults.add(_make(RoomKind.bedroom, 'Спальня'));
      defaults.add(_make(RoomKind.kitchen, 'Кухня'));
      defaults.add(_make(RoomKind.bathroom, 'Санузел'));
      defaults.add(_make(RoomKind.livingRoom, 'Гостиная'));
    } else {
      // 2 спальни (по одной на 1-й и 2-й этаж — распределение в
      // _distributeByFloors), 2 санузла, 1 кухня, 1 гостиная.
      defaults.add(_make(RoomKind.bedroom, 'Спальня 1'));
      defaults.add(_make(RoomKind.bedroom, 'Спальня 2'));
      defaults.add(_make(RoomKind.bathroom, 'Санузел 1'));
      defaults.add(_make(RoomKind.bathroom, 'Санузел 2'));
      defaults.add(_make(RoomKind.kitchen, 'Кухня'));
      defaults.add(_make(RoomKind.livingRoom, 'Гостиная'));
      for (var i = 3; i <= floors; i++) {
        defaults.add(_make(RoomKind.bedroom, 'Спальня этажа $i'));
      }
    }
    return [...rooms, ...defaults];
  }

  static _RoomReq _make(RoomKind kind, String label) => _RoomReq(
        kind: kind,
        label: label,
        area: _typicalArea[kind] ?? 10,
      );

  /// Жёсткое ограничение площади санузлов, кладовых, котельных.
  ///
  /// 1) Абсолютный порог: санузел ≤ 15 м² (требование п. 6 handoff v37).
  ///    Независимо от того, что указал пользователь в ТЗ.
  /// 2) Относительный порог (СП 55.13330.2017 п. 6.2): площадь
  ///    санузла/кладовой/котельной ≤ 60 % наименьшей жилой/кухонной
  ///    комнаты (но не менее 3 м²).
  static const double _bathroomMaxArea = 15.0;

  static void _enforceBathroomSizeRule(List<_RoomReq> rooms) {
    if (rooms.isEmpty) return;
    // 1) Абсолютный клэмп для санузлов.
    for (var i = 0; i < rooms.length; i++) {
      final r = rooms[i];
      if (r.kind == RoomKind.bathroom && r.area > _bathroomMaxArea) {
        rooms[i] = _RoomReq(
          kind: r.kind,
          label: r.label,
          area: _bathroomMaxArea,
        );
      }
    }
    // 2) Относительный клэмп для всех сервисных помещений.
    double minLivingKitchen = double.infinity;
    for (final r in rooms) {
      if (r.kind == RoomKind.bedroom ||
          r.kind == RoomKind.livingRoom ||
          r.kind == RoomKind.kitchen ||
          r.kind == RoomKind.study) {
        if (r.area < minLivingKitchen) minLivingKitchen = r.area;
      }
    }
    if (minLivingKitchen.isInfinite) return;
    final cap = math.max(3.0, minLivingKitchen * 0.6);
    for (var i = 0; i < rooms.length; i++) {
      final r = rooms[i];
      final isService = r.kind == RoomKind.bathroom ||
          r.kind == RoomKind.storage ||
          r.kind == RoomKind.boilerRoom;
      if (!isService) continue;
      if (r.area > cap) {
        rooms[i] = _RoomReq(
          kind: r.kind,
          label: r.label,
          area: cap,
        );
      }
    }
  }

  static List<List<_RoomReq>> _distributeByFloors(
    List<_RoomReq> rooms,
    int floors, {
    ClientBrief? brief,
  }) {
    if (floors <= 1) return [List.of(rooms)];
    final ground = <_RoomReq>[];
    final upstairs = <_RoomReq>[];
    for (final r in rooms) {
      if (_publicZone.contains(r.kind)) {
        ground.add(r);
      } else {
        upstairs.add(r);
      }
    }
    if (floors == 2) {
      // Гарантируем, что хотя бы одна спальня и один санузел остаются
      // на 1-м этаже (СП 55.13330.2017 рекомендует располагать на
      // первом этаже комнату для людей с ограниченной мобильностью).
      _ensureGroundDuplicate(ground, upstairs, RoomKind.bedroom);
      _ensureGroundDuplicate(ground, upstairs, RoomKind.bathroom);
      return [ground, upstairs];
    }
    final extras = floors - 1;
    final slices = List<List<_RoomReq>>.generate(extras, (_) => <_RoomReq>[]);
    for (var i = 0; i < upstairs.length; i++) {
      slices[i % extras].add(upstairs[i]);
    }
    return [ground, ...slices];
  }

  /// Перекидывает одну комнату нужного типа с верхних этажей на 1-й,
  /// если на 1-м её нет, а наверху таких ≥2.
  static void _ensureGroundDuplicate(
    List<_RoomReq> ground,
    List<_RoomReq> upstairs,
    RoomKind kind,
  ) {
    final hasOnGround = ground.any((r) => r.kind == kind);
    if (hasOnGround) return;
    final upstairsCount = upstairs.where((r) => r.kind == kind).length;
    if (upstairsCount >= 2) {
      // Перекидываем одну на 1-й этаж.
      final idx = upstairs.indexWhere((r) => r.kind == kind);
      if (idx >= 0) {
        ground.add(upstairs.removeAt(idx));
      }
    } else if (upstairsCount == 0) {
      // Если такого типа вообще нет — добавляем новую (типовой минимум).
      ground.add(_make(kind, kind.title));
    }
  }

  /// Гарантирует наличие на первом этаже: 1 кухни, 1 гостиной, 1 санузла,
  /// 1 спальни. Применяется только для домов с ≥3 этажами. Если нужной
  /// комнаты нет на первом этаже — сперва забираем с других этажей,
  /// иначе добавляем новую комнату типовой площади.
  static void _ensureGroundFloorMandatoryRooms(
    List<List<_RoomReq>> perFloor,
  ) {
    const required = <RoomKind>[
      RoomKind.kitchen,
      RoomKind.livingRoom,
      RoomKind.bathroom,
      RoomKind.bedroom,
    ];
    final ground = perFloor.first;
    for (final rk in required) {
      final hasOnGround = ground.any((r) => r.kind == rk);
      if (hasOnGround) continue;
      // Ищем на верхних этажах.
      _RoomReq? moved;
      for (var i = 1; i < perFloor.length; i++) {
        final idx = perFloor[i].indexWhere((r) => r.kind == rk);
        if (idx >= 0) {
          moved = perFloor[i].removeAt(idx);
          break;
        }
      }
      if (moved != null) {
        ground.add(moved);
      } else {
        ground.add(_RoomReq(
          kind: rk,
          label: rk.title,
          area: _typicalArea[rk] ?? 10,
        ));
      }
    }
  }

  /// Подготавливаем раскладку этажа. Лестница, если нужна, размещается в
  /// фиксированной полосе (вдоль правой или верхней стены) — это гарантирует,
  /// что лестница окажется в одних и тех же координатах на всех этажах.
  /// Оставшаяся область раскладывается комнатами + свободной зоной (≥0.20).
  static List<PlanRoom> _layoutFloor(
    List<_RoomReq> rooms,
    double width,
    double length, {
    required bool needsStaircase,
    required bool isFirstFloor,
    required LayoutScheme scheme,
  }) {
    final result = <PlanRoom>[];
    var areaX = 0.0;
    var areaY = 0.0;
    var areaW = width;
    var areaH = length;

    if (needsStaircase) {
      // Выбираем ориентацию полосы: полоса вдоль правой стены, если пятно
      // достаточно широкое; иначе — вдоль верхней.
      final stripVertical = width >= 6.0;
      if (stripVertical) {
        final stripX = width - _staircaseStripWidth;
        // Правило 10 — лестница располагается в центральной части
        // плана (а не у угла), чтобы спуск был равноудалён от
        // помещений верхнего этажа. Сама лестница ставится в
        // середину полосы по Y; над и под ней — короткие
        // лестничные площадки/холлы.
        final stairH = _staircaseDepth.clamp(0.0, length).toDouble();
        final stairY = ((length - stairH) / 2).clamp(0.0, length - stairH);
        if (stairY > 0.1) {
          result.add(PlanRoom(
            label: 'Холл лестницы',
            x: stripX,
            y: 0,
            width: _staircaseStripWidth,
            height: stairY,
            area: _staircaseStripWidth * stairY,
            kind: PlanRoomKind.free,
          ));
        }
        result.add(PlanRoom(
          label: 'Лестница',
          x: stripX,
          y: stairY,
          width: _staircaseStripWidth,
          height: stairH,
          area: _staircaseStripWidth * stairH,
          kind: PlanRoomKind.staircase,
        ));
        final bottomY = stairY + stairH;
        if (length - bottomY > 0.1) {
          result.add(PlanRoom(
            label: 'Холл лестницы',
            x: stripX,
            y: bottomY,
            width: _staircaseStripWidth,
            height: length - bottomY,
            area: _staircaseStripWidth * (length - bottomY),
            kind: PlanRoomKind.free,
          ));
        }
        areaX = 0;
        areaY = 0;
        areaW = width - _staircaseStripWidth;
        areaH = length;
      } else {
        // Полоса сверху. По правилу 10 лестница ставится по центру
        // верхней полосы, а не в левый угол.
        final stairW = _staircaseDepth.clamp(0.0, width).toDouble();
        final stairX = ((width - stairW) / 2).clamp(0.0, width - stairW);
        if (stairX > 0.1) {
          result.add(PlanRoom(
            label: 'Холл лестницы',
            x: 0,
            y: 0,
            width: stairX,
            height: _staircaseStripWidth,
            area: stairX * _staircaseStripWidth,
            kind: PlanRoomKind.free,
          ));
        }
        result.add(PlanRoom(
          label: 'Лестница',
          x: stairX,
          y: 0,
          width: stairW,
          height: _staircaseStripWidth,
          area: stairW * _staircaseStripWidth,
          kind: PlanRoomKind.staircase,
        ));
        final rightX = stairX + stairW;
        if (width - rightX > 0.1) {
          result.add(PlanRoom(
            label: 'Холл лестницы',
            x: rightX,
            y: 0,
            width: width - rightX,
            height: _staircaseStripWidth,
            area: (width - rightX) * _staircaseStripWidth,
            kind: PlanRoomKind.free,
          ));
        }
        areaX = 0;
        areaY = _staircaseStripWidth;
        areaW = width;
        areaH = length - _staircaseStripWidth;
      }
    }

    // Коридорная раскладка: в оставшейся области прорезаем магистральный
    // коридор сквозь весь этаж. На 1-м этаже начало коридора у наружной
    // стены становится прихожей. Комнаты делятся на два «банка» по обе
    // стороны от коридора — каждая комната гарантированно выходит
    // в коридор одной своей длинной стороной.
    if (areaW > 0 && areaH > 0) {
      switch (scheme) {
        case LayoutScheme.enfilade:
          _placeEnfilade(result, rooms, areaX, areaY, areaW, areaH,
              isFirstFloor: isFirstFloor);
        case LayoutScheme.hall:
          _placeHall(result, rooms, areaX, areaY, areaW, areaH,
              isFirstFloor: isFirstFloor);
        case LayoutScheme.studio:
          _placeStudio(result, rooms, areaX, areaY, areaW, areaH,
              isFirstFloor: isFirstFloor);
        case LayoutScheme.centralCore:
          _placeCentralCore(result, rooms, areaX, areaY, areaW, areaH,
              isFirstFloor: isFirstFloor);
        case LayoutScheme.corridor:
          _placeWithCorridor(result, rooms, areaX, areaY, areaW, areaH,
              isFirstFloor: isFirstFloor);
      }
    }
    return result;
  }

  /// Минимальная ширина коридора (СП 55.13330.2017 п. 4.10 — 0.85 м,
  /// берём с запасом для удобного прохода с дверьми).
  static const double _corridorWidth = 1.4;

  /// Начальный сегмент коридора, который становится прихожей.
  static const double _hallwayLen = 3.0;

  static void _placeWithCorridor(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double areaX,
    double areaY,
    double areaW,
    double areaH, {
    required bool isFirstFloor,
  }) {
    // Ориентируем коридор вдоль длинной стороны области — станет
    // больше комнат вдоль него и они будут пропорциональными.
    final horizontal = areaW >= areaH;
    final canPlaceCorridor = horizontal
        ? areaH > _corridorWidth + 2.0
        : areaW > _corridorWidth + 2.0;
    if (!canPlaceCorridor) {
      // Область слишком мала — откатываемся к старой логике.
      final positioned = _layoutRoomsInRect(rooms, areaW, areaH);
      for (final p in positioned) {
        result.add(PlanRoom(
          label: p.label,
          x: p.x + areaX,
          y: p.y + areaY,
          width: p.width,
          height: p.height,
          area: p.area,
          kind: p.kind,
          roomKindName: p.roomKindName,
        ));
      }
      return;
    }

    final (groupA, groupB) = _balanceSplit(rooms);

    if (horizontal) {
      final cy = areaY + (areaH - _corridorWidth) / 2;
      _addCorridorBlocks(
        result,
        x: areaX,
        y: cy,
        w: areaW,
        h: _corridorWidth,
        isFirstFloor: isFirstFloor,
        horizontal: true,
      );
      // Верхний банк (выше коридора).
      final topH = cy - areaY;
      _fillBank(result, groupA, areaX, areaY, areaW, topH);
      // Нижний банк.
      final botY = cy + _corridorWidth;
      final botH = areaY + areaH - botY;
      _fillBank(result, groupB, areaX, botY, areaW, botH);
    } else {
      final cx = areaX + (areaW - _corridorWidth) / 2;
      _addCorridorBlocks(
        result,
        x: cx,
        y: areaY,
        w: _corridorWidth,
        h: areaH,
        isFirstFloor: isFirstFloor,
        horizontal: false,
      );
      // Левый банк.
      final leftW = cx - areaX;
      _fillBank(result, groupA, areaX, areaY, leftW, areaH);
      // Правый банк.
      final rightX = cx + _corridorWidth;
      final rightW = areaX + areaW - rightX;
      _fillBank(result, groupB, rightX, areaY, rightW, areaH);
    }
  }

  static void _addCorridorBlocks(
    List<PlanRoom> result, {
    required double x,
    required double y,
    required double w,
    required double h,
    required bool isFirstFloor,
    required bool horizontal,
  }) {
    if (w <= 0 || h <= 0) return;
    if (!isFirstFloor) {
      result.add(PlanRoom(
        label: 'Коридор',
        x: x,
        y: y,
        width: w,
        height: h,
        area: w * h,
        kind: PlanRoomKind.free,
      ));
      return;
    }
    if (horizontal && w > _hallwayLen + 1.5) {
      // Прихожая — левый край (наружная стена).
      result.add(PlanRoom(
        label: 'Прихожая',
        x: x,
        y: y,
        width: _hallwayLen,
        height: h,
        area: _hallwayLen * h,
        kind: PlanRoomKind.free,
        roomKindName: RoomKind.hallway.name,
      ));
      result.add(PlanRoom(
        label: 'Коридор',
        x: x + _hallwayLen,
        y: y,
        width: w - _hallwayLen,
        height: h,
        area: (w - _hallwayLen) * h,
        kind: PlanRoomKind.free,
      ));
    } else if (!horizontal && h > _hallwayLen + 1.5) {
      // Прихожая — нижний край.
      result.add(PlanRoom(
        label: 'Коридор',
        x: x,
        y: y,
        width: w,
        height: h - _hallwayLen,
        area: w * (h - _hallwayLen),
        kind: PlanRoomKind.free,
      ));
      result.add(PlanRoom(
        label: 'Прихожая',
        x: x,
        y: y + h - _hallwayLen,
        width: w,
        height: _hallwayLen,
        area: w * _hallwayLen,
        kind: PlanRoomKind.free,
        roomKindName: RoomKind.hallway.name,
      ));
    } else {
      // Для коротких коридоров весь сегмент «Прихожая».
      result.add(PlanRoom(
        label: 'Прихожая',
        x: x,
        y: y,
        width: w,
        height: h,
        area: w * h,
        kind: PlanRoomKind.free,
        roomKindName: RoomKind.hallway.name,
      ));
    }
  }

  /// Делим список комнат на две группы с минимальным разрывом по сумме
  /// площадей: сортируем по убыванию и жадно раскладываем по балансу.
  /// Если кухня и гостиная оказались в разных группах — пробуем
  /// поменять кухню местами с одной из мелких комнат группы гостиной,
  /// чтобы они попали в один банк (правило 15 — кухня и гостиная
  /// рядом). Подмена не должна сильно нарушить баланс площадей
  /// (допуск 25 %).
  static (List<_RoomReq>, List<_RoomReq>) _balanceSplit(
    List<_RoomReq> rooms,
  ) {
    final sorted = List<_RoomReq>.from(rooms)
      ..sort((a, b) => b.area.compareTo(a.area));
    final a = <_RoomReq>[];
    final b = <_RoomReq>[];
    var sumA = 0.0;
    var sumB = 0.0;
    for (final r in sorted) {
      if (sumA <= sumB) {
        a.add(r);
        sumA += r.area;
      } else {
        b.add(r);
        sumB += r.area;
      }
    }

    int findIdx(List<_RoomReq> g, RoomKind k) {
      for (var i = 0; i < g.length; i++) {
        if (g[i].kind == k) return i;
      }
      return -1;
    }

    final aLiving = findIdx(a, RoomKind.livingRoom);
    final bLiving = findIdx(b, RoomKind.livingRoom);
    final aKitchen = findIdx(a, RoomKind.kitchen);
    final bKitchen = findIdx(b, RoomKind.kitchen);

    // Кухня и гостиная в разных группах — пробуем перенести кухню.
    List<_RoomReq>? livingGroup;
    List<_RoomReq>? kitchenGroup;
    int kitchenIdxIn = -1;
    if (aLiving >= 0 && bKitchen >= 0) {
      livingGroup = a;
      kitchenGroup = b;
      kitchenIdxIn = bKitchen;
    } else if (bLiving >= 0 && aKitchen >= 0) {
      livingGroup = b;
      kitchenGroup = a;
      kitchenIdxIn = aKitchen;
    }
    if (livingGroup != null && kitchenGroup != null && kitchenIdxIn >= 0) {
      final kitchen = kitchenGroup[kitchenIdxIn];
      // Ищем в группе гостиной комнату для обмена. Гостиную не
      // трогаем (это и есть якорь). Кандидаты: bedroom, storage,
      // hallway, bathroom, study, wardrobe. `_interleaveBedrooms`
      // в `_fillBank` потом разнесёт спальни в банке кухни так,
      // чтобы они не оказались смежными.
      int swapIdx = -1;
      double bestDelta = double.infinity;
      for (var i = 0; i < livingGroup.length; i++) {
        final r = livingGroup[i];
        if (r.kind == RoomKind.livingRoom) continue;
        if (r.kind == RoomKind.kitchen) continue;
        // Считаем дельту суммы при свапе.
        final newSumLiving =
            livingGroup.fold<double>(0, (s, x) => s + x.area) -
                r.area +
                kitchen.area;
        final newSumKitchen =
            kitchenGroup.fold<double>(0, (s, x) => s + x.area) -
                kitchen.area +
                r.area;
        final delta = (newSumLiving - newSumKitchen).abs();
        // Допустимый дисбаланс — 25 % от общей площади.
        final total = newSumLiving + newSumKitchen;
        if (total > 0 && delta / total > 0.25) continue;
        if (delta < bestDelta) {
          bestDelta = delta;
          swapIdx = i;
        }
      }
      if (swapIdx >= 0) {
        final r = livingGroup[swapIdx];
        livingGroup[swapIdx] = kitchen;
        kitchenGroup[kitchenIdxIn] = r;
      }
    }

    return (a, b);
  }

  /// Раскладывает комнаты в прямоугольник [w]×[h] с полным
  /// заполнением (без свободной зоны внутри банка). Если комнат нет —
  /// весь банк становится свободной зоной.
  static void _fillBank(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double x,
    double y,
    double w,
    double h,
  ) {
    if (w <= 0.5 || h <= 0.5) return;
    if (rooms.isEmpty) {
      result.add(PlanRoom(
        label: 'Свободная зона',
        x: x,
        y: y,
        width: w,
        height: h,
        area: w * h,
        kind: PlanRoomKind.free,
      ));
      return;
    }
    final total = rooms.fold<double>(0, (s, r) => s + r.area);
    final bankArea = w * h;
    final scale = total > 0 ? bankArea / total : 1.0;
    // При scale > 1 банк больше суммарной площади комнат (рассеиваем
    // комнаты). Перед raw-rescale зажимаем санузел потолком 15 м² —
    // даже если банк гораздо шире, санузел не должен «раздуться».
    var residual = 0.0;
    final scaled = <_RoomReq>[];
    for (final r in rooms) {
      var area = r.area * scale;
      if (r.kind == RoomKind.bathroom && area > _bathroomMaxArea) {
        residual += area - _bathroomMaxArea;
        area = _bathroomMaxArea;
      }
      scaled.add(_RoomReq(kind: r.kind, label: r.label, area: area));
    }
    if (residual > 0.5) {
      // Остаток площади банка отдаём свободной зоне, чтобы банк
      // полностью замостился без «дырок».
      scaled.add(_RoomReq.free(residual));
    }
    // Правило 8 — спальни не должны делить общую стену. Чтобы slice-
    // and-dice не ставил два соседних элемента-спальни рядом, заранее
    // переставляем порядок: спальни перемежаем не-спальнями. Если
    // не-спален не хватает — две подряд неизбежны (правило 8 потом
    // починит post-process'ом).
    final ordered = _interleaveBedrooms(scaled);
    final out = <PlanRoom>[];
    _slice(out, ordered, 0, 0, w, h);
    for (final p in out) {
      result.add(PlanRoom(
        label: p.label,
        x: p.x + x,
        y: p.y + y,
        width: p.width,
        height: p.height,
        area: p.area,
        kind: p.kind,
        roomKindName: p.roomKindName,
      ));
    }
  }

  /// Анфиладная схема: комнаты идут одна за другой без коридора.
  /// Реализация — slice-and-dice по всей площади (комнаты «делят» этаж),
  /// без выделения коридора. Двери между комнатами расставит планировщик
  /// проёмов: соседи по slice-and-dice автоматически получат проходные двери.
  static void _placeEnfilade(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double areaX,
    double areaY,
    double areaW,
    double areaH, {
    required bool isFirstFloor,
  }) {
    final positioned = _layoutRoomsInRect(rooms, areaW, areaH);
    for (final p in positioned) {
      result.add(PlanRoom(
        label: p.label,
        x: p.x + areaX,
        y: p.y + areaY,
        width: p.width,
        height: p.height,
        area: p.area,
        kind: p.kind,
        roomKindName: p.roomKindName,
      ));
    }
  }

  /// Зальная схема: одна большая центральная зала-гостиная (увеличиваем
  /// её площадь до 50% этажа), остальные комнаты — по периметру.
  static void _placeHall(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double areaX,
    double areaY,
    double areaW,
    double areaH, {
    required bool isFirstFloor,
  }) {
    final boosted = <_RoomReq>[];
    const targetHallShare = 0.5; // 50% этажа — большая зала
    final targetHallArea = areaW * areaH * targetHallShare;
    bool didBoost = false;
    for (final r in rooms) {
      if (!didBoost && r.kind == RoomKind.livingRoom) {
        boosted.add(_RoomReq(
          kind: r.kind,
          label: r.label,
          area: targetHallArea,
        ));
        didBoost = true;
      } else {
        boosted.add(r);
      }
    }
    final positioned = _layoutRoomsInRect(boosted, areaW, areaH);
    for (final p in positioned) {
      result.add(PlanRoom(
        label: p.label,
        x: p.x + areaX,
        y: p.y + areaY,
        width: p.width,
        height: p.height,
        area: p.area,
        kind: p.kind,
        roomKindName: p.roomKindName,
      ));
    }
  }

  /// Квартирная (студия): кухня + столовая + гостиная объединяются в одно
  /// большое открытое помещение «Кухня-гостиная». Остальные расставляются
  /// slice-and-dice.
  static void _placeStudio(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double areaX,
    double areaY,
    double areaW,
    double areaH, {
    required bool isFirstFloor,
  }) {
    double mergedArea = 0;
    final rest = <_RoomReq>[];
    for (final r in rooms) {
      if (r.kind == RoomKind.livingRoom || r.kind == RoomKind.kitchen) {
        mergedArea += r.area;
      } else {
        rest.add(r);
      }
    }
    final merged = <_RoomReq>[
      if (mergedArea > 0)
        _RoomReq(
          kind: RoomKind.livingRoom,
          label: 'Кухня-гостиная',
          area: mergedArea + 4, // +обеденная зона ~4 м²
        ),
      ...rest,
    ];
    final positioned = _layoutRoomsInRect(merged, areaW, areaH);
    for (final p in positioned) {
      result.add(PlanRoom(
        label: p.label,
        x: p.x + areaX,
        y: p.y + areaY,
        width: p.width,
        height: p.height,
        area: p.area,
        kind: p.kind,
        roomKindName: p.roomKindName,
      ));
    }
  }

  /// Компактная (центральное ядро): служебные помещения (санузел,
  /// котельная, кладовая) — в центральной полосе шириной ~2.5 м, жилые
  /// комнаты — по периметру (вдоль внешних стен с лучшим освещением).
  static void _placeCentralCore(
    List<PlanRoom> result,
    List<_RoomReq> rooms,
    double areaX,
    double areaY,
    double areaW,
    double areaH, {
    required bool isFirstFloor,
  }) {
    const coreThickness = 2.5;
    final horizontal = areaW >= areaH;
    final canPlaceCore = horizontal
        ? areaH > coreThickness + 2.0
        : areaW > coreThickness + 2.0;
    if (!canPlaceCore) {
      _placeWithCorridor(result, rooms, areaX, areaY, areaW, areaH,
          isFirstFloor: isFirstFloor);
      return;
    }

    final core = <_RoomReq>[];
    final perimeter = <_RoomReq>[];
    for (final r in rooms) {
      if (r.kind == RoomKind.bathroom ||
          r.kind == RoomKind.boilerRoom ||
          r.kind == RoomKind.storage) {
        core.add(r);
      } else {
        perimeter.add(r);
      }
    }

    if (horizontal) {
      final cy = areaY + (areaH - coreThickness) / 2;
      // Ядро в центре по горизонтали
      _fillBank(result, core, areaX, cy, areaW, coreThickness);
      // Жилые комнаты сверху и снизу
      final topH = cy - areaY;
      final (topGroup, botGroup) = _balanceSplit(perimeter);
      _fillBank(result, topGroup, areaX, areaY, areaW, topH);
      final botY = cy + coreThickness;
      final botH = areaY + areaH - botY;
      _fillBank(result, botGroup, areaX, botY, areaW, botH);
    } else {
      final cx = areaX + (areaW - coreThickness) / 2;
      _fillBank(result, core, cx, areaY, coreThickness, areaH);
      final leftW = cx - areaX;
      final (leftGroup, rightGroup) = _balanceSplit(perimeter);
      _fillBank(result, leftGroup, areaX, areaY, leftW, areaH);
      final rightX = cx + coreThickness;
      final rightW = areaX + areaW - rightX;
      _fillBank(result, rightGroup, rightX, areaY, rightW, areaH);
    }
  }

  /// Раскладка комнат в прямоугольник [w] × [h] (без лестницы):
  /// масштабируем комнаты под «(1 - _minFreeShare)», добавляем свободную зону,
  /// пропускаем через slice-and-dice.
  static List<PlanRoom> _layoutRoomsInRect(
    List<_RoomReq> rooms,
    double w,
    double h,
  ) {
    if (w <= 0 || h <= 0) return const [];
    final footprint = w * h;
    final maxRoomsArea = footprint * (1 - _minFreeShare);
    final realRooms = List<_RoomReq>.from(rooms);
    final realArea = realRooms.fold<double>(0, (s, r) => s + r.area);
    final scale = realArea > maxRoomsArea && realArea > 0
        ? maxRoomsArea / realArea
        : 1.0;
    // Зажимаем санузел потолком 15 м² даже при scale = 1: пользователь
    // мог запросить большой санузел в брифе, и он успешно прошёл
    // _enforceBathroomSizeRule, но в случае scale > 1 (несколько комнат
    // на большое пятно) — мог бы пере-расчёт раздуть его.
    final scaled = <_RoomReq>[];
    for (final r in realRooms) {
      var area = r.area * scale;
      if (r.kind == RoomKind.bathroom && area > _bathroomMaxArea) {
        area = _bathroomMaxArea;
      }
      scaled.add(_RoomReq(kind: r.kind, label: r.label, area: area));
    }
    final used = scaled.fold<double>(0, (s, r) => s + r.area);
    if (used < footprint * 0.99) {
      // В схемах без магистрального коридора (анфилада/студия/холл)
      // остаток ведёт себя как прихожая-коридор. В схеме corridor этот
      // путь — фолбэк для очень узких пятен; «Прихожая / коридор» там
      // тоже корректно — в маленьком пятне отдельный коридор не нужен.
      scaled.add(_RoomReq.hallway(footprint - used));
    }
    return _sliceAndDice(scaled, w, h);
  }

  static List<PlanRoom> _sliceAndDice(
    List<_RoomReq> rooms,
    double width,
    double length,
  ) {
    final out = <PlanRoom>[];
    if (rooms.isEmpty) return out;
    _slice(out, rooms, 0, 0, width, length);
    return out;
  }

  /// Переставляет порядок комнат, чтобы спальни не оказывались рядом
  /// в выходе `_slice`. Алгоритм: вытаскиваем спальни и не-спальни в
  /// два списка и собираем результат, чередуя группы — каждая
  /// спальня окружена не-спальней. Если спален больше, чем
  /// не-спален + 1, лишние идут подряд (это уже починит
  /// `_postProcessBedroomSeparation`). Гардеробные тоже считаем
  /// «не-спальнями» — у них своя смежность к спальне (правило 16),
  /// и они НЕ должны разрывать связку спальня-гардеробная: поэтому
  /// гардеробные используются как разделитель только в самом конце
  /// списка не-спален.
  static List<_RoomReq> _interleaveBedrooms(List<_RoomReq> rooms) {
    final beds = <_RoomReq>[];
    final others = <_RoomReq>[];
    final wardrobes = <_RoomReq>[];
    for (final r in rooms) {
      if (r.kind == RoomKind.bedroom) {
        beds.add(r);
      } else if (r.kind == RoomKind.wardrobe) {
        wardrobes.add(r);
      } else {
        others.add(r);
      }
    }
    // Правка пользователя (Волна 2.1): если спальня соединена с
    // санузлом — спальня должна идти первой по очерёдности (от входа).
    // Раньше при одной спальне separators шли впереди, и санузел
    // оказывался ДО спальни на пути по коридору. Теперь:
    //  • если есть хотя бы одна спальня — она идёт первой;
    //  • дальше — разделители (санузел, кухня, ...);
    //  • гардеробные — в самом конце (рядом со последней спальней).
    if (beds.isEmpty && wardrobes.isEmpty) return rooms;
    final separators = <_RoomReq>[...others, ...wardrobes];
    final out = <_RoomReq>[];
    if (beds.length <= 1) {
      out.addAll(beds);
      out.addAll(separators);
      return out;
    }
    // Размещаем спальни на нечётных позициях, разделители на чётных:
    // [bed, sep, bed, sep, bed]. Если разделителей не хватает —
    // лишние спальни уходят в конец и могут оказаться смежными
    // (post-process потом починит).
    var bi = 0;
    var si = 0;
    out.add(beds[bi++]);
    while (bi < beds.length || si < separators.length) {
      if (si < separators.length) out.add(separators[si++]);
      if (bi < beds.length) out.add(beds[bi++]);
    }
    return out;
  }

  static void _slice(
    List<PlanRoom> out,
    List<_RoomReq> rooms,
    double x,
    double y,
    double w,
    double h,
  ) {
    if (rooms.isEmpty) return;
    if (rooms.length == 1) {
      final r = rooms.first;
      out.add(PlanRoom(
        label: r.label,
        x: x,
        y: y,
        width: w,
        height: h,
        area: w * h,
        kind: r.planKind,
        roomKindName: r.kind?.name,
      ));
      return;
    }
    final total = rooms.fold<double>(0, (s, r) => s + r.area);
    final half = total / 2;
    var acc = 0.0;
    var splitIdx = 1;
    for (var i = 0; i < rooms.length; i++) {
      acc += rooms[i].area;
      if (acc >= half) {
        splitIdx = i + 1;
        break;
      }
    }
    splitIdx = splitIdx.clamp(1, rooms.length - 1);
    final left = rooms.sublist(0, splitIdx);
    final right = rooms.sublist(splitIdx);
    final leftArea = left.fold<double>(0, (s, r) => s + r.area);
    final ratio = total > 0 ? leftArea / total : 0.5;

    // Правило 1: форма комнат — стремимся к квадрату/3:4. На каждом шаге
    // slice-and-dice выбираем ось разреза не по «более длинной стороне»,
    // а по той, что даёт детям лучший aspect-ratio. Это предотвращает
    // появление узких «коридорных» комнат 7×1.5 м из обычных
    // 14 м² спален.
    final wCut = w * ratio;
    final hCut = h * ratio;
    final wOptionWorst = math.max(
      _maxAspect(wCut, h),
      _maxAspect(w - wCut, h),
    );
    final hOptionWorst = math.max(
      _maxAspect(w, hCut),
      _maxAspect(w, h - hCut),
    );
    final cutAlongW = wOptionWorst <= hOptionWorst;

    if (cutAlongW) {
      _slice(out, left, x, y, wCut, h);
      _slice(out, right, x + wCut, y, w - wCut, h);
    } else {
      _slice(out, left, x, y, w, hCut);
      _slice(out, right, x, y + hCut, w, h - hCut);
    }
  }

  /// Максимальный аспект-рейтинг прямоугольника (max(w,h)/min(w,h)).
  /// Для квадрата = 1, для соотношения 3:4 ≈ 1.33, для 1:2 = 2.0,
  /// для 1:3 ≈ 3.0. Цель — держать значение ≤ 2 для жилых комнат.
  static double _maxAspect(double w, double h) {
    if (w <= 1e-6 || h <= 1e-6) return double.infinity;
    return w >= h ? w / h : h / w;
  }

  // ---------------------------------------------------------------------
  // Расстановка дверей и окон по нормам (СП 55.13330.2017, СП 1.13130.2020, СП 50,
  // СП 23-102). Логика упрощённая, но соответствует принципам нормативов:
  //   * жилые комнаты должны иметь окно (СП 55.13330.2017, п. 9.12);
  //   * межкомнатные двери ≥ 0.8 м, в санузел ≥ 0.6 м (СП 1.13130.2020);
  //   * входная дверь — на 1-м этаже со стороны прихожей.
  // ---------------------------------------------------------------------

  /// Стандартные ширины проёмов (м).
  static const double _doorWidth = 0.9; // межкомнатная типовая
  static const double _bathDoorWidth = 0.7; // санузел/кладовая
  static const double _entryDoorWidth = 0.95; // входная (СП 1.13130.2020)
  static const double _minWindow = 1.0;
  static const double _maxWindow = 2.4;
  // Правило 5: служебные помещения (санузел/кладовая/котельная)
  // получают форточку 0.6–1.0 м.
  static const double _minServiceWindow = 0.6;
  static const double _maxServiceWindow = 1.0;

  /// Минимальная длина общей стены, чтобы дверь поместилась с зазорами.
  static const double _minSharedWallForDoor = 1.4;

  /// Пересчитать набор проёмов для уже готовой [plan]. Используется
  /// редактором плана: после ручной правки координат комнат двери и окна
  /// нужно переразложить под новую геометрию (СП 55.13330.2017, СП 1.13130.2020,
  /// СП 23-102 — те же правила, что в авторасчёте).
  static List<PlanOpening> recomputeOpenings(
    FloorPlan plan, {
    required bool isFirstFloor,
    ClientBrief? brief,
  }) =>
      _planOpenings(
        plan.rooms,
        plan.width,
        plan.height,
        isFirstFloor: isFirstFloor,
        brief: brief,
      );

  /// Планирует пристройки к дому: крыльцо у входной двери и (если запрошено)
  /// террасу у гостиной. Возвращаемые координаты могут быть отрицательными
  /// или превышать [width]/[length] — пристройка выходит за внешний контур.
  static List<PlanAttachment> _planAttachments({
    required ClientBrief brief,
    required List<PlanRoom> rooms,
    required List<PlanOpening> openings,
    required double width,
    required double length,
    required bool isFirstFloor,
  }) {
    if (!isFirstFloor) return const [];
    final out = <PlanAttachment>[];
    // Крыльцо у входной двери: 1.5 м в плане × 1.0 м глубины наружу.
    PlanOpening? entry;
    for (final o in openings) {
      if (o.kind == OpeningKind.externalDoor) {
        entry = o;
        break;
      }
    }
    if (entry != null) {
      const porchExtra = 0.3; // по 30 см в стороны от дверного проёма
      const porchDepth = 1.0;
      double px, py, pw, ph;
      switch (entry.side) {
        case WallSide.top:
          px = entry.x - porchExtra;
          py = -porchDepth;
          pw = entry.length + porchExtra * 2;
          ph = porchDepth;
          break;
        case WallSide.bottom:
          px = entry.x - porchExtra;
          py = length;
          pw = entry.length + porchExtra * 2;
          ph = porchDepth;
          break;
        case WallSide.left:
          px = -porchDepth;
          py = entry.y - porchExtra;
          pw = porchDepth;
          ph = entry.length + porchExtra * 2;
          break;
        case WallSide.right:
          px = width;
          py = entry.y - porchExtra;
          pw = porchDepth;
          ph = entry.length + porchExtra * 2;
          break;
      }
      out.add(PlanAttachment(
        kind: PlanAttachmentKind.porch,
        label: 'Крыльцо',
        x: px,
        y: py,
        width: pw,
        height: ph,
      ));
    }
    // Терраса у гостиной — габариты из brief.terraceSpec
    // (если пользователь не задал — 4×2 м по умолчанию).
    if (brief.hasTerrace == true) {
      PlanRoom? living;
      for (final r in rooms) {
        if (r.roomKindName == 'livingRoom') {
          living = r;
          break;
        }
      }
      living ??= () {
        PlanRoom? best;
        for (final r in rooms) {
          if (r.kind == PlanRoomKind.staircase) continue;
          if (best == null || r.area > best.area) best = r;
        }
        return best;
      }();
      if (living != null) {
        final spec = brief.terraceSpec;
        final terraceWidthAlong = spec?.width ?? 4.0;
        final terraceDepth = spec?.length ?? 2.0;
        final terraceW = math.min(terraceWidthAlong, living.width);
        final terraceH = math.min(terraceWidthAlong, living.height);
        final onBottom = (living.y + living.height - length).abs() < 0.01;
        final onRight = (living.x + living.width - width).abs() < 0.01;
        final onTop = living.y.abs() < 0.01;
        final onLeft = living.x.abs() < 0.01;
        double tx = 0, ty = 0, tw = 0, th = 0;
        if (onBottom) {
          tx = living.x + (living.width - terraceW) / 2;
          ty = length;
          tw = terraceW;
          th = terraceDepth;
        } else if (onRight) {
          tx = width;
          ty = living.y + (living.height - terraceH) / 2;
          tw = terraceDepth;
          th = terraceH;
        } else if (onTop) {
          tx = living.x + (living.width - terraceW) / 2;
          ty = -terraceDepth;
          tw = terraceW;
          th = terraceDepth;
        } else if (onLeft) {
          tx = -terraceDepth;
          ty = living.y + (living.height - terraceH) / 2;
          tw = terraceDepth;
          th = terraceH;
        }
        if (tw > 0) {
          out.add(PlanAttachment(
            kind: PlanAttachmentKind.terrace,
            label: 'Терраса',
            x: tx,
            y: ty,
            width: tw,
            height: th,
          ));
        }
      }
    }
    // Гараж — рисуется как блок-пристройка к одной из наружных стен.
    // Сторона выбирается по принципу: предпочитаем правую, затем левую,
    // затем низ. Гараж не должен перекрывать крыльцо/террасу.
    if (brief.hasGarage == true) {
      final spec = brief.garageSpec ?? AttachmentSpec.defaultGarage(
        brief.wallMaterial,
      );
      final gw = spec.width;
      final gl = spec.length;
      // Существующие пристройки — чтобы избежать наложения.
      bool overlapsExisting(double x, double y, double w, double h) {
        for (final a in out) {
          if (x + w <= a.x) continue;
          if (a.x + a.width <= x) continue;
          if (y + h <= a.y) continue;
          if (a.y + a.height <= y) continue;
          return true;
        }
        return false;
      }
      // Перебираем варианты: правая (вдоль длины), левая, низ, верх.
      // Для каждой стороны — позицию по середине.
      final candidates = <(double, double, double, double)>[
        // (x, y, w, h)
        (width, (length - gl) / 2, gw, gl),
        (-gw, (length - gl) / 2, gw, gl),
        ((width - gw) / 2, length, gw, gl),
        ((width - gw) / 2, -gl, gw, gl),
      ];
      for (final c in candidates) {
        if (!overlapsExisting(c.$1, c.$2, c.$3, c.$4)) {
          out.add(PlanAttachment(
            kind: PlanAttachmentKind.garage,
            label: 'Гараж',
            x: c.$1,
            y: c.$2,
            width: c.$3,
            height: c.$4,
          ));
          break;
        }
      }
    }
    return out;
  }

  static List<PlanOpening> _planOpenings(
    List<PlanRoom> rooms,
    double planWidth,
    double planHeight, {
    required bool isFirstFloor,
    ClientBrief? brief,
  }) {
    final openings = <PlanOpening>[];
    if (rooms.isEmpty) return openings;

    // Правило: если санузел граничит со свободной зоной (коридор/прихожая),
    // вход должен быть ТОЛЬКО из коридора. Считаем эти санузлы заранее,
    // чтобы потом отказывать в дверях из спальни/гостиной.
    final bathroomsWithCorridor = <PlanRoom>{};
    for (final r in rooms) {
      if (r.roomKindName != RoomKind.bathroom.name) continue;
      for (final n in rooms) {
        if (identical(n, r)) continue;
        if (n.kind != PlanRoomKind.free) continue;
        final sw = _sharedWall(r, n);
        if (sw != null && sw.length >= _minSharedWallForDoor) {
          bathroomsWithCorridor.add(r);
          break;
        }
      }
    }

    // 1. Двери между смежными комнатами по правилам связности.
    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        final a = rooms[i];
        final b = rooms[j];
        // Между двумя свободными зонами — открытый проход (архивольт),
        // чтобы не было визуальной стены между «Прихожей» и «Коридором»
        // или между основным и лестничным коридорами.
        if (a.kind == PlanRoomKind.free && b.kind == PlanRoomKind.free) {
          final shared = _sharedWall(a, b);
          if (shared != null && shared.length > 0.5) {
            openings.add(PlanOpening(
              kind: OpeningKind.archway,
              side: shared.isVertical ? WallSide.left : WallSide.top,
              x: shared.isVertical ? shared.coord : shared.start,
              y: shared.isVertical ? shared.start : shared.coord,
              length: shared.length,
            ));
          }
          continue;
        }
        // Если санузел может быть открыт из коридора — закрываем все
        // остальные двери в этот санузел.
        final aBath = a.roomKindName == RoomKind.bathroom.name;
        final bBath = b.roomKindName == RoomKind.bathroom.name;
        if (aBath && bathroomsWithCorridor.contains(a) &&
            b.kind != PlanRoomKind.free) {
          continue;
        }
        if (bBath && bathroomsWithCorridor.contains(b) &&
            a.kind != PlanRoomKind.free) {
          continue;
        }
        if (!_shouldHaveDoor(a, b)) continue;
        final shared = _sharedWall(a, b);
        if (shared == null) continue;
        final width = _doorWidthBetween(a, b);
        if (shared.length < _minSharedWallForDoor) continue;
        if (shared.length < width + 0.4) continue;
        // Дверь по центру общего сегмента.
        final mid = (shared.start + shared.end) / 2;
        final doorStart = mid - width / 2;
        final swing = shared.swing;
        openings.add(PlanOpening(
          kind: OpeningKind.door,
          side: shared.isVertical ? WallSide.left : WallSide.top,
          x: shared.isVertical ? shared.coord : doorStart,
          y: shared.isVertical ? doorStart : shared.coord,
          length: width,
          swing: swing,
        ));
      }
    }

    // 2. Окна на наружных стенах. Жилые комнаты получают полноценное
    // окно 1.0–2.4 м (СП 23-102). Служебные (санузел/кладовая/
    // котельная) — компактную форточку 0.6–1.0 м (правило 5,
    // СП 60.13330.2020 — естественная вентиляция).
    for (final r in rooms) {
      if (!_needsWindow(r)) continue;
      final isService = _needsServiceWindow(r);
      // Из всех наружных сторон выбираем самую длинную.
      WallSide? bestSide;
      var bestLen = 0.0;
      for (final side in WallSide.values) {
        if (!_isOuterWall(r, side, planWidth, planHeight)) continue;
        final wallLen = side.isHorizontal ? r.width : r.height;
        if (wallLen > bestLen) {
          bestLen = wallLen;
          bestSide = side;
        }
      }
      // Минимальная длина окна и зазор от углов зависят от типа.
      final minWin = isService ? _minServiceWindow : _minWindow;
      final maxWin = isService ? _maxServiceWindow : _maxWindow;
      if (bestSide == null || bestLen < minWin + 0.6) continue;
      // Ширина по правилу So/Sp ≈ 1:8 (СП 23-102) при высоте окна ~1.5 м.
      // Для служебных помещений берём меньший делитель (форточка
      // ≈ 1:10–1:12 от площади). Ограничиваем сверху/снизу типовыми
      // значениями для каждого типа.
      final ratio = isService ? 16.0 : 12.0;
      final desired = (r.area / ratio).clamp(minWin, maxWin);
      final usable = (bestLen - 0.6).clamp(minWin, maxWin);
      final winLen = desired < usable ? desired : usable;
      final wallStart = bestSide.isHorizontal ? r.x : r.y;
      final winStart = wallStart + (bestLen - winLen) / 2;
      double winX, winY;
      switch (bestSide) {
        case WallSide.top:
          winX = winStart;
          winY = r.y;
          break;
        case WallSide.bottom:
          winX = winStart;
          winY = r.y + r.height;
          break;
        case WallSide.left:
          winX = r.x;
          winY = winStart;
          break;
        case WallSide.right:
          winX = r.x + r.width;
          winY = winStart;
          break;
      }
      openings.add(PlanOpening(
        kind: OpeningKind.window,
        side: bestSide,
        x: winX,
        y: winY,
        length: winLen,
      ));
    }

    // 2b. Проверка связности: каждая комната должна иметь хотя бы одну
    // внутреннюю дверь/проход. Если после п.1 остались изолированные
    // помещения (нет общей стены с коридором или не прошли по правилу
    // смежности), принудительно добавляем дверь в ближайшую смежную
    // комнату — иначе в неё невозможно попасть.
    _enforceRoomConnectivity(rooms, openings);

    // 2c. Глобальная проверка достижимости (СП 55.13330.2017 п. 6.6:
    // в каждое помещение должен быть обеспечен доступ из мест общего
    // пользования). Строим граф «комната → комнаты, связанные дверью/
    // проходом», находим корни (на 1-м этаже — комнаты с входной
    // дверью; на верхних этажах — свободные зоны рядом с лестницей)
    // и BFS-ом проверяем, что каждая жилая/служебная комната достижима
    // из корня. Если нет — добавляем принудительный проход в ближайшую
    // достижимую соседнюю комнату.
    _enforceGlobalReachability(
      rooms,
      openings,
      planWidth,
      planHeight,
      isFirstFloor: isFirstFloor,
    );

    // 3. Входная дверь — на 1-м этаже. Приоритет:
    //   a) прихожая с выходом на улицу;
    //   b) свободная зона/коридор с выходом на улицу;
    //   c) фолбэк: любая «жилая» комната с длинной наружной стеной
    //      (кроме санузла, котельной, кладовой и лестницы).
    // Это страхует случаи, когда планировщик «прячет» прихожую внутрь
    // здания — без этого дом получался бы вообще без входной двери.
    if (isFirstFloor) {
      // Правило 2: вход в дом ближе к центру и равноудалён от жилых
      // комнат. Среди всех free/hallway-зон с наружной стеной выбираем
      // ту, чей центр ближе всего к геометрическому центру плана.
      // Если такого помещения нет — фолбэк на «любую жилую комнату
      // не-сервисную с длинной наружной стеной».
      final cx = planWidth / 2;
      final cy = planHeight / 2;
      double centralDistance(PlanRoom r) {
        final rx = r.x + r.width / 2;
        final ry = r.y + r.height / 2;
        final dx = rx - cx;
        final dy = ry - cy;
        return math.sqrt(dx * dx + dy * dy);
      }

      PlanRoom? entryRoom;
      double bestDist = double.infinity;
      bool bestIsHallway = false;
      for (final r in rooms) {
        final isHallway = r.roomKindName == RoomKind.hallway.name;
        final isFree = r.kind == PlanRoomKind.free;
        if (!isHallway && !isFree) continue;
        if (!_hasOuterWall(r, planWidth, planHeight)) continue;
        final d = centralDistance(r);
        // Прихожая важнее по приоритету, чем просто free-зона.
        // При равном статусе — побеждает та, что ближе к центру.
        final betterStatus = isHallway && !bestIsHallway;
        final equalStatus = isHallway == bestIsHallway;
        if (entryRoom == null ||
            betterStatus ||
            (equalStatus && d < bestDist)) {
          entryRoom = r;
          bestDist = d;
          bestIsHallway = isHallway;
        }
      }
      // Фолбэк — самая большая «не-сервисная» комната у наружного контура,
      // ближайшая к центру плана.
      if (entryRoom == null) {
        const skipKinds = {
          'bathroom',
          'boilerRoom',
          'storage',
        };
        var bestArea = 0.0;
        var bestCenter = double.infinity;
        for (final r in rooms) {
          if (r.kind == PlanRoomKind.staircase) continue;
          if (skipKinds.contains(r.roomKindName)) continue;
          if (!_hasOuterWall(r, planWidth, planHeight)) continue;
          final d = centralDistance(r);
          // Вначале по площади, при равной площади — по центральности.
          if (r.area > bestArea + 0.5 ||
              ((r.area - bestArea).abs() < 0.5 && d < bestCenter)) {
            bestArea = r.area;
            bestCenter = d;
            entryRoom = r;
          }
        }
      }
      if (entryRoom != null) {
        WallSide? bestSide;
        var bestLen = 0.0;
        // По архитектурной традиции вход располагается с главного (южного)
        // фасада дома. В нашей системе координат ось Y направлена «вниз»
        // и «южная» стена плана — это `WallSide.bottom`. Поэтому при
        // наличии достаточного внешнего проёма предпочитаем именно её;
        // иначе — просто самая длинная наружная стена.
        const sideOrder = <WallSide>[
          WallSide.bottom,
          WallSide.top,
          WallSide.left,
          WallSide.right,
        ];
        for (final side in sideOrder) {
          if (!_isOuterWall(entryRoom, side, planWidth, planHeight)) continue;
          final wallLen = side.isHorizontal
              ? entryRoom.width
              : entryRoom.height;
          if (wallLen >= _entryDoorWidth + 0.6) {
            bestSide = side;
            bestLen = wallLen;
            break;
          }
        }
        if (bestSide == null) {
          for (final side in WallSide.values) {
            if (!_isOuterWall(entryRoom, side, planWidth, planHeight)) continue;
            final wallLen = side.isHorizontal
                ? entryRoom.width
                : entryRoom.height;
            if (wallLen > bestLen) {
              bestLen = wallLen;
              bestSide = side;
            }
          }
        }
        if (bestSide != null && bestLen >= _entryDoorWidth + 0.6) {
          final wallStart = bestSide.isHorizontal ? entryRoom.x : entryRoom.y;
          final start = wallStart + (bestLen - _entryDoorWidth) / 2;
          double dx, dy;
          switch (bestSide) {
            case WallSide.top:
              dx = start;
              dy = entryRoom.y;
              break;
            case WallSide.bottom:
              dx = start;
              dy = entryRoom.y + entryRoom.height;
              break;
            case WallSide.left:
              dx = entryRoom.x;
              dy = start;
              break;
            case WallSide.right:
              dx = entryRoom.x + entryRoom.width;
              dy = start;
              break;
          }
          openings.add(PlanOpening(
            kind: OpeningKind.externalDoor,
            side: bestSide,
            x: dx,
            y: dy,
            length: _entryDoorWidth,
            swing: 1,
          ));
        }
      }
    }

    // 3.4. Правило 9: техпомещение (котельная) — отдельный наружный
    // вход с улицы. Размещаем `externalDoor` на самой длинной
    // наружной стене котельной. Если её совсем нет на наружном
    // контуре (бывает в очень компактных пятнах) — пропускаем; вход
    // в котельную в этом случае останется внутренний (через
    // коридор), что хотя бы соответствует СП 60.13330 для
    // негазового оборудования.
    if (isFirstFloor) {
      for (final r in rooms) {
        if (r.roomKindName != RoomKind.boilerRoom.name) continue;
        WallSide? bestSide;
        var bestLen = 0.0;
        for (final side in WallSide.values) {
          if (!_isOuterWall(r, side, planWidth, planHeight)) continue;
          final wallLen = side.isHorizontal ? r.width : r.height;
          if (wallLen > bestLen) {
            bestLen = wallLen;
            bestSide = side;
          }
        }
        if (bestSide == null || bestLen < _entryDoorWidth + 0.6) continue;
        // Не дублируем дверь, если рядом уже есть externalDoor от
        // другого правила (например, главный вход стоит на той же
        // стене этой же комнаты — теоретически невозможно, но на
        // случай редких пограничных случаев).
        var alreadyHasExternal = false;
        for (final o in openings) {
          if (o.kind != OpeningKind.externalDoor) continue;
          if (_openingLiesOnRoomWall(o, r)) {
            alreadyHasExternal = true;
            break;
          }
        }
        if (alreadyHasExternal) continue;
        final wallStart = bestSide.isHorizontal ? r.x : r.y;
        final start = wallStart + (bestLen - _entryDoorWidth) / 2;
        double dx, dy;
        switch (bestSide) {
          case WallSide.top:
            dx = start;
            dy = r.y;
            break;
          case WallSide.bottom:
            dx = start;
            dy = r.y + r.height;
            break;
          case WallSide.left:
            dx = r.x;
            dy = start;
            break;
          case WallSide.right:
            dx = r.x + r.width;
            dy = start;
            break;
        }
        openings.add(PlanOpening(
          kind: OpeningKind.externalDoor,
          side: bestSide,
          x: dx,
          y: dy,
          length: _entryDoorWidth,
          swing: 1,
        ));
      }
    }

    // 3.5. Правило 14: второй вход с участка — через гостиную/террасу.
    // Если в ТЗ запрошена терраса, размещаем «французскую» внешнюю
    // дверь шириной _entryDoorWidth на стене гостиной, выходящей на
    // террасу. Терраса крепится к гостиной (см. _planAttachments),
    // поэтому стена двери совпадает со стеной примыкания террасы.
    if (isFirstFloor && brief != null && brief.hasTerrace == true) {
      _addTerraceExternalDoor(rooms, openings, planWidth, planHeight);
    }

    // 3.6. Правило 13: гостиная — лист графа путей. Маршруты не должны
    // проходить через гостиную: если у неё несколько связей с
    // коридором/free-зонами, оставляем только одну — при условии, что
    // глобальная достижимость не нарушится. Студийный проход
    // гостиная↔кухня (livingRoom↔kitchen) не трогаем.
    _enforceLivingRoomLeaf(rooms, openings, planWidth, planHeight,
        isFirstFloor: isFirstFloor);

    // 3.7. Правило 11: дверь в санузел/спальню не должна быть
    // напротив унитаза/кровати. На этапе расстановки мебели/сантехники
    // эти приборы ставятся на длинную дальнюю стену; чтобы дверной
    // створ не «смотрел» на них, сдвигаем дверь от центра общей стены
    // к ближнему углу комнаты. Внутри комнаты остаётся прямой угол
    // под установку прибора без визуального контакта с дверью.
    _offsetDoorsForPrivateRooms(rooms, openings);

    // 3.8. Правило 6: двери не «створ-в-створ». Если две двери на
    // противоположных стенах коридора (free-зоны) перекрываются по
    // координате вдоль стены — сдвигаем одну из них, чтобы они не
    // были строго друг напротив друга.
    _avoidFacingDoors(rooms, openings);

    // 4. Финальная проверка «бюджета» проёмов на каждой стене (п.3 v43):
    // суммарная длина проёмов на одной стене комнаты не должна
    // превышать 60% длины этой стены — иначе стена потеряет несущую
    // способность (для несущих стен) или станет нечитаемой архитектурно.
    // Двери и арки не трогаем (сократить дверь нельзя — она и так
    // нормативный минимум 0.9 м), а вот окна шириной > 1.0 м можно
    // ужать.
    _clampOpeningsToWallBudget(rooms, openings);

    return openings;
  }

  /// Правило 6 — две двери не должны стоять «створ-в-створ» через
  /// коридор: при открывании они бы сталкивались, а звукоизоляция
  /// между смежными комнатами резко падает (двери — слабое звено).
  ///
  /// Алгоритм:
  ///  • для каждой пары дверей, лежащих на параллельных горизонтальных
  ///    или вертикальных стенах на расстоянии ≤ 2.5 м (типовая ширина
  ///    коридора + запас), считаем перекрытие проекций на ось вдоль
  ///    стены;
  ///  • если перекрытие > 0.05 м — сдвигаем «вторую» дверь вдоль её
  ///    стены так, чтобы перекрытие пропало;
  ///  • новый старт двери должен оставаться внутри всех комнат, на
  ///    стене которых она лежит (используем `_openingLiesOnRoomWall`).
  ///    Если допустимого сдвига нет — дверь оставляем как есть.
  ///
  /// Правило 14 — второй вход с участка через гостиную/террасу.
  /// Размещаем «французскую» наружную дверь на стене гостиной,
  /// которая выходит на ту же сторону, что и предполагаемая
  /// терраса (логика выбора стены — та же, что в `_planAttachments`:
  /// противоположная стене входной двери, либо самая длинная
  /// наружная стена). Если уже есть наружная дверь на этой стене
  /// (например, входная дверь, ведущая в прихожую) — пропускаем,
  /// чтобы не дублировать вход.
  static void _addTerraceExternalDoor(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
    double planW,
    double planH,
  ) {
    PlanRoom? living;
    for (final r in rooms) {
      if (r.roomKindName == RoomKind.livingRoom.name) {
        living = r;
        break;
      }
    }
    if (living == null) return;
    if (!_hasOuterWall(living, planW, planH)) return;

    // Выбираем сторону: предпочитаем юг (нижняя стена), затем
    // самую длинную наружную сторону — тогда терраса располагается
    // на «жилой» стороне дома и получает максимум солнца.
    WallSide? bestSide;
    double bestLen = 0;
    for (final s in WallSide.values) {
      if (!_isOuterWall(living, s, planW, planH)) continue;
      final len = (s == WallSide.top || s == WallSide.bottom)
          ? living.width
          : living.height;
      // Юг получает приоритет (бонус 0.5 м к длине).
      final score = len + (s == WallSide.bottom ? 0.5 : 0);
      if (score > bestLen) {
        bestLen = score;
        bestSide = s;
      }
    }
    if (bestSide == null) return;

    const doorWidth = _entryDoorWidth;
    if (bestLen < doorWidth + 0.4) return;

    // Если на этой стене уже есть наружная дверь — не добавляем
    // дублирующую (например, у одноэтажки гостиная иногда тоже
    // принимает входную дверь).
    for (final o in openings) {
      if (o.kind != OpeningKind.externalDoor) continue;
      if (o.side != bestSide) continue;
      if (!_openingLiesOnRoomWall(o, living)) continue;
      return;
    }

    // Дверь по центру стены, но с учётом длины двери.
    double dx, dy;
    switch (bestSide) {
      case WallSide.top:
        dx = living.x + (living.width - doorWidth) / 2;
        dy = living.y;
      case WallSide.bottom:
        dx = living.x + (living.width - doorWidth) / 2;
        dy = living.y + living.height;
      case WallSide.left:
        dx = living.x;
        dy = living.y + (living.height - doorWidth) / 2;
      case WallSide.right:
        dx = living.x + living.width;
        dy = living.y + (living.height - doorWidth) / 2;
    }

    // Если рядом окажется существующее окно гостиной — сдвигаем
    // дверь к ближнему углу, чтобы не пересекаться. Простая
    // эвристика: если в проекциях на ось окно и дверь
    // перекрываются, сдвигаем дверь на (perpendicular center →
    // ближайшая стена комнаты).
    bool overlapsWindow() {
      const eps = 0.01;
      for (final o in openings) {
        if (o.kind != OpeningKind.window) continue;
        if (o.side != bestSide) continue;
        if (!_openingLiesOnRoomWall(o, living!)) continue;
        if (bestSide == WallSide.top || bestSide == WallSide.bottom) {
          if (dx + doorWidth > o.x - eps && dx < o.x + o.length + eps) {
            return true;
          }
        } else {
          if (dy + doorWidth > o.y - eps && dy < o.y + o.length + eps) {
            return true;
          }
        }
      }
      return false;
    }

    if (overlapsWindow()) {
      // Сдвигаем к одному из углов комнаты (где меньше окно/проёмов).
      if (bestSide == WallSide.top || bestSide == WallSide.bottom) {
        final left = living.x + 0.2;
        final right = living.x + living.width - doorWidth - 0.2;
        dx = (left + 0.1).clamp(left, right);
      } else {
        final top = living.y + 0.2;
        final bot = living.y + living.height - doorWidth - 0.2;
        dy = (top + 0.1).clamp(top, bot);
      }
    }

    openings.add(PlanOpening(
      kind: OpeningKind.externalDoor,
      side: bestSide,
      x: dx,
      y: dy,
      length: doorWidth,
      swing: 1,
    ));
  }

  /// Правило 13 — гостиная не должна служить транзитом между
  /// комнатами. Маршруты не идут через гостиную: гостиная — лист
  /// графа путей.
  ///
  /// Если у гостиной несколько «связей» с коридором/free-зонами,
  /// оставляем только самую длинную; остальные удаляем при условии,
  /// что глобальная достижимость не пострадает (BFS без удалённой
  /// двери должен достигать всех помещений).
  /// Студийный проход «гостиная↔кухня» не трогаем — это эргономическое
  /// зонирование (правило 15), а не маршрут.
  static void _enforceLivingRoomLeaf(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
    double planW,
    double planH, {
    required bool isFirstFloor,
  }) {
    if (rooms.isEmpty) return;
    final livingRooms = <int>[];
    for (var i = 0; i < rooms.length; i++) {
      if (rooms[i].roomKindName == RoomKind.livingRoom.name) {
        livingRooms.add(i);
      }
    }
    if (livingRooms.isEmpty) return;

    bool reachableWithout(int idxLiving, PlanOpening removed) {
      // Воссоздаём граф без удалённой двери и проверяем, достигают
      // ли все non-staircase non-free комнаты корня.
      final n = rooms.length;
      final adj = List<Set<int>>.generate(n, (_) => <int>{});
      for (final o in openings) {
        if (identical(o, removed)) continue;
        if (o.kind != OpeningKind.door && o.kind != OpeningKind.archway) {
          continue;
        }
        final on = <int>[];
        for (var i = 0; i < n; i++) {
          if (_openingLiesOnRoomWall(o, rooms[i])) on.add(i);
        }
        for (var i = 0; i < on.length; i++) {
          for (var j = i + 1; j < on.length; j++) {
            adj[on[i]].add(on[j]);
            adj[on[j]].add(on[i]);
          }
        }
      }
      // Корни — те же, что в _enforceGlobalReachability.
      final roots = <int>{};
      if (isFirstFloor) {
        for (var i = 0; i < n; i++) {
          final r = rooms[i];
          if (r.kind != PlanRoomKind.free) continue;
          if (_hasOuterWall(r, planW, planH)) roots.add(i);
        }
      }
      for (var i = 0; i < n; i++) {
        if (rooms[i].kind != PlanRoomKind.staircase) continue;
        for (var j = 0; j < n; j++) {
          if (i == j) continue;
          if (rooms[j].kind != PlanRoomKind.free) continue;
          final sw = _sharedWall(rooms[j], rooms[i]);
          if (sw != null && sw.length >= _corridorWidth - 0.1) roots.add(j);
        }
      }
      if (roots.isEmpty) return true;
      // BFS.
      final reached = <int>{...roots};
      final queue = <int>[...roots];
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        for (final nb in adj[cur]) {
          if (reached.add(nb)) queue.add(nb);
        }
      }
      for (var i = 0; i < n; i++) {
        final r = rooms[i];
        if (r.kind == PlanRoomKind.free) continue;
        if (r.kind == PlanRoomKind.staircase) continue;
        if (!reached.contains(i)) return false;
      }
      return true;
    }

    for (final livingIdx in livingRooms) {
      // Считаем двери гостиная↔free-зона. Двери гостиная↔кухня
      // оставляем нетронутыми (правило 15 — открытый проход студии).
      final candidates = <PlanOpening>[];
      for (final o in openings) {
        if (o.kind != OpeningKind.door && o.kind != OpeningKind.archway) {
          continue;
        }
        if (!_openingLiesOnRoomWall(o, rooms[livingIdx])) continue;
        // Найдём вторую комнату, на стене которой лежит проём.
        int otherIdx = -1;
        for (var i = 0; i < rooms.length; i++) {
          if (i == livingIdx) continue;
          if (_openingLiesOnRoomWall(o, rooms[i])) {
            otherIdx = i;
            break;
          }
        }
        if (otherIdx < 0) continue;
        final other = rooms[otherIdx];
        if (other.kind != PlanRoomKind.free) continue;
        candidates.add(o);
      }
      if (candidates.length <= 1) continue;
      // Сортируем по длине (самые широкие проходы сохраняем — они,
      // скорее всего, главный).
      candidates.sort((a, b) => b.length.compareTo(a.length));
      // Пытаемся удалить лишние, начиная с самых узких.
      for (var k = candidates.length - 1; k >= 1; k--) {
        final cand = candidates[k];
        if (reachableWithout(livingIdx, cand)) {
          openings.remove(cand);
        }
      }
    }
  }

  /// Правило 11 — дверь в санузел/спальню не должна быть напротив
  /// унитаза/кровати. На этапе расстановки сантехники/мебели эти
  /// приборы располагаются на длинной дальней стене; чтобы дверной
  /// створ не «смотрел» на них прямо, сдвигаем дверь от центра общей
  /// стены к ближнему углу комнаты — внутри остаётся прямой угол
  /// (back-of-room), куда и встанет унитаз/кровать без визуального
  /// контакта с дверью.
  ///
  /// Алгоритм:
  ///  • для каждой обычной (не наружной) двери смотрим обе комнаты, на
  ///    стене которых она лежит; если хотя бы одна — `bathroom`/
  ///    `bedroom`, считаем эту комнату «приватной»;
  ///  • вычисляем общий отрезок стены между приватной комнатой и
  ///    соседом (`_sharedWall`); если дверь сейчас стоит в средней
  ///    трети отрезка, сдвигаем её к ближнему углу (start + 0.2 м или
  ///    end − width − 0.2 м), сохраняя `length` и `kind`;
  ///  • новая позиция должна оставаться валидной для обеих комнат
  ///    (`_openingLiesOnRoomWall`); если ни один сдвиг не подходит —
  ///    дверь не трогаем.
  static void _offsetDoorsForPrivateRooms(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
  ) {
    bool isPrivate(PlanRoom r) {
      if (r.kind != PlanRoomKind.room) return false;
      final n = r.roomKindName;
      return n == RoomKind.bathroom.name || n == RoomKind.bedroom.name;
    }

    for (var oi = 0; oi < openings.length; oi++) {
      final o = openings[oi];
      if (o.kind != OpeningKind.door) continue;
      // Найдём обе комнаты, на стене которых лежит дверь.
      PlanRoom? privateRoom;
      PlanRoom? other;
      for (final r in rooms) {
        if (!_openingLiesOnRoomWall(o, r)) continue;
        if (isPrivate(r)) {
          privateRoom = r;
        } else {
          other ??= r;
        }
      }
      if (privateRoom == null || other == null) continue;

      final sw = _sharedWall(privateRoom, other);
      if (sw == null) continue;
      final width = o.length;
      if (sw.length < width + 0.4) continue;

      final isHorizontal =
          o.side == WallSide.top || o.side == WallSide.bottom;
      // Сейчас старт двери на оси вдоль стены.
      final curStart = isHorizontal ? o.x : o.y;
      final curEnd = curStart + width;
      final wallStart = sw.start;
      final wallEnd = sw.end;
      final wallMid = (wallStart + wallEnd) / 2;

      // Если дверь уже стоит ≤ 0.4 м от ближнего угла стены —
      // считаем её достаточно смещённой и пропускаем.
      if (curStart - wallStart <= 0.4 || wallEnd - curEnd <= 0.4) {
        continue;
      }

      // Координата приватной комнаты вдоль стены.
      double pStart, pEnd;
      if (isHorizontal) {
        pStart = privateRoom.x;
        pEnd = privateRoom.x + privateRoom.width;
      } else {
        pStart = privateRoom.y;
        pEnd = privateRoom.y + privateRoom.height;
      }
      // Выбираем ближний угол приватной комнаты к середине общей
      // стены: туда и сдвигаем дверь, чтобы дальний угол остался
      // под унитаз/кровать.
      final distStart = (wallMid - pStart).abs();
      final distEnd = (wallMid - pEnd).abs();
      final preferStart = distStart <= distEnd;

      final candidates = <double>[];
      if (preferStart) {
        candidates.add(math.max(wallStart + 0.2, pStart + 0.2));
        candidates.add(wallEnd - width - 0.2);
      } else {
        candidates.add(math.min(wallEnd - width - 0.2, pEnd - width - 0.2));
        candidates.add(wallStart + 0.2);
      }
      for (final c in candidates) {
        if (c < wallStart - 0.01 || c + width > wallEnd + 0.01) continue;
        final newOpening = PlanOpening(
          kind: o.kind,
          side: o.side,
          x: isHorizontal ? c : o.x,
          y: isHorizontal ? o.y : c,
          length: o.length,
          swing: o.swing,
        );
        // Должно остаться валидным для обеих комнат.
        if (!_openingLiesOnRoomWall(newOpening, privateRoom)) continue;
        if (!_openingLiesOnRoomWall(newOpening, other)) continue;
        openings[oi] = newOpening;
        break;
      }
    }
  }

  static void _avoidFacingDoors(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
  ) {
    const double maxFacingDist = 2.5; // м — типовая ширина коридора + запас
    const double minOverlap = 0.05; // м — допуск на «не строго створ»

    PlanOpening shifted(PlanOpening o, double newStart) =>
        PlanOpening(
          kind: o.kind,
          side: o.side,
          x: o.side.isHorizontal ? newStart : o.x,
          y: o.side.isHorizontal ? o.y : newStart,
          length: o.length,
          swing: o.swing,
        );

    bool fitsInRooms(PlanOpening test) {
      // Проверка: дверь по-прежнему лежит хотя бы на одной общей стене
      // двух комнат (после сдвига вдоль той же стены).
      var hits = 0;
      for (final r in rooms) {
        if (_openingLiesOnRoomWall(test, r)) hits++;
        if (hits >= 2) return true;
      }
      return false;
    }

    for (var i = 0; i < openings.length; i++) {
      final a = openings[i];
      if (a.kind != OpeningKind.door) continue;
      for (var j = i + 1; j < openings.length; j++) {
        var b = openings[j];
        if (b.kind != OpeningKind.door) continue;
        if (a.side.isHorizontal != b.side.isHorizontal) continue;
        if (a.side.isHorizontal) {
          // Параллельные горизонтальные стены — расстояние по Y.
          final perpDist = (a.y - b.y).abs();
          if (perpDist < 0.1 || perpDist > maxFacingDist) continue;
          final aStart = a.x;
          final aEnd = a.x + a.length;
          final bStart = b.x;
          final bEnd = b.x + b.length;
          final ovStart = math.max(aStart, bStart);
          final ovEnd = math.min(aEnd, bEnd);
          if (ovEnd - ovStart < minOverlap) continue;
          // Сдвигаем `b` вдоль X. Цель — чтобы её правый край стал
          // левее `aStart` либо левый край — правее `aEnd` + запас 0.1.
          final shiftLeft = aStart - 0.1 - b.length;
          final shiftRight = aEnd + 0.1;
          final candidates = <double>[];
          if (shiftLeft != b.x) candidates.add(shiftLeft);
          if (shiftRight != b.x) candidates.add(shiftRight);
          for (final newStart in candidates) {
            final test = shifted(b, newStart);
            if (fitsInRooms(test)) {
              openings[j] = test;
              b = test;
              break;
            }
          }
        } else {
          // Параллельные вертикальные стены — расстояние по X.
          final perpDist = (a.x - b.x).abs();
          if (perpDist < 0.1 || perpDist > maxFacingDist) continue;
          final aStart = a.y;
          final aEnd = a.y + a.length;
          final bStart = b.y;
          final bEnd = b.y + b.length;
          final ovStart = math.max(aStart, bStart);
          final ovEnd = math.min(aEnd, bEnd);
          if (ovEnd - ovStart < minOverlap) continue;
          final shiftUp = aStart - 0.1 - b.length;
          final shiftDown = aEnd + 0.1;
          final candidates = <double>[];
          if (shiftUp != b.y) candidates.add(shiftUp);
          if (shiftDown != b.y) candidates.add(shiftDown);
          for (final newStart in candidates) {
            final test = shifted(b, newStart);
            if (fitsInRooms(test)) {
              openings[j] = test;
              b = test;
              break;
            }
          }
        }
      }
    }
  }

  /// Бюджет проёмов на стене (п.3 v43).
  /// Группирует проёмы по (комната, сторона), считает суммарную длину
  /// проёмов и длину стены. Если суммарная длина > 60% длины стены,
  /// окна ужимаются (шире — сильнее) до тех пор, пока сумма не
  /// уложится в бюджет; если даже после ужимания окно меньше
  /// `_minWindow` — оно удаляется.
  ///
  /// Двери/арки/входные двери не модифицируются — у них нормативная
  /// минимальная ширина (СП 1.13130.2020), и физически их «обрезать»
  /// нельзя.
  static void _clampOpeningsToWallBudget(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
  ) {
    if (rooms.isEmpty || openings.isEmpty) return;
    const double maxRatio = 0.6;
    // Index map: opening → room/side it belongs to.
    // Каждый проём может «висеть» на стене ровно одной комнаты
    // (если проём — внешний, у соседа просто нет, и обработка
    // прозрачна).
    for (final r in rooms) {
      for (final side in WallSide.values) {
        final wallLen = side.isHorizontal ? r.width : r.height;
        if (wallLen <= 0) continue;
        // Соберём проёмы, лежащие именно на этой стене этой комнаты.
        final onWall = <PlanOpening>[];
        for (final o in openings) {
          if (o.side != side) continue;
          if (!_openingLiesOnRoomSide(o, r, side)) continue;
          onWall.add(o);
        }
        if (onWall.isEmpty) continue;
        final total = onWall.fold<double>(0, (s, o) => s + o.length);
        final budget = wallLen * maxRatio;
        if (total <= budget) continue;
        // Превышение. Ужимаем окна по очереди от самого широкого.
        final windows = onWall
            .where((o) => o.kind == OpeningKind.window)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        var leftToShrink = total - budget;
        for (final w in windows) {
          if (leftToShrink <= 0) break;
          final canShrink = w.length - _minWindow;
          if (canShrink <= 0) continue;
          final delta = canShrink < leftToShrink ? canShrink : leftToShrink;
          // PlanOpening — immutable, заменяем в общем списке.
          final idx = openings.indexOf(w);
          openings[idx] = PlanOpening(
            kind: w.kind,
            side: w.side,
            x: w.x,
            y: w.y,
            length: w.length - delta,
            swing: w.swing,
          );
          leftToShrink -= delta;
        }
        // Если после ужимания всё равно превышаем бюджет, удаляем
        // самое узкое окно. Двери / архивольты / внешние двери не
        // трогаем.
        if (leftToShrink > 0) {
          final remainingWindows = onWall
              .where((o) => o.kind == OpeningKind.window)
              .toList();
          remainingWindows.sort((a, b) => a.length.compareTo(b.length));
          for (final w in remainingWindows) {
            if (leftToShrink <= 0) break;
            openings.remove(w);
            leftToShrink -= w.length;
          }
        }
      }
    }
  }

  /// True, если проём лежит на указанной стороне комнаты.
  static bool _openingLiesOnRoomSide(
    PlanOpening o,
    PlanRoom r,
    WallSide side,
  ) {
    const eps = 0.01;
    if (side == WallSide.top) {
      return (o.y - r.y).abs() < eps &&
          o.x >= r.x - eps &&
          o.x + o.length <= r.x + r.width + eps;
    }
    if (side == WallSide.bottom) {
      return (o.y - (r.y + r.height)).abs() < eps &&
          o.x >= r.x - eps &&
          o.x + o.length <= r.x + r.width + eps;
    }
    if (side == WallSide.left) {
      return (o.x - r.x).abs() < eps &&
          o.y >= r.y - eps &&
          o.y + o.length <= r.y + r.height + eps;
    }
    return (o.x - (r.x + r.width)).abs() < eps &&
        o.y >= r.y - eps &&
        o.y + o.length <= r.y + r.height + eps;
  }

  /// Гарантирует, что каждая комната плана доступна — хотя бы одной
  /// внутренней дверью/проходом. Если есть изолированные помещения
  /// (ни одной двери/архивольта не ведёт в них), добавляем
  /// принудительную дверь по самой длинной общей стене. Предпочтение —
  /// общая стена со свободной зоной (коридор/прихожая).
  static void _enforceRoomConnectivity(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
  ) {
    if (rooms.length <= 1) return;

    // Для каждой комнаты считаем, сколько дверей/архивольтов в неё входит.
    bool hasAnyOpening(PlanRoom r) {
      for (final o in openings) {
        if (o.kind != OpeningKind.door &&
            o.kind != OpeningKind.archway) {
          continue;
        }
        // Проём на стене комнаты — значит комната доступна.
        if (_openingLiesOnRoomWall(o, r)) return true;
      }
      return false;
    }

    for (final r in rooms) {
      if (r.kind == PlanRoomKind.free) continue; // коридоры — общие.
      if (r.kind == PlanRoomKind.staircase) continue;
      if (hasAnyOpening(r)) continue;

      // Ищем лучшую смежную комнату: сперва free-зону, затем жилую.
      _SharedWall? best;
      PlanRoom? bestNb;
      bool bestIsFree = false;
      final isBathroom = r.roomKindName == RoomKind.bathroom.name;
      for (final n in rooms) {
        if (identical(n, r)) continue;
        if (n.kind == PlanRoomKind.staircase) continue;
        final sw = _sharedWall(r, n);
        if (sw == null || sw.length < _minSharedWallForDoor) continue;
        final isFree = n.kind == PlanRoomKind.free;
        // Правило 3 — даже при принудительном подключении не открываем
        // санузел в гостиную/столовую (livingRoom). Лучше получить
        // тупик, чем строить план с неправильной эргономикой —
        // глобальная проверка достижимости подскажет переразложить.
        if (isBathroom && n.roomKindName == RoomKind.livingRoom.name) {
          continue;
        }
        // Запрет кухня↔санузел — не подключаем напрямую даже из-за изоляции.
        if (!isFree && !_shouldHaveDoor(r, n)) continue;
        // Предпочтение: (free > non-free), затем по длине стены.
        if (best == null ||
            (isFree && !bestIsFree) ||
            (isFree == bestIsFree && sw.length > best.length)) {
          best = sw;
          bestNb = n;
          bestIsFree = isFree;
        }
      }

      if (best == null || bestNb == null) continue;
      final width = _doorWidthBetween(r, bestNb);
      if (best.length < width + 0.2) continue;
      final mid = (best.start + best.end) / 2;
      final doorStart = mid - width / 2;
      openings.add(PlanOpening(
        kind: OpeningKind.door,
        side: best.isVertical ? WallSide.left : WallSide.top,
        x: best.isVertical ? best.coord : doorStart,
        y: best.isVertical ? doorStart : best.coord,
        length: width,
        swing: best.swing,
      ));
    }
  }

  /// Глобальная проверка достижимости (СП 55.13330.2017 п. 6.6).
  ///
  /// Строит граф «комната ↔ комната» по существующим дверям/проходам и
  /// проверяет, что каждая жилая/служебная комната достижима из корня
  /// (входной/лестничной зоны). Если есть «островки» из нескольких
  /// связанных между собой комнат, но без связи с корнем — добавляет
  /// проход (дверь или открытый проём) в ближайшую достижимую соседку.
  ///
  /// В отличие от [_enforceRoomConnectivity], которая проверяет только
  /// «у комнаты есть хоть один проём», этот метод гарантирует, что
  /// проход реально ведёт к выходу из дома, а не в изолированную
  /// группу комнат.
  static void _enforceGlobalReachability(
    List<PlanRoom> rooms,
    List<PlanOpening> openings,
    double planWidth,
    double planHeight, {
    required bool isFirstFloor,
  }) {
    if (rooms.length <= 1) return;
    final n = rooms.length;

    // Граф смежности по проёмам: какие пары комнат связаны
    // существующей дверью/архивольтом.
    final adj = List<Set<int>>.generate(n, (_) => <int>{});
    for (final o in openings) {
      if (o.kind != OpeningKind.door && o.kind != OpeningKind.archway) {
        continue;
      }
      final on = <int>[];
      for (var i = 0; i < n; i++) {
        if (_openingLiesOnRoomWall(o, rooms[i])) on.add(i);
      }
      for (var i = 0; i < on.length; i++) {
        for (var j = i + 1; j < on.length; j++) {
          adj[on[i]].add(on[j]);
          adj[on[j]].add(on[i]);
        }
      }
    }

    // Корни:
    //   • 1-й этаж — все «свободные» зоны на внешнем контуре (потенциальные
    //     прихожие, через одну из них планировщик в шаге 3 поставит
    //     входную дверь);
    //   • верхние этажи — свободные зоны, граничащие с лестницей.
    final roots = <int>{};
    if (isFirstFloor) {
      for (var i = 0; i < n; i++) {
        final r = rooms[i];
        if (r.kind != PlanRoomKind.free) continue;
        if (_hasOuterWall(r, planWidth, planHeight)) roots.add(i);
      }
    }
    for (var i = 0; i < n; i++) {
      if (rooms[i].kind != PlanRoomKind.staircase) continue;
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        if (rooms[j].kind != PlanRoomKind.free) continue;
        final sw = _sharedWall(rooms[j], rooms[i]);
        if (sw != null && sw.length >= _corridorWidth - 0.1) roots.add(j);
      }
    }
    // Фолбэк: если корней не нашли (например, вырожденный случай —
    // ручная раскладка без free-зон), берём первую свободную зону или
    // любую большую комнату с внешней стеной.
    if (roots.isEmpty) {
      for (var i = 0; i < n; i++) {
        if (rooms[i].kind == PlanRoomKind.free) {
          roots.add(i);
          break;
        }
      }
    }
    if (roots.isEmpty) {
      for (var i = 0; i < n; i++) {
        if (rooms[i].kind == PlanRoomKind.staircase) continue;
        if (_hasOuterWall(rooms[i], planWidth, planHeight)) {
          roots.add(i);
          break;
        }
      }
    }
    if (roots.isEmpty) return;

    // BFS от корней.
    Set<int> bfs() {
      final reached = <int>{...roots};
      final queue = <int>[...roots];
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        for (final nb in adj[cur]) {
          if (reached.add(nb)) queue.add(nb);
        }
      }
      return reached;
    }

    // Итеративно добавляем проёмы для недостижимых комнат, пока что-то
    // меняется. На каждой итерации обходим все «запертые» комнаты и
    // подключаем их к ближайшей достижимой через новый дверной проём.
    for (var iter = 0; iter < n + 1; iter++) {
      final reached = bfs();
      var added = false;
      for (var i = 0; i < n; i++) {
        if (reached.contains(i)) continue;
        if (rooms[i].kind == PlanRoomKind.staircase) continue;

        _SharedWall? bestSw;
        int? bestJ;
        bool bestIsFree = false;
        for (final j in reached) {
          if (rooms[j].kind == PlanRoomKind.staircase) continue;
          final sw = _sharedWall(rooms[i], rooms[j]);
          if (sw == null || sw.length < _minSharedWallForDoor) continue;
          // Запрет кухня↔санузел (СП 55.13330.2017 п. 9.22). Если
          // соседка — не free и пара запрещена — пропускаем.
          final jFree = rooms[j].kind == PlanRoomKind.free;
          if (!jFree && !_shouldHaveDoor(rooms[i], rooms[j])) continue;
          if (bestSw == null ||
              (jFree && !bestIsFree) ||
              (jFree == bestIsFree && sw.length > bestSw.length)) {
            bestSw = sw;
            bestJ = j;
            bestIsFree = jFree;
          }
        }
        if (bestSw == null || bestJ == null) continue;
        final width = _doorWidthBetween(rooms[i], rooms[bestJ]);
        if (bestSw.length < width + 0.2) continue;
        final mid = (bestSw.start + bestSw.end) / 2;
        final doorStart = mid - width / 2;
        // Между двумя свободными зонами — открытый проход (архивольт).
        final isFreePair =
            rooms[i].kind == PlanRoomKind.free && bestIsFree;
        openings.add(PlanOpening(
          kind: isFreePair ? OpeningKind.archway : OpeningKind.door,
          side: bestSw.isVertical ? WallSide.left : WallSide.top,
          x: bestSw.isVertical ? bestSw.coord : doorStart,
          y: bestSw.isVertical ? doorStart : bestSw.coord,
          length: isFreePair ? bestSw.length : width,
          swing: bestSw.swing,
        ));
        adj[i].add(bestJ);
        adj[bestJ].add(i);
        added = true;
      }
      if (!added) break;
    }
  }

  /// Проверка: лежит ли проём на одной из стен комнаты.
  ///
  /// Стена общая для двух смежных комнат (верх одной = низ другой). Проём
  /// создаётся с конкретным [PlanOpening.side], но физически лежит на
  /// общей стене обоих помещений. Поэтому сравниваем координату проёма
  /// с обеими стенами комнаты (top/bottom для горизонтального проёма,
  /// left/right для вертикального) и считаем матч, если совпала любая.
  static bool _openingLiesOnRoomWall(PlanOpening o, PlanRoom r) {
    const eps = 0.01;
    if (o.side == WallSide.top || o.side == WallSide.bottom) {
      final onTop = (o.y - r.y).abs() < eps;
      final onBottom = (o.y - (r.y + r.height)).abs() < eps;
      if (!onTop && !onBottom) return false;
      return o.x >= r.x - eps && o.x + o.length <= r.x + r.width + eps;
    }
    final onLeft = (o.x - r.x).abs() < eps;
    final onRight = (o.x - (r.x + r.width)).abs() < eps;
    if (!onLeft && !onRight) return false;
    return o.y >= r.y - eps && o.y + o.length <= r.y + r.height + eps;
  }

  static bool _shouldHaveDoor(PlanRoom a, PlanRoom b) {
    // Лестница связана через коридор/прихожую без двери (открытый проём
    // не отрисовываем как дверь, чтобы не загромождать схему).
    if (a.kind == PlanRoomKind.staircase || b.kind == PlanRoomKind.staircase) {
      return false;
    }
    final aFree = a.kind == PlanRoomKind.free;
    final bFree = b.kind == PlanRoomKind.free;
    // Между двумя свободными зонами двери не нужны (это один коридор).
    if (aFree && bFree) return false;
    final aKind = a.roomKindName;
    final bKind = b.roomKindName;
    // Запрет СП 55.13330.2017 п. 9.22 + СанПиН 2.1.3684-21:
    // дверь из кухни в санузел (через короткое расстояние от плиты до
    // унитаза) запрещена. Свободная зона/коридор между ними обязательны.
    final isKitchenBathroom = (aKind == RoomKind.kitchen.name &&
            bKind == RoomKind.bathroom.name) ||
        (aKind == RoomKind.bathroom.name && bKind == RoomKind.kitchen.name);
    if (isKitchenBathroom) return false;
    // Свободная зона <-> любая комната — дверь есть.
    if (aFree || bFree) return true;
    // Гостиная <-> кухня — открытый проход (студия). Считаем как дверь.
    final livingKitchen = (aKind == RoomKind.livingRoom.name &&
            bKind == RoomKind.kitchen.name) ||
        (aKind == RoomKind.kitchen.name &&
            bKind == RoomKind.livingRoom.name);
    if (livingKitchen) return true;
    // Правило 3: дверь санузла НЕ должна выходить в гостиную/столовую.
    // Это эргономическое требование (запах, шум) — санузел всегда
    // открывается только в коридор/прихожую/спальню (en-suite). Если
    // у санузла нет смежной free-зоны и нет смежной спальни,
    // _enforceRoomConnectivity всё равно подключит его, но через
    // ближайшую non-living комнату (см. соответствующий фильтр там).
    final livingBathroom = (aKind == RoomKind.livingRoom.name &&
            bKind == RoomKind.bathroom.name) ||
        (aKind == RoomKind.bathroom.name &&
            bKind == RoomKind.livingRoom.name);
    if (livingBathroom) return false;
    // Спальня <-> санузел — допустимо (en-suite санузел при спальне).
    final bedroomBathroom = (aKind == RoomKind.bedroom.name &&
            bKind == RoomKind.bathroom.name) ||
        (aKind == RoomKind.bathroom.name &&
            bKind == RoomKind.bedroom.name);
    if (bedroomBathroom) return true;
    // Все остальные пары жилых/служебных комнат напрямую не соединяем —
    // только через коридор (СП 55.13330.2017).
    return false;
  }

  static double _doorWidthBetween(PlanRoom a, PlanRoom b) {
    bool isNarrow(String? n) =>
        n == RoomKind.bathroom.name ||
        n == RoomKind.storage.name ||
        n == RoomKind.boilerRoom.name;
    if (isNarrow(a.roomKindName) || isNarrow(b.roomKindName)) {
      return _bathDoorWidth;
    }
    return _doorWidth;
  }

  /// Жилые комнаты, для которых обязательно нужно полноценное окно
  /// 1.0–2.4 м (СП 55.13330.2017, СП 23-102).
  static bool _needsPrimaryWindow(PlanRoom r) {
    if (r.kind != PlanRoomKind.room) return false;
    final n = r.roomKindName;
    return n == RoomKind.bedroom.name ||
        n == RoomKind.livingRoom.name ||
        n == RoomKind.kitchen.name ||
        n == RoomKind.study.name;
  }

  /// Правило 5: служебные помещения с наружной стеной тоже получают
  /// окно (форточку 0.6–1.0 м) — это и комфорт, и улучшенная
  /// вентиляция (СП 60.13330.2020). Касается санузлов, кладовых,
  /// котельных. Прихожая/коридор остаются без окон, чтобы не
  /// загромождать схему — у них нет наружных требований к
  /// инсоляции.
  static bool _needsServiceWindow(PlanRoom r) {
    if (r.kind != PlanRoomKind.room) return false;
    final n = r.roomKindName;
    return n == RoomKind.bathroom.name ||
        n == RoomKind.storage.name ||
        n == RoomKind.boilerRoom.name;
  }

  static bool _needsWindow(PlanRoom r) =>
      _needsPrimaryWindow(r) || _needsServiceWindow(r);

  static bool _isOuterWall(
    PlanRoom r,
    WallSide side,
    double planW,
    double planH,
  ) {
    const eps = 0.05;
    switch (side) {
      case WallSide.top:
        return r.y < eps;
      case WallSide.bottom:
        return (r.y + r.height) > planH - eps;
      case WallSide.left:
        return r.x < eps;
      case WallSide.right:
        return (r.x + r.width) > planW - eps;
    }
  }

  static bool _hasOuterWall(PlanRoom r, double planW, double planH) {
    for (final s in WallSide.values) {
      if (_isOuterWall(r, s, planW, planH)) return true;
    }
    return false;
  }

  static _SharedWall? _sharedWall(PlanRoom a, PlanRoom b) {
    const eps = 0.05;
    // Вертикальная общая стена: a.right == b.left или наоборот.
    if ((a.x + a.width - b.x).abs() < eps) {
      final top = a.y > b.y ? a.y : b.y;
      final bottom = (a.y + a.height) < (b.y + b.height)
          ? (a.y + a.height)
          : (b.y + b.height);
      if (bottom - top > eps) {
        return _SharedWall(
          isVertical: true,
          coord: a.x + a.width,
          start: top,
          end: bottom,
          swing: 1,
        );
      }
    }
    if ((b.x + b.width - a.x).abs() < eps) {
      final top = a.y > b.y ? a.y : b.y;
      final bottom = (a.y + a.height) < (b.y + b.height)
          ? (a.y + a.height)
          : (b.y + b.height);
      if (bottom - top > eps) {
        return _SharedWall(
          isVertical: true,
          coord: a.x,
          start: top,
          end: bottom,
          swing: -1,
        );
      }
    }
    // Горизонтальная общая стена: a.bottom == b.top или наоборот.
    if ((a.y + a.height - b.y).abs() < eps) {
      final left = a.x > b.x ? a.x : b.x;
      final right = (a.x + a.width) < (b.x + b.width)
          ? (a.x + a.width)
          : (b.x + b.width);
      if (right - left > eps) {
        return _SharedWall(
          isVertical: false,
          coord: a.y + a.height,
          start: left,
          end: right,
          swing: 1,
        );
      }
    }
    if ((b.y + b.height - a.y).abs() < eps) {
      final left = a.x > b.x ? a.x : b.x;
      final right = (a.x + a.width) < (b.x + b.width)
          ? (a.x + a.width)
          : (b.x + b.width);
      if (right - left > eps) {
        return _SharedWall(
          isVertical: false,
          coord: a.y,
          start: left,
          end: right,
          swing: -1,
        );
      }
    }
    return null;
  }
}

class _SharedWall {
  final bool isVertical;
  final double coord; // x для вертикальной, y для горизонтальной
  final double start; // y или x начала пересечения
  final double end;
  final int swing;
  double get length => end - start;
  const _SharedWall({
    required this.isVertical,
    required this.coord,
    required this.start,
    required this.end,
    required this.swing,
  });
}

class _RoomReq {
  final RoomKind? kind;
  final String label;
  final double area;
  final bool isFree;

  _RoomReq({
    required this.kind,
    required this.label,
    required this.area,
    this.isFree = false,
  });

  factory _RoomReq.free(double area) => _RoomReq(
        kind: null,
        label: 'Свободная зона',
        area: area,
        isFree: true,
      );

  /// Альтернативная фабрика — для обозначения свободной зоны в схеме
  /// без магистрального коридора (анфилада/студия/гостиная-холл),
  /// где остаток площади визуально работает как «прихожая/коридор».
  factory _RoomReq.hallway(double area) => _RoomReq(
        kind: null,
        label: 'Прихожая / коридор',
        area: area,
        isFree: true,
      );

  PlanRoomKind get planKind =>
      isFree ? PlanRoomKind.free : PlanRoomKind.room;
}
