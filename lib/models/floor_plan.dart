import 'dart:convert';

import 'building_footprint.dart';
import 'furniture_symbol.dart';

/// Категория элемента плана — определяет внешний вид при отрисовке.
enum PlanRoomKind {
  room, // обычная комната
  staircase, // лестничный проём
  free; // свободная зона / коридор / прихожая

  static PlanRoomKind fromName(String? n) {
    return PlanRoomKind.values.firstWhere(
      (v) => v.name == n,
      orElse: () => PlanRoomKind.room,
    );
  }
}

/// Тип проёма в стене.
enum OpeningKind {
  door, // межкомнатная дверь
  externalDoor, // входная дверь со стороны улицы
  window, // окно
  archway; // открытый проход (между свободными зонами)

  static OpeningKind fromName(String? n) {
    return OpeningKind.values.firstWhere(
      (v) => v.name == n,
      orElse: () => OpeningKind.door,
    );
  }
}

/// Сторона стены, на которой расположен проём (от точки `(x, y)` комнаты).
enum WallSide {
  top,
  bottom,
  left,
  right;

  bool get isHorizontal => this == top || this == bottom;

  static WallSide fromName(String? n) {
    return WallSide.values.firstWhere(
      (v) => v.name == n,
      orElse: () => WallSide.top,
    );
  }
}

/// Прямоугольник на схематическом плане.
///
/// Координаты и размеры — в метрах от левого верхнего угла пятна застройки.
class PlanRoom {
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;
  final double area;
  final PlanRoomKind kind;

  /// Имя функционального типа комнаты (`RoomKind.name`), например
  /// `bedroom`, `kitchen`, `bathroom`. Нужно для правил расстановки
  /// дверей/окон. Не заполняется для staircase/free.
  final String? roomKindName;

  /// Размещённая мебель внутри комнаты — заполняется автоматическим
  /// расстановщиком из `services/furniture/placement_engine.dart`.
  /// Координаты экземпляров — в системе координат плана (как `x`/`y`
  /// у самой комнаты). Может быть пустой.
  final List<FurnitureSymbol> furniture;

  const PlanRoom({
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.area,
    this.kind = PlanRoomKind.room,
    this.roomKindName,
    this.furniture = const [],
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'area': area,
        'kind': kind.name,
        if (roomKindName != null) 'roomKindName': roomKindName,
        if (furniture.isNotEmpty)
          'furniture': furniture.map((f) => f.toJson()).toList(),
      };

  PlanRoom copyWith({
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    double? area,
    PlanRoomKind? kind,
    String? roomKindName,
    List<FurnitureSymbol>? furniture,
  }) =>
      PlanRoom(
        label: label ?? this.label,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        area: area ?? this.area,
        kind: kind ?? this.kind,
        roomKindName: roomKindName ?? this.roomKindName,
        furniture: furniture ?? this.furniture,
      );

  static PlanRoom fromJson(Map<String, dynamic> j) {
    final fjson = j['furniture'];
    final furniture = <FurnitureSymbol>[];
    if (fjson is List) {
      for (final f in fjson) {
        if (f is Map<String, dynamic>) {
          final sym = FurnitureSymbol.fromJson(f);
          if (sym != null) furniture.add(sym);
        }
      }
    }
    return PlanRoom(
      label: j['label'] as String,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      area: (j['area'] as num).toDouble(),
      kind: PlanRoomKind.fromName(j['kind'] as String?),
      roomKindName: j['roomKindName'] as String?,
      furniture: furniture,
    );
  }
}

/// Проём в стене — дверь, входная дверь или окно.
///
/// Координата проёма задаётся в системе координат пятна застройки:
/// [x], [y] — координата начала проёма по той стене, на которой он стоит,
/// [length] — длина проёма вдоль стены. Например, окно шириной 1.5 м на
/// верхней стене комнаты, начинающееся в 1 м от её левого угла, имеет
/// `side = top`, `x = roomX + 1`, `y = roomY`, `length = 1.5`.
class PlanOpening {
  final OpeningKind kind;
  final WallSide side;
  final double x;
  final double y;
  final double length;

  /// Сторона, на которую открывается дверь (для рисования створки).
  /// Условные значения: `1` — наружу/внутрь по нормали справа/вниз,
  /// `-1` — слева/вверх. Игнорируется для окон.
  final int swing;

  const PlanOpening({
    required this.kind,
    required this.side,
    required this.x,
    required this.y,
    required this.length,
    this.swing = 1,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'side': side.name,
        'x': x,
        'y': y,
        'length': length,
        'swing': swing,
      };

  static PlanOpening fromJson(Map<String, dynamic> j) => PlanOpening(
        kind: OpeningKind.fromName(j['kind'] as String?),
        side: WallSide.fromName(j['side'] as String?),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        length: (j['length'] as num).toDouble(),
        swing: (j['swing'] as num?)?.toInt() ?? 1,
      );
}

/// Тип пристройки к дому (крыльцо, терраса, гараж).
enum PlanAttachmentKind {
  porch,
  terrace,
  garage;

