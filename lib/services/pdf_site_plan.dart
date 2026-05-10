import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/building_footprint.dart';
import '../models/client_brief.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import 'pdf_builder.dart';

/// Лист АР-0a — «Схема планировочной организации земельного участка»
/// (Phase-3a-2 §17.1.2).
///
/// Условный участок 20 × 20 м (масштаб 1:200), пятно застройки взято
/// из `brief.footprintWidth × footprintLength`. Участок отрисован как
/// квадрат со штрих-пунктирной границей и размерными цепочками 20 000 /
/// 20 000 по периметру (с засечками СПДС).
///
/// На участке расположены:
///   • пятно застройки (центр со смещением 5 м к северной границе,
///     серая заливка `0xE5E5E5`, чёрный контур 0.7 pt);
///   • четыре размерные привязки от стен здания до ближайших границ
///     участка (СНиП 30-102 — 3 м до забора, 5 м до красной линии);
///   • подъезд от северной границы шириной 5 м (асфальт, штриховка);
///   • пешеходная дорожка от калитки до входной двери дома;
///   • газон по периметру (заливка `0xE0F0D8`) с условными
///     круглыми «деревьями» ⌀1.5 м;
///   • символ «Север» (стрелка ↑ + N) в правом верхнем углу;
///   • легенда условных обозначений в правой колонке;
///   • штамп ГОСТ Р 21.101-2020 со значением `АР-0a` и наименованием
///     «Схема планировочной организации земельного участка».
class PdfSitePlan {
  PdfSitePlan._();

  /// Размер условного участка по умолчанию, м (квадрат).
  static const double _defaultPlotM = 20.0;

  /// Отступ пятна застройки от северной границы участка по умолчанию,
  /// м (СНиП 30-102 — 5 м до красной линии).
  static const double _defaultSetbackNorthM = 5.0;

