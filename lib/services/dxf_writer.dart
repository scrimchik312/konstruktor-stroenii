import '../models/floor_plan.dart';

/// Минимальный экспорт в формат DXF (AutoCAD R12 ASCII).
///
/// DXF — открытый текстовый формат, поддерживаемый AutoCAD, LibreCAD,
/// QCAD, BricsCAD и большинством профессиональных CAD-программ. Здесь
/// мы реализуем подмножество R12: HEADER (минимум переменных), TABLES
/// (LAYER), ENTITIES (LINE, TEXT, CIRCLE/ARC). Этого достаточно, чтобы
/// импортировать в инженерное ПО и продолжить работу.
///
/// Координатная система DXF — обычная декартова, ось Y направлена вверх.
/// В наших моделях ось Y направлена вниз (как в Flutter Canvas), поэтому
/// при экспорте мы её отражаем: `dxfY = plan.height - y`.
class DxfWriter {
  DxfWriter._();

  /// Сериализовать [plan] в строку DXF. Если передан [title] — он будет
  /// добавлен как TEXT в верхней части листа.
  static String write(FloorPlan plan, {String? title}) {
    final b = StringBuffer();
    _writeHeader(b);
    _writeTables(b);
    b.writeln('0');
    b.writeln('SECTION');
    b.writeln('2');
    b.writeln('ENTITIES');

    // Контур пятна застройки.
    _line(b, 0, 0, plan.width, 0, layer: 'OUTLINE', color: 7);
    _line(b, plan.width, 0, plan.width, plan.height,
        layer: 'OUTLINE', color: 7);
    _line(b, plan.width, plan.height, 0, plan.height,
        layer: 'OUTLINE', color: 7);
    _line(b, 0, plan.height, 0, 0, layer: 'OUTLINE', color: 7);

    // Комнаты — прямоугольники + подписи.
    for (final r in plan.rooms) {
      final layer = switch (r.kind) {
        PlanRoomKind.staircase => 'STAIR',
        PlanRoomKind.free => 'FREE',
        PlanRoomKind.room => 'ROOM',
      };
      final color = switch (r.kind) {
        PlanRoomKind.staircase => 6, // magenta
        PlanRoomKind.free => 8, // gray
        PlanRoomKind.room => 5, // blue
      };
      final x0 = r.x;
      final y0 = plan.height - r.y;
      final x1 = r.x + r.width;
      final y1 = plan.height - (r.y + r.height);
      _line(b, x0, y0, x1, y0, layer: layer, color: color);
      _line(b, x1, y0, x1, y1, layer: layer, color: color);
      _line(b, x1, y1, x0, y1, layer: layer, color: color);
      _line(b, x0, y1, x0, y0, layer: layer, color: color);
      // Подпись комнаты по центру.
      final cx = r.x + r.width / 2;
      final cy = plan.height - (r.y + r.height / 2);
      _text(b, cx, cy, '${r.label} ${r.area.toStringAsFixed(1)} м²',
          layer: 'ROOM_LABEL',
          height: 0.30,
          color: 7);
    }

    // Проёмы — отрезки на стене + маркеры.
    for (final o in plan.openings) {
      final layer = switch (o.kind) {
        OpeningKind.door => 'DOOR',
        OpeningKind.externalDoor => 'DOOR_EXT',
        OpeningKind.window => 'WINDOW',
        OpeningKind.archway => 'ARCHWAY',
      };
      final color = switch (o.kind) {
        OpeningKind.door => 3, // green
        OpeningKind.externalDoor => 1, // red
        OpeningKind.window => 4, // cyan
        OpeningKind.archway => 8, // gray
      };
      double x0, y0, x1, y1;
      if (o.side.isHorizontal) {
        x0 = o.x;
        x1 = o.x + o.length;
        y0 = y1 = plan.height - o.y;
      } else {
        x0 = x1 = o.x;
        y0 = plan.height - o.y;
        y1 = plan.height - (o.y + o.length);
      }
      _line(b, x0, y0, x1, y1, layer: layer, color: color);
      // Кружок-маркер по центру (для наглядности импортированной геометрии).
      final mx = (x0 + x1) / 2;
      final my = (y0 + y1) / 2;
      _circle(b, mx, my, 0.12, layer: layer, color: color);
    }

    // Заголовок листа.
    if (title != null && title.isNotEmpty) {
      _text(b, 0, plan.height + 0.5, title,
          layer: 'TITLE', height: 0.5, color: 7);
    }

    b.writeln('0');
    b.writeln('ENDSEC');
    b.writeln('0');
    b.writeln('EOF');
    return b.toString();
  }

