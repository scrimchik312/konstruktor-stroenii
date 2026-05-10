import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/foundation_plan.dart';

/// Виджет-рендер плана фундамента (вид сверху).
///
/// Все геометрические данные приходят в [FoundationPlanModel] из
/// [FoundationPlanGenerator]. Виджет ничего не считает и не предполагает —
/// только отрисовывает то, что уже подобрано по СП 22 / СП 24 / СП 63.
class FoundationPlanView extends StatelessWidget {
  const FoundationPlanView({
    super.key,
    required this.model,
    this.padding = 12,
    this.showNotes = true,
  });

  final FoundationPlanModel model;
  final double padding;
  final bool showNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: model.buildingWidth / model.buildingLength * 1.15 + 0.05,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ПЛАН ФУНДАМЕНТА (М 1:100)',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: CustomPaint(
                painter: _FoundationPlanPainter(
                  model: model,
                  axisColor: theme.colorScheme.onSurface,
                  bandFill: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  slabFill: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  pileFill: theme.colorScheme.primary,
                  pileBorder: theme.colorScheme.onSurface,
                  outlineColor: theme.colorScheme.onSurface,
                  dimensionColor: theme.colorScheme.outline,
                  textColor: theme.colorScheme.onSurface,
                  hatchColor: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            if (showNotes && model.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              _NotesBlock(notes: model.notes, codes: model.codeReferences),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotesBlock extends StatelessWidget {
  const _NotesBlock({required this.notes, required this.codes});
  final List<String> notes;
  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Технические указания (из расчёта)',
            style: small?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $n', style: small),
            ),
          if (codes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Нормативы: ${codes.join(' · ')}',
              style: small?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

class _FoundationPlanPainter extends CustomPainter {
  _FoundationPlanPainter({
    required this.model,
    required this.axisColor,
    required this.bandFill,
    required this.slabFill,
    required this.pileFill,
    required this.pileBorder,
    required this.outlineColor,
    required this.dimensionColor,
    required this.textColor,
    required this.hatchColor,
  });

  final FoundationPlanModel model;
  final Color axisColor;
  final Color bandFill;
  final Color slabFill;
  final Color pileFill;
  final Color pileBorder;
  final Color outlineColor;
  final Color dimensionColor;
  final Color textColor;
  final Color hatchColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (model.buildingWidth <= 0 || model.buildingLength <= 0) return;
    // Отступы под оси, размерные цепи и пометки.
    const marginLeft = 36.0;
    const marginRight = 110.0; // под аннотацию глубины и размерную цепь
    const marginTop = 20.0;
    const marginBottom = 56.0;

    final availW = size.width - marginLeft - marginRight;
    final availH = size.height - marginTop - marginBottom;
    if (availW <= 0 || availH <= 0) return;

    final scale = math.min(
        availW / model.buildingWidth, availH / model.buildingLength);
    final planW = model.buildingWidth * scale;
    final planH = model.buildingLength * scale;
    final ox = marginLeft + (availW - planW) / 2;
    final oy = marginTop + (availH - planH) / 2;

    Offset toCanvas(double mx, double my) =>
        Offset(ox + mx * scale, oy + my * scale);

    // 1. Контур пятна застройки — толстый чёрный.
    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(Rect.fromLTWH(ox, oy, planW, planH), outlinePaint);

    // 2. Плита (если есть) — заштрихованная зона + контур.
    if (model.slab != null) {
      _drawSlab(canvas, model.slab!, toCanvas, scale);
    }

    // 3. Ленты фундамента — заполненный прямоугольник вдоль линии,
    // штриховка как у бетона (косыми линиями).
    for (final band in model.bands) {
      _drawBand(canvas, band, toCanvas, scale);
    }

    // 4. Сваи / столбы.
    for (final pile in model.piles) {
      _drawPile(canvas, pile, toCanvas, scale);
    }

    // 5. Оси.
    _drawAxes(canvas, size, ox, oy, planW, planH, scale, toCanvas);

    // 6. Размерные цепи.
    _drawDimensionChains(canvas, size, ox, oy, planW, planH, scale);

    // 7. Аннотации.
    for (final ann in model.annotations) {
      _drawAnnotation(canvas, ann, toCanvas, scale);
    }
  }

  void _drawSlab(Canvas canvas, FoundationSlab slab,
      Offset Function(double, double) toCanvas, double scale) {
    final path = Path();
    for (var i = 0; i < slab.polygon.length; i++) {
      final p = slab.polygon[i];
      final c = toCanvas(p.x, p.y);
      if (i == 0) {
        path.moveTo(c.dx, c.dy);
      } else {
        path.lineTo(c.dx, c.dy);
      }
    }
    path.close();
    final fill = Paint()
      ..color = slabFill
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);
    _hatchPath(canvas, path, hatchColor, spacing: 6, angle: math.pi / 4);

    final stroke = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, stroke);
  }

  void _drawBand(Canvas canvas, FoundationBand band,
      Offset Function(double, double) toCanvas, double scale) {
    final dx = band.x2 - band.x1;
    final dy = band.y2 - band.y1;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;
    final tx = dx / length;
    final ty = dy / length;
    // Перпендикуляр (поворот на 90°): (-ty, tx).
    final nx = -ty;
    final ny = tx;
    final hw = band.thicknessM / 2;
    final p1 = toCanvas(band.x1 + nx * hw, band.y1 + ny * hw);
    final p2 = toCanvas(band.x2 + nx * hw, band.y2 + ny * hw);
    final p3 = toCanvas(band.x2 - nx * hw, band.y2 - ny * hw);
    final p4 = toCanvas(band.x1 - nx * hw, band.y1 - ny * hw);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    final fillColor = switch (band.kind) {
      FoundationBandKind.external => bandFill,
      FoundationBandKind.internal => bandFill,
      FoundationBandKind.grillage => bandFill.withValues(alpha: 0.55),
    };
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);
    _hatchPath(canvas, path, axisColor.withValues(alpha: 0.5),
        spacing: 4, angle: math.pi / 4);
    final stroke = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(path, stroke);
  }

