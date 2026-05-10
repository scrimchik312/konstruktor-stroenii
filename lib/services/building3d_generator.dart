import 'dart:math' as math;

import '../models/building3d.dart';
import '../models/building_dimensions.dart';
import '../models/building_footprint.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import 'floor_plan_generator.dart';
import 'foundation_plan_generator.dart';
import 'roof_plan_geometry.dart';

/// Собирает трёхмерную модель [Building3D] из реальных параметров проекта.
///
/// Все цифры — из расчётов и ТЗ:
/// • пятно W×L — `brief.footprintWidth/Length`;
/// • высота этажа — `staircase.floorHeight` или 2.8 м (СП 55.13330.2017);
/// • число этажей — `brief.floors`, мансарда — `brief.hasMansard`;
/// • глубина и тип фундамента — из [FoundationPlanGenerator];
/// • уклон кровли — `roof.slopeAngle`, тип — `roof.type`;
/// • окна и наружные двери — из `plan.openings` каждого этажа.
///
/// Если ТЗ не заполнено (нет пятна) — возвращает `null`.
class Building3DGenerator {
  Building3DGenerator._();

  /// Стандартные размеры проёмов (СП 55.13330.2017, типовая практика):
  /// окно 1.5 м (h), подоконник 0.9 м, входная дверь 2.1 м.
  static const double _defaultWindowHeight = 1.5;
  static const double _defaultWindowSillHeight = 0.9;
  static const double _defaultDoorHeight = 2.1;

