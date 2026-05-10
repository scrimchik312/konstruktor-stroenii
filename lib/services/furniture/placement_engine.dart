// Расстановщик мебели — Phase-2.
//
// Соответствует Части II §5–§7 техзадания konstruktor_stroenii_full_spec.md.
// Покрывает: bedroom, kidsRoom, livingRoom, kitchen, kitchenDining,
// bathroom, toilet, dining, study, wardrobe, hallway, laundry,
// boilerRoom, garage, terrace, balcony.
//
// Все размеры — в МЕТРАХ. Координаты возвращаемой `FurnitureSymbol`
// привязаны к координатам пятна застройки (как `PlanRoom.x/y`).
//
// В отличие от Phase-1, расстановщик в Phase-2:
//   1. Учитывает forbidden-зоны от проёмов (дверь даёт зону распахивания
//      на 0.9 м внутрь комнаты, окно — полосу 0.4 м под подоконником).
//   2. Симметризует мебель: если рядом 2 предмета на одной стене с
//      зазором ≤ 0.2 м, выравнивает их по центру стены.
//   3. Возвращает только то, что НЕ пересекает forbidden-зоны и
//      границы внутреннего прямоугольника.

import 'dart:math' as math;

import '../../data/rooms_catalog.dart';
import '../../models/floor_plan.dart';
import '../../models/furniture_symbol.dart';

/// Заполнить мебель для всего плана.
FloorPlan placeFurnitureForPlan(FloorPlan plan) {
  final newRooms = <PlanRoom>[];
  for (final r in plan.rooms) {
    if (r.kind != PlanRoomKind.room) {
      newRooms.add(r);
      continue;
    }
    if (r.furniture.isNotEmpty) {
      newRooms.add(r);
      continue;
    }
    final furniture = _placeForRoom(r, plan);
    if (furniture.isEmpty) {
      newRooms.add(r);
    } else {
      newRooms.add(r.copyWith(furniture: furniture));
    }
  }
  return FloorPlan(
    floorLabel: plan.floorLabel,
    width: plan.width,
    height: plan.height,
    rooms: newRooms,
    openings: plan.openings,
    attachments: plan.attachments,
  );
}

/// Расставить мебель внутри пристройки (`PlanAttachment`).
///
/// Гараж получает 1 или 2 силуэта авто (в зависимости от ширины
/// короткой стороны). Терраса/балкон — стол с зонтом и до 4 стульев.
/// Крыльцо — пусто (слишком тесно).
List<FurnitureSymbol> placeFurnitureForAttachment(PlanAttachment a) {
  final dummy = PlanRoom(
    label: a.label,
    x: a.x,
    y: a.y,
    width: a.width,
    height: a.height,
    area: a.width * a.height,
  );
  final inner = _innerOf(dummy);
  final ctx = _RoomCtx(dummy, inner, const []);
  switch (a.kind) {
    case PlanAttachmentKind.garage:
      return _filter(ctx, _placeGarage(ctx));
    case PlanAttachmentKind.terrace:
      return _filter(ctx, _placeTerrace(ctx));
    case PlanAttachmentKind.porch:
      return const [];
  }
}

List<FurnitureSymbol> _placeForRoom(PlanRoom r, FloorPlan plan) {
  final kind = _kindOf(r.roomKindName);
  if (kind == null) return const [];
  final inner = _innerOf(r);
  final forbidden = _forbiddenZonesFor(r, plan);
  // Узкий «коридор прохода» 0.4 м у каждой двери — Phase-2b BFS-like
  // защита: даже если расстановщик в fallback'е перестал учитывать
  // полный 0.7-м swing, дверь в 40 см должна остаться свободной,
  // иначе комната становится недоступной.
  final critical = _criticalDoorZonesFor(r, plan);
  // Сначала пытаемся с forbidden-зонами. Если расстановщик ничего не
  // вернул (комната «забита» дверями), пытаемся без forbidden-зон —
  // лучше показать мебель «впритык к двери», чем пустую комнату.
  for (final zones in <List<_Rect>>[forbidden, const []]) {
    final ctx = _RoomCtx(r, inner, zones);
    var items = _filter(ctx, _byKind(kind, ctx));
    // Жёсткий финальный фильтр: даже в fallback'е мебель НЕ должна
    // налезать на узкий проход через дверь.
    items = items
        .where((f) =>
            !_hitsForbidden(critical, f.x, f.y, f.width, f.height))
        .toList();
    if (items.isNotEmpty) return items;
  }
  return const [];
}

/// Узкие (0.4 м) зоны прохода у каждой двери комнаты — обязательные
/// для соблюдения даже в fallback-расстановке.
List<_Rect> _criticalDoorZonesFor(PlanRoom r, FloorPlan plan) {
  const passDepth = 0.4;
  final out = <_Rect>[];
  for (final o in plan.openings) {
    if (o.kind == OpeningKind.window) continue;
    final z = _openingZone(o, r);
    if (z == null) continue;
    // Сжимаем глубину до 0.4 м, ширину оставляем равной длине проёма.
    if (z.h <= z.w) {
      // горизонтальная стена (top/bottom)
      final newY = (z.y + r.y < r.y + r.height / 2)
          ? z.y // top: оставляем верхний край
          : z.y + z.h - passDepth; // bottom: прижимаем к низу
      out.add(_Rect(z.x, newY, z.w, passDepth));
    } else {
      final newX = (z.x + r.x < r.x + r.width / 2) ? z.x : z.x + z.w - passDepth;
      out.add(_Rect(newX, z.y, passDepth, z.h));
    }
  }
  return out;
}