  static pw.Page buildPage({
    required HouseProject project,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
    required int versionNumber,
    List<FloorPlan> plans = const [],
  }) {
    final brief = project.brief;
    // §27.1: реальный полигон пятна берём из проекта — для L/T/U/+
    // форм будет полигон с >4 вершинами, для прямоугольника — стандарт.
    // Это синхронизирует ПОЗУ с планами этажей и аксонометрией.
    final fp = project.effectiveArchitectureFootprint;
    final bbox = fp.bbox;
    final buildingW = bbox.width;
    final buildingD = bbox.height;
    // §27.1: автоматическое масштабирование участка — если пятно
    // больше 14 м, делаем участок 30×30 м (СНиП 30-102: минимум 3 м
    // от стены до забора + 5 м до красной линии + место под подъезд).
    final maxFootprint = math.max(buildingW, buildingD);
    final plotSide = maxFootprint <= 14.0
        ? _defaultPlotM
        : (maxFootprint + 16.0).clamp(20.0, 60.0).toDouble();
    final plotW = plotSide;
    final plotD = plotSide;
    final setbackN = _defaultSetbackNorthM
        .clamp(3.0, math.max(3.0, plotD - buildingD - 3.0))
        .toDouble();

    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _header(project, font, fontBold),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.LayoutBuilder(
                              builder: (context, constraints) {
                                final c = constraints!;
                                return pw.SizedBox(
                                  width: c.maxWidth,
                                  height: c.maxHeight,
                                  child: pw.CustomPaint(
                                    size: PdfPoint(c.maxWidth, c.maxHeight),
                                    painter: (canvas, size) =>
                                        _paintSitePlan(
                                      canvas: canvas,
                                      size: size,
                                      pdfFont: pdfTtfRegular,
                                      plotWidthM: plotW,
                                      plotDepthM: plotD,
                                      buildingWidthM: buildingW,
                                      buildingDepthM: buildingD,
                                      setbackNorthM: setbackN,
                                      brief: brief,
                                      plans: plans,
                                      footprint: fp,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          pw.Expanded(
                            flex: 2,
                            child: _legend(font, fontBold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          ],
        );
      },
    );
  }

  // ─────────────────────────── Шапка ───────────────────────────────────

  static pw.Widget _header(
    HouseProject project,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              project.name.isEmpty
                  ? 'Индивидуальный жилой дом'
                  : project.name,
              style: pw.TextStyle(
                fontSize: 12,
                font: fontBold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Схема планировочной организации земельного участка',
              style: pw.TextStyle(fontSize: 9, font: font),
            ),
          ],
        ),
        pw.Text(
          'Масштаб 1:200',
          style: pw.TextStyle(fontSize: 9, font: font),
        ),
      ],
    );
  }

  // ─────────────────────────── Легенда ─────────────────────────────────

  static pw.Widget _legend(pw.Font font, pw.Font fontBold) {
    pw.Widget item(pw.Widget swatch, String text) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(width: 28, height: 14, child: swatch),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  text,
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ),
            ],
          ),
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Условные обозначения',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Divider(height: 6, color: PdfColors.grey400),
          item(
            pw.CustomPaint(
              size: const PdfPoint(28, 14),
              painter: (canvas, size) {
                canvas.setStrokeColor(PdfColors.black);
                canvas.setLineWidth(0.8);
                _dashDotLine(
                    canvas, 0, size.y / 2, size.x, size.y / 2);
              },
            ),
            'Граница земельного участка',
          ),
          item(
            pw.Container(
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFE5E5E5),
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
              ),
            ),
            'Пятно застройки (проектируемое)',
          ),
          item(
            pw.Container(
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFD7D7D7),
                border: pw.Border.all(color: PdfColors.grey700, width: 0.5),
              ),
            ),
            'Подъезд (асфальт)',
          ),
          item(
            pw.Container(
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFEFE6D8),
                border: pw.Border.all(color: PdfColors.grey700, width: 0.4),
              ),
            ),
            'Пешеходная дорожка (плитка)',
          ),
          item(
            pw.Container(
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFE0F0D8),
                border: pw.Border.all(color: PdfColors.grey500, width: 0.4),
              ),
            ),
            'Газон / зелёные насаждения',
          ),
          item(
            pw.CustomPaint(
              size: const PdfPoint(28, 14),
              painter: (canvas, size) {
                canvas.setColor(const PdfColor(0.55, 0.78, 0.46));
                canvas.drawEllipse(size.x / 2, size.y / 2, 5, 5);
                canvas.fillPath();
                canvas.setStrokeColor(PdfColors.grey700);
                canvas.setLineWidth(0.4);
                canvas.drawEllipse(size.x / 2, size.y / 2, 5, 5);
                canvas.strokePath();
              },
            ),
            'Деревья / кустарники (⌀ 1,5 м)',
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Масштаб 1:200',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Размеры участка приведены условно (20 × 20 м). '
            'При наличии данных кадастровой съёмки границы участка и '
            'привязки уточняются.',
            style: pw.TextStyle(
              font: font,
              fontSize: 7,
              color: PdfColors.grey700,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'СНиП 30-102-99 — расстояние от жилого дома до границы '
            'соседнего участка ≥ 3 м, до красной линии улицы ≥ 5 м.',
            style: pw.TextStyle(
              font: font,
              fontSize: 7,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Painter: схема планировочной организации ─────────────

  static void _paintSitePlan({
    required PdfGraphics canvas,
    required PdfPoint size,
    required PdfFont pdfFont,
    required double plotWidthM,
    required double plotDepthM,
    required double buildingWidthM,
    required double buildingDepthM,
    required double setbackNorthM,
    required ClientBrief brief,
    required List<FloorPlan> plans,
    required BuildingFootprint footprint,
  }) {
    // Резервируем поля под цепочки размеров (≈ 36 pt) и подпись «Север».
    const margin = 36.0;
    final availW = size.x - margin * 2;
    final availH = size.y - margin * 2;
    final scaleX = availW / plotWidthM;
    final scaleY = availH / plotDepthM;
    final scale = math.min(scaleX, scaleY);
    final plotW = plotWidthM * scale;
    final plotH = plotDepthM * scale;
    final plotX = (size.x - plotW) / 2;
    final plotY = (size.y - plotH) / 2;

    // 1) ГАЗОН — фон всего участка.
    canvas.setColor(const PdfColor.fromInt(0xFFE0F0D8));
    canvas.drawRect(plotX, plotY, plotW, plotH);
    canvas.fillPath();

    // 2) Граница участка — штрих-пунктирная.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    _dashDotRect(canvas, plotX, plotY, plotW, plotH);

    // 3) ПЯТНО ЗАСТРОЙКИ — центр по X, отступ от северной границы.
    // На плане «Север сверху», поэтому северная граница — верхняя
    // (Y = plotY + plotH в PDF-координатах).
    final bldgW = buildingWidthM * scale;
    final bldgH = buildingDepthM * scale;
    final bldgX = plotX + (plotW - bldgW) / 2;
    final bldgY = plotY + plotH - setbackNorthM * scale - bldgH;

    // 4) ПОДЪЕЗД — от северной границы к фронту здания, ширина 5 м.
    final drivewayW = 5.0 * scale;
    final drivewayX = bldgX + bldgW / 2 - drivewayW / 2;
    final drivewayY1 = bldgY + bldgH; // фронт здания
    final drivewayY2 = plotY + plotH; // северная граница
    canvas.setColor(const PdfColor.fromInt(0xFFD7D7D7));
    canvas.drawRect(
      drivewayX,
      drivewayY1,
      drivewayW,
      drivewayY2 - drivewayY1,
    );
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.5);
    canvas.drawRect(
      drivewayX,
      drivewayY1,
      drivewayW,
      drivewayY2 - drivewayY1,
    );
    canvas.strokePath();
    // Штриховка асфальта — 45° тонкие линии.
    _hatchRect(
      canvas,
      drivewayX,
      drivewayY1,
      drivewayW,
      drivewayY2 - drivewayY1,
      step: 4.5,
      colour: PdfColors.grey500,
      lineWidth: 0.3,
    );

    // 5) ПЕШЕХОДНАЯ ДОРОЖКА — от калитки (1 м влево от подъезда на
    // северной границе) к входу в дом (центр южной стены здания).
    final walkwayWidth = 1.0 * scale;
    final gateX = drivewayX - 1.5 * scale;
    final gateY = plotY + plotH;
    final entranceX = bldgX + bldgW / 2;
    final entranceY = bldgY; // южная стена здания
    _drawWalkway(
      canvas,
      gateX,
      gateY,
      entranceX,
      entranceY,
      walkwayWidth,
    );

    // 6) ПЯТНО ЗАСТРОЙКИ — поверх дорожек.
    // §27.1: рисуем РЕАЛЬНЫЙ полигон (L/T/U/+ форма), а не просто bbox.
    // Координаты outline-а — в системе плана (Y растёт вниз, начало —
    // лево-верх bbox-а). Конвертируем в координаты PDF (Y вверх,
    // привязка к bldgX/bldgY как лево-низ bbox-а).
    final fpBbox = footprint.bbox;
    final fpW = fpBbox.width;
    final fpH = fpBbox.height;
    final outlinePoints = footprint.outline.map((v) {
      final localX = v.x - fpBbox.minX; // 0..fpW
      final localY = v.y - fpBbox.minY; // 0..fpH
      // bldgY — это нижняя граница bbox в PDF (PDF Y=0 снизу).
      // bldgY + bldgH — верхняя граница. План имеет Y вниз, поэтому
      // флипаем: PDF_y = bldgY + bldgH - localY.
      return [
        bldgX + localX * (bldgW / fpW),
        bldgY + bldgH - localY * (bldgH / fpH),
      ];
    }).toList();
    canvas.setColor(const PdfColor.fromInt(0xFFE5E5E5));
    canvas.moveTo(outlinePoints[0][0], outlinePoints[0][1]);
    for (var i = 1; i < outlinePoints.length; i++) {
      canvas.lineTo(outlinePoints[i][0], outlinePoints[i][1]);
    }
    canvas.closePath();
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.moveTo(outlinePoints[0][0], outlinePoints[0][1]);
    for (var i = 1; i < outlinePoints.length; i++) {
      canvas.lineTo(outlinePoints[i][0], outlinePoints[i][1]);
    }
    canvas.closePath();
    canvas.strokePath();
    // Тонкая диагональ «крыша на плане» — только для прямоугольных
    // пятен; для не-rect форм она бессмысленна.
    if (outlinePoints.length == 4) {
      canvas.setStrokeColor(PdfColors.grey600);
      canvas.setLineWidth(0.4);
      canvas.drawLine(bldgX, bldgY, bldgX + bldgW, bldgY + bldgH);
      canvas.drawLine(bldgX + bldgW, bldgY, bldgX, bldgY + bldgH);
      canvas.strokePath();
    }

    // 6a) ПРИСТРОЙКИ: гараж, терраса, балкон — если выбраны.
    // Все прямоугольники «исключений» для деревьев (не сажать внутри).
    final exclusions = <List<double>>[
      [bldgX, bldgY, bldgW, bldgH],
    ];

    void _drawAttachment(double ax, double ay, double aw, double ah,
        String label, PdfColor fill) {
      canvas.setColor(fill);
      canvas.drawRect(ax, ay, aw, ah);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      canvas.drawRect(ax, ay, aw, ah);
      canvas.strokePath();
      final lw = pdfFont.stringMetrics(label).advanceWidth * 5.5;
      canvas.setColor(PdfColors.black);
      canvas.drawString(pdfFont, 5.5, label,
          ax + aw / 2 - lw / 2, ay + ah / 2 - 3);
      exclusions.add([ax, ay, aw, ah]);
    }

    // Пристройки из планировки 1-го этажа (гараж, терраса, крыльцо).
    // Координаты берём из FloorPlan.attachments — так лист участка
    // синхронизирован с планами этажей и аксонометрией.
    if (plans.isNotEmpty) {
      for (final att in plans.first.attachments) {
        final aw = att.width * scale;
        final ah = att.height * scale;
        // Флип Y: att.y в плане растёт вниз, в PDF — вверх.
        final ax = bldgX + att.x * scale;
        final ay = bldgY + bldgH - (att.y + att.height) * scale;
        final fill = switch (att.kind) {
          PlanAttachmentKind.garage =>
            const PdfColor.fromInt(0xFFDADADA),
          PlanAttachmentKind.terrace =>
            const PdfColor.fromInt(0xFFE8DCC8),
          PlanAttachmentKind.porch =>
            const PdfColor.fromInt(0xFFD5E8F0),
        };
        _drawAttachment(ax, ay, aw, ah, att.label, fill);
      }
    }

    // 7) ДЕРЕВЬЯ — по периметру участка, с пропуском в зонах построек.
    final treeR = 0.75 * scale;
    final treePositions = <List<double>>[];

    bool _treeOverlapsExclusion(double tx, double ty) {
      for (final ex in exclusions) {
        final rx = ex[0], ry = ex[1], rw = ex[2], rh = ex[3];
        final cx = tx.clamp(rx, rx + rw);
        final cy = ty.clamp(ry, ry + rh);
        final dx = tx - cx;
        final dy = ty - cy;
        if (dx * dx + dy * dy < treeR * treeR) return true;
      }
      return false;
    }

    // Север (без подъезда).
    final northTreeCount = 5;
    for (var i = 1; i <= northTreeCount; i++) {
      final tx = plotX + plotW * i / (northTreeCount + 1);
      if ((tx - (drivewayX + drivewayW / 2)).abs() < drivewayW / 2 + treeR) {
        continue;
      }
      final ty = plotY + plotH - 1.5 * scale;
      if (!_treeOverlapsExclusion(tx, ty)) treePositions.add([tx, ty]);
    }
    // Юг (улица — 3 дерева).
    for (var i = 1; i <= 3; i++) {
      final tx = plotX + plotW * i / 4;
      final ty = plotY + 1.5 * scale;
      if (!_treeOverlapsExclusion(tx, ty)) treePositions.add([tx, ty]);
    }
    // Восток / Запад — по 2 дерева.
    for (var i = 1; i <= 2; i++) {
      final ty = plotY + plotH * i / 3;
      final txW = plotX + 1.5 * scale;
      final txE = plotX + plotW - 1.5 * scale;
      if (!_treeOverlapsExclusion(txW, ty)) treePositions.add([txW, ty]);
      if (!_treeOverlapsExclusion(txE, ty)) treePositions.add([txE, ty]);
    }
    for (final t in treePositions) {
      canvas.setColor(const PdfColor(0.55, 0.78, 0.46));
      canvas.drawEllipse(t[0], t[1], treeR, treeR);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.grey700);
      canvas.setLineWidth(0.3);
      canvas.drawEllipse(t[0], t[1], treeR, treeR);
      canvas.strokePath();
    }

    // 8) РАЗМЕРНЫЕ ЦЕПИ участка по периметру: 20 000 / 20 000.
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: plotX,
      y1: plotY - 18,
      x2: plotX + plotW,
      y2: plotY - 18,
      label: '${(plotWidthM * 1000).toStringAsFixed(0)}',
    );
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: plotX - 18,
      y1: plotY,
      x2: plotX - 18,
      y2: plotY + plotH,
      label: '${(plotDepthM * 1000).toStringAsFixed(0)}',
      vertical: true,
    );

    // 9) РАЗМЕРНЫЕ ПРИВЯЗКИ от стен здания до границ участка.
    // Север (от верхней стены здания до северной границы).
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: bldgX + bldgW + 6,
      y1: bldgY + bldgH,
      x2: bldgX + bldgW + 6,
      y2: plotY + plotH,
      label: setbackNorthM.toStringAsFixed(1).replaceAll('.', ',') + ' м',
      vertical: true,
      shortMarks: true,
    );
    // Юг.
    final southSetback = (bldgY - plotY) / scale;
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: bldgX - 6,
      y1: plotY,
      x2: bldgX - 6,
      y2: bldgY,
      label: southSetback.toStringAsFixed(1).replaceAll('.', ',') + ' м',
      vertical: true,
      shortMarks: true,
    );
    // Запад / восток.
    final westSetback = (bldgX - plotX) / scale;
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: plotX,
      y1: bldgY - 6,
      x2: bldgX,
      y2: bldgY - 6,
      label: westSetback.toStringAsFixed(1).replaceAll('.', ',') + ' м',
      shortMarks: true,
    );
    final eastSetback = (plotX + plotW - bldgX - bldgW) / scale;
    _drawDimChain(
      canvas: canvas,
      pdfFont: pdfFont,
      x1: bldgX + bldgW,
      y1: bldgY - 6,
      x2: plotX + plotW,
      y2: bldgY - 6,
      label: eastSetback.toStringAsFixed(1).replaceAll('.', ',') + ' м',
      shortMarks: true,
    );

    // 10) СИМВОЛ «СЕВЕР» — стрелка ↑ + N в правом верхнем углу.
    _drawNorthSymbol(
      canvas,
      pdfFont,
      cx: plotX + plotW + 18,
      cy: plotY + plotH - 18,
    );

    // 11) Подпись зданию «Жилой дом».
    canvas.setColor(PdfColors.black);
    const labelSize = 7.5;
    final label = 'Жилой дом';
    final labelW = pdfFont.stringMetrics(label).advanceWidth * labelSize;
    canvas.drawString(
      pdfFont,
      labelSize,
      label,
      bldgX + bldgW / 2 - labelW / 2,
      bldgY + bldgH / 2 - 4,
    );
  }

  // ─────────────────────── Низкоуровневые рисователи ────────────────────

  static void _dashDotLine(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2, {
    double dash = 7,
    double gap = 3,
    double dot = 1.4,
  }) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-3) return;
    final ux = dx / len;
    final uy = dy / len;
    var t = 0.0;
    while (t < len) {
      // Отрезок «штрих».
      final ds = math.min(dash, len - t);
      canvas.drawLine(
        x1 + ux * t,
        y1 + uy * t,
        x1 + ux * (t + ds),
        y1 + uy * (t + ds),
      );
      t += ds + gap;
      if (t >= len) break;
      // Отрезок «точка».
      final dt = math.min(dot, len - t);
      canvas.drawLine(
        x1 + ux * t,
        y1 + uy * t,
        x1 + ux * (t + dt),
        y1 + uy * (t + dt),
      );
      t += dt + gap;
    }
    canvas.strokePath();
  }

  static void _dashDotRect(
    PdfGraphics canvas,
    double x,
    double y,
    double w,
    double h,
  ) {
    _dashDotLine(canvas, x, y, x + w, y);
    _dashDotLine(canvas, x + w, y, x + w, y + h);
    _dashDotLine(canvas, x + w, y + h, x, y + h);
    _dashDotLine(canvas, x, y + h, x, y);
  }

  static void _hatchRect(
    PdfGraphics canvas,
    double x,
    double y,
    double w,
    double h, {
    double step = 5,
    PdfColor colour = PdfColors.grey500,
    double lineWidth = 0.3,
  }) {
    canvas.setStrokeColor(colour);
    canvas.setLineWidth(lineWidth);
    // Диагональные штрихи 45°.
    final last = w + h;
    for (var d = -h; d < last; d += step) {
      final x1 = (d).clamp(0.0, w);
      final y1 = (d - x1).clamp(0.0, h);
      final maxLen = math.min(w - x1, h - y1);
      final x2 = x1 + maxLen;
      final y2 = y1 + maxLen;
      canvas.drawLine(x + x1, y + y1, x + x2, y + y2);
    }
    canvas.strokePath();
  }

  static void _drawWalkway(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    double width,
  ) {
    // Простая «лента» прямоугольной формы из трёх сегментов:
    // gate → промежуточная точка по X = entranceX, Y = gateY → entranceY.
    final corner1X = x2;
    final corner1Y = y1;

    void seg(double sx, double sy, double ex, double ey) {
      final dx = ex - sx;
      final dy = ey - sy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-3) return;
      // Перпендикуляр.
      final ux = dx / len;
      final uy = dy / len;
      final px = -uy * width / 2;
      final py = ux * width / 2;
      canvas.setColor(const PdfColor.fromInt(0xFFEFE6D8));
      canvas.moveTo(sx + px, sy + py);
      canvas.lineTo(ex + px, ey + py);
      canvas.lineTo(ex - px, ey - py);
      canvas.lineTo(sx - px, sy - py);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.grey700);
      canvas.setLineWidth(0.4);
      canvas.drawLine(sx + px, sy + py, ex + px, ey + py);
      canvas.drawLine(sx - px, sy - py, ex - px, ey - py);
      canvas.strokePath();
    }

    seg(x1, y1, corner1X, corner1Y);
    seg(corner1X, corner1Y, x2, y2);
  }

  /// Размерная цепь СПДС: линия с засечками на концах + подпись по
  /// середине. Если `vertical=true` — линия идёт вертикально (засечки
  /// поворачиваются на 90°).
  static void _drawDimChain({
    required PdfGraphics canvas,
    required PdfFont pdfFont,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required String label,
    bool vertical = false,
    bool shortMarks = false,
  }) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawLine(x1, y1, x2, y2);
    // Засечки 2 × 2 мм под 45°.
    final markLen = shortMarks ? 3.0 : 4.0;
    final dx = vertical ? markLen : 0.0;
    canvas.drawLine(x1 - dx, y1 - markLen, x1 + dx, y1 + markLen);
    canvas.drawLine(x2 - dx, y2 - markLen, x2 + dx, y2 + markLen);
    if (vertical) {
      // Поворот на 90° для вертикальной подписи — упростим: подпись
      // ставим горизонтально слева от середины.
      canvas.setColor(PdfColors.black);
      final cx = (x1 + x2) / 2;
      final cy = (y1 + y2) / 2;
      const fontSize = 7.0;
      final tw = pdfFont.stringMetrics(label).advanceWidth * fontSize;
      canvas.drawString(pdfFont, fontSize, label, cx - tw - 4, cy - 3);
    } else {
      canvas.strokePath();
      canvas.setColor(PdfColors.black);
      final cx = (x1 + x2) / 2;
      final cy = (y1 + y2) / 2;
      const fontSize = 7.0;
      final tw = pdfFont.stringMetrics(label).advanceWidth * fontSize;
      canvas.drawString(pdfFont, fontSize, label, cx - tw / 2, cy + 3);
    }
    canvas.strokePath();
  }

  /// Условный знак «Север» — окружность ⌀26 pt со стрелкой ↑ и буквой N.
  static void _drawNorthSymbol(
    PdfGraphics canvas,
    PdfFont pdfFont, {
    required double cx,
    required double cy,
  }) {
    canvas.setColor(PdfColors.white);
    canvas.drawEllipse(cx, cy, 13, 13);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawEllipse(cx, cy, 13, 13);
    canvas.strokePath();
    // Стрелка ↑.
    canvas.setColor(PdfColors.black);
    canvas.moveTo(cx, cy + 9);
    canvas.lineTo(cx - 4, cy + 1);
    canvas.lineTo(cx + 4, cy + 1);
    canvas.fillPath();
    // Буква N.
    canvas.setColor(PdfColors.black);
    canvas.drawString(pdfFont, 8, 'N', cx - 2.5, cy - 6);
    // Подпись «Север» снизу.
    canvas.drawString(pdfFont, 7, 'Север', cx - 11, cy - 22);
  }
}