  /// Собирает 3D-модель из текущего проекта.
  ///
  /// Если переданы [floorPlans] — используются они (это реальные планы
  /// этажей, отрисованные пользователем; именно их проёмы должны
  /// отображаться на фасаде/аксонометрии). Иначе планы достраиваются
  /// автоматически из `brief` через [FloorPlanGenerator].
  static Building3D? generate(
    HouseProject project, {
    List<FloorPlan>? floorPlans,
  }) {
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    if (w <= 0 || l <= 0) return null;

    // v68.11: единый источник истины для габаритов. Те же цифры в
    // фасадах/разрезах (`PdfBuilder._elevation`), КЖ-1 и в 3D-модели.
    final dims = BuildingDimensions.of(project, widthM: w, lengthM: l);
    final floors = dims.floors;
    final ceilingH = dims.floorHeight;
    final hasMansard = dims.hasMansard;
    final hasBasement = dims.hasBasement;
    final wallThickness = dims.wallThicknessM;
    final slabThickness = dims.slabThicknessM;
    final foundationDepth = dims.foundationDepth;
    final plinthHeight = dims.plinthHeight;

    // Подпись типа фундамента — отдельно от расчёта (нужна для
    // штампа КЖ и подсказок в 3D).
    String foundationLabel = 'Фундамент';
    final fp = FoundationPlanGenerator.generate(project);
    if (fp != null) {
      foundationLabel = fp.typeLabel;
    } else if (project.foundation.type != null) {
      foundationLabel = project.foundation.summary;
    }
    if (hasBasement) {
      foundationLabel = '$foundationLabel · подвал';
    }

    // -------- Floor plans for openings ------------------------------
    // Приоритет: явно переданные планы (от пользователя) → авто-генерация
    // из brief.
    final plans = (floorPlans != null && floorPlans.isNotEmpty)
        ? floorPlans
        : _resolveFloorPlans(project);

    // -------- Build outline (rectangle / polygon) -------------------
    // Phase-3b §17.2.1: если у проекта задан полигональный
    // architectureFootprint — берём его контур, иначе строим
    // прямоугольник bbox-а w×l (старое поведение).
    final archFp = project.architectureFootprint;
    final isPolygonalFp = archFp != null && _isFpPolygonal(archFp, w, l);
    final outline = <Vec3>[
      if (isPolygonalFp)
        for (final v in archFp.outline) Vec3(v.x, v.y, 0)
      else ...[
        Vec3(0, 0, 0),
        Vec3(w, 0, 0),
        Vec3(w, l, 0),
        Vec3(0, l, 0),
      ],
    ];

    final foundation = Foundation3D(
      outline: outline,
      depthM: foundationDepth,
      plinthHeightM: plinthHeight,
      typeLabel: foundationLabel,
    );

    // -------- Floors -----------------------------------------------
    final floors3d = <Floor3D>[];
    final totalFloors = floors + (hasMansard ? 1 : 0);
    for (var i = 0; i < totalFloors; i++) {
      final isMansard = hasMansard && i == totalFloors - 1;
      final h = isMansard ? ceilingH * 0.8 : ceilingH;
      final elevation = plinthHeight + i * ceilingH;
      final plan = i < plans.length
          ? plans[i]
          : (plans.isNotEmpty ? plans.last : null);
      final walls = isPolygonalFp
          ? _buildPolygonalExteriorWalls(
              footprint: archFp,
              elevation: elevation,
              wallHeight: h,
              wallThickness: wallThickness,
              plan: plan,
            )
          : _buildExteriorWalls(
              w: w,
              l: l,
              elevation: elevation,
              wallHeight: h,
              wallThickness: wallThickness,
              plan: plan,
              floorIndex: i,
            );
      floors3d.add(Floor3D(
        elevationM: elevation,
        heightM: h,
        walls: walls,
        label: isMansard ? 'Мансарда' : '${i + 1} этаж',
        ceilingSlab: i < totalFloors - 1
            ? Slab3D(
                outline: outline,
                thicknessM: slabThickness,
              )
            : null,
      ));
    }

    // -------- Roof --------------------------------------------------
    final wallTopElev = plinthHeight + totalFloors * ceilingH +
        (hasMansard ? -ceilingH * 0.2 : 0);
    final slopeDeg = dims.slopeDeg;
    final roofShape = dims.roofShape;
    // Phase-3b §17.2.1 next-slice: для полигональных проектов (L/T/U/Г-форм)
    // bbox-овая кровля «висит» над зоной выреза. Раскладываем полигон
    // на оси-выровненные прямоугольники и строим отдельную кровлю
    // (плоскую/двускатную) над каждым.  Конёк, если он один —
    // идёт по самому длинному прямоугольнику; для остальных
    // ставится перпендикулярный конёк с тем же углом ската, что
    // образует валентную долину на стыке.
    final roof = isPolygonalFp
        ? _buildPolygonalRoof(
            footprint: archFp,
            wallTopZ: wallTopElev,
            slopeDeg: slopeDeg,
            shape: roofShape,
          )
        : _buildRoof(
            w: w,
            l: l,
            wallTopZ: wallTopElev,
            slopeDeg: slopeDeg,
            shape: roofShape,
          );

    // -------- Attachments -----------------------------------------
    final attachments3d = <Attachment3D>[];
    if (plans.isNotEmpty) {
      for (final att in plans.first.attachments) {
        attachments3d.add(Attachment3D(
          outline: [
            Vec3(att.x, att.y, 0),
            Vec3(att.x + att.width, att.y, 0),
            Vec3(att.x + att.width, att.y + att.height, 0),
            Vec3(att.x, att.y + att.height, 0),
          ],
          heightM: switch (att.kind) {
            // Гараж — 3.0 м (типовая высота для пристроенного гаража
            // ИЖС, чтобы помещался автомобиль с гаражными воротами 2.4 м).
            PlanAttachmentKind.garage => 3.0,
            PlanAttachmentKind.terrace => 0.6,
            PlanAttachmentKind.porch => 0.45,
          },
          typeLabel: switch (att.kind) {
            PlanAttachmentKind.garage => 'Гараж',
            PlanAttachmentKind.terrace => 'Терраса',
            PlanAttachmentKind.porch => 'Крыльцо',
          },
        ));
      }
    }

    final totalHeight = foundationDepth + wallTopElev + roof.totalHeight;

    return Building3D(
      projectName:
          project.name.isEmpty ? 'Индивидуальный жилой дом' : project.name,
      footprintWidth: w,
      footprintLength: l,
      totalHeight: totalHeight,
      foundation: foundation,
      floors: floors3d,
      roof: roof.model,
      attachments: attachments3d,
      wallMaterialName: project.brief.wallMaterial?.name,
      roofMaterialId: project.roof.roofingMaterial,
    );
  }