List<FurnitureSymbol> _byKind(RoomKind kind, _RoomCtx ctx) {
  switch (kind) {
    case RoomKind.bedroom:
    case RoomKind.kidsRoom:
      return _placeBedroom(ctx);
    case RoomKind.livingRoom:
      return _placeLivingRoom(ctx);
    case RoomKind.kitchen:
    case RoomKind.kitchenDining:
      return _placeKitchen(ctx, withIsland: kind == RoomKind.kitchenDining);
    case RoomKind.bathroom:
      return _placeBathroom(ctx, isToilet: false);
    case RoomKind.toilet:
      return _placeBathroom(ctx, isToilet: true);
    case RoomKind.dining:
      return _placeDining(ctx);
    case RoomKind.study:
      return _placeStudy(ctx);
    case RoomKind.wardrobe:
      return _placeWardrobe(ctx);
    case RoomKind.hallway:
      return _placeHallway(ctx);
    case RoomKind.laundry:
      return _placeLaundry(ctx);
    case RoomKind.boilerRoom:
      return _placeBoilerRoom(ctx);
    case RoomKind.garage:
      return _placeGarage(ctx);
    case RoomKind.terrace:
    case RoomKind.balcony:
      return _placeTerrace(ctx);
    case RoomKind.storage:
    case RoomKind.pantry:
    case RoomKind.technical:
      return const [];
  }
}