  void _drawPile(Canvas canvas, FoundationPile pile,
      Offset Function(double, double) toCanvas, double scale) {
    final c = toCanvas(pile.x, pile.y);
    final r = math.max(3.0, pile.diameterM * scale / 2);
    final fill = Paint()
      ..color = pileFill
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, fill);
    final stroke = Paint()
      ..color = pileBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawCircle(c, r, stroke);
    if (pile.label.isNotEmpty) {
      _drawTextPaint(
        canvas,
        pile.label,
        Offset(c.dx + r + 2, c.dy - 6),
        textColor,
        7,
      );
    }
  }

  void _drawAxes(
      Canvas canvas,
      Size size,
      double ox,
      double oy,
      double planW,
      double planH,
      double scale,
      Offset Function(double, double) toCanvas) {
    final axisPaint = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final dashArray = [4.0, 3.0];
    // Вертикальные оси (цифры) — выходят за границы плана сверху и снизу.
    for (final ax in model.verticalAxes) {
      final x = ox + ax.position * scale;
      _drawDashedLine(
          canvas, Offset(x, oy - 14), Offset(x, oy + planH + 14),
          axisPaint, dashArray);
      _drawAxisCircle(canvas, Offset(x, oy - 14), ax.label, textColor);
      _drawAxisCircle(canvas, Offset(x, oy + planH + 14), ax.label, textColor);
    }
    // Горизонтальные оси (буквы) — выходят за границы слева и справа.
    for (final ax in model.horizontalAxes) {
      final y = oy + ax.position * scale;
      _drawDashedLine(
          canvas, Offset(ox - 14, y), Offset(ox + planW + 14, y),
          axisPaint, dashArray);
      _drawAxisCircle(canvas, Offset(ox - 14, y), ax.label, textColor);
      _drawAxisCircle(canvas, Offset(ox + planW + 14, y), ax.label, textColor);
    }
  }

  void _drawAxisCircle(
      Canvas canvas, Offset center, String label, Color color) {
    const r = 8.0;
    final fill = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawCircle(center, r, stroke);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawDashedLine(
      Canvas canvas, Offset a, Offset b, Paint paint, List<double> dashArray) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;
    final ux = dx / length;
    final uy = dy / length;
    var travelled = 0.0;
    var idx = 0;
    var draw = true;
    while (travelled < length) {
      final segLen = math.min(dashArray[idx % dashArray.length], length - travelled);
      if (draw) {
        canvas.drawLine(
          Offset(a.dx + ux * travelled, a.dy + uy * travelled),
          Offset(a.dx + ux * (travelled + segLen),
              a.dy + uy * (travelled + segLen)),
          paint,
        );
      }
      travelled += segLen;
      idx++;
      draw = !draw;
    }
  }

  void _drawDimensionChains(Canvas canvas, Size size, double ox, double oy,
      double planW, double planH, double scale) {
    final paint = Paint()
      ..color = dimensionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final chain in model.dimensionChains) {
      final stops = [...chain.stops]..sort();
      if (stops.length < 2) continue;

      switch (chain.side) {
        case FoundationDimSide.bottom:
          final y = oy + planH + 22.0 + (chain.level - 1) * 14;
          // Линия цепи.
          canvas.drawLine(
              Offset(ox + stops.first * scale, y),
              Offset(ox + stops.last * scale, y),
              paint);
          for (var i = 0; i < stops.length; i++) {
            final cx = ox + stops[i] * scale;
            _drawTick(canvas, Offset(cx, y - 3), Offset(cx, y + 3), paint);
            // Засечки до плана.
            canvas.drawLine(
                Offset(cx, oy + planH + 4), Offset(cx, y),
                paint..strokeWidth = 0.4);
            paint.strokeWidth = 0.6;
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final mx = ox + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              _drawTextPaint(
                  canvas,
                  '$dimMm',
                  Offset(mx, y - 12),
                  dimensionColor,
                  9,
                  align: _TextAlign.center);
            }
          }
          break;
        case FoundationDimSide.top:
          final y = oy - 18.0 - (chain.level - 1) * 14;
          canvas.drawLine(
              Offset(ox + stops.first * scale, y),
              Offset(ox + stops.last * scale, y),
              paint);
          for (var i = 0; i < stops.length; i++) {
            final cx = ox + stops[i] * scale;
            _drawTick(canvas, Offset(cx, y - 3), Offset(cx, y + 3), paint);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final mx = ox + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              _drawTextPaint(
                  canvas, '$dimMm', Offset(mx, y - 11),
                  dimensionColor, 9, align: _TextAlign.center);
            }
          }
          break;
        case FoundationDimSide.right:
          final x = ox + planW + 22.0 + (chain.level - 1) * 14;
          canvas.drawLine(
              Offset(x, oy + stops.first * scale),
              Offset(x, oy + stops.last * scale),
              paint);
          for (var i = 0; i < stops.length; i++) {
            final cy = oy + stops[i] * scale;
            _drawTick(canvas, Offset(x - 3, cy), Offset(x + 3, cy), paint);
            // Засечки до плана.
            canvas.drawLine(
                Offset(ox + planW + 4, cy), Offset(x, cy),
                paint..strokeWidth = 0.4);
            paint.strokeWidth = 0.6;
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final my = oy + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              _drawTextPaint(
                  canvas, '$dimMm', Offset(x + 5, my - 5),
                  dimensionColor, 9);
            }
          }
          break;
        case FoundationDimSide.left:
          final x = ox - 22.0 - (chain.level - 1) * 14;
          canvas.drawLine(
              Offset(x, oy + stops.first * scale),
              Offset(x, oy + stops.last * scale),
              paint);
          for (var i = 0; i < stops.length; i++) {
            final cy = oy + stops[i] * scale;
            _drawTick(canvas, Offset(x - 3, cy), Offset(x + 3, cy), paint);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final my = oy + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              _drawTextPaint(canvas, '$dimMm',
                  Offset(x - 5, my - 5), dimensionColor, 9,
                  align: _TextAlign.right);
            }
          }
          break;
      }
    }
  }

  void _drawTick(Canvas canvas, Offset a, Offset b, Paint paint) {
    canvas.drawLine(a, b, paint);
  }

  void _drawAnnotation(Canvas canvas, FoundationAnnotation ann,
      Offset Function(double, double) toCanvas, double scale) {
    final p = toCanvas(ann.x, ann.y);
    if (ann.targetX != null && ann.targetY != null) {
      final t = toCanvas(ann.targetX!, ann.targetY!);
      final paint = Paint()
        ..color = textColor
        ..strokeWidth = 0.6;
      canvas.drawLine(t, p, paint);
    }
    _drawTextPaint(canvas, ann.text, p, textColor, 8);
  }

  void _drawTextPaint(Canvas canvas, String text, Offset position, Color color,
      double fontSize,
      {_TextAlign align = _TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    Offset offset = position;
    switch (align) {
      case _TextAlign.left:
        break;
      case _TextAlign.center:
        offset = position - Offset(tp.width / 2, 0);
        break;
      case _TextAlign.right:
        offset = position - Offset(tp.width, 0);
        break;
    }
    tp.paint(canvas, offset);
  }

  void _hatchPath(Canvas canvas, Path path, Color color,
      {required double spacing, required double angle}) {
    final bounds = path.getBounds();
    canvas.save();
    canvas.clipPath(path);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final diag = math.sqrt(bounds.width * bounds.width +
            bounds.height * bounds.height) /
        2;
    final dx = math.cos(angle);
    final dy = math.sin(angle);
    // Перпендикуляр.
    final px = -dy;
    final py = dx;
    final lines = (2 * diag / spacing).ceil();
    for (var i = -lines; i <= lines; i++) {
      final shift = i * spacing;
      final ax = cx + px * shift - dx * diag * 1.5;
      final ay = cy + py * shift - dy * diag * 1.5;
      final bx = cx + px * shift + dx * diag * 1.5;
      final by = cy + py * shift + dy * diag * 1.5;
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoundationPlanPainter oldDelegate) {
    return oldDelegate.model != model;
  }
}

enum _TextAlign { left, center, right }