  // ------------------------------------------------------------------

  /// Возвращает планы этажей, сгенерированные через [FloorPlanGenerator].
  /// Это даёт реальные `openings`, иначе фасад будет «глухим».
  static List<FloorPlan> _resolveFloorPlans(HouseProject project) {
    final generated = FloorPlanGenerator.generate(
      project.brief,
      ceilingHeight: project.walls.height ?? project.staircase.floorHeight,
    );
    if (generated.isNotEmpty) return generated;
    return const [];
  }

  /// Строит 4 наружные стены пятна.
  static List<Wall3D> _buildExteriorWalls({
    required double w,
    required double l,
    required double elevation,
    required double wallHeight,
    required double wallThickness,
    required FloorPlan? plan,
    required int floorIndex,
  }) {
    // Контур: SW (0,0) → SE (w,0) → NE (w,l) → NW (0,l).
    // Описание сторон в системе координат пятна:
    //   bottom (south) = y == l, идёт от (0,l) к (w,l) — wallSide.bottom
    //   top    (north) = y == 0, идёт от (0,0) к (w,0) — wallSide.top
    //   left   (west)  = x == 0, идёт от (0,0) к (0,l) — wallSide.left
    //   right  (east)  = x == w, идёт от (w,0) к (w,l) — wallSide.right
    //
    // Outward-нормаль направлена «наружу» от здания.
    final south = Wall3D(
      start: Vec3(0, l, elevation),
      end: Vec3(w, l, elevation),
      height: wallHeight,
      thickness: wallThickness,
      outwardNormal: const Vec3(0, 1, 0),
      openings: _externalOpeningsForSide(
          plan: plan, side: WallSide.bottom, wallLength: w),
    );
    final north = Wall3D(
      start: Vec3(w, 0, elevation),
      end: Vec3(0, 0, elevation),
      height: wallHeight,
      thickness: wallThickness,
      outwardNormal: const Vec3(0, -1, 0),
      openings: _externalOpeningsForSide(
          plan: plan, side: WallSide.top, wallLength: w, mirror: true),
    );
    final east = Wall3D(
      start: Vec3(w, l, elevation),
      end: Vec3(w, 0, elevation),
      height: wallHeight,
      thickness: wallThickness,
      outwardNormal: const Vec3(1, 0, 0),
      openings: _externalOpeningsForSide(
          plan: plan, side: WallSide.right, wallLength: l, mirror: true),
    );
    final west = Wall3D(
      start: Vec3(0, 0, elevation),
      end: Vec3(0, l, elevation),
      height: wallHeight,
      thickness: wallThickness,
      outwardNormal: const Vec3(-1, 0, 0),
      openings: _externalOpeningsForSide(
          plan: plan, side: WallSide.left, wallLength: l),
    );
    return [south, north, east, west];
  }

  /// Является ли `footprint` полигональным (не равен прямоугольнику w×l).
  static bool _isFpPolygonal(BuildingFootprint footprint, double w, double l) {
    if (footprint.outline.length != 4) return true;
    final b = footprint.bbox;
    if ((b.width - w).abs() > 1e-3) return true;
    if ((b.height - l).abs() > 1e-3) return true;
    final corners = {
      (b.minX, b.minY),
      (b.maxX, b.minY),
      (b.maxX, b.maxY),
      (b.minX, b.maxY),
    };
    final got = {for (final p in footprint.outline) (p.x, p.y)};
    return !got.containsAll(corners);
  }