RoomKind? _kindOf(String? name) {
  if (name == null) return null;
  for (final k in RoomKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

// ─── Геометрические помощники ─────────────────────────────────────────

const double _wallClear = 0.05;
const double _doorSwingDepth = 0.7; // глубина forbidden-зоны двери внутрь
const double _windowStripDepth = 0.0; // окно НЕ ограничивает мебель в Phase-2

class _Inner {
  final double x;
  final double y;
  final double w;
  final double h;
  bool get horizontalLonger => w >= h;
  const _Inner(this.x, this.y, this.w, this.h);
}

class _Rect {
  final double x;
  final double y;
  final double w;
  final double h;
  const _Rect(this.x, this.y, this.w, this.h);
  bool intersects(_Rect other) =>
      !(other.x + other.w <= x ||
          other.x >= x + w ||
          other.y + other.h <= y ||
          other.y >= y + h);
  bool intersectsXY(double rx, double ry, double rw, double rh) =>
      !(rx + rw <= x || rx >= x + w || ry + rh <= y || ry >= y + h);
}

class _RoomCtx {
  final PlanRoom room;
  final _Inner inner;
  final List<_Rect> forbidden;
  const _RoomCtx(this.room, this.inner, this.forbidden);
}

_Inner _innerOf(PlanRoom r) {
  const wallHalf = 0.10;
  return _Inner(
    r.x + wallHalf + _wallClear,
    r.y + wallHalf + _wallClear,
    math.max(0, r.width - 2 * (wallHalf + _wallClear)),
    math.max(0, r.height - 2 * (wallHalf + _wallClear)),
  );
}

/// Forbidden-зоны для комнаты (дверной арки, под окнами и т.п.). Возвращает
/// прямоугольники в системе координат плана (как у мебели и `PlanRoom.x/y`).
List<_Rect> _forbiddenZonesFor(PlanRoom r, FloorPlan plan) {
  final rects = <_Rect>[];
  for (final o in plan.openings) {
    final z = _openingZone(o, r);
    if (z != null) rects.add(z);
  }
  return rects;
}

_Rect? _openingZone(PlanOpening o, PlanRoom r) {
  // Окна не создают forbidden-зон — мебель может стоять под окном
  // (диван, кровать, кухонный гарнитур — все нормальные сценарии).
  if (o.kind == OpeningKind.window) return null;
  // Проём принадлежит комнате, если он лежит на одной из её четырёх
  // сторон (с допуском 0.05 м).
  const eps = 0.05;
  final isOnTop =
      o.side == WallSide.top && (o.y - r.y).abs() < eps && o.x + 0.001 >= r.x &&
      o.x + o.length - 0.001 <= r.x + r.width;
  final isOnBottom =
      o.side == WallSide.bottom && (o.y - (r.y + r.height)).abs() < eps &&
      o.x + 0.001 >= r.x && o.x + o.length - 0.001 <= r.x + r.width;
  final isOnLeft =
      o.side == WallSide.left && (o.x - r.x).abs() < eps &&
      o.y + 0.001 >= r.y && o.y + o.length - 0.001 <= r.y + r.height;
  final isOnRight =
      o.side == WallSide.right && (o.x - (r.x + r.width)).abs() < eps &&
      o.y + 0.001 >= r.y && o.y + o.length - 0.001 <= r.y + r.height;
  if (!isOnTop && !isOnBottom && !isOnLeft && !isOnRight) return null;

  // Глубина forbidden-зоны зависит от типа проёма.
  final depth = (o.kind == OpeningKind.window)
      ? _windowStripDepth
      : _doorSwingDepth;

  if (isOnTop) {
    return _Rect(o.x, r.y, o.length, depth);
  }
  if (isOnBottom) {
    return _Rect(o.x, r.y + r.height - depth, o.length, depth);
  }
  if (isOnLeft) {
    return _Rect(r.x, o.y, depth, o.length);
  }
  return _Rect(r.x + r.width - depth, o.y, depth, o.length);
}

bool _hitsForbidden(List<_Rect> zones, double x, double y, double w, double h) {
  for (final z in zones) {
    if (z.intersectsXY(x, y, w, h)) return true;
  }
  return false;
}

/// Финальный фильтр: убираем мебель, которая (а) вылезла за inner-rect
/// или (б) попала в forbidden-зону.
List<FurnitureSymbol> _filter(_RoomCtx ctx, List<FurnitureSymbol> items) {
  final out = <FurnitureSymbol>[];
  for (final f in items) {
    final fits = f.x >= ctx.inner.x - 0.001 &&
        f.y >= ctx.inner.y - 0.001 &&
        f.x + f.width <= ctx.inner.x + ctx.inner.w + 0.001 &&
        f.y + f.height <= ctx.inner.y + ctx.inner.h + 0.001;
    if (!fits) continue;
    if (_hitsForbidden(ctx.forbidden, f.x, f.y, f.width, f.height)) continue;
    out.add(f);
  }
  return _symmetrize(out, ctx.inner);
}

/// Симметризация мебели — Часть II §7.
///
/// Если на одной стене лежат ровно ДВА предмета одного и того же
/// `FurnitureKind` и их центры почти симметричны относительно центра
/// стены (отклонение ≤ 0.2 м), сдвигаем оба ровно на симметричные
/// позиции, чтобы пара выглядела «причёсанной» (как на референсах).
List<FurnitureSymbol> _symmetrize(List<FurnitureSymbol> items, _Inner inner) {
  if (items.length < 2) return items;
  // wall: 0=top, 1=bottom, 2=left, 3=right
  int? wallOf(FurnitureSymbol f) {
    const tol = 0.06;
    if ((f.y - inner.y).abs() < tol) return 0;
    if ((f.y + f.height - (inner.y + inner.h)).abs() < tol) return 1;
    if ((f.x - inner.x).abs() < tol) return 2;
    if ((f.x + f.width - (inner.x + inner.w)).abs() < tol) return 3;
    return null;
  }

  final byWall = <(int, FurnitureKind), List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final w = wallOf(items[i]);
    if (w == null) continue;
    byWall.putIfAbsent((w, items[i].kind), () => []).add(i);
  }

  final out = List<FurnitureSymbol>.from(items);
  for (final entry in byWall.entries) {
    final ids = entry.value;
    if (ids.length != 2) continue;
    final wall = entry.key.$1;
    final a = out[ids[0]];
    final b = out[ids[1]];
    final isHorizWall = wall == 0 || wall == 1;
    final mid = isHorizWall ? inner.x + inner.w / 2 : inner.y + inner.h / 2;
    final ca = isHorizWall ? a.x + a.width / 2 : a.y + a.height / 2;
    final cb = isHorizWall ? b.x + b.width / 2 : b.y + b.height / 2;
    final da = ca - mid;
    final db = cb - mid;
    // Должны лежать по разные стороны от центра стены и иметь близкое
    // расстояние от него.
    if (da.sign == db.sign) continue;
    if ((da.abs() - db.abs()).abs() > 0.2) continue;
    final d = (da.abs() + db.abs()) / 2;
    if (isHorizWall) {
      final aLeft = da < 0;
      final newAx = (aLeft ? mid - d : mid + d) - a.width / 2;
      final newBx = (aLeft ? mid + d : mid - d) - b.width / 2;
      out[ids[0]] = FurnitureSymbol(
        kind: a.kind, x: newAx, y: a.y, width: a.width, height: a.height,
        rotationDeg: a.rotationDeg, label: a.label,
      );
      out[ids[1]] = FurnitureSymbol(
        kind: b.kind, x: newBx, y: b.y, width: b.width, height: b.height,
        rotationDeg: b.rotationDeg, label: b.label,
      );
    } else {
      final aTop = da < 0;
      final newAy = (aTop ? mid - d : mid + d) - a.height / 2;
      final newBy = (aTop ? mid + d : mid - d) - b.height / 2;
      out[ids[0]] = FurnitureSymbol(
        kind: a.kind, x: a.x, y: newAy, width: a.width, height: a.height,
        rotationDeg: a.rotationDeg, label: a.label,
      );
      out[ids[1]] = FurnitureSymbol(
        kind: b.kind, x: b.x, y: newBy, width: b.width, height: b.height,
        rotationDeg: b.rotationDeg, label: b.label,
      );
    }
  }
  return out;
}

// ─── BEDROOM ──────────────────────────────────────────────────────────

List<FurnitureSymbol> _placeBedroom(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 2.0 || inner.h < 2.0) return const [];

  final isHorizontal = inner.w >= inner.h;
  final bedDoubleFits = math.min(inner.w, inner.h) >= 2.5;
  final bedKind =
      bedDoubleFits ? FurnitureKind.bedDouble : FurnitureKind.bedSingle;
  final bedSize = bedKind.defaultSize;
  final bedW = isHorizontal ? bedSize.h : bedSize.w;
  final bedH = isHorizontal ? bedSize.w : bedSize.h;

  // Кровать ставим у длинной стены, изголовьем к ней. Пытаемся сначала
  // у «верхней» (top), при коллизии — у противоположной.
  for (final headTop in [true, false]) {
    final bedX = inner.x + (inner.w - bedW) / 2;
    final bedY = isHorizontal
        ? (headTop ? inner.y : inner.y + inner.h - bedH)
        : inner.y + (inner.h - bedH) / 2;
    if (_hitsForbidden(ctx.forbidden, bedX, bedY, bedW, bedH)) continue;
    final out = <FurnitureSymbol>[
      FurnitureSymbol(
        kind: bedKind,
        x: bedX,
        y: bedY,
        width: bedW,
        height: bedH,
      ),
    ];
    if (bedKind == FurnitureKind.bedDouble && isHorizontal) {
      final ns = FurnitureKind.nightstand.defaultSize;
      final nsY = bedY;
      if (bedX - ns.w >= inner.x &&
          !_hitsForbidden(ctx.forbidden, bedX - ns.w, nsY, ns.w, ns.h)) {
        out.add(FurnitureSymbol(
          kind: FurnitureKind.nightstand,
          x: bedX - ns.w,
          y: nsY,
          width: ns.w,
          height: ns.h,
        ));
      }
      if (bedX + bedW + ns.w <= inner.x + inner.w &&
          !_hitsForbidden(ctx.forbidden, bedX + bedW, nsY, ns.w, ns.h)) {
        out.add(FurnitureSymbol(
          kind: FurnitureKind.nightstand,
          x: bedX + bedW,
          y: nsY,
          width: ns.w,
          height: ns.h,
        ));
      }
    }

    // Шкаф у противоположной от изголовья стены.
    final wardrobeSize = FurnitureKind.wardrobe.defaultSize;
    final wW = isHorizontal ? math.min(wardrobeSize.w, inner.w) : wardrobeSize.h;
    final wH = isHorizontal ? wardrobeSize.h : math.min(wardrobeSize.w, inner.h);
    final wX = isHorizontal
        ? inner.x + (inner.w - wW) / 2
        : inner.x + inner.w - wW;
    final wY = isHorizontal
        ? (headTop ? inner.y + inner.h - wH : inner.y)
        : inner.y + (inner.h - wH) / 2;
    if (!_hitsForbidden(ctx.forbidden, wX, wY, wW, wH)) {
      out.add(FurnitureSymbol(
        kind: FurnitureKind.wardrobe,
        x: wX,
        y: wY,
        width: wW,
        height: wH,
      ));
    }
    return out;
  }
  return const [];
}

