import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/rooms_catalog.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'building3d_generator.dart';
import 'pdf_builder.dart';
import 'pdf_builder_materials.dart';
import 'pdf_title_block.dart';
import 'room_palette.dart';

/// Каталожная карточка проекта (Лист АР-0). Phase-3a-2 §17.1.1.
///
/// Одна страница A3-landscape, идёт сразу после титульного листа альбома.
/// Структура (сверху вниз):
///   1. Шапка ≈30 mm — крупное «ИНДИВИДУАЛЬНЫЙ ЖИЛОЙ ДОМ», название
///      проекта, артикул `Т-{площадь}`, бренд-плашка справа.
///   2. Основная сетка 3×2 (≈ 270 × 165 mm):
///      • верх-лево  — миниатюра аксонометрии (3D, та же камера, что в
///                     АР-N «Общий вид»);
///      • верх-центр — мини-план 1-го этажа (комнаты с заливкой палитры
///                     и крупными номерами; без осей и размерных цепей);
///      • верх-право — главный (южный) фасад: силуэт со скатами и
///                     заливкой материала стен;
///      • низ-лево (⅔ ширины) — таблица ТЭП (Технико-Экономические
///                              Показатели);
///      • низ-право (⅓ ширины) — легенда материалов (стены / кровля /
///                                фундамент).
///   3. Штамп ГОСТ Р 21.101-2020 в правом нижнем углу
///      (`sheetCode = 'АР-0'`, `name = 'Каталожная карточка'`).
///
/// АР-0 не входит в `sheets` (это «обложка», аналог титула — он не
/// получает сквозного номера). Поэтому в `pdf_builder.dart`
/// `totalSheets` остаётся прежним.
class PdfCatalogCard {
  PdfCatalogCard._();

  /// Phase-3b §17.2.1 next-slice: возвращает площадь застройки,
  /// которую карточка АР-0 запишет в ТЭП. Для прямоугольных проектов —
  /// `width × length`, для полигональных — площадь полигона
  /// `effectiveArchitectureFootprint`. Используется тестами для регрессии
  /// «площадь застройки L-формы = площадь полигона, не bbox».
  @visibleForTesting
  static double computeBuiltAreaM2(
    HouseProject project,
    List<FloorPlan> plans,
  ) =>
      _TepFigures.fromProject(project, plans).builtAreaM2;