  /// Phase-3b §17.2.1. Строит наружные стены по контуру полигонального
  /// footprint-а: на каждый сегмент outline создаётся свой `Wall3D`.
  /// Outward-нормаль рассчитывается как `(dy, -dx)/|edge|` (валидно
  /// для CCW-ориентированного контура). Поддерживаются только
  /// axis-aligned полигоны (L/T/U/+) — диагональные сегменты отдельной
  /// фазой не покрываются.
  static List<Wall3D> _buildPolygonalExteriorWalls({
    required BuildingFootprint footprint,
    required double elevation,
    required double wallHeight,
    required double wallThickness,
    required FloorPlan? plan,
  }) {
    final walls = <Wall3D>[];
    final n = footprint.outline.length;
    for (var i = 0; i < n; i++) {
      final a = footprint.outline[i];
      final b = footprint.outline[(i + 1) % n];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      final nxv = dy / len;
      final nyv = -dx / len;
      // Определяем сопоставимый WallSide для маппинга проёмов из плана.
      // Только для axis-aligned сегментов.
      WallSide? side;
      if (dy.abs() < 1e-6) {
        // Горизонтальный сегмент.
        side = (nyv < 0) ? WallSide.top : WallSide.bottom;
      } else if (dx.abs() < 1e-6) {
        side = (nxv < 0) ? WallSide.left : WallSide.right;
      }
      walls.add(Wall3D(
        start: Vec3(a.x, a.y, elevation),
        end: Vec3(b.x, b.y, elevation),
        height: wallHeight,
        thickness: wallThickness,
        outwardNormal: Vec3(nxv, nyv, 0),
        openings: _externalOpeningsForSegment(
          plan: plan,
          a: a,
          b: b,
          side: side,
          wallLength: len,
        ),
      ));
    }
    return walls;
  }

  /// Маппинг проёмов плана на сегмент полигонального outline-а.
  /// Берём только проёмы со стороной [side], координата которых
  /// (фиксированная: y для горизонтальных, x для вертикальных) совпадает
  /// с сегментом, а позиция вдоль стены укладывается в `[a → b]`.
  static List<Opening3D> _externalOpeningsForSegment({
    required FloorPlan? plan,
    required Vec2 a,
    required Vec2 b,
    required WallSide? side,
    required double wallLength,
  }) {
    if (plan == null || side == null) return const [];
    final isHoriz = side == WallSide.top || side == WallSide.bottom;
    final segFixed = isHoriz ? a.y : a.x;
    final segMin = isHoriz ? math.min(a.x, b.x) : math.min(a.y, b.y);
    final segMax = isHoriz ? math.max(a.x, b.x) : math.max(a.y, b.y);
    // Направление сегмента (для расчёта offsetAlong от a→b).
    final reversed = isHoriz ? (b.x < a.x) : (b.y < a.y);
    final res = <Opening3D>[];
    const eps = 1e-2;
    for (final o in plan.openings) {
      if (o.side != side) continue;
      if (o.kind != OpeningKind.window &&
          o.kind != OpeningKind.externalDoor) {
        continue;
      }
      final fixedCoord = isHoriz ? o.y : o.x;
      if ((fixedCoord - segFixed).abs() > eps) continue;
      final off = isHoriz ? o.x : o.y;
      if (off < segMin - eps || off + o.length > segMax + eps) continue;
      // offsetAlong считаем от вершины a, следуя направлению a→b.
      final offsetAlong = reversed
          ? segMax - off - o.length
          : off - segMin;
      final isDoor = o.kind == OpeningKind.externalDoor;
      res.add(Opening3D(
        offsetAlong: offsetAlong.clamp(0.0, wallLength).toDouble(),
        bottom: isDoor ? 0.0 : _defaultWindowSillHeight,
        width: o.length.clamp(0.0, wallLength).toDouble(),
        height: isDoor ? _defaultDoorHeight : _defaultWindowHeight,
        kind: isDoor ? OpeningKind3D.door : OpeningKind3D.window,
      ));
    }
    return res;
  }

