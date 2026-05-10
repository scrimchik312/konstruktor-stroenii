import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/floor_plan.dart';

/// Отрисовка схематического плана этажа.
///
/// Рендер двухслойный: сначала всё пятно заливается цветом «материал стены»
/// (тёмный onSurface), поверх — внутренние прямоугольники комнат, отступ
/// от рёбер которых равен половине толщины стены (380 мм для наружных,
/// 200 мм для внутренних). Это даёт визуальный эффект реальных стен.
///
/// Дверные и оконные проёмы (СП 55.13330.2017, СП 1.13130.2020) рисуются поверх:
/// дверь — «вырезом» в стене и дугой направления открывания, окно —
/// светлой заливкой и двумя параллельными линиями (стандартный
/// CAD-символ).
class FloorPlanView extends StatelessWidget {
  const FloorPlanView({
    super.key,
    required this.plan,
    this.padding = 16,
    this.showLabels = true,
  });

  final FloorPlan plan;
  final double padding;
  final bool showLabels;

  /// Толщина наружной стены, м.
  static const double outerWall = 0.38;

  /// Толщина внутренней перегородки, м.
  static const double innerWall = 0.20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: plan.width / plan.height,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: FloorPlanPainter(
            plan: plan,
            padding: padding,
            showLabels: showLabels,
            wallColor: theme.colorScheme.onSurface,
            surfaceColor: theme.colorScheme.surface,
            roomFill: theme.colorScheme.primaryContainer.withValues(alpha: 0.50),
            staircaseFill:
                theme.colorScheme.tertiaryContainer.withValues(alpha: 0.65),
            staircaseStroke: theme.colorScheme.tertiary,
            freeFill:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
            doorColor: theme.colorScheme.primary,
            entryDoorColor: theme.colorScheme.error,
            windowFill: theme.colorScheme.surface,
            windowStroke: theme.colorScheme.primary,
            labelStyle: theme.textTheme.bodySmall ?? const TextStyle(),
            dimensionStyle: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ) ??
                const TextStyle(),
            entryStyle: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ) ??
                const TextStyle(),
          ),
        ),
      ),
    );
  }
}

/// Преобразование координат «метры → пиксели» для отрисовки и хит-тестинга
/// плана этажа.
///
/// Используется одинаково и в [FloorPlanPainter], и в редакторе плана —
/// благодаря этому ручки выделения, хит-тесты жестов и сам план остаются
/// идеально согласованы по координатам.
class FloorPlanTransform {
  const FloorPlanTransform({
    required this.scale,
    required this.originX,
    required this.originY,
  });

  /// Сколько пикселей в одном метре.
  final double scale;

  /// Координата (в пикселях канваса), в которой стоит точка `(0, 0)` плана.
  final double originX;
  final double originY;

  Offset toCanvas(double mx, double my) =>
      Offset(originX + mx * scale, originY + my * scale);

  Offset toMeters(Offset canvas) => Offset(
        (canvas.dx - originX) / scale,
        (canvas.dy - originY) / scale,
      );

  /// Считает преобразование под размер канваса [size] и план [plan]:
  /// внутренняя зона рисования получает отступ [padding] со всех сторон.
  static FloorPlanTransform compute({
    required Size size,
    required FloorPlan plan,
    required double padding,
  }) {
    final availW = size.width - padding * 2;
    final availH = size.height - padding * 2;
    final scale = math.min(availW / plan.width, availH / plan.height);
    final drawW = plan.width * scale;
    final drawH = plan.height * scale;
    final originX = padding + (availW - drawW) / 2;
    final originY = padding + (availH - drawH) / 2;
    return FloorPlanTransform(
      scale: scale,
      originX: originX,
      originY: originY,
    );
  }
}