// ─── LIVING ROOM ──────────────────────────────────────────────────────

List<FurnitureSymbol> _placeLivingRoom(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 3.0 || inner.h < 3.0) return const [];

  final isHorizontal = inner.w >= inner.h;
  final out = <FurnitureSymbol>[];

  final sofa = FurnitureKind.sofa3.defaultSize;
  final sofaW = isHorizontal ? sofa.w : sofa.h;
  final sofaH = isHorizontal ? sofa.h : sofa.w;

  // Перебираем стороны (top/bottom для горизонтальных и left/right для
  // вертикальных) — выбираем ту, где меньше всего forbidden-наложений.
  final candidates = isHorizontal
      ? [
          (inner.x + (inner.w - sofaW) / 2, inner.y),
          (inner.x + (inner.w - sofaW) / 2, inner.y + inner.h - sofaH),
        ]
      : [
          (inner.x, inner.y + (inner.h - sofaH) / 2),
          (inner.x + inner.w - sofaW, inner.y + (inner.h - sofaH) / 2),
        ];
  (double, double)? sofaPos;
  for (final pos in candidates) {
    if (!_hitsForbidden(ctx.forbidden, pos.$1, pos.$2, sofaW, sofaH)) {
      sofaPos = pos;
      break;
    }
  }
  if (sofaPos == null) return const [];

  final sofaX = sofaPos.$1;
  final sofaY = sofaPos.$2;
  out.add(FurnitureSymbol(
    kind: FurnitureKind.sofa3,
    x: sofaX,
    y: sofaY,
    width: sofaW,
    height: sofaH,
  ));

  // Журнальный стол.
  final ct = FurnitureKind.coffeeTable.defaultSize;
  final ctW = isHorizontal ? ct.w : ct.h;
  final ctH = isHorizontal ? ct.h : ct.w;
  final ctX = sofaX + (sofaW - ctW) / 2;
  final ctY = isHorizontal
      ? (sofaY < inner.y + inner.h / 2
          ? sofaY + sofaH + 0.45
          : sofaY - 0.45 - ctH)
      : sofaY + (sofaH - ctH) / 2;
  if (!_hitsForbidden(ctx.forbidden, ctX, ctY, ctW, ctH) &&
      ctX >= inner.x && ctY >= inner.y &&
      ctX + ctW <= inner.x + inner.w &&
      ctY + ctH <= inner.y + inner.h) {
    out.add(FurnitureSymbol(
      kind: FurnitureKind.coffeeTable,
      x: ctX,
      y: ctY,
      width: ctW,
      height: ctH,
    ));
  }

  // ТВ-тумба у противоположной стены.
  final tv = FurnitureKind.tvStand.defaultSize;
  final tvW = isHorizontal ? tv.w : tv.h;
  final tvH = isHorizontal ? tv.h : tv.w;
  final tvX = isHorizontal ? inner.x + (inner.w - tvW) / 2 : (sofaX < inner.x + inner.w / 2 ? inner.x + inner.w - tvW : inner.x);
  final tvY = isHorizontal
      ? (sofaY < inner.y + inner.h / 2 ? inner.y + inner.h - tvH : inner.y)
      : inner.y + (inner.h - tvH) / 2;
  if (!_hitsForbidden(ctx.forbidden, tvX, tvY, tvW, tvH)) {
    out.add(FurnitureSymbol(
      kind: FurnitureKind.tvStand,
      x: tvX,
      y: tvY,
      width: tvW,
      height: tvH,
    ));
  }

  return out;
}