  static pw.Page buildPage({
    required HouseProject project,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
    required List<FloorPlan> plans,
    required int versionNumber,
    OrganizationSettings? organization,
  }) {
    final tep = _TepFigures.fromProject(project, plans);
    final mainPlan = plans.isNotEmpty ? plans.first : null;

    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(
                      project: project,
                      font: font,
                      fontBold: fontBold,
                    ),
                    pw.SizedBox(height: 10),
                    pw.Expanded(
                      flex: 5,
                      child: _buildMiniaturesRow(
                        project: project,
                        plans: plans,
                        mainPlan: mainPlan,
                        pdfFont: pdfTtfRegular,
                        font: font,
                        fontBold: fontBold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: _buildTepTable(
                              tep: tep,
                              font: font,
                              fontBold: fontBold,
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Expanded(
                            flex: 1,
                            child: _buildLegend(
                              tep: tep,
                              font: font,
                              fontBold: fontBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.Positioned(
              right: 5 * PdfPageFormat.mm,
              bottom: 5 * PdfPageFormat.mm,
              child: PdfTitleBlock.build(
                font: font,
                fontBold: fontBold,
                projectName: project.name.isEmpty
                    ? 'Индивидуальный жилой дом'
                    : project.name,
                sectionTitle: 'Архитектурные решения',
                sheetTitle: 'Каталожная карточка',
                sheetCode: 'АР-0',
                sheetNumber: 0,
                totalSheets: 0,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────── Шапка ───────────────────────────────────

  static pw.Widget _buildHeader({
    required HouseProject project,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    final projectName =
        project.name.isEmpty ? 'Индивидуальный жилой дом' : project.name;
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ИНДИВИДУАЛЬНЫЙ ЖИЛОЙ ДОМ',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  projectName,
                  style: pw.TextStyle(font: font, fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'КОНСТРУКТОР СТРОЕНИЙ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 8,
                  letterSpacing: 0.6,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Ряд миниатюр ──────────────────────────────

  static pw.Widget _buildMiniaturesRow({
    required HouseProject project,
    required List<FloorPlan> plans,
    required FloorPlan? mainPlan,
    required PdfFont pdfFont,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: _miniBox(
            title: 'Аксонометрия',
            font: font,
            fontBold: fontBold,
            child: pw.LayoutBuilder(
              builder: (context, constraints) {
                final c = constraints!;
                return pw.SizedBox(
                  width: c.maxWidth,
                  height: c.maxHeight,
                  child: pw.CustomPaint(
                    size: PdfPoint(c.maxWidth, c.maxHeight),
                    painter: (canvas, size) => _paintMiniAxono(
                      canvas: canvas,
                      size: size,
                      project: project,
                      plans: plans,
                      pdfFont: pdfFont,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _miniBox(
            title: 'План 1-го этажа',
            font: font,
            fontBold: fontBold,
            child: pw.LayoutBuilder(
              builder: (context, constraints) {
                final c = constraints!;
                return pw.SizedBox(
                  width: c.maxWidth,
                  height: c.maxHeight,
                  child: pw.CustomPaint(
                    size: PdfPoint(c.maxWidth, c.maxHeight),
                    painter: (canvas, size) => _paintMiniPlan(
                      canvas: canvas,
                      size: size,
                      plan: mainPlan,
                      pdfFont: pdfFont,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _miniBox(
            title: 'Главный фасад',
            font: font,
            fontBold: fontBold,
            child: pw.LayoutBuilder(
              builder: (context, constraints) {
                final c = constraints!;
                return pw.SizedBox(
                  width: c.maxWidth,
                  height: c.maxHeight,
                  child: pw.CustomPaint(
                    size: PdfPoint(c.maxWidth, c.maxHeight),
                    painter: (canvas, size) => _paintMiniFacade(
                      canvas: canvas,
                      size: size,
                      project: project,
                      plan: mainPlan,
                      pdfFont: pdfFont,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _miniBox({
    required String title,
    required pw.Widget child,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      ),
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Expanded(child: child),
        ],
      ),
    );
  }

  // ───────────────── Публичные обёртки для переиспользования ─────────────
  //
  // Phase-3b §17.2.4 — лист «Планшет А1» собирает мини-виды поверх
  // существующих painters. Чтобы не дублировать код и не делать
  // приватные методы публичными «насовсем», экспонируем тонкие
  // обёртки. Сигнатуры идентичны приватным — подробности скрыты.
  static void paintMiniAxono({
    required PdfGraphics canvas,
    required PdfPoint size,
    required HouseProject project,
    required List<FloorPlan> plans,
    required PdfFont pdfFont,
  }) =>
      _paintMiniAxono(
        canvas: canvas,
        size: size,
        project: project,
        plans: plans,
        pdfFont: pdfFont,
      );

  static void paintMiniPlan({
    required PdfGraphics canvas,
    required PdfPoint size,
    required FloorPlan? plan,
    required PdfFont pdfFont,
  }) =>
      _paintMiniPlan(
        canvas: canvas,
        size: size,
        plan: plan,
        pdfFont: pdfFont,
      );

  static void paintMiniFacade({
    required PdfGraphics canvas,
    required PdfPoint size,
    required HouseProject project,
    required FloorPlan? plan,
    required PdfFont pdfFont,
  }) =>
      _paintMiniFacade(
        canvas: canvas,
        size: size,
        project: project,
        plan: plan,
        pdfFont: pdfFont,
      );

  // ───────────────── Painter: миниатюра аксонометрии ───────────────────

  static void _paintMiniAxono({
    required PdfGraphics canvas,
    required PdfPoint size,
    required HouseProject project,
    required List<FloorPlan> plans,
    required PdfFont pdfFont,
  }) {
    final building =
        Building3DGenerator.generate(project, floorPlans: plans);
    if (building == null) {
      _paintEmptyPlaceholder(canvas, size, pdfFont,
          'Нет данных для модели');
      return;
    }
    PdfBuilderMaterials.renderBuilding3DToPdf(
      canvas: canvas,
      size: size,
      building: building,
      font: pdfFont,
      caption: '',
    );
  }

  // ──────────────── Painter: мини-план 1-го этажа ──────────────────────

  static void _paintMiniPlan({
    required PdfGraphics canvas,
    required PdfPoint size,
    required FloorPlan? plan,
    required PdfFont pdfFont,
  }) {
    if (plan == null || plan.rooms.isEmpty) {
      _paintEmptyPlaceholder(canvas, size, pdfFont, 'Нет плана');
      return;
    }
    // Собираем bbox по комнатам и пристройкам, чтобы рисовать всё пятно.
    var minX = 0.0;
    var minY = 0.0;
    var maxX = plan.width;
    var maxY = plan.height;
    for (final a in plan.attachments) {
      if (a.x < minX) minX = a.x;
      if (a.y < minY) minY = a.y;
      if (a.x + a.width > maxX) maxX = a.x + a.width;
      if (a.y + a.height > maxY) maxY = a.y + a.height;
    }
    final bboxW = (maxX - minX).abs();
    final bboxH = (maxY - minY).abs();
    if (bboxW < 1e-3 || bboxH < 1e-3) {
      _paintEmptyPlaceholder(canvas, size, pdfFont, 'Нет плана');
      return;
    }
    const margin = 8.0;
    final scaleX = (size.x - margin * 2) / bboxW;
    final scaleY = (size.y - margin * 2) / bboxH;
    final scale = math.min(scaleX, scaleY);
    final drawW = bboxW * scale;
    final drawH = bboxH * scale;
    final offX = (size.x - drawW) / 2;
    final offY = (size.y - drawH) / 2;

    // Координата комнаты в метрах → в pt (Y инвертируется: на плане низ
    // сверху, в PDF — низ снизу).
    double mx(double xM) => offX + (xM - minX) * scale;
    double my(double yM) => offY + drawH - (yM - minY) * scale;

    // Пристройки — серым фоном за домом.
    canvas.setLineWidth(0.4);
    for (final a in plan.attachments) {
      final ax = mx(a.x);
      final ay = my(a.y + a.height);
      final aw = a.width * scale;
      final ah = a.height * scale;
      switch (a.kind) {
        case PlanAttachmentKind.garage:
          canvas.setColor(const PdfColor(0.93, 0.93, 0.93));
          break;
        case PlanAttachmentKind.terrace:
          canvas.setColor(const PdfColor(0.93, 0.96, 0.91));
          break;
        case PlanAttachmentKind.porch:
          canvas.setColor(const PdfColor(0.96, 0.94, 0.88));
          break;
      }
      canvas.drawRect(ax, ay, aw, ah);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.grey600);
      canvas.drawRect(ax, ay, aw, ah);
      canvas.strokePath();
    }

    // Контур пятна дома — толстая линия (внешние стены).
    // Phase-3b §17.2.1: для полигональных планов обводим по `outline`,
    // иначе — стандартный bbox.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    if (plan.hasPolygonalFootprint) {
      final fp = plan.effectiveFootprint;
      if (fp.outline.isNotEmpty) {
        final p0 = fp.outline.first;
        canvas.moveTo(mx(p0.x), my(p0.y));
        for (var i = 1; i < fp.outline.length; i++) {
          final pi = fp.outline[i];
          canvas.lineTo(mx(pi.x), my(pi.y));
        }
        canvas.closePath();
        canvas.strokePath();
      }
    } else {
      canvas.drawRect(
        mx(0),
        my(plan.height),
        plan.width * scale,
        plan.height * scale,
      );
      canvas.strokePath();
    }

    // Комнаты: заливка по палитре, тонкие границы, крупный номер.
    var idx = 0;
    canvas.setLineWidth(0.4);
    for (final r in plan.rooms) {
      idx++;
      final rx = mx(r.x);
      final ry = my(r.y + r.height);
      final rw = r.width * scale;
      final rh = r.height * scale;
      final fill = RoomPalette.fillFor(r);
      canvas.setColor(fill);
      canvas.drawRect(rx, ry, rw, rh);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.grey700);
      canvas.drawRect(rx, ry, rw, rh);
      canvas.strokePath();
      // Номер комнаты — кружок ø10 pt в центре.
      if (rw > 14 && rh > 14) {
        final cx = rx + rw / 2;
        final cy = ry + rh / 2;
        canvas.setColor(PdfColors.white);
        canvas.drawEllipse(cx, cy, 5.5, 5.5);
        canvas.fillPath();
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.5);
        canvas.drawEllipse(cx, cy, 5.5, 5.5);
        canvas.strokePath();
        canvas.setColor(PdfColors.black);
        final label = '$idx';
        final tw = pdfFont.stringMetrics(label).advanceWidth * 7.5;
        canvas.drawString(pdfFont, 7.5, label, cx - tw / 2, cy - 2.5);
      }
    }
  }

  // ──────────────── Painter: упрощённый главный фасад ──────────────────

  static void _paintMiniFacade({
    required PdfGraphics canvas,
    required PdfPoint size,
    required HouseProject project,
    required FloorPlan? plan,
    required PdfFont pdfFont,
  }) {
    final brief = project.brief;
    final widthM = brief.footprintWidth ?? plan?.width ?? 12;
    final floors = brief.floors ?? 1;
    final floorH =
        project.walls.height ?? project.staircase.floorHeight ?? 2.8;
    final hasMansard = brief.hasMansard == true;
    final hasBasement = brief.hasBasement == true;
    final hasRoof = project.roof.isFilled;
    final slopeDeg = (project.roof.slopeAngle ?? 30).clamp(5, 60).toDouble();
    final wallsHeightM = floorH * floors;
    // Высота конька от уровня земли — упрощённо.
    final ridgeRiseM = hasRoof
        ? widthM * 0.5 * math.tan(slopeDeg * math.pi / 180.0)
        : 0.0;
    final mansardExtraM = hasMansard ? floorH * 0.7 : 0.0;
    final totalHeightM = wallsHeightM + ridgeRiseM + mansardExtraM;
    final basementVisibleM = hasBasement ? 1.2 : 0.5; // цоколь над землёй
    final modelHeightM = totalHeightM + basementVisibleM;
    final modelWidthM = widthM;

    const margin = 10.0;
    final scaleX = (size.x - margin * 2) / modelWidthM;
    final scaleY = (size.y - margin * 2) / modelHeightM;
    final scale = math.min(scaleX, scaleY);
    final drawW = modelWidthM * scale;
    final drawH = modelHeightM * scale;
    final offX = (size.x - drawW) / 2;
    // Центрируем фасад по вертикали; уровень земли — внизу.
    final offY = (size.y - drawH) / 2;
    final groundY = offY + basementVisibleM * scale;

    // Цвет стены — по материалу.
    PdfColor wallColor;
    switch (brief.wallMaterial?.name) {
      case 'brick':
        wallColor = const PdfColor(0.83, 0.55, 0.42);
        break;
      case 'aerated':
        wallColor = const PdfColor(0.92, 0.92, 0.88);
        break;
      case 'expandedClay':
        wallColor = const PdfColor(0.78, 0.74, 0.66);
        break;
      case 'timber':
        wallColor = const PdfColor(0.78, 0.62, 0.42);
        break;
      case 'frame':
        wallColor = const PdfColor(0.94, 0.86, 0.66);
        break;
      default:
        wallColor = const PdfColor(0.88, 0.84, 0.74);
    }

    // ЗЕМЛЯ — линия и штриховка.
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.6);
    canvas.drawLine(margin, groundY, size.x - margin, groundY);
    canvas.strokePath();
    canvas.setLineWidth(0.4);
    for (var x = margin; x < size.x - margin; x += 8) {
      canvas.drawLine(x, groundY, x + 4, groundY - 4);
    }
    canvas.strokePath();

    // ЦОКОЛЬ — ниже уровня земли (видимая часть фундамента).
    canvas.setColor(const PdfColor(0.82, 0.80, 0.74));
    canvas.drawRect(offX, offY, drawW, basementVisibleM * scale);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(offX, offY, drawW, basementVisibleM * scale);
    canvas.strokePath();

    // СТЕНЫ — над уровнем земли.
    final wallsBottom = groundY;
    final wallsTop = wallsBottom + wallsHeightM * scale;
    canvas.setColor(wallColor);
    canvas.drawRect(offX, wallsBottom, drawW, wallsHeightM * scale);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawRect(offX, wallsBottom, drawW, wallsHeightM * scale);
    canvas.strokePath();

    // КРОВЛЯ — двускатная: треугольник от верхней грани стен.
    if (hasRoof && ridgeRiseM > 0.05) {
      final ridgeY = wallsTop + ridgeRiseM * scale;
      final cx = offX + drawW / 2;
      canvas.setColor(_roofColorFor(project.roof.roofingMaterial));
      canvas.moveTo(offX, wallsTop);
      canvas.lineTo(cx, ridgeY);
      canvas.lineTo(offX + drawW, wallsTop);
      canvas.lineTo(offX, wallsTop);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.7);
      canvas.moveTo(offX, wallsTop);
      canvas.lineTo(cx, ridgeY);
      canvas.lineTo(offX + drawW, wallsTop);
      canvas.strokePath();
    }

    // ОКНА — простая равномерная сетка по этажам.
    const winColor = PdfColor(0.62, 0.80, 0.92);
    final winsPerFloor = math.max(2, (widthM / 3).round());
    final winW = (drawW / (winsPerFloor + 1)) * 0.55;
    final winH = (floorH * 0.55) * scale;
    for (var f = 0; f < floors; f++) {
      final flBottom = wallsBottom + f * floorH * scale;
      final winY = flBottom + (floorH * scale - winH) / 2;
      for (var i = 1; i <= winsPerFloor; i++) {
        final cx = offX + drawW * i / (winsPerFloor + 1);
        if (f == 0 && (cx - (offX + drawW / 2)).abs() < winW) continue;
        canvas.setColor(winColor);
        canvas.drawRect(cx - winW / 2, winY, winW, winH);
        canvas.fillPath();
        canvas.setStrokeColor(PdfColors.grey800);
        canvas.setLineWidth(0.4);
        canvas.drawRect(cx - winW / 2, winY, winW, winH);
        canvas.strokePath();
      }
    }
    // Входная дверь — по центру первого этажа.
    final doorW = math.min(drawW * 0.08, 22.0);
    final doorH = math.min(floorH * 0.85 * scale, drawH * 0.45);
    final doorX = offX + drawW / 2 - doorW / 2;
    final doorY = wallsBottom;
    canvas.setColor(const PdfColor(0.45, 0.30, 0.20));
    canvas.drawRect(doorX, doorY, doorW, doorH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(doorX, doorY, doorW, doorH);
    canvas.strokePath();
  }

  static PdfColor _roofColorFor(String? id) {
    switch (id) {
      case 'metal':
      case 'metal_tile':
        return const PdfColor(0.40, 0.20, 0.18);
      case 'tile':
      case 'ceramic':
        return const PdfColor(0.62, 0.36, 0.26);
      case 'soft':
      case 'soft_tile':
        return const PdfColor(0.30, 0.30, 0.32);
      case 'profnastil':
        return const PdfColor(0.32, 0.42, 0.52);
      default:
        return const PdfColor(0.55, 0.32, 0.24);
    }
  }

  // ─────────────────────────── ТЭП-таблица ─────────────────────────────

  static pw.Widget _buildTepTable({
    required _TepFigures tep,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    pw.Widget headerCell(String text) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: PdfColors.grey200,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
    pw.Widget cell(String text, {bool bold = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              font: bold ? fontBold : font,
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [headerCell('Технико-экономические показатели'), headerCell('Значение')],
      ),
      pw.TableRow(children: [
        cell('Площадь застройки, м²'),
        cell(_fmt(tep.builtAreaM2), bold: true),
      ]),
      pw.TableRow(children: [
        cell('Общая площадь, м²'),
        cell(_fmt(tep.totalAreaM2), bold: true),
      ]),
      pw.TableRow(children: [
        cell('Жилая площадь, м²'),
        cell(_fmt(tep.livingAreaM2)),
      ]),
      pw.TableRow(children: [
        cell('Полезная площадь, м²'),
        cell(_fmt(tep.usableAreaM2)),
      ]),
      pw.TableRow(children: [
        cell('Этажность'),
        cell('${tep.floorsCount}'),
      ]),
      pw.TableRow(children: [
        cell('Высота от земли до конька, м'),
        cell(_fmt(tep.ridgeHeightM)),
      ]),
      pw.TableRow(children: [
        cell('Размеры в плане, м'),
        cell('${_fmt(tep.plotWidthM)} × ${_fmt(tep.plotDepthM)}'),
      ]),
      pw.TableRow(children: [
        cell('Площадь крыши, м²'),
        cell(_fmt(tep.roofAreaM2)),
      ]),
      pw.TableRow(children: [
        cell('Объём здания, м³'),
        cell(_fmt(tep.volumeM3)),
      ]),
      pw.TableRow(children: [
        cell('Материал стен'),
        cell(tep.wallMaterial),
      ]),
      pw.TableRow(children: [
        cell('Тип фундамента'),
        cell(tep.foundationLabel),
      ]),
      pw.TableRow(children: [
        cell('Тип кровли'),
        cell(tep.roofingLabel),
      ]),
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      child: pw.Table(
        border: pw.TableBorder.symmetric(
          inside: const pw.BorderSide(color: PdfColors.grey500, width: 0.4),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
        children: rows,
      ),
    );
  }

  // ───────────────────────────── Легенда ───────────────────────────────

  static pw.Widget _buildLegend({
    required _TepFigures tep,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    pw.Widget swatch(PdfColor c, String label) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 22,
                height: 14,
                decoration: pw.BoxDecoration(
                  color: c,
                  border: pw.Border.all(color: PdfColors.black, width: 0.5),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
              ),
            ],
          ),
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
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
          swatch(_legendWallColor(tep.wallMaterial),
              'Стены: ${tep.wallMaterial}'),
          swatch(_roofColorFor(tep.roofingMaterialId),
              'Кровля: ${tep.roofingLabel}'),
          swatch(const PdfColor(0.82, 0.80, 0.74),
              'Фундамент: ${tep.foundationLabel}'),
          pw.Spacer(),
          pw.Text(
            'Все размеры в метрах. Высоты — относительные, от уровня '
            'чистого пола первого этажа.',
            style: pw.TextStyle(
              font: font,
              fontSize: 7.5,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  static PdfColor _legendWallColor(String label) {
    switch (label) {
      case 'Кирпич':
        return const PdfColor(0.83, 0.55, 0.42);
      case 'Газобетон':
        return const PdfColor(0.92, 0.92, 0.88);
      case 'Керамзитоблок':
        return const PdfColor(0.78, 0.74, 0.66);
      case 'Брус':
        return const PdfColor(0.78, 0.62, 0.42);
      case 'Каркас':
        return const PdfColor(0.94, 0.86, 0.66);
      default:
        return const PdfColor(0.88, 0.84, 0.74);
    }
  }

  // ───────────────────────────── Утилиты ───────────────────────────────

  static String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return '—';
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  static void _paintEmptyPlaceholder(
    PdfGraphics canvas,
    PdfPoint size,
    PdfFont font,
    String text,
  ) {
    canvas.setColor(PdfColors.grey200);
    canvas.drawRect(0, 0, size.x, size.y);
    canvas.fillPath();
    canvas.setColor(PdfColors.grey700);
    final tw = font.stringMetrics(text).advanceWidth * 9;
    canvas.drawString(font, 9, text, (size.x - tw) / 2, size.y / 2 - 4);
  }
}

// ────────────────── Расчёт ТЭП по данным проекта ────────────────────────

class _TepFigures {
  final double builtAreaM2;
  final double totalAreaM2;
  final double livingAreaM2;
  final double usableAreaM2;
  final int floorsCount;
  final double ridgeHeightM;
  final double plotWidthM;
  final double plotDepthM;
  final double roofAreaM2;
  final double volumeM3;
  final String wallMaterial;
  final String foundationLabel;
  final String roofingLabel;
  final String? roofingMaterialId;

  const _TepFigures({
    required this.builtAreaM2,
    required this.totalAreaM2,
    required this.livingAreaM2,
    required this.usableAreaM2,
    required this.floorsCount,
    required this.ridgeHeightM,
    required this.plotWidthM,
    required this.plotDepthM,
    required this.roofAreaM2,
    required this.volumeM3,
    required this.wallMaterial,
    required this.foundationLabel,
    required this.roofingLabel,
    required this.roofingMaterialId,
  });

  static _TepFigures fromProject(
    HouseProject project,
    List<FloorPlan> plans,
  ) {
    final brief = project.brief;
    final w = brief.footprintWidth ?? (plans.isNotEmpty ? plans.first.width : 0);
    final l =
        brief.footprintLength ?? (plans.isNotEmpty ? plans.first.height : 0);
    // Phase-3b §17.2.1 next-slice: для полигональных проектов (L/T/U/Г-форма)
    // площадь застройки в ТЭП — это площадь полигона `effectiveFootprint`,
    // а не bbox `width × length`. Для прямоугольных проектов остаётся w*l.
    final effectiveFp = project.effectiveArchitectureFootprint;
    double polygonArea = 0;
    try {
      polygonArea = effectiveFp.area;
    } catch (_) {
      polygonArea = 0;
    }
    final bboxArea = w * l;
    final builtArea = polygonArea > 0 ? polygonArea : bboxArea;
    final floors = math.max(brief.floors ?? 1, 1);
    final floorH =
        project.walls.height ?? project.staircase.floorHeight ?? 2.8;

    var total = 0.0;
    var living = 0.0;
    var usable = 0.0;
    const livingKinds = <RoomKind>{
      RoomKind.bedroom,
      RoomKind.livingRoom,
      RoomKind.kidsRoom,
      RoomKind.dining,
      RoomKind.kitchenDining,
      RoomKind.study,
    };
    const technicalKinds = <RoomKind>{
      RoomKind.boilerRoom,
      RoomKind.pantry,
      RoomKind.hallway,
      RoomKind.storage,
      RoomKind.technical,
    };
    for (final plan in plans) {
      for (final r in plan.rooms) {
        if (r.kind == PlanRoomKind.staircase) continue;
        total += r.area;
        final kindName = r.roomKindName;
        final kind = kindName == null
            ? null
            : RoomKind.values
                .where((k) => k.name == kindName)
                .cast<RoomKind?>()
                .firstWhere((_) => true, orElse: () => null);
        if (kind != null && livingKinds.contains(kind)) living += r.area;
        if (kind == null || !technicalKinds.contains(kind)) {
          usable += r.area;
        }
      }
    }
    if (total <= 0) {
      total = builtArea * floors;
    }

    final slope = (project.roof.slopeAngle ?? 30).toDouble();
    final ridgeRise = project.roof.isFilled
        ? w * 0.5 * math.tan(slope * math.pi / 180.0)
        : 0.0;
    final ridge = floorH * floors + ridgeRise;
    // Площадь крыши — приближённо (двускатная).
    final slopeRad = slope * math.pi / 180.0;
    final roofArea = project.roof.isFilled
        ? builtArea / math.max(math.cos(slopeRad), 0.3)
        : builtArea;
    final volume = builtArea * floorH * floors;

    return _TepFigures(
      builtAreaM2: builtArea,
      totalAreaM2: total,
      livingAreaM2: living,
      usableAreaM2: usable > 0 ? usable : total * 0.85,
      floorsCount: floors,
      ridgeHeightM: ridge,
      plotWidthM: w,
      plotDepthM: l,
      roofAreaM2: roofArea,
      volumeM3: volume,
      wallMaterial: brief.wallMaterial?.title ?? '—',
      foundationLabel: project.foundation.type?.title ?? '—',
      roofingLabel: _roofingLabel(project.roof.roofingMaterial),
      roofingMaterialId: project.roof.roofingMaterial,
    );
  }

  static String _roofingLabel(String? id) {
    switch (id) {
      case 'metal':
        return 'Металл';
      case 'metal_tile':
        return 'Металлочерепица';
      case 'tile':
      case 'ceramic':
        return 'Керамическая черепица';
      case 'soft':
      case 'soft_tile':
        return 'Мягкая кровля';
      case 'profnastil':
        return 'Профнастил';
      case null:
        return '—';
      default:
        return id;
    }
  }
}