  /// Берёт из плана этажа все внешние проёмы на указанной стороне и
  /// конвертирует в [Opening3D] с offset вдоль стены.
  static List<Opening3D> _externalOpeningsForSide({
    required FloorPlan? plan,
    required WallSide side,
    required double wallLength,
    bool mirror = false,
  }) {
    if (plan == null) return const [];
    final res = <Opening3D>[];
    for (final o in plan.openings) {
      if (o.side != side) continue;
      if (o.kind != OpeningKind.window &&
          o.kind != OpeningKind.externalDoor) {
        continue;
      }
      final isHoriz = side == WallSide.top || side == WallSide.bottom;
      final off = isHoriz ? o.x : o.y;
      final start = mirror ? wallLength - off - o.length : off;
      final isDoor = o.kind == OpeningKind.externalDoor;
      res.add(Opening3D(
        offsetAlong: start.clamp(0.0, wallLength).toDouble(),
        bottom: isDoor ? 0.0 : _defaultWindowSillHeight,
        width: o.length.clamp(0.0, wallLength).toDouble(),
        height: isDoor ? _defaultDoorHeight : _defaultWindowHeight,
        kind: isDoor ? OpeningKind3D.door : OpeningKind3D.window,
      ));
    }
    return res;
  }

  /// Phase-3b §17.2.1 next-slice: кровля для полигональных footprint-ов
  /// (L/T/U/Г-форм). Раскладывает полигон на оси-выровненные
  /// прямоугольники через [BuildingFootprint.rectangleDecomposition], для
  /// каждого собирает отдельную базовую кровлю (двускатную или плоскую)
  /// и склеивает скаты в единый [Roof3D].
  ///
  /// Простая первая итерация: над каждым прямоугольником декомпозиции
  /// ставится свой конёк по своему длинному боку. Угол ската
  /// сохраняется одинаковый, поэтому для близких по ширине
  /// прямоугольников высоты коньков совпадают; для разных — образуется
  /// «ступень». Это «достаточно хорошо» для предпросмотра и убирает
  /// главный артефакт — крышу, висящую над зоной выреза. Полная
  /// hip+valley геометрия с правильными ендовами — следующий слайс.
  ///
  /// Для `RoofShape.flat` строит одну плоскую плоскость по полигону.
  /// Для `RoofShape.shed`, `hip`, `mansard` пока работает как `gable`
  /// над каждым подпрямоугольником (упрощение «первого слайса»).
  static _RoofBuildResult _buildPolygonalRoof({
    required BuildingFootprint footprint,
    required double wallTopZ,
    required double slopeDeg,
    required RoofShape shape,
  }) {
    // Плоская кровля по полигону: одна «грань» по контуру + лёгкий
    // парапетный подъём, как у прямоугольной плоской.
    if (shape == RoofShape.flat) {
      const flatRise = 0.3;
      final z1 = wallTopZ + flatRise;
      final corners = [
        for (final v in footprint.outline) Vec3(v.x, v.y, z1),
      ];
      return _RoofBuildResult(
        model: Roof3D(
          slopes: [RoofSlope3D(corners: corners)],
          edges: const [],
          typeLabel: 'Плоская',
          slopeDegrees: 1.5,
        ),
        totalHeight: flatRise,
      );
    }

    // Все остальные формы — собираем «букет» двускатных кровель.
    final rects = footprint.rectangleDecomposition();
    if (rects.length <= 1) {
      // Декомпозиция не нашла уступов — фолбэк на bbox-овую логику.
      final b = footprint.bbox;
      return _buildRoof(
        w: b.width,
        l: b.height,
        wallTopZ: wallTopZ,
        slopeDeg: slopeDeg,
        shape: shape,
      );
    }

    final tan = math.tan(slopeDeg * math.pi / 180);
    final allSlopes = <RoofSlope3D>[];
    final allEdges = <RoofEdge3D>[];
    var maxRise = 0.0;
    for (final r in rects) {
      final rW = r.width;
      final rL = r.height;
      final ridgeAlongY = rL >= rW;
      final shortSide = ridgeAlongY ? rW : rL;
      final rise = shortSide / 2 * tan;
      if (rise > maxRise) maxRise = rise;
      // Координаты углов прямоугольника (в системе footprint-а).
      final swTop = Vec3(r.x, r.y, wallTopZ);
      final seTop = Vec3(r.x + rW, r.y, wallTopZ);
      final neTop = Vec3(r.x + rW, r.y + rL, wallTopZ);
      final nwTop = Vec3(r.x, r.y + rL, wallTopZ);
      if (ridgeAlongY) {
        final cx = r.x + rW / 2;
        final ridgeA = Vec3(cx, r.y, wallTopZ + rise);
        final ridgeB = Vec3(cx, r.y + rL, wallTopZ + rise);
        allSlopes.add(RoofSlope3D(corners: [seTop, neTop, ridgeB, ridgeA]));
        allSlopes.add(RoofSlope3D(corners: [ridgeA, ridgeB, nwTop, swTop]));
        allEdges.add(RoofEdge3D(ridgeA, ridgeB));
        allEdges.add(RoofEdge3D(swTop, ridgeA));
        allEdges.add(RoofEdge3D(seTop, ridgeA));
        allEdges.add(RoofEdge3D(nwTop, ridgeB));
        allEdges.add(RoofEdge3D(neTop, ridgeB));
      } else {
        final cy = r.y + rL / 2;
        final ridgeA = Vec3(r.x, cy, wallTopZ + rise);
        final ridgeB = Vec3(r.x + rW, cy, wallTopZ + rise);
        allSlopes.add(RoofSlope3D(corners: [swTop, seTop, ridgeB, ridgeA]));
        allSlopes.add(RoofSlope3D(corners: [ridgeA, ridgeB, neTop, nwTop]));
        allEdges.add(RoofEdge3D(ridgeA, ridgeB));
        allEdges.add(RoofEdge3D(swTop, ridgeA));
        allEdges.add(RoofEdge3D(nwTop, ridgeA));
        allEdges.add(RoofEdge3D(seTop, ridgeB));
        allEdges.add(RoofEdge3D(neTop, ridgeB));
      }
    }
    return _RoofBuildResult(
      model: Roof3D(
        slopes: allSlopes,
        edges: allEdges,
        typeLabel: 'Комбинированная двускатная (по уступам)',
        slopeDegrees: slopeDeg,
      ),
      totalHeight: maxRise,
    );
  }