// ─── KITCHEN ─────────────────────────────────────────────────────────

List<FurnitureSymbol> _placeKitchen(_RoomCtx ctx, {required bool withIsland}) {
  final inner = ctx.inner;
  if (inner.w < 2.0 || inner.h < 2.0) return const [];

  final isHorizontal = inner.w >= inner.h;
  final out = <FurnitureSymbol>[];

  const depth = 0.6;
  final sections = <FurnitureKind>[
    FurnitureKind.kitchenFridge,
    FurnitureKind.kitchenSection,
    FurnitureKind.kitchenSink,
    FurnitureKind.kitchenSection,
    FurnitureKind.kitchenStove,
  ];

  final wide = isHorizontal ? inner.w : inner.h;
  if (wide < 3.0) return const [];

  final totalFixed = 0.6 * 3;
  final fillerCount = 2;
  final fillerLength =
      math.max(0.4, (wide - totalFixed) / fillerCount).clamp(0.4, 1.0);
  final usable = totalFixed + fillerCount * fillerLength;

  // Пытаемся вдоль стены top, при неудаче — bottom (или left/right
  // для вертикальной комнаты).
  for (final placeNear in [true, false]) {
    final start = isHorizontal
        ? inner.x + (inner.w - usable) / 2
        : inner.y + (inner.h - usable) / 2;
    double cursor = start;
    final candidate = <FurnitureSymbol>[];
    var blocked = false;
    for (final k in sections) {
      final size = k == FurnitureKind.kitchenSection
          ? (w: fillerLength, h: depth)
          : (w: 0.6, h: depth);
      final w = isHorizontal ? size.w : size.h;
      final h = isHorizontal ? size.h : size.w;
      final x = isHorizontal
          ? cursor
          : (placeNear ? inner.x : inner.x + inner.w - depth);
      final y = isHorizontal
          ? (placeNear ? inner.y : inner.y + inner.h - depth)
          : cursor;
      if (_hitsForbidden(ctx.forbidden, x, y, w, h)) {
        blocked = true;
        break;
      }
      candidate.add(FurnitureSymbol(kind: k, x: x, y: y, width: w, height: h));
      cursor += isHorizontal ? size.w : size.w;
    }
    if (!blocked) {
      out.addAll(candidate);
      // Островок (для kitchenDining при достаточной ширине).
      if (withIsland) {
        final isl = FurnitureKind.kitchenIsland.defaultSize;
        final iW = isHorizontal ? isl.w : isl.h;
        final iH = isHorizontal ? isl.h : isl.w;
        final iX = inner.x + (inner.w - iW) / 2;
        final iY = isHorizontal
            ? (placeNear ? inner.y + depth + 0.9 : inner.y + inner.h - depth - 0.9 - iH)
            : inner.y + (inner.h - iH) / 2;
        if (!_hitsForbidden(ctx.forbidden, iX, iY, iW, iH) &&
            iX >= inner.x && iY >= inner.y &&
            iX + iW <= inner.x + inner.w &&
            iY + iH <= inner.y + inner.h) {
          out.add(FurnitureSymbol(
            kind: FurnitureKind.kitchenIsland,
            x: iX, y: iY, width: iW, height: iH,
          ));
        }
      }
      // Обеденный стол при достаточной ширине.
      final shortSide = isHorizontal ? inner.h : inner.w;
      if (shortSide >= 2.5 && !withIsland) {
        final dt = FurnitureKind.diningTable.defaultSize;
        final dtW = dt.w;
        final dtH = dt.h;
        if (isHorizontal && inner.h >= depth + dtH + 0.6) {
          final tX = inner.x + (inner.w - dtW) / 2;
          final tY = placeNear
              ? inner.y + inner.h - dtH
              : inner.y;
          if (!_hitsForbidden(ctx.forbidden, tX, tY, dtW, dtH)) {
            out.add(FurnitureSymbol(
              kind: FurnitureKind.diningTable,
              x: tX,
              y: tY,
              width: dtW,
              height: dtH,
            ));
          }
        }
      }
      return out;
    }
  }
  return const [];
}

// ─── BATHROOM ────────────────────────────────────────────────────────