class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.plan,
    required this.padding,
    required this.showLabels,
    required this.wallColor,
    required this.surfaceColor,
    required this.roomFill,
    required this.staircaseFill,
    required this.staircaseStroke,
    required this.freeFill,
    required this.doorColor,
    required this.entryDoorColor,
    required this.windowFill,
    required this.windowStroke,
    required this.labelStyle,
    required this.dimensionStyle,
    required this.entryStyle,
  });

  final FloorPlan plan;
  final double padding;
  final bool showLabels;
  final Color wallColor;
  final Color surfaceColor;
  final Color roomFill;
  final Color staircaseFill;
  final Color staircaseStroke;
  final Color freeFill;
  final Color doorColor;
  final Color entryDoorColor;
  final Color windowFill;
  final Color windowStroke;
  final TextStyle labelStyle;
  final TextStyle dimensionStyle;
  final TextStyle entryStyle;

  static const double _outerWall = FloorPlanView.outerWall;
  static const double _innerWall = FloorPlanView.innerWall;
  static const double _eps = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= padding * 2 || size.height <= padding * 2) return;
    final t = FloorPlanTransform.compute(
      size: size,
      plan: plan,
      padding: padding,
    );
    final scale = t.scale;

    Offset toCanvas(double mx, double my) => t.toCanvas(mx, my);
    Rect rectM(double mx, double my, double mw, double mh) => Rect.fromLTWH(
          t.originX + mx * scale,
          t.originY + my * scale,
          mw * scale,
          mh * scale,
        );

    // 1. Заливка пятна цветом «стены» (масса материала).
    final wallPaint = Paint()..color = wallColor;
    canvas.drawRect(rectM(0, 0, plan.width, plan.height), wallPaint);

    // 2. Внутренние прямоугольники комнат поверх стен.
    for (final r in plan.rooms) {
      final left = _isOuter(r.x, 0) ? _outerWall / 2 : _innerWall / 2;
      final right = _isOuter(r.x + r.width, plan.width)
          ? _outerWall / 2
          : _innerWall / 2;
      final top = _isOuter(r.y, 0) ? _outerWall / 2 : _innerWall / 2;
      final bottom = _isOuter(r.y + r.height, plan.height)
          ? _outerWall / 2
          : _innerWall / 2;
      final innerW = r.width - left - right;
      final innerH = r.height - top - bottom;
      if (innerW <= 0 || innerH <= 0) continue;
      final inner = rectM(r.x + left, r.y + top, innerW, innerH);
      final fill = Paint();
      switch (r.kind) {
        case PlanRoomKind.staircase:
          fill.color = staircaseFill;
          break;
        case PlanRoomKind.free:
          fill.color = freeFill;
          break;
        case PlanRoomKind.room:
          fill.color = roomFill;
          break;
      }
      canvas.drawRect(inner, fill);
      if (r.kind == PlanRoomKind.staircase) {
        _drawStaircasePattern(canvas, inner, staircaseStroke);
      }
    }

    // 3. Проёмы: окна и двери.
    for (final o in plan.openings) {
      _drawOpening(canvas, o, toCanvas, scale);
    }

    // 4. Подписи комнат поверх внутренних прямоугольников.
    if (showLabels) {
      for (final r in plan.rooms) {
        final left = _isOuter(r.x, 0) ? _outerWall / 2 : _innerWall / 2;
        final right = _isOuter(r.x + r.width, plan.width)
            ? _outerWall / 2
            : _innerWall / 2;
        final top = _isOuter(r.y, 0) ? _outerWall / 2 : _innerWall / 2;
        final bottom = _isOuter(r.y + r.height, plan.height)
            ? _outerWall / 2
            : _innerWall / 2;
        final innerW = r.width - left - right;
        final innerH = r.height - top - bottom;
        if (innerW <= 0 || innerH <= 0) continue;
        final inner = rectM(r.x + left, r.y + top, innerW, innerH);
        if (inner.width < 30 || inner.height < 24) continue;
        final tp = TextPainter(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${r.label}\n',
                style: labelStyle.copyWith(fontWeight: FontWeight.w500),
              ),
              TextSpan(
                text: '${r.area.toStringAsFixed(1)} м²',
                style: dimensionStyle,
              ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 3,
          ellipsis: '…',
        )..layout(maxWidth: inner.width - 4);
        tp.paint(
          canvas,
          Offset(
            inner.center.dx - tp.width / 2,
            inner.center.dy - tp.height / 2,
          ),
        );
      }
    }

    // 5. Габаритная подпись внизу.
    final outerRect = rectM(0, 0, plan.width, plan.height);
    final dim = TextPainter(
      text: TextSpan(
        text: '${plan.width.toStringAsFixed(1)} × '
            '${plan.height.toStringAsFixed(1)} м · ${plan.floorLabel}',
        style: dimensionStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dim.paint(
      canvas,
      Offset(
        outerRect.center.dx - dim.width / 2,
        outerRect.bottom + 4,
      ),
    );
  }

  void _drawOpening(
    Canvas canvas,
    PlanOpening o,
    Offset Function(double, double) toCanvas,
    double scale,
  ) {
    // Определяем толщину стены, на которой стоит проём (наружная/внутренняя).
    final isExternalWall = _isOpeningOnOuterWall(o);
    final thickness = isExternalWall ? _outerWall : _innerWall;

    // Прямоугольник проёма в метрах. Координаты (o.x, o.y) — точка стены,
    // куда «вписан» проём. Проём перпендикулярен стене.
    //
    // Правило: проём не должен выступать за наружную грань стены —
    // если стена внешняя, центр прямоугольника прижимается к
    // внутренней стороне стены. Для внутренних стен оставляем центр
    // на оси стены.
    Rect openingRectM;
    final isVerticalWall = !o.side.isHorizontal;
    if (isVerticalWall) {
      // Стена вертикальная. Если она внешняя слева/справа — смещаем
      // прямоугольник так, чтобы он целиком лежал ВНУТРИ контура.
      double left;
      if (isExternalWall && o.x <= thickness * 0.6) {
        // Левая внешняя стена: проём от 0 до thickness.
        left = 0;
      } else if (isExternalWall && o.x >= plan.width - thickness * 0.6) {
        // Правая внешняя стена.
        left = plan.width - thickness;
      } else {
        left = o.x - thickness / 2;
      }
      openingRectM = Rect.fromLTWH(left, o.y, thickness, o.length);
    } else {
      double top;
      if (isExternalWall && o.y <= thickness * 0.6) {
        top = 0;
      } else if (isExternalWall && o.y >= plan.height - thickness * 0.6) {
        top = plan.height - thickness;
      } else {
        top = o.y - thickness / 2;
      }
      openingRectM = Rect.fromLTWH(o.x, top, o.length, thickness);
    }
    final openingRect = Rect.fromLTRB(
      toCanvas(openingRectM.left, openingRectM.top).dx,
      toCanvas(openingRectM.left, openingRectM.top).dy,
      toCanvas(openingRectM.right, openingRectM.bottom).dx,
      toCanvas(openingRectM.right, openingRectM.bottom).dy,
    );

    if (o.kind == OpeningKind.archway) {
      // Открытый проход: «вырезаем» стену цветом свободной зоны, ничего
      // больше не рисуем — две свободные зоны визуально соединены в единое
      // пространство.
      canvas.drawRect(openingRect, Paint()..color = freeFill);
      return;
    }

    if (o.kind == OpeningKind.window) {
      // Окно: заливаем светлой заливкой и рисуем две параллельные линии
      // вдоль стены (стандартный CAD-символ окна, СП 50.13330.2024).
      canvas.drawRect(openingRect, Paint()..color = windowFill);
      final stroke = Paint()
        ..color = windowStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(openingRect, stroke);
      if (isVerticalWall) {
        final x1 = openingRect.left + openingRect.width * 0.33;
        final x2 = openingRect.left + openingRect.width * 0.67;
        canvas.drawLine(
          Offset(x1, openingRect.top + 1),
          Offset(x1, openingRect.bottom - 1),
          stroke,
        );
        canvas.drawLine(
          Offset(x2, openingRect.top + 1),
          Offset(x2, openingRect.bottom - 1),
          stroke,
        );
      } else {
        final y1 = openingRect.top + openingRect.height * 0.33;
        final y2 = openingRect.top + openingRect.height * 0.67;
        canvas.drawLine(
          Offset(openingRect.left + 1, y1),
          Offset(openingRect.right - 1, y1),
          stroke,
        );
        canvas.drawLine(
          Offset(openingRect.left + 1, y2),
          Offset(openingRect.right - 1, y2),
          stroke,
        );
      }
      return;
    }

    // Дверь: «вырезаем» стену, рисуем створку и дугу открывания.
    canvas.drawRect(openingRect, Paint()..color = surfaceColor);
    final isEntry = o.kind == OpeningKind.externalDoor;
    final doorColorEff = isEntry ? entryDoorColor : doorColor;
    final stroke = Paint()
      ..color = doorColorEff
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEntry ? 1.6 : 1.2;
    final lengthPx = o.length * scale;

    // Створка (полотно двери) — линия от петли в открытом положении.
    // Дуга — четверть круга радиусом = длина проёма.
    Offset hinge;
    Offset leafEnd;
    Rect arcRect;
    double startAngle;
    if (isVerticalWall) {
      // Дверь на вертикальной стене. Открываем «вглубь комнаты» — для
      // простоты рисуем дугу со стороны swing (>0 — вниз, <0 — вверх).
      if (o.swing >= 0) {
        hinge = Offset(openingRect.center.dx, openingRect.top);
        leafEnd =
            Offset(openingRect.center.dx + lengthPx, openingRect.top);
        arcRect = Rect.fromCircle(center: hinge, radius: lengthPx);
        startAngle = 0; // 0..pi/2
      } else {
        hinge = Offset(openingRect.center.dx, openingRect.bottom);
        leafEnd =
            Offset(openingRect.center.dx + lengthPx, openingRect.bottom);
        arcRect = Rect.fromCircle(center: hinge, radius: lengthPx);
        startAngle = -math.pi / 2;
      }
    } else {
      if (o.swing >= 0) {
        hinge = Offset(openingRect.left, openingRect.center.dy);
        leafEnd =
            Offset(openingRect.left, openingRect.center.dy + lengthPx);
        arcRect = Rect.fromCircle(center: hinge, radius: lengthPx);
        startAngle = math.pi / 2;
      } else {
        hinge = Offset(openingRect.right, openingRect.center.dy);
        leafEnd =
            Offset(openingRect.right, openingRect.center.dy + lengthPx);
        arcRect = Rect.fromCircle(center: hinge, radius: lengthPx);
        startAngle = math.pi / 2;
      }
    }
    canvas.drawLine(hinge, leafEnd, stroke);
    final arcPaint = Paint()
      ..color = doorColorEff.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawArc(arcRect, startAngle, math.pi / 2, false, arcPaint);

    if (isEntry) {
      final tp = TextPainter(
        text: TextSpan(text: 'Вход', style: entryStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Подпись «Вход» снаружи стены, со стороны улицы.
      Offset labelOffset;
      switch (o.side) {
        case WallSide.top:
          labelOffset = Offset(
            openingRect.center.dx - tp.width / 2,
            openingRect.top - tp.height - 1,
          );
          break;
        case WallSide.bottom:
          labelOffset = Offset(
            openingRect.center.dx - tp.width / 2,
            openingRect.bottom + 1,
          );
          break;
        case WallSide.left:
          labelOffset = Offset(
            openingRect.left - tp.width - 2,
            openingRect.center.dy - tp.height / 2,
          );
          break;
        case WallSide.right:
          labelOffset = Offset(
            openingRect.right + 2,
            openingRect.center.dy - tp.height / 2,
          );
          break;
      }
      tp.paint(canvas, labelOffset);
    }
  }

  bool _isOpeningOnOuterWall(PlanOpening o) {
    switch (o.side) {
      case WallSide.top:
        return o.y < _eps;
      case WallSide.bottom:
        return (plan.height - o.y).abs() < _eps;
      case WallSide.left:
        return o.x < _eps;
      case WallSide.right:
        return (plan.width - o.x).abs() < _eps;
    }
  }

  bool _isOuter(double v, double boundary) => (v - boundary).abs() < _eps;

  void _drawStaircasePattern(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final horizontal = rect.width >= rect.height;
    const steps = 8;
    if (horizontal) {
      final stepW = rect.width / steps;
      for (var i = 1; i < steps; i++) {
        final x = rect.left + stepW * i;
        canvas.drawLine(
          Offset(x, rect.top + 2),
          Offset(x, rect.bottom - 2),
          paint,
        );
      }
    } else {
      final stepH = rect.height / steps;
      for (var i = 1; i < steps; i++) {
        final y = rect.top + stepH * i;
        canvas.drawLine(
          Offset(rect.left + 2, y),
          Offset(rect.right - 2, y),
          paint,
        );
      }
    }
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(rect.left + 4, rect.bottom - 4),
      Offset(rect.right - 4, rect.top + 4),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.padding != padding;
}