  static PlanAttachmentKind fromName(String? n) =>
      PlanAttachmentKind.values.firstWhere(
        (v) => v.name == n,
        orElse: () => PlanAttachmentKind.porch,
      );
}

/// Пристройка к дому, рисуется отдельным блоком за наружной стеной.
///
/// Координаты [x], [y] — в системе координат пятна застройки. Могут быть
/// отрицательными или превышать [FloorPlan.width]/[FloorPlan.height]
/// (привязка — снаружи дома).
class PlanAttachment {
  final PlanAttachmentKind kind;
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;

  const PlanAttachment({
    required this.kind,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'label': label,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  static PlanAttachment fromJson(Map<String, dynamic> j) => PlanAttachment(
        kind: PlanAttachmentKind.fromName(j['kind'] as String?),
        label: j['label'] as String? ?? '',
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

/// Схематический план одного этажа.
/// Колонна в плане (квадратная или круглая) — рисуется внутри
/// помещения для уменьшения пролёта плит перекрытия по СП 63.13330.2018.
/// Координаты [x], [y] — центр колонны в системе координат пятна
/// застройки (м); [sizeM] — сторона квадрата (или диаметр для круглых).
class PlanColumn {
  final double x;
  final double y;
  final double sizeM;
  final String label;

  const PlanColumn({
    required this.x,
    required this.y,
    required this.sizeM,
    this.label = 'К',
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'sizeM': sizeM,
        'label': label,
      };

  static PlanColumn fromJson(Map<String, dynamic> j) => PlanColumn(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        sizeM: (j['sizeM'] as num).toDouble(),
        label: j['label'] as String? ?? 'К',
      );
}

class FloorPlan {
  final String floorLabel;
  final double width;
  final double height;
  final List<PlanRoom> rooms;
  final List<PlanOpening> openings;
  final List<PlanAttachment> attachments;
  final List<PlanColumn> columns;

  /// Полигональный контур пятна застройки этажа (Phase-3b §17.2.1).
  ///
  /// Если задан — стены этажа рисуются по полигону `outline`, а bbox
  /// (`width`/`height`) совпадает с `footprint!.bbox`. Это позволяет
  /// L/T/U-образные дома (см. `BuildingFootprint.lShape`).
  ///
  /// Если `null` — этаж считается прямоугольным с габаритами
  /// `width × height` от точки `(0, 0)` (старый рендер v64.x). Все
  /// существующие planы остаются совместимыми и работают как
  /// раньше.
  final BuildingFootprint? footprint;

  const FloorPlan({
    required this.floorLabel,
    required this.width,
    required this.height,
    required this.rooms,
    this.openings = const [],
    this.attachments = const [],
    this.columns = const [],
    this.footprint,
  });

  /// Возвращает контур этажа: либо явно заданный `footprint`, либо
  /// прямоугольник по `width × height` (фолбэк для старых планов).
  BuildingFootprint get effectiveFootprint =>
      footprint ?? BuildingFootprint.rect(width, height);

  /// Этаж имеет НЕ-прямоугольный контур (полигон с уступами)?
  bool get hasPolygonalFootprint {
    final fp = footprint;
    if (fp == null) return false;
    if (fp.outline.length != 4) return true;
    // 4 вершины: проверяем что это axis-aligned прямоугольник.
    final b = fp.bbox;
    final corners = {
      (b.minX, b.minY),
      (b.maxX, b.minY),
      (b.maxX, b.maxY),
      (b.minX, b.maxY),
    };
    final got = {for (final p in fp.outline) (p.x, p.y)};
    return corners.length != 4 || !got.containsAll(corners);
  }

  FloorPlan copyWith({
    String? floorLabel,
    double? width,
    double? height,
    List<PlanRoom>? rooms,
    List<PlanOpening>? openings,
    List<PlanAttachment>? attachments,
    List<PlanColumn>? columns,
    BuildingFootprint? footprint,
  }) =>
      FloorPlan(
        floorLabel: floorLabel ?? this.floorLabel,
        width: width ?? this.width,
        height: height ?? this.height,
        rooms: rooms ?? this.rooms,
        openings: openings ?? this.openings,
        attachments: attachments ?? this.attachments,
        columns: columns ?? this.columns,
        footprint: footprint ?? this.footprint,
      );

  Map<String, dynamic> toJson() => {
        'floorLabel': floorLabel,
        'width': width,
        'height': height,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'columns': columns.map((c) => c.toJson()).toList(),
        if (footprint != null) 'footprint': footprint!.toJson(),
      };

  static FloorPlan fromJson(Map<String, dynamic> j) => FloorPlan(
        floorLabel: j['floorLabel'] as String,
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        rooms: [
          for (final r in (j['rooms'] as List))
            PlanRoom.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
        openings: [
          for (final o in (j['openings'] as List? ?? const []))
            PlanOpening.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
        attachments: [
          for (final a in (j['attachments'] as List? ?? const []))
            PlanAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        columns: [
          for (final c in (j['columns'] as List? ?? const []))
            PlanColumn.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        footprint: j['footprint'] is Map<String, dynamic>
            ? BuildingFootprint.fromJson(
                Map<String, dynamic>.from(j['footprint'] as Map),
              )
            : null,
      );

  String encode() => jsonEncode(toJson());

  static FloorPlan? tryDecode(String payload) {
    try {
      final m = jsonDecode(payload);
      if (m is Map<String, dynamic>) return FloorPlan.fromJson(m);
    } catch (_) {}
    return null;
  }
}