List<FurnitureSymbol> _placeBathroom(_RoomCtx ctx, {required bool isToilet}) {
  final inner = ctx.inner;
  if (inner.w < 1.2 || inner.h < 1.2) return const [];

  final isHorizontal = inner.w >= inner.h;
  final out = <FurnitureSymbol>[];

  final tlt = FurnitureKind.toilet.defaultSize;
  final tltW = isHorizontal ? tlt.h : tlt.w;
  final tltH = isHorizontal ? tlt.w : tlt.h;
  // Перебор четырёх углов под унитаз.
  final tltCandidates = <(double, double)>[
    (isHorizontal ? inner.x : inner.x + (inner.w - tltW) / 2,
     isHorizontal ? inner.y + (inner.h - tltH) / 2 : inner.y),
    (isHorizontal ? inner.x + inner.w - tltW : inner.x + (inner.w - tltW) / 2,
     isHorizontal ? inner.y + (inner.h - tltH) / 2 : inner.y + inner.h - tltH),
    (isHorizontal ? inner.x : inner.x + inner.w - tltW,
     isHorizontal ? inner.y : inner.y + (inner.h - tltH) / 2),
  ];
  (double, double)? tltPos;
  for (final c in tltCandidates) {
    if (!_hitsForbidden(ctx.forbidden, c.$1, c.$2, tltW, tltH)) {
      tltPos = c;
      break;
    }
  }
  if (tltPos == null) return const [];
  out.add(FurnitureSymbol(
    kind: FurnitureKind.toilet,
    x: tltPos.$1, y: tltPos.$2, width: tltW, height: tltH,
  ));
  if (isToilet) return out;

  // Раковина — на свободной соседней стене.
  final wb = FurnitureKind.washbasin.defaultSize;
  final wbW = isHorizontal ? wb.h : wb.w;
  final wbH = isHorizontal ? wb.w : wb.h;
  final wbCandidates = <(double, double)>[
    if (isHorizontal) ...[
      (inner.x, inner.y),
      (inner.x, inner.y + inner.h - wbH),
      (inner.x + inner.w - wbW, inner.y),
      (inner.x + inner.w - wbW, inner.y + inner.h - wbH),
    ] else ...[
      (inner.x, inner.y),
      (inner.x + inner.w - wbW, inner.y),
      (inner.x, inner.y + inner.h - wbH),
      (inner.x + inner.w - wbW, inner.y + inner.h - wbH),
    ]
  ];
  for (final c in wbCandidates) {
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, wbW, wbH)) continue;
    if (_overlaps(out, c.$1, c.$2, wbW, wbH)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.washbasin,
      x: c.$1, y: c.$2, width: wbW, height: wbH,
    ));
    break;
  }

  // Ванна или душ — у длинной стены.
  final hasBathtubFit =
      math.max(inner.w, inner.h) >= 1.8 && math.min(inner.w, inner.h) >= 0.8;
  if (hasBathtubFit) {
    final bt = FurnitureKind.bathtub.defaultSize;
    final btW = isHorizontal ? bt.w : bt.h;
    final btH = isHorizontal ? bt.h : bt.w;
    final candidates = isHorizontal
        ? [
            (inner.x + (inner.w - btW) / 2, inner.y + inner.h - btH),
            (inner.x + (inner.w - btW) / 2, inner.y),
          ]
        : [
            (inner.x + inner.w - btW, inner.y + (inner.h - btH) / 2),
            (inner.x, inner.y + (inner.h - btH) / 2),
          ];
    for (final c in candidates) {
      if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, btW, btH)) continue;
      if (_overlaps(out, c.$1, c.$2, btW, btH)) continue;
      out.add(FurnitureSymbol(
        kind: FurnitureKind.bathtub,
        x: c.$1, y: c.$2, width: btW, height: btH,
      ));
      break;
    }
  } else {
    final sh = FurnitureKind.shower.defaultSize;
    final c = (inner.x + inner.w - sh.w, inner.y + inner.h - sh.h);
    if (!_hitsForbidden(ctx.forbidden, c.$1, c.$2, sh.w, sh.h) &&
        !_overlaps(out, c.$1, c.$2, sh.w, sh.h)) {
      out.add(FurnitureSymbol(
        kind: FurnitureKind.shower,
        x: c.$1, y: c.$2, width: sh.w, height: sh.h,
      ));
    }
  }

  return out;
}

bool _overlaps(List<FurnitureSymbol> list, double x, double y, double w, double h) {
  for (final f in list) {
    if (!(x + w <= f.x || x >= f.x + f.width ||
          y + h <= f.y || y >= f.y + f.height)) {
      return true;
    }
  }
  return false;
}

// ─── DINING / STUDY / WARDROBE ───────────────────────────────────────

List<FurnitureSymbol> _placeDining(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 2.0 || inner.h < 2.0) return const [];
  final dt = FurnitureKind.diningTable.defaultSize;
  final tx = inner.x + (inner.w - dt.w) / 2;
  final ty = inner.y + (inner.h - dt.h) / 2;
  final out = <FurnitureSymbol>[
    FurnitureSymbol(
      kind: FurnitureKind.diningTable,
      x: tx, y: ty, width: dt.w, height: dt.h,
    ),
  ];
  // 4 стула вокруг стола.
  final ch = FurnitureKind.diningChair.defaultSize;
  final chairs = <(double, double)>[
    (tx + dt.w / 2 - ch.w / 2, ty - ch.h - 0.05),
    (tx + dt.w / 2 - ch.w / 2, ty + dt.h + 0.05),
    (tx - ch.w - 0.05, ty + dt.h / 2 - ch.h / 2),
    (tx + dt.w + 0.05, ty + dt.h / 2 - ch.h / 2),
  ];
  for (final c in chairs) {
    if (c.$1 >= inner.x && c.$2 >= inner.y &&
        c.$1 + ch.w <= inner.x + inner.w &&
        c.$2 + ch.h <= inner.y + inner.h) {
      out.add(FurnitureSymbol(
        kind: FurnitureKind.diningChair,
        x: c.$1, y: c.$2, width: ch.w, height: ch.h,
      ));
    }
  }
  return out;
}