  /// Строит 3D-кровлю по типу и углу ската (для прямоугольных проектов).
  static _RoofBuildResult _buildRoof({
    required double w,
    required double l,
    required double wallTopZ,
    required double slopeDeg,
    required RoofShape shape,
  }) {
    final tan = math.tan(slopeDeg * math.pi / 180);
    switch (shape) {
      case RoofShape.flat:
        // Плоская — небольшой парапет/слой; делаем «гипсокартонную»
        // плоскую крышу высотой 0.3 м.
        const flatRise = 0.3;
        final z1 = wallTopZ + flatRise;
        final corners = [
          Vec3(0, 0, z1),
          Vec3(w, 0, z1),
          Vec3(w, l, z1),
          Vec3(0, l, z1),
        ];
        return _RoofBuildResult(
          model: Roof3D(
            slopes: [
              RoofSlope3D(corners: corners),
            ],
            edges: const [],
            typeLabel: 'Плоская',
            slopeDegrees: 1.5,
          ),
          totalHeight: flatRise,
        );
      case RoofShape.gable:
        // Двускатная — конёк вдоль длинной стороны.
        // Если l > w → конёк параллелен Y, на середине X.
        final bool ridgeAlongY = l >= w;
        final double rise =
            (ridgeAlongY ? w : l) / 2 * tan;
        if (ridgeAlongY) {
          final ridge = w / 2;
          final ridgeA = Vec3(ridge, 0, wallTopZ + rise);
          final ridgeB = Vec3(ridge, l, wallTopZ + rise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          // Восточный скат CCW снаружи.
          final eastSlope = RoofSlope3D(corners: [
            seTop,
            neTop,
            ridgeB,
            ridgeA,
          ]);
          final westSlope = RoofSlope3D(corners: [
            ridgeA,
            ridgeB,
            nwTop,
            swTop,
          ]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [eastSlope, westSlope],
              edges: [
                RoofEdge3D(ridgeA, ridgeB),
                RoofEdge3D(swTop, ridgeA),
                RoofEdge3D(seTop, ridgeA),
                RoofEdge3D(nwTop, ridgeB),
                RoofEdge3D(neTop, ridgeB),
              ],
              typeLabel: 'Двускатная',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        } else {
          final ridge = l / 2;
          final ridgeA = Vec3(0, ridge, wallTopZ + rise);
          final ridgeB = Vec3(w, ridge, wallTopZ + rise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          final southSlope = RoofSlope3D(corners: [
            swTop,
            seTop,
            ridgeB,
            ridgeA,
          ]);
          final northSlope = RoofSlope3D(corners: [
            ridgeA,
            ridgeB,
            neTop,
            nwTop,
          ]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [southSlope, northSlope],
              edges: [
                RoofEdge3D(ridgeA, ridgeB),
                RoofEdge3D(swTop, ridgeA),
                RoofEdge3D(nwTop, ridgeA),
                RoofEdge3D(seTop, ridgeB),
                RoofEdge3D(neTop, ridgeB),
              ],
              typeLabel: 'Двускатная',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        }
      case RoofShape.hip:
        // Вальмовая — конёк короче, по центру длинной стороны, четыре
        // ската + накосы.
        final bool ridgeAlongY = l >= w;
        final shortSide = math.min(w, l).toDouble();
        final longSide = math.max(w, l).toDouble();
        final rise = shortSide / 2 * tan;
        // Конёк = (длинная - короткая) — типичная пропорция.
        final ridgeLen = math.max(longSide - shortSide, longSide * 0.3);
        if (ridgeAlongY) {
          final ridgeY1 = (l - ridgeLen) / 2;
          final ridgeY2 = ridgeY1 + ridgeLen;
          final cx = w / 2;
          final ra = Vec3(cx, ridgeY1, wallTopZ + rise);
          final rb = Vec3(cx, ridgeY2, wallTopZ + rise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          // Юг (трапеция или треуг.) — между swTop, seTop и точкой ra.
          final southHip =
              RoofSlope3D(corners: [swTop, seTop, ra]);
          final northHip =
              RoofSlope3D(corners: [neTop, nwTop, rb]);
          final eastSlope = RoofSlope3D(corners: [seTop, neTop, rb, ra]);
          final westSlope = RoofSlope3D(corners: [nwTop, swTop, ra, rb]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [southHip, northHip, eastSlope, westSlope],
              edges: [
                RoofEdge3D(ra, rb),
                RoofEdge3D(swTop, ra),
                RoofEdge3D(seTop, ra),
                RoofEdge3D(nwTop, rb),
                RoofEdge3D(neTop, rb),
              ],
              typeLabel: 'Вальмовая',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        } else {
          final ridgeX1 = (w - ridgeLen) / 2;
          final ridgeX2 = ridgeX1 + ridgeLen;
          final cy = l / 2;
          final ra = Vec3(ridgeX1, cy, wallTopZ + rise);
          final rb = Vec3(ridgeX2, cy, wallTopZ + rise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          final westHip =
              RoofSlope3D(corners: [nwTop, swTop, ra]);
          final eastHip =
              RoofSlope3D(corners: [seTop, neTop, rb]);
          final southSlope =
              RoofSlope3D(corners: [swTop, seTop, rb, ra]);
          final northSlope =
              RoofSlope3D(corners: [neTop, nwTop, ra, rb]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [westHip, eastHip, southSlope, northSlope],
              edges: [
                RoofEdge3D(ra, rb),
                RoofEdge3D(swTop, ra),
                RoofEdge3D(nwTop, ra),
                RoofEdge3D(seTop, rb),
                RoofEdge3D(neTop, rb),
              ],
              typeLabel: 'Вальмовая',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        }
      case RoofShape.shed:
        // Односкатная — поднимается вдоль X (восточная сторона выше).
        final rise = w * tan;
        final swTop = Vec3(0, 0, wallTopZ);
        final seTop = Vec3(w, 0, wallTopZ + rise);
        final neTop = Vec3(w, l, wallTopZ + rise);
        final nwTop = Vec3(0, l, wallTopZ);
        return _RoofBuildResult(
          model: Roof3D(
            slopes: [
              RoofSlope3D(corners: [swTop, seTop, neTop, nwTop]),
            ],
            edges: const [],
            typeLabel: 'Односкатная',
            slopeDegrees: slopeDeg,
          ),
          totalHeight: rise,
        );
      case RoofShape.mansard:
        // Мансардная (ломаная): нижние скаты крутые, верхние пологие.
        // Делаем как двускатную с коньком высотой rise, но добавляем
        // промежуточный «слом» на 60% высоты.
        final bool ridgeAlongY = l >= w;
        final shortSide = ridgeAlongY ? w : l;
        final rise = shortSide / 2 * tan;
        final breakRise = rise * 0.5;
        final breakOffset = shortSide / 4;
        if (ridgeAlongY) {
          final ridge = w / 2;
          final ridgeA = Vec3(ridge, 0, wallTopZ + rise);
          final ridgeB = Vec3(ridge, l, wallTopZ + rise);
          final breakLeftA = Vec3(breakOffset, 0, wallTopZ + breakRise);
          final breakRightA =
              Vec3(w - breakOffset, 0, wallTopZ + breakRise);
          final breakLeftB = Vec3(breakOffset, l, wallTopZ + breakRise);
          final breakRightB =
              Vec3(w - breakOffset, l, wallTopZ + breakRise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          final eastLow =
              RoofSlope3D(corners: [seTop, neTop, breakRightB, breakRightA]);
          final eastHigh = RoofSlope3D(corners: [
            breakRightA,
            breakRightB,
            ridgeB,
            ridgeA,
          ]);
          final westLow =
              RoofSlope3D(corners: [nwTop, swTop, breakLeftA, breakLeftB]);
          final westHigh = RoofSlope3D(corners: [
            ridgeA,
            ridgeB,
            breakLeftB,
            breakLeftA,
          ]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [eastLow, eastHigh, westLow, westHigh],
              edges: [
                RoofEdge3D(ridgeA, ridgeB),
                RoofEdge3D(breakLeftA, breakLeftB),
                RoofEdge3D(breakRightA, breakRightB),
              ],
              typeLabel: 'Мансардная',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        } else {
          final ridge = l / 2;
          final ridgeA = Vec3(0, ridge, wallTopZ + rise);
          final ridgeB = Vec3(w, ridge, wallTopZ + rise);
          final breakSouthA = Vec3(0, breakOffset, wallTopZ + breakRise);
          final breakSouthB = Vec3(w, breakOffset, wallTopZ + breakRise);
          final breakNorthA =
              Vec3(0, l - breakOffset, wallTopZ + breakRise);
          final breakNorthB =
              Vec3(w, l - breakOffset, wallTopZ + breakRise);
          final swTop = Vec3(0, 0, wallTopZ);
          final seTop = Vec3(w, 0, wallTopZ);
          final neTop = Vec3(w, l, wallTopZ);
          final nwTop = Vec3(0, l, wallTopZ);
          final southLow =
              RoofSlope3D(corners: [swTop, seTop, breakSouthB, breakSouthA]);
          final southHigh = RoofSlope3D(corners: [
            breakSouthA,
            breakSouthB,
            ridgeB,
            ridgeA,
          ]);
          final northLow =
              RoofSlope3D(corners: [neTop, nwTop, breakNorthA, breakNorthB]);
          final northHigh = RoofSlope3D(corners: [
            ridgeA,
            ridgeB,
            breakNorthB,
            breakNorthA,
          ]);
          return _RoofBuildResult(
            model: Roof3D(
              slopes: [southLow, southHigh, northLow, northHigh],
              edges: [
                RoofEdge3D(ridgeA, ridgeB),
                RoofEdge3D(breakSouthA, breakSouthB),
                RoofEdge3D(breakNorthA, breakNorthB),
              ],
              typeLabel: 'Мансардная',
              slopeDegrees: slopeDeg,
            ),
            totalHeight: rise,
          );
        }
    }
  }
}

class _RoofBuildResult {
  final Roof3D model;
  final double totalHeight;
  const _RoofBuildResult({required this.model, required this.totalHeight});
}