  static void _writeHeader(StringBuffer b) {
    b.writeln('0');
    b.writeln('SECTION');
    b.writeln('2');
    b.writeln('HEADER');
    b.writeln('9');
    b.writeln(r'$ACADVER');
    b.writeln('1');
    b.writeln('AC1009'); // R12
    b.writeln('9');
    b.writeln(r'$INSUNITS');
    b.writeln('70');
    b.writeln('6'); // метры
    b.writeln('0');
    b.writeln('ENDSEC');
  }

  static void _writeTables(StringBuffer b) {
    b.writeln('0');
    b.writeln('SECTION');
    b.writeln('2');
    b.writeln('TABLES');
    b.writeln('0');
    b.writeln('TABLE');
    b.writeln('2');
    b.writeln('LAYER');
    b.writeln('70');
    b.writeln('9');
    for (final layer in const [
      ('OUTLINE', 7),
      ('ROOM', 5),
      ('ROOM_LABEL', 7),
      ('STAIR', 6),
      ('FREE', 8),
      ('DOOR', 3),
      ('DOOR_EXT', 1),
      ('WINDOW', 4),
      ('ARCHWAY', 8),
      ('TITLE', 7),
    ]) {
      b.writeln('0');
      b.writeln('LAYER');
      b.writeln('2');
      b.writeln(layer.$1);
      b.writeln('70');
      b.writeln('0');
      b.writeln('62');
      b.writeln('${layer.$2}');
      b.writeln('6');
      b.writeln('CONTINUOUS');
    }
    b.writeln('0');
    b.writeln('ENDTAB');
    b.writeln('0');
    b.writeln('ENDSEC');
  }

  static void _line(
    StringBuffer b,
    double x0,
    double y0,
    double x1,
    double y1, {
    required String layer,
    required int color,
  }) {
    b.writeln('0');
    b.writeln('LINE');
    b.writeln('8');
    b.writeln(layer);
    b.writeln('62');
    b.writeln('$color');
    b.writeln('10');
    b.writeln(_n(x0));
    b.writeln('20');
    b.writeln(_n(y0));
    b.writeln('30');
    b.writeln('0.0');
    b.writeln('11');
    b.writeln(_n(x1));
    b.writeln('21');
    b.writeln(_n(y1));
    b.writeln('31');
    b.writeln('0.0');
  }

  static void _text(
    StringBuffer b,
    double x,
    double y,
    String s, {
    required String layer,
    required double height,
    required int color,
  }) {
    b.writeln('0');
    b.writeln('TEXT');
    b.writeln('8');
    b.writeln(layer);
    b.writeln('62');
    b.writeln('$color');
    b.writeln('10');
    b.writeln(_n(x));
    b.writeln('20');
    b.writeln(_n(y));
    b.writeln('30');
    b.writeln('0.0');
    b.writeln('40');
    b.writeln(_n(height));
    b.writeln('1');
    b.writeln(_dxfStr(s));
    // Выравнивание по центру (group 72 = 1, group 11/21 = выравнивающая точка).
    b.writeln('72');
    b.writeln('1');
    b.writeln('11');
    b.writeln(_n(x));
    b.writeln('21');
    b.writeln(_n(y));
    b.writeln('31');
    b.writeln('0.0');
  }

  static void _circle(
    StringBuffer b,
    double cx,
    double cy,
    double r, {
    required String layer,
    required int color,
  }) {
    b.writeln('0');
    b.writeln('CIRCLE');
    b.writeln('8');
    b.writeln(layer);
    b.writeln('62');
    b.writeln('$color');
    b.writeln('10');
    b.writeln(_n(cx));
    b.writeln('20');
    b.writeln(_n(cy));
    b.writeln('30');
    b.writeln('0.0');
    b.writeln('40');
    b.writeln(_n(r));
  }

  static String _n(double v) => v.toStringAsFixed(4);

  /// DXF не любит «опасные» символы в TEXT — переводы строк, кавычки.
  /// Минимальная санитизация.
  static String _dxfStr(String s) =>
      s.replaceAll('\n', ' ').replaceAll('\r', ' ');
}