List<FurnitureSymbol> _placeStudy(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 1.5 || inner.h < 1.5) return const [];
  final isHorizontal = inner.w >= inner.h;
  final ds = FurnitureKind.desk.defaultSize;
  final dW = isHorizontal ? ds.w : ds.h;
  final dH = isHorizontal ? ds.h : ds.w;
  final out = <FurnitureSymbol>[];
  // Стол у окна или у стены.
  final candidates = isHorizontal
      ? [
          (inner.x + (inner.w - dW) / 2, inner.y),
          (inner.x + (inner.w - dW) / 2, inner.y + inner.h - dH),
        ]
      : [
          (inner.x, inner.y + (inner.h - dH) / 2),
          (inner.x + inner.w - dW, inner.y + (inner.h - dH) / 2),
        ];
  for (final c in candidates) {
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, dW, dH)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.desk, x: c.$1, y: c.$2, width: dW, height: dH,
    ));
    out.add(FurnitureSymbol(
      kind: FurnitureKind.chair,
      x: c.$1 + dW / 2 - 0.225,
      y: isHorizontal ? c.$2 + dH + 0.15 : c.$2 + dH / 2 - 0.225,
      width: 0.45,
      height: 0.45,
    ));
    return out;
  }
  return const [];
}

List<FurnitureSymbol> _placeWardrobe(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 1.0 || inner.h < 1.0) return const [];
  final w = FurnitureKind.wardrobe.defaultSize;
  return [
    FurnitureSymbol(
      kind: FurnitureKind.wardrobe,
      x: inner.x, y: inner.y,
      width: math.min(w.w, inner.w),
      height: math.min(w.h, inner.h),
    ),
  ];
}

// ─── HALLWAY ──────────────────────────────────────────────────────────

List<FurnitureSymbol> _placeHallway(_RoomCtx ctx) {
  final inner = ctx.inner;
  // Узкие коридоры (< 1.2 м) — не трогаем.
  if (math.min(inner.w, inner.h) < 1.2) return const [];
  final isHorizontal = inner.w >= inner.h;
  final out = <FurnitureSymbol>[];
  final sc = FurnitureKind.shoeCabinet.defaultSize;
  final scW = isHorizontal ? sc.w : sc.h;
  final scH = isHorizontal ? sc.h : sc.w;
  // У одной из коротких стен.
  final candidates = isHorizontal
      ? [
          (inner.x, inner.y),
          (inner.x + inner.w - scW, inner.y),
          (inner.x, inner.y + inner.h - scH),
          (inner.x + inner.w - scW, inner.y + inner.h - scH),
        ]
      : [
          (inner.x, inner.y),
          (inner.x + inner.w - scW, inner.y),
          (inner.x, inner.y + inner.h - scH),
          (inner.x + inner.w - scW, inner.y + inner.h - scH),
        ];
  for (final c in candidates) {
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, scW, scH)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.shoeCabinet,
      x: c.$1, y: c.$2, width: scW, height: scH,
    ));
    break;
  }
  // Вешалка рядом.
  final hr = FurnitureKind.hangerRack.defaultSize;
  final hrW = isHorizontal ? hr.w : hr.h;
  final hrH = isHorizontal ? hr.h : hr.w;
  for (final c in candidates) {
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, hrW, hrH)) continue;
    if (_overlaps(out, c.$1, c.$2, hrW, hrH)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.hangerRack,
      x: c.$1, y: c.$2, width: hrW, height: hrH,
    ));
    break;
  }
  return out;
}

// ─── LAUNDRY / BOILER ROOM ────────────────────────────────────────────

List<FurnitureSymbol> _placeLaundry(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 1.5 || inner.h < 1.0) return const [];
  final isHorizontal = inner.w >= inner.h;
  final wm = FurnitureKind.washingMachine.defaultSize;
  final dr = FurnitureKind.dryer.defaultSize;
  final out = <FurnitureSymbol>[];
  // Стиралка + сушилка рядом.
  final wmW = isHorizontal ? wm.w : wm.h;
  final wmH = isHorizontal ? wm.h : wm.w;
  final drW = isHorizontal ? dr.w : dr.h;
  final drH = isHorizontal ? dr.h : dr.w;
  final wmX = inner.x;
  final wmY = inner.y;
  if (!_hitsForbidden(ctx.forbidden, wmX, wmY, wmW, wmH)) {
    out.add(FurnitureSymbol(
      kind: FurnitureKind.washingMachine,
      x: wmX, y: wmY, width: wmW, height: wmH,
    ));
    final drX = isHorizontal ? wmX + wmW : wmX;
    final drY = isHorizontal ? wmY : wmY + wmH;
    if (!_hitsForbidden(ctx.forbidden, drX, drY, drW, drH) &&
        drX + drW <= inner.x + inner.w &&
        drY + drH <= inner.y + inner.h) {
      out.add(FurnitureSymbol(
        kind: FurnitureKind.dryer,
        x: drX, y: drY, width: drW, height: drH,
      ));
    }
  }
  return out;
}

List<FurnitureSymbol> _placeBoilerRoom(_RoomCtx ctx) {
  final inner = ctx.inner;
  if (inner.w < 0.8 || inner.h < 0.8) return const [];
  final b = FurnitureKind.boiler.defaultSize;
  final out = <FurnitureSymbol>[];
  // У левой стены, по центру.
  final candidates = <(double, double)>[
    (inner.x, inner.y),
    (inner.x + inner.w - b.w, inner.y),
    (inner.x, inner.y + inner.h - b.h),
    (inner.x + inner.w - b.w, inner.y + inner.h - b.h),
  ];
  for (final c in candidates) {
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, b.w, b.h)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.boiler,
      x: c.$1, y: c.$2, width: b.w, height: b.h,
    ));
    return out;
  }
  return const [];
}

// ─── GARAGE / TERRACE ─────────────────────────────────────────────────

List<FurnitureSymbol> _placeGarage(_RoomCtx ctx) {
  final inner = ctx.inner;
  // Гараж требует минимум ~4.5 м длинной стороны (под авто) и ~2.5 м
  // короткой. Ориентация авто — вдоль длинной стороны, поэтому
  // проверяем именно длинную/короткую, а не «w/h».
  final longSide = math.max(inner.w, inner.h);
  final shortSide = math.min(inner.w, inner.h);
  if (longSide < 4.5 || shortSide < 2.5) return const [];
  final isHorizontal = inner.w >= inner.h;
  final car = FurnitureKind.carSilhouette.defaultSize;
  final out = <FurnitureSymbol>[];
  // Авто ставим вдоль длинной стороны, по центру.
  final cW = isHorizontal ? car.w : car.h;
  final cH = isHorizontal ? car.h : car.w;
  // Один или два авто в зависимости от ширины короткой стороны.
  // (shortSide уже посчитан выше как min(w,h).)
  final twoCars = shortSide >= 4.6;
  final cars = <(double, double)>[];
  if (twoCars) {
    if (isHorizontal) {
      cars.add((inner.x + (inner.w - cW) / 2, inner.y + 0.3));
      cars.add((inner.x + (inner.w - cW) / 2, inner.y + inner.h - 0.3 - cH));
    } else {
      cars.add((inner.x + 0.3, inner.y + (inner.h - cH) / 2));
      cars.add((inner.x + inner.w - 0.3 - cW, inner.y + (inner.h - cH) / 2));
    }
  } else {
    cars.add((inner.x + (inner.w - cW) / 2, inner.y + (inner.h - cH) / 2));
  }
  for (final c in cars) {
    if (c.$1 < inner.x || c.$2 < inner.y) continue;
    if (c.$1 + cW > inner.x + inner.w || c.$2 + cH > inner.y + inner.h) continue;
    if (_hitsForbidden(ctx.forbidden, c.$1, c.$2, cW, cH)) continue;
    out.add(FurnitureSymbol(
      kind: FurnitureKind.carSilhouette,
      x: c.$1, y: c.$2, width: cW, height: cH,
    ));
  }
  return out;
}

List<FurnitureSymbol> _placeTerrace(_RoomCtx ctx) {
  final inner = ctx.inner;
  // Минимум для какой-нибудь мебели: 1.5×1.2 м.
  if (inner.w < 1.5 || inner.h < 1.2) return const [];

  final ch = FurnitureKind.outdoorChair.defaultSize;
  final out = <FurnitureSymbol>[];

  // Узкая терраса (короткая сторона < 1.8 м): кладём маленький
  // круглый стол ⌀0.7 м у внутренней (длинной) стены и до двух
  // стульев по сторонам.
  if (math.min(inner.w, inner.h) < 1.8) {
    const tSize = 0.70;
    final isHoriz = inner.w >= inner.h;
    double tx, ty;
    if (isHoriz) {
      tx = inner.x + (inner.w - tSize) / 2;
      ty = inner.y + inner.h - tSize - 0.1;
    } else {
      tx = inner.x + inner.w - tSize - 0.1;
      ty = inner.y + (inner.h - tSize) / 2;
    }
    out.add(FurnitureSymbol(
      kind: FurnitureKind.outdoorTable,
      x: tx, y: ty, width: tSize, height: tSize,
    ));
    final chairs = isHoriz
        ? <(double, double)>[
            (tx - ch.w - 0.05, ty + tSize / 2 - ch.h / 2),
            (tx + tSize + 0.05, ty + tSize / 2 - ch.h / 2),
          ]
        : <(double, double)>[
            (tx + tSize / 2 - ch.w / 2, ty - ch.h - 0.05),
            (tx + tSize / 2 - ch.w / 2, ty + tSize + 0.05),
          ];
    for (final c in chairs) {
      if (c.$1 >= inner.x &&
          c.$2 >= inner.y &&
          c.$1 + ch.w <= inner.x + inner.w &&
          c.$2 + ch.h <= inner.y + inner.h) {
        out.add(FurnitureSymbol(
          kind: FurnitureKind.outdoorChair,
          x: c.$1, y: c.$2, width: ch.w, height: ch.h,
        ));
      }
    }
    return out;
  }

  // Просторная терраса: прямоугольный стол + до 4 стульев по сторонам.
  final ot = FurnitureKind.outdoorTable.defaultSize;
  final tx = inner.x + (inner.w - ot.w) / 2;
  final ty = inner.y + (inner.h - ot.h) / 2;
  out.add(FurnitureSymbol(
    kind: FurnitureKind.outdoorTable,
    x: tx, y: ty, width: ot.w, height: ot.h,
  ));
  final chairs = <(double, double)>[
    (tx + ot.w / 2 - ch.w / 2, ty - ch.h - 0.05),
    (tx + ot.w / 2 - ch.w / 2, ty + ot.h + 0.05),
    (tx - ch.w - 0.05, ty + ot.h / 2 - ch.h / 2),
    (tx + ot.w + 0.05, ty + ot.h / 2 - ch.h / 2),
  ];
  for (final c in chairs) {
    if (c.$1 >= inner.x &&
        c.$2 >= inner.y &&
        c.$1 + ch.w <= inner.x + inner.w &&
        c.$2 + ch.h <= inner.y + inner.h) {
      out.add(FurnitureSymbol(
        kind: FurnitureKind.outdoorChair,
        x: c.$1, y: c.$2, width: ch.w, height: ch.h,
      ));
    }
  }
  return out;
}
