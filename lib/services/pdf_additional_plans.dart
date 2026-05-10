import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/building_footprint.dart';
import '../models/floor_plan.dart';
import '../models/foundation.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'pdf_builder.dart';
import 'pdf_title_block.dart';
import 'rafter_section_picker.dart';

/// Доп. листы итерации 2: план перегородок, план полов, план подвала,
/// план технического подполья, план чердака, схемы балок перекрытия (КД-1)
/// и стропил (КД-2). Все листы рисуются на канве A3-landscape с тем же
/// штампом по ГОСТ Р 21.101-2020 ф.3, что и остальной комплект.
class PdfAdditionalPlans {
  PdfAdditionalPlans._();

  // ───────────────────────────── ПЛАН ПЕРЕГОРОДОК (АР) ──────────────────
  static pw.Page partitionsPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'План расположения перегородок · 1 этаж',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintPartitions(canvas, size, plan, pdfFont),
                            ),
                          );
                        },
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
                sheetTitle: 'План расположения перегородок',
                sheetCode: 'АР-$sheetNumber',
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────── ПЛАН ПОЛОВ (АР) ────────────────────────
  static pw.Page floorTypesPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'План полов · 1 этаж (типы П1…П3 + типовой пирог)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintFloorTypes(canvas, size, plan, pdfFont),
                            ),
                          );
                        },
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
                sheetTitle: 'План полов',
                sheetCode: 'АР-$sheetNumber',
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────── ПЛАН ПОДВАЛА (КР) ──────────────────────
  static pw.Page basementPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КР-2',
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'План подвала на отметке −2.700 (СП 54.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintBasement(canvas, size, plan, pdfFont,
                                      project),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструктивные решения',
                sheetTitle: 'План подвала',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────── ПЛАН ТЕХНИЧЕСКОГО ПОДПОЛЬЯ (КР) ────────────────
  static pw.Page subfloorPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КР-2',
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'План технического подполья (СП 24.13330, СП 50.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintSubfloor(canvas, size, plan, pdfFont,
                                      project),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструктивные решения',
                sheetTitle: 'План технического подполья',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────── ПЛАН ЧЕРДАКА (АР) ──────────────────────
  static pw.Page atticPage({
    required HouseProject project,
    required FloorPlan topPlan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'План холодного чердака (СП 17.13330, СП 50.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintAttic(canvas, size, topPlan, pdfFont,
                                      project),
                            ),
                          );
                        },
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
                sheetTitle: 'План холодного чердака',
                sheetCode: 'АР-$sheetNumber',
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────── СХЕМА БАЛОК ПЕРЕКРЫТИЯ (КД-1) ────────────────────
  static pw.Page beamsPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КД-1',
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'Схема расположения балок перекрытия (СП 64.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintBeams(canvas, size, plan, pdfFont,
                                      project),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструкции деревянные',
                sheetTitle: 'Схема расположения балок перекрытия',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────── ОБЪЕДИНЁННЫЙ ЛИСТ КД-2 (схема + разрез + узлы) ───────────
  /// Один лист КД-2 «Стропильная система: разрез и схема расположения».
  ///
  /// Объединяет три ранее раздельных вида (Разрез 1-1 / Разрез 2-2 со
  /// схемой плана + отдельный «детальный» разрез по стропильной системе
  /// + детальные узлы в отдельных У-N) в один цельный лист по образцу
  /// типовых учебных схем стропил (см. альбом «Стропильные системы
  /// малопролётных деревянных зданий», эл. 1…11).
  ///
  /// Состав листа:
  ///   • Главный поперечный разрез (≈ 60 % площади листа) — каждый
  ///     элемент стропильной фермы пронумерован выноской 1…11; авто-
  ///     подбор конфигурации по фактическому пролёту:
  ///        L ≤ 6 м   — простая ферма (стропила 3, мауэрлат, кровля 8);
  ///        6 < L ≤ 10 — + затяжка 1, бабка 2, перекрытие 4;
  ///        L > 10 м  — + подкосы 5, накладки 9, болты 10, нагели 11.
  ///   • Деталь «А» — опирание стропилы на мауэрлат (масштаб 1:5).
  ///   • Деталь «Б» — коньковый узел (масштаб 1:5).
  ///   • План стропил — упрощённый вид сверху (правое нижнее поле).
  ///   • Спецификация и расчёт стропил — полная таблица из
  ///     RafterSectionPicker (СП 20.13330 + СП 64.13330).
  ///   • Условные обозначения 1…11 — по эталонному альбому.
  ///
  /// Все размеры берутся из расчётов (RafterSectionPicker, brief,
  /// roof.slopeAngle, walls.height/.thickness). Никаких хардкод-значений.
  static pw.Page raftersCombinedPage({
    required HouseProject project,
    required FloorPlan topPlan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КД-2',
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'Стропильная система — разрез и схема расположения '
                          '(СП 64.13330, СП 17.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintRaftersCombined(
                                canvas,
                                size,
                                topPlan,
                                pdfFont,
                                project,
                              ),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструкции деревянные',
                sheetTitle: 'Стропильная система: разрез и схема',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Внутренняя отрисовка объединённого листа КД-2.
  ///
  /// Раскладка (A3 landscape, рабочее поле ~1107×692 pt после padding):
  ///   • Левая колонка ~70 % ширины:
  ///       – Верх (≈ 60 % высоты) — главный разрез фермы со всеми
  ///         элементами 1…11 и размерными цепями;
  ///       – Низ-лево (≈ 40 %, половина левой колонки) — план стропил;
  ///       – Низ-право (≈ 40 %, вторая половина левой колонки) — узлы
  ///         «А» (опирание стропилы) и «Б» (коньковый узел) в стопке.
  ///   • Правая колонка ~30 % ширины:
  ///       – Верх — спецификация и расчёт стропил (как было в КД-2.1);
  ///       – Низ — Условные обозначения 1…11 (на основе образца).
  static void _paintRaftersCombined(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan topPlan,
    PdfFont font,
    HouseProject project,
  ) {
    final w = size.x;
    final h = size.y;
    final roofType = (project.roof.type ?? 'gable').toLowerCase();
    final isFlat = roofType.contains('flat') || roofType.contains('плос');
    if (isFlat) {
      // Плоская кровля: стропильная ферма не нужна, выводим короткую
      // справку и план балок.
      _drawText(canvas, font, 11,
          'Кровля — плоская. Стропильная ферма не требуется. '
          'См. КД-1 «Схема расположения балок».',
          24, h - 24);
      return;
    }

    final isHip = roofType.contains('hip') || roofType.contains('вальм');
    final pick = RafterSectionPicker.pickFor(project);
    final slopeDeg = project.roof.slopeAngle ?? 30.0;
    final slopeRad = slopeDeg * math.pi / 180.0;
    final ridgeAlongX = topPlan.width >= topPlan.height;
    final spanM = ridgeAlongX ? topPlan.height : topPlan.width;
    final ridgeLengthM = ridgeAlongX ? topPlan.width : topPlan.height;
    final raftersStep =
        RafterSectionPicker.rafterStep(project.roof.roofingMaterial);

    // ── РАЗМЕТКА ЛИСТА ─────────────────────────────────────────────
    const gap = 10.0;
    final rightW = 270.0; // правая колонка: спецификация + легенда
    final leftW = w - rightW - gap;
    final mainH = (h - gap) * 0.62; // главный разрез — 62 % высоты
    final bottomH = (h - gap) - mainH;
    final planW = leftW * 0.55; // план занимает 55 % низа
    final detailsW = leftW - planW - gap;

    final mainRect = _Rect(0, h - mainH, leftW, mainH);
    final planRect = _Rect(0, 0, planW, bottomH);
    final detailsRect = _Rect(planW + gap, 0, detailsW, bottomH);
    final rightRect = _Rect(w - rightW, 0, rightW, h);

    // Тонкие рамки секций.
    _drawPanelFrame(canvas, mainRect, hairline: true);
    _drawPanelFrame(canvas, planRect, hairline: true);
    _drawPanelFrame(canvas, rightRect, hairline: true);

    // ── ГЛАВНЫЙ РАЗРЕЗ ФЕРМЫ ───────────────────────────────────────
    _drawCenteredText(canvas, font, 10,
        'Разрез 1-1 — стропильная ферма (пролёт ${(spanM * 1000).round()} мм)',
        mainRect.cx, mainRect.top - 14);
    final detailAnchors = _drawTrussSection(
      canvas,
      font,
      mainRect.shrink(top: 22, bottom: 8, left: 18, right: 18),
      spanM: spanM,
      slopeRad: slopeRad,
      slopeDeg: slopeDeg,
      pick: pick,
      project: project,
    );

    // ── ПЛАН СТРОПИЛ ───────────────────────────────────────────────
    _drawCenteredText(canvas, font, 9.5, 'План стропил',
        planRect.cx, planRect.top - 12);
    _drawRaftersPlanView(
      canvas,
      font,
      planRect.shrink(top: 18, bottom: 8, left: 12, right: 12),
      topPlan: topPlan,
      isHip: isHip,
      ridgeAlongX: ridgeAlongX,
      raftersStep: raftersStep,
      pick: pick,
      spanM: spanM,
      ridgeLengthM: ridgeLengthM,
    );

    // ── УЗЛЫ «А» И «Б» ─────────────────────────────────────────────
    final detailAH = (detailsRect.h - gap) * 0.5;
    final detailBH = (detailsRect.h - gap) - detailAH;
    final detailA = _Rect(detailsRect.left,
        detailsRect.bottom + detailBH + gap, detailsRect.w, detailAH);
    final detailB = _Rect(detailsRect.left, detailsRect.bottom,
        detailsRect.w, detailBH);
    _drawPanelFrame(canvas, detailA, hairline: true);
    _drawPanelFrame(canvas, detailB, hairline: true);
    _drawCenteredText(canvas, font, 8.5,
        'Узел «А». Опирание на мауэрлат',
        detailA.cx, detailA.top - 12);
    _drawCenteredText(canvas, font, 8.5,
        'Узел «Б». Конёк',
        detailB.cx, detailB.top - 12);
    _drawDetailA(
      canvas,
      font,
      detailA.shrink(top: 18, bottom: 8, left: 10, right: 10),
      project: project,
      pick: pick,
      slopeDeg: slopeDeg,
      slopeRad: slopeRad,
    );
    _drawDetailB(
      canvas,
      font,
      detailB.shrink(top: 18, bottom: 8, left: 10, right: 10),
      project: project,
      pick: pick,
      slopeDeg: slopeDeg,
      slopeRad: slopeRad,
    );

    // Маркеры «А» и «Б» на главном разрезе — у анкеров узлов.
    if (detailAnchors.eaveAnchor != null) {
      _drawDetailMarker(canvas, font, detailAnchors.eaveAnchor!.x,
          detailAnchors.eaveAnchor!.y, 'А');
    }
    if (detailAnchors.ridgeAnchor != null) {
      _drawDetailMarker(canvas, font, detailAnchors.ridgeAnchor!.x,
          detailAnchors.ridgeAnchor!.y, 'Б');
    }

    // ── ПРАВАЯ КОЛОНКА: СПЕЦИФИКАЦИЯ + ЛЕГЕНДА ─────────────────────
    final rightContent = rightRect.shrink(top: 8, bottom: 8, left: 10,
        right: 10);
    final specBottomY = _drawRaftersSpecTable(
      canvas,
      font,
      rightContent,
      project: project,
      pick: pick,
      spanM: spanM,
      slopeDeg: slopeDeg,
    );
    // Легенда — ниже таблицы спецификации.
    _drawTrussLegend(
      canvas,
      font,
      _Rect(rightContent.left, rightContent.bottom,
          rightContent.w, specBottomY - rightContent.bottom - 8),
    );
  }

  /// Главный поперечный разрез фермы со всеми элементами 1…11.
  ///
  /// Конфигурация выбирается по фактическому пролёту (см. таблицу в
  /// шапке raftersCombinedPage). Каждое из изображённых элементов
  /// (затяжка, бабка, стропила, перекрытие, подкосы, кровля, накладки,
  /// болты, нагели) получает выноску с цифрой по эталонному альбому.
  ///
  /// Возвращает якорные точки для маркеров «А» (опирание) и «Б» (конёк),
  /// чтобы вызывающий код мог проставить указатели на детали.
  static _DetailAnchors _drawTrussSection(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required double spanM,
    required double slopeRad,
    required double slopeDeg,
    required RafterPickResult pick,
    required HouseProject project,
  }) {
    // Ферма по пролёту: бабка/подкосы/нагели появляются ступенчато.
    final hasTie = spanM > 6.0; // затяжка нужна, как только бабка появилась
    final hasKingPost = spanM > 6.0; // подвеска / бабка
    final hasStruts = spanM > 10.0; // подкосы под бабку
    final hasDowels = spanM > 12.0; // болтовые нагели у узлов

    // Высота конька (от мауэрлата) = (полупролёт) · tan α.
    final apexHm = (spanM / 2) * math.tan(slopeRad);
    // Высота стены — из проекта (если задана).
    final wallHeightM = project.walls.height ??
        project.staircase.floorHeight ??
        2.7;
    const eaveOverhangM = 0.5; // СП 17 п. 6.1.4
    const mauerlatHM = 0.15; // 100×150 мм по сечению М-1
    // Полная высота сцены: чердачное перекрытие (≈ 0.20 м) + стена +
    // мауэрлат + конёк + поле под подписи кровли (≈ 0.30 м).
    final totalHm = 0.20 + wallHeightM + mauerlatHM + apexHm + 0.30;
    final totalWm = spanM + 2 * eaveOverhangM;
    // Масштаб: вписываем в (r.w-90)×(r.h-110) — оставляем поля для
    // вертикальной размерной цепи справа и горизонтальной снизу.
    final sx = (r.w - 110) / totalWm;
    final sy = (r.h - 100) / totalHm;
    final s = math.min(sx, sy);

    // Координаты в PDF (Y растёт вверх).
    final cx = r.cx;
    // Низ чердачного перекрытия — горизонтальная база.
    final attBaseY = r.bottom + 32; // запас под нижнюю размерную цепь
    final wallBottomY = attBaseY + 0.20 * s;
    final wallTopY = wallBottomY + wallHeightM * s;
    final mauerlatTopY = wallTopY + mauerlatHM * s;
    final apexY = mauerlatTopY + apexHm * s;
    final leftWallX = cx - (spanM / 2) * s;
    final rightWallX = cx + (spanM / 2) * s;
    final apexX = cx;
    final eaveLeftX = leftWallX - eaveOverhangM * s;
    final eaveRightX = rightWallX + eaveOverhangM * s;

    // ── Чердачное перекрытие (поз. 4) ──────────────────────────────
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.55);
    canvas.drawLine(eaveLeftX - 8, attBaseY, eaveRightX + 8, attBaseY);
    canvas.drawLine(eaveLeftX - 8, wallBottomY, eaveRightX + 8, wallBottomY);
    canvas.strokePath();
    // Штриховка перекрытия — ГОСТ 2.306-68 (наклонные линии).
    canvas.setLineWidth(0.3);
    for (double xx = eaveLeftX - 6; xx < eaveRightX + 8; xx += 6) {
      canvas.drawLine(xx, attBaseY, xx + 4, wallBottomY);
    }
    canvas.strokePath();

    // ── Наружные стены (поз. 15 в учебнике, оставляем без выноски) ──
    final wallThickPx = ((project.walls.thickness ?? 350) / 1000.0) * s;
    final wallW = math.max(14.0, math.min(28.0, wallThickPx));
    canvas.setFillColor(const PdfColor(0.93, 0.93, 0.93));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawRect(leftWallX - wallW / 2, wallBottomY,
        wallW, wallTopY - wallBottomY);
    canvas.fillAndStrokePath();
    canvas.drawRect(rightWallX - wallW / 2, wallBottomY,
        wallW, wallTopY - wallBottomY);
    canvas.fillAndStrokePath();

    // ── Мауэрлат — оранжевый прямоугольник 150×100 поверх стен ──────
    canvas.setFillColor(const PdfColor(0.85, 0.55, 0.20));
    final mW = math.max(wallW + 4, 0.15 * s);
    final mH = mauerlatHM * s;
    canvas.drawRect(leftWallX - mW / 2, wallTopY, mW, mH);
    canvas.fillAndStrokePath();
    canvas.drawRect(rightWallX - mW / 2, wallTopY, mW, mH);
    canvas.fillAndStrokePath();

    // ── Стропильные ноги (поз. 3) ──────────────────────────────────
    final rafterDpx = math.max(6.0, 0.20 * s); // высота сечения 200 мм
    canvas.setFillColor(const PdfColor(0.80, 0.62, 0.42));
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(0.55);
    // Левая стропилина: от свеса до конька.
    final lx0 = eaveLeftX;
    final ly0 = mauerlatTopY;
    final lx1 = apexX;
    final ly1 = apexY;
    final dxL = lx1 - lx0;
    final dyL = ly1 - ly0;
    final lenL = math.sqrt(dxL * dxL + dyL * dyL);
    // Нормаль к скату направлена «вверх» (в небо).
    final nxL = -dyL / lenL;
    final nyL = dxL / lenL;
    canvas.moveTo(lx0, ly0);
    canvas.lineTo(lx1, ly1);
    canvas.lineTo(lx1 + nxL * rafterDpx, ly1 + nyL * rafterDpx);
    canvas.lineTo(lx0 + nxL * rafterDpx, ly0 + nyL * rafterDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();
    // Правая стропилина (зеркально).
    final rx0 = eaveRightX;
    final ry0 = mauerlatTopY;
    final rx1 = apexX;
    final ry1 = apexY;
    final dxR = rx1 - rx0;
    final dyR = ry1 - ry0;
    final lenR = math.sqrt(dxR * dxR + dyR * dyR);
    final nxR = dyR / lenR;
    final nyR = -dxR / lenR;
    canvas.moveTo(rx0, ry0);
    canvas.lineTo(rx1, ry1);
    canvas.lineTo(rx1 + nxR * rafterDpx, ry1 + nyR * rafterDpx);
    canvas.lineTo(rx0 + nxR * rafterDpx, ry0 + nyR * rafterDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();

    // ── Покрытие кровли (поз. 8) — линия выше стропил на 50–60 мм ───
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(1.2);
    final coverOff = rafterDpx + math.max(4.0, 0.06 * s);
    canvas.drawLine(lx0 + nxL * coverOff, ly0 + nyL * coverOff,
        lx1 + nxL * coverOff, ly1 + nyL * coverOff);
    canvas.drawLine(rx0 + nxR * coverOff, ry0 + nyR * coverOff,
        rx1 + nxR * coverOff, ry1 + nyR * coverOff);
    canvas.strokePath();

    // ── Затяжка (поз. 1) и подвесное чердачное перекрытие (поз. 4) ──
    final tieY = mauerlatTopY + mH * 0.05;
    if (hasTie) {
      // Затяжка — горизонтальный брус 50×200 на высоте мауэрлата.
      canvas.setFillColor(const PdfColor(0.80, 0.62, 0.42));
      canvas.setStrokeColor(PdfColors.brown800);
      canvas.setLineWidth(0.45);
      final tieH = math.max(4.0, 0.05 * s);
      canvas.drawRect(leftWallX - mW / 2 + 2, tieY,
          (rightWallX + mW / 2 - 2) - (leftWallX - mW / 2 + 2), tieH);
      canvas.fillAndStrokePath();
    }

    // ── Бабка / подвеска (поз. 2) ──────────────────────────────────
    final kingX = apexX;
    if (hasKingPost) {
      canvas.setFillColor(const PdfColor(0.85, 0.65, 0.45));
      canvas.setStrokeColor(PdfColors.brown800);
      canvas.setLineWidth(0.5);
      final postW = math.max(5.0, 0.08 * s);
      // Верх бабки — точно под подвесом конька (на 8 pt ниже apex,
      // чтобы влезала накладка).
      final postTopY = apexY - rafterDpx * 0.7;
      canvas.drawRect(kingX - postW / 2,
          tieY + math.max(4.0, 0.05 * s),
          postW, postTopY - tieY - math.max(4.0, 0.05 * s));
      canvas.fillAndStrokePath();
    }

    // ── Подкосы (поз. 5) — две диагонали от низа бабки к стропилам ──
    if (hasStruts) {
      canvas.setStrokeColor(const PdfColor(0.55, 0.40, 0.25));
      canvas.setLineWidth(2.5);
      // Точки прихода подкосов на стропила — ≈ 1/3 длины от мауэрлата.
      final tL = 0.40;
      final tR = 0.40;
      final spxL = lx0 + dxL * tL;
      final spyL = ly0 + dyL * tL;
      final spxR = rx0 + dxR * tR;
      final spyR = ry0 + dyR * tR;
      // Низ бабки — точка на затяжке.
      final postBaseX = kingX;
      final postBaseY = tieY + math.max(4.0, 0.05 * s) + 4;
      canvas.drawLine(postBaseX, postBaseY, spxL, spyL);
      canvas.drawLine(postBaseX, postBaseY, spxR, spyR);
      canvas.strokePath();

      // Накладки (поз. 9) у узлов схождения подкосов со стропилами.
      canvas.setFillColor(const PdfColor(0.95, 0.85, 0.65));
      canvas.setStrokeColor(PdfColors.brown600);
      canvas.setLineWidth(0.4);
      final plW = 14.0;
      final plH = 6.0;
      canvas.drawRect(spxL - plW / 2, spyL - plH / 2, plW, plH);
      canvas.fillAndStrokePath();
      canvas.drawRect(spxR - plW / 2, spyR - plH / 2, plW, plH);
      canvas.fillAndStrokePath();

      // Болты (поз. 10) — две точки в каждой накладке.
      canvas.setFillColor(PdfColors.black);
      _drawCircle(canvas, spxL - 3, spyL, 0.9);
      _drawCircle(canvas, spxL + 3, spyL, 0.9);
      _drawCircle(canvas, spxR - 3, spyR, 0.9);
      _drawCircle(canvas, spxR + 3, spyR, 0.9);

      // Болтовые нагели (поз. 11) — короткие штрихи в накладках.
      if (hasDowels) {
        canvas.setStrokeColor(PdfColors.grey800);
        canvas.setLineWidth(0.45);
        canvas.drawLine(spxL - 5, spyL - 1.5, spxL + 5, spyL - 1.5);
        canvas.drawLine(spxR - 5, spyR - 1.5, spxR + 5, spyR - 1.5);
        canvas.strokePath();
      }

      // Выноска позиций для подкоса (5), накладок (9), болтов (10),
      // нагелей (11) — выходит за поле фермы, чтобы не накладываться.
      _drawPosCallout(canvas, font, (kingX + spxL) / 2,
          (tieY + spyL) / 2,
          5, leftWallX + (kingX - leftWallX) * 0.5, tieY - 18);
      _drawPosCallout(canvas, font, spxL, spyL,
          9, lx0 + dxL * 0.18, ly0 + dyL * 0.18 + nyL * 30,
          radius: 6.0);
      _drawPosCallout(canvas, font, spxR + 3, spyR,
          10, rx0 + dxR * 0.18, ry0 + dyR * 0.18 + nyR * 30,
          radius: 6.0);
      if (hasDowels) {
        _drawPosCallout(canvas, font, spxR, spyR + 2,
            11, rx0 + dxR * 0.18, ry0 + dyR * 0.18 + nyR * 50,
            radius: 6.0);
      }
    }

    // ── Аварийный болт (поз. 6) — у конька, под стропилами ─────────
    canvas.setFillColor(PdfColors.black);
    final boltX = apexX;
    final boltY = apexY - rafterDpx * 0.7;
    _drawCircle(canvas, boltX, boltY, 1.2);
    // Гайка (горизонтальная полочка).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawLine(boltX - 4, boltY - 0.5, boltX + 4, boltY - 0.5);
    canvas.strokePath();

    // ── Гвозди (поз. 7) — точки на узлах (свес + конёк) ────────────
    canvas.setFillColor(PdfColors.grey700);
    _drawCircle(canvas, lx0 + nxL * (rafterDpx * 0.5),
        ly0 + nyL * (rafterDpx * 0.5), 0.7);
    _drawCircle(canvas, rx0 + nxR * (rafterDpx * 0.5),
        ry0 + nyR * (rafterDpx * 0.5), 0.7);
    _drawCircle(canvas, apexX - 5, apexY - 4, 0.7);
    _drawCircle(canvas, apexX + 5, apexY - 4, 0.7);

    // ── Размерные цепи ─────────────────────────────────────────────
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Низ — пролёт.
    final dimY = wallBottomY - 14;
    canvas.drawLine(eaveLeftX, dimY, eaveRightX, dimY);
    canvas.drawLine(leftWallX, dimY, leftWallX, wallBottomY - 4);
    canvas.drawLine(rightWallX, dimY, rightWallX, wallBottomY - 4);
    canvas.drawLine(eaveLeftX, dimY - 3, eaveLeftX, dimY + 3);
    canvas.drawLine(eaveRightX, dimY - 3, eaveRightX, dimY + 3);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7.5,
        '${(spanM * 1000).round()}',
        (leftWallX + rightWallX) / 2, dimY - 9);
    _drawCenteredText(canvas, font, 7,
        '${(eaveOverhangM * 1000).round()}',
        (eaveLeftX + leftWallX) / 2, dimY - 9);
    _drawCenteredText(canvas, font, 7,
        '${(eaveOverhangM * 1000).round()}',
        (rightWallX + eaveRightX) / 2, dimY - 9);

    // Цепь высот справа: стена → мауэрлат → конёк.
    final rightDimX = eaveRightX + 28;
    canvas.drawLine(rightDimX, wallBottomY, rightDimX, apexY);
    canvas.drawLine(rightDimX - 3, wallBottomY, rightDimX + 3, wallBottomY);
    canvas.drawLine(rightDimX - 3, wallTopY, rightDimX + 3, wallTopY);
    canvas.drawLine(rightDimX - 3, apexY, rightDimX + 3, apexY);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${(wallHeightM * 1000).round()}',
        rightDimX + 4, (wallBottomY + wallTopY) / 2 - 3);
    _drawText(canvas, font, 7,
        '${((apexHm + mauerlatHM) * 1000).round()}',
        rightDimX + 4, (wallTopY + apexY) / 2 - 3);

    // Угол ската — слева у конька.
    _drawText(canvas, font, 9,
        '∠ ${slopeDeg.toStringAsFixed(0)}°',
        apexX - 70, apexY - 18, bold: true);

    // ── Цифровые выноски 1…8 ───────────────────────────────────────
    if (hasTie) {
      _drawPosCallout(canvas, font,
          leftWallX + (rightWallX - leftWallX) * 0.18, tieY + 2,
          1, leftWallX - 16, tieY - 10);
    }
    if (hasKingPost) {
      _drawPosCallout(canvas, font, kingX + 2, (tieY + apexY) / 2,
          2, apexX + 26, (tieY + apexY) / 2 - 4);
    }
    // 3 — стропильная нога.
    _drawPosCallout(canvas, font,
        lx0 + dxL * 0.66 + nxL * (rafterDpx * 0.4),
        ly0 + dyL * 0.66 + nyL * (rafterDpx * 0.4),
        3, lx0 + dxL * 0.45, ly0 + dyL * 0.45 + 26);
    // 4 — подвесное чердачное перекрытие.
    _drawPosCallout(canvas, font,
        leftWallX + (rightWallX - leftWallX) * 0.78,
        (attBaseY + wallBottomY) / 2,
        4, rightWallX + 2, attBaseY - 2);
    // 6 — аварийный болт.
    _drawPosCallout(canvas, font, boltX + 1, boltY - 1,
        6, apexX + 36, apexY - 22);
    // 7 — гвозди (на коньке).
    _drawPosCallout(canvas, font, apexX - 5, apexY - 4,
        7, apexX - 60, apexY + 18);
    // 8 — покрытие кровли.
    final coverMidX = lx0 + dxL * 0.45 + nxL * coverOff;
    final coverMidY = ly0 + dyL * 0.45 + nyL * coverOff;
    _drawPosCallout(canvas, font, coverMidX, coverMidY,
        8, coverMidX - 22, coverMidY + 22);

    // ── Маркеры выносных деталей «А» и «Б» ─────────────────────────
    final eaveAnchor = _Pt(eaveLeftX + (lx0 - leftWallX) * 0.4,
        ly0 + nyL * (rafterDpx * 0.5));
    final ridgeAnchor = _Pt(apexX, apexY - 2);
    return _DetailAnchors(
      eaveAnchor: eaveAnchor,
      ridgeAnchor: ridgeAnchor,
    );
  }

  /// Маркер выносной детали («А» или «Б») — кружок с буквой и
  /// тонкой обводкой.
  static void _drawDetailMarker(
    PdfGraphics canvas,
    PdfFont font,
    double x,
    double y,
    String letter,
  ) {
    // Окружность диаметром ~24 pt с пунктирным контуром (как на чертеже-
    // образце «А», «Б»). Имитируем «зону детали» — обводим тонкой линией.
    canvas.setStrokeColor(const PdfColor(0.10, 0.45, 0.85));
    canvas.setLineWidth(0.4);
    canvas.drawEllipse(x, y, 14, 14);
    canvas.strokePath();
    // Буква над окружностью.
    canvas.setFillColor(const PdfColor(0.10, 0.45, 0.85));
    _drawCenteredText(canvas, font, 9.5, letter, x + 18, y + 8);
  }

  /// Деталь «А»: опирание стропилы на мауэрлат + крепление мауэрлата
  /// к стене через анкер с гидроизоляцией.
  static void _drawDetailA(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required HouseProject project,
    required RafterPickResult pick,
    required double slopeDeg,
    required double slopeRad,
  }) {
    // Окно ≈ 0.6×0.5 м, масштаб 1:5 → 6×5 → используем ≈ 90 % rect.
    final s = math.min(r.w / 0.65, r.h / 0.55);
    final ox = r.left + (r.w - 0.65 * s) / 2 + 0.10 * s;
    final oy = r.bottom + 12;

    // Стена.
    final wallH = 0.30 * s;
    final wallW = ((project.walls.thickness ?? 350) / 1000.0) * s;
    canvas.setFillColor(const PdfColor(0.92, 0.92, 0.92));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawRect(ox, oy, wallW, wallH);
    canvas.fillAndStrokePath();
    // Гидроизоляция (две линии под мауэрлатом).
    final waterproofY = oy + wallH;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.45);
    canvas.drawLine(ox - 2, waterproofY, ox + wallW + 2, waterproofY);
    canvas.drawLine(ox - 2, waterproofY + 2, ox + wallW + 2, waterproofY + 2);
    canvas.strokePath();
    // Штриховка гидроизоляции (наклон 45°).
    canvas.setLineWidth(0.3);
    for (var hx = ox; hx < ox + wallW; hx += 3) {
      canvas.drawLine(hx, waterproofY, hx + 2, waterproofY + 2);
    }
    canvas.strokePath();

    // Мауэрлат (100×150).
    final mTopY = waterproofY + 2;
    final mH = 0.15 * s;
    final mW = 0.15 * s;
    final mX = ox + (wallW - mW) / 2;
    canvas.setFillColor(const PdfColor(0.85, 0.55, 0.20));
    canvas.drawRect(mX, mTopY, mW, mH);
    canvas.fillAndStrokePath();

    // Анкер крепления мауэрлата (вертикальная линия в стену).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawLine(mX + mW / 2, mTopY + mH * 0.6,
        mX + mW / 2, oy + wallH * 0.2);
    canvas.strokePath();
    // Шайба.
    canvas.setFillColor(PdfColors.black);
    canvas.drawRect(mX + mW / 2 - 3, mTopY + mH * 0.6 - 1, 6, 1.5);
    canvas.fillPath();

    // Стропилина с запилом (опорная вырубка).
    final rafterTopY = mTopY + mH;
    // Угол ската: рисуем стропилину с правым скатом вверх.
    final rDpx = math.max(8.0, 0.20 * s);
    final cosA = math.cos(slopeRad);
    final sinA = math.sin(slopeRad);
    final length = math.min(r.w * 0.55, 0.55 * s);
    // Точки оси стропилы.
    final ax0 = mX + mW / 2 - 0.06 * s;
    final ay0 = rafterTopY;
    final ax1 = ax0 + length * cosA;
    final ay1 = ay0 + length * sinA;
    // Перпендикуляр (нормаль) к скату — вверх в небо.
    final nx = -sinA;
    final ny = cosA;
    canvas.setFillColor(const PdfColor(0.80, 0.62, 0.42));
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(0.5);
    canvas.moveTo(ax0, ay0);
    canvas.lineTo(ax1, ay1);
    canvas.lineTo(ax1 + nx * rDpx, ay1 + ny * rDpx);
    canvas.lineTo(ax0 + nx * rDpx, ay0 + ny * rDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();
    // Запил на мауэрлате (треугольник).
    canvas.setFillColor(const PdfColor(0.85, 0.55, 0.20));
    canvas.moveTo(ax0, ay0);
    canvas.lineTo(ax0 + 14, ay0);
    canvas.lineTo(ax0 + 14, ay0 - 5);
    canvas.closePath();
    canvas.fillAndStrokePath();

    // Кобылка (свес) — продление стропилы за мауэрлат на 0.5 м.
    final eaveLen = 0.5 * s;
    final ex0 = ax0 - eaveLen * cosA;
    final ey0 = ay0 - eaveLen * sinA;
    canvas.setFillColor(const PdfColor(0.70, 0.55, 0.40));
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.moveTo(ex0, ey0);
    canvas.lineTo(ax0, ay0);
    canvas.lineTo(ax0 + nx * rDpx, ay0 + ny * rDpx);
    canvas.lineTo(ex0 + nx * rDpx, ey0 + ny * rDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();

    // Покрытие кровли (поз. 8) — линия выше стропилы.
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(1.0);
    final coverOff = rDpx + 4;
    canvas.drawLine(ex0 + nx * coverOff, ey0 + ny * coverOff,
        ax1 + nx * coverOff, ay1 + ny * coverOff);
    canvas.strokePath();

    // Гвозди (поз. 7) — две точки на стропиле над запилом.
    canvas.setFillColor(PdfColors.grey800);
    _drawCircle(canvas, ax0 + 4, ay0 + rDpx * 0.5, 0.8);
    _drawCircle(canvas, ax0 + 9, ay0 + rDpx * 0.5, 0.8);

    // Подписи.
    _drawText(canvas, font, 7, 'мауэрлат 100×150',
        mX + mW + 4, mTopY + mH - 4);
    _drawText(canvas, font, 7, 'стропила ${pick.sectionLabel}',
        ax0 + length * 0.45, ay0 + rDpx * 0.5 + 14);
    _drawText(canvas, font, 7, 'кобылка',
        ex0 - 4, ey0 + rDpx + 14);
    _drawText(canvas, font, 7, 'гидроизоляция (рулон)',
        ox - 4, waterproofY + 6);
    _drawText(canvas, font, 7, 'стена',
        ox + wallW / 2 - 12, oy + wallH / 2);
    _drawText(canvas, font, 7, 'анкер М-12',
        mX + mW + 4, oy + wallH * 0.25);

    // Цифровые выноски в зоне детали (3 — стропилина, 7 — гвозди,
    // 8 — кровля).
    _drawPosCallout(canvas, font, ax0 + 4, ay0 + rDpx * 0.5,
        7, ax0 + 16, ay0 + rDpx + 22, radius: 5.5);
    _drawPosCallout(canvas, font,
        (ax1 + ax0) / 2 + nx * coverOff,
        (ay1 + ay0) / 2 + ny * coverOff,
        8, ax1 + nx * coverOff + 4, ay1 + ny * coverOff + 8,
        radius: 5.5);
    _drawPosCallout(canvas, font,
        ax0 + length * 0.4 + nx * (rDpx * 0.4),
        ay0 + length * sinA * 0.4 + ny * (rDpx * 0.4),
        3, ax0 + length * 0.5 - 12, ay0 + length * sinA * 0.5 - 12,
        radius: 5.5);
  }

  /// Деталь «Б»: коньковый узел с накладками, аварийным болтом, гвоздями
  /// и нагелями.
  static void _drawDetailB(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required HouseProject project,
    required RafterPickResult pick,
    required double slopeDeg,
    required double slopeRad,
  }) {
    // Зум на коньковый узел: две концы стропил под углом, накладка,
    // аварийный болт, гвозди, нагели.
    final s = math.min(r.w / 0.90, r.h / 0.50);
    final cx = r.cx;
    // Конёк — точка по центру панели, чуть выше середины.
    final apexY = r.bottom + r.h * 0.55;
    final apexX = cx;
    final cosA = math.cos(slopeRad);
    final sinA = math.sin(slopeRad);
    final rDpx = math.max(10.0, 0.22 * s);
    final lengthM = math.min(0.45, (r.w / 2) / s * 0.85);
    // Концы стропил.
    final lx0 = apexX - lengthM * s * cosA;
    final ly0 = apexY - lengthM * s * sinA;
    final rx0 = apexX + lengthM * s * cosA;
    final ry0 = apexY - lengthM * s * sinA;
    // Левая стропилина.
    final dxL = apexX - lx0;
    final dyL = apexY - ly0;
    final lenL = math.sqrt(dxL * dxL + dyL * dyL);
    final nxL = -dyL / lenL;
    final nyL = dxL / lenL;
    canvas.setFillColor(const PdfColor(0.80, 0.62, 0.42));
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(0.5);
    canvas.moveTo(lx0, ly0);
    canvas.lineTo(apexX, apexY);
    canvas.lineTo(apexX + nxL * rDpx, apexY + nyL * rDpx);
    canvas.lineTo(lx0 + nxL * rDpx, ly0 + nyL * rDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();
    // Правая.
    final dxR = apexX - rx0;
    final dyR = apexY - ry0;
    final lenR = math.sqrt(dxR * dxR + dyR * dyR);
    final nxR = dyR / lenR;
    final nyR = -dxR / lenR;
    canvas.moveTo(rx0, ry0);
    canvas.lineTo(apexX, apexY);
    canvas.lineTo(apexX + nxR * rDpx, apexY + nyR * rDpx);
    canvas.lineTo(rx0 + nxR * rDpx, ry0 + nyR * rDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();

    // Покрытие кровли.
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(1.0);
    final coverOff = rDpx + 4;
    canvas.drawLine(lx0 + nxL * coverOff, ly0 + nyL * coverOff,
        apexX + nxL * coverOff, apexY + nyL * coverOff);
    canvas.drawLine(rx0 + nxR * coverOff, ry0 + nyR * coverOff,
        apexX + nxR * coverOff, apexY + nyR * coverOff);
    canvas.strokePath();

    // Накладки (поз. 9) — две деревянные пластины 30×200, по обеим
    // сторонам конькового стыка. Рисуем как прямоугольник 36×16
    // повёрнутый поперёк линии конька.
    canvas.setFillColor(const PdfColor(0.95, 0.85, 0.65));
    canvas.setStrokeColor(PdfColors.brown600);
    canvas.setLineWidth(0.45);
    final plW = 36.0;
    final plH = 12.0;
    canvas.drawRect(apexX - plW / 2, apexY - plH * 0.7 - rDpx * 0.25,
        plW, plH);
    canvas.fillAndStrokePath();

    // Аварийный болт (поз. 6) — горизонтальная линия с гайками.
    canvas.setFillColor(PdfColors.black);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    final boltY = apexY - plH * 0.7 - rDpx * 0.25 + plH / 2;
    canvas.drawLine(apexX - plW / 2 - 4, boltY, apexX + plW / 2 + 4, boltY);
    canvas.strokePath();
    // Гайки на концах болта.
    canvas.drawRect(apexX - plW / 2 - 4, boltY - 1.5, 4, 3);
    canvas.drawRect(apexX + plW / 2, boltY - 1.5, 4, 3);
    canvas.fillPath();

    // Гвозди (поз. 7) — четыре точки на накладке.
    canvas.setFillColor(PdfColors.grey800);
    _drawCircle(canvas, apexX - plW * 0.30, boltY - 4, 1.0);
    _drawCircle(canvas, apexX + plW * 0.30, boltY - 4, 1.0);
    _drawCircle(canvas, apexX - plW * 0.30, boltY + 4, 1.0);
    _drawCircle(canvas, apexX + plW * 0.30, boltY + 4, 1.0);

    // Нагели (поз. 11) — два штриха в накладке.
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(0.5);
    canvas.drawLine(apexX - plW * 0.45, boltY - 1.5,
        apexX - plW * 0.45, boltY + 1.5);
    canvas.drawLine(apexX + plW * 0.45, boltY - 1.5,
        apexX + plW * 0.45, boltY + 1.5);
    canvas.strokePath();

    // Подписи (с умеренным отступом от элементов).
    _drawText(canvas, font, 7,
        'стропила ${pick.sectionLabel}',
        lx0 + 4, ly0 + rDpx + 18);
    _drawText(canvas, font, 7, 'накладка 30×200',
        apexX - plW / 2 - 30, apexY - plH * 0.7 - rDpx * 0.25 - 10);
    _drawText(canvas, font, 7, 'болт М-12 (аварийный)',
        apexX + plW / 2 + 8, boltY + 8);

    // Цифровые выноски: 3 — стропила, 6 — болт, 9 — накладка, 7 — гвозди,
    // 11 — нагели.
    _drawPosCallout(canvas, font,
        lx0 + dxL * 0.5 + nxL * rDpx * 0.4,
        ly0 + dyL * 0.5 + nyL * rDpx * 0.4,
        3, lx0 - 4, ly0 + nyL * rDpx + 28, radius: 5.5);
    _drawPosCallout(canvas, font, apexX + plW / 2 + 1, boltY,
        6, apexX + plW / 2 + 18, boltY - 18, radius: 5.5);
    _drawPosCallout(canvas, font, apexX - plW * 0.40, boltY + 0.5,
        9, apexX - plW / 2 - 26, boltY + 22, radius: 5.5);
    _drawPosCallout(canvas, font, apexX + plW * 0.30, boltY + 4,
        7, apexX + plW / 2 + 4, boltY + 22, radius: 5.5);
    _drawPosCallout(canvas, font, apexX + plW * 0.45, boltY,
        11, apexX + plW / 2 + 28, boltY + 6, radius: 5.5);
  }

  /// 11-позиционная легенда по эталонному альбому стропильных систем.
  static void _drawTrussLegend(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r,
  ) {
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 9.5, 'Условные обозначения',
        r.left + 6, r.top - 14, bold: true);
    final items = <String>[
      '1 — затяжки;',
      '2 — подвеска (бабка);',
      '3 — стропильная нога;',
      '4 — подвесное чердачное',
      '       перекрытие;',
      '5 — подкос;',
      '6 — аварийный болт;',
      '7 — гвозди;',
      '8 — покрытие кровли;',
      '9 — две накладки;',
      '10 — болты;',
      '11 — болтовые нагели.',
    ];
    var ty = r.top - 30;
    for (final line in items) {
      _drawText(canvas, font, 8, line, r.left + 8, ty);
      ty -= 11.5;
    }
  }

  /// Полная таблица «Спецификация и расчёт стропил» (как на КД-2.1).
  /// Возвращает Y нижней границы таблицы — чтобы вызывающий код мог
  /// разместить ниже этой Y легенду без наслоения.
  static double _drawRaftersSpecTable(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required HouseProject project,
    required RafterPickResult pick,
    required double spanM,
    required double slopeDeg,
  }) {
    final wallHeightM = project.walls.height ??
        project.staircase.floorHeight ??
        2.7;
    final slopeRad = slopeDeg * math.pi / 180;
    final ridgeRiseM = (spanM / 2) * math.tan(slopeRad);
    final rafterLengthM = (spanM / 2) / math.cos(slopeRad);
    const eaveOverhangM = 0.5;
    final muValue = pick.snowSgKnPerM2 == 0
        ? 0.0
        : pick.snowS0KnPerM2 / pick.snowSgKnPerM2;
    final passLabel = pick.passes
        ? 'проходит'
        : 'НЕ проходит — ферма';
    final c1 = r.w * 0.34;
    final c2 = r.w * 0.30;
    final c3 = r.w - c1 - c2;
    return _drawWrappedTable(
      canvas,
      font,
      r.left,
      r.top - 4,
      r.w,
      title: 'Спецификация и расчёт стропил',
      headers: const ['Параметр', 'Значение', 'Прим.'],
      colWidths: [c1, c2, c3],
      rows: [
        ['Сечение С-1', pick.sectionLabel, 'СП 64.13330'],
        [
          'Шаг стропил',
          '${(pick.stepM * 1000).round()} мм',
          'СП 17.13330',
        ],
        ['Угол ската', '${slopeDeg.toStringAsFixed(0)}°', 'из проекта'],
        [
          'Длина стропилины',
          '${(rafterLengthM * 1000).round()} мм',
          'L = (пролёт/2) / cos α',
        ],
        [
          'Высота конька',
          '${(ridgeRiseM * 1000).round()} мм',
          'h = (пролёт/2) · tan α',
        ],
        [
          'Высота стены',
          '${(wallHeightM * 1000).round()} мм',
          'walls.height',
        ],
        [
          'Вынос свеса',
          '${(eaveOverhangM * 1000).round()} мм',
          'СП 17 п. 6.1.4',
        ],
        [
          'Снег. район',
          'район ${pick.snowZone}',
          'Sg = ${pick.snowSgKnPerM2.toStringAsFixed(1)} кН/м²',
        ],
        [
          'S₀ = Sg·μ',
          '${pick.snowS0KnPerM2.toStringAsFixed(2)} кН/м²',
          'μ = ${muValue.toStringAsFixed(2)}',
        ],
        [
          'g (постоянная)',
          '${pick.permKnPerM2.toStringAsFixed(2)} кН/м²',
          'кровля + обрешётка',
        ],
        [
          'q расч.',
          '${pick.qDesignKnPerM2.toStringAsFixed(2)} кН/м²',
          'γg·g + γs·S₀',
        ],
        [
          'q линейн.',
          '${pick.qKnPerM.toStringAsFixed(2)} кН/м',
          'q·шаг',
        ],
        [
          'M = q·L²/8',
          '${pick.momentKnm.toStringAsFixed(2)} кН·м',
          'расч. изгиб',
        ],
        [
          'σ = M/Wx',
          '${pick.sigmaNmm2.toStringAsFixed(1)} Н/мм²',
          '≤ 14 Н/мм²',
        ],
        [
          'f',
          '${pick.deflectionMm.toStringAsFixed(1)} мм',
          '≤ ${(pick.spanM * 1000 / 200).round()} мм',
        ],
        [
          'R',
          '${pick.reactionKn.toStringAsFixed(2)} кН',
          'на мауэрлат',
        ],
        [
          'Проверка',
          passLabel,
          'СП 64.13330',
        ],
      ],
      headerHeight: 14,
      minRowHeight: 12,
      lineHeight: 8.0,
      bodyFontSize: 6.5,
      headerFontSize: 7.0,
      wrapColumns: const {2},
    );
  }

  // ───────────────────────── СХЕМА СТРОПИЛ (КД-2 — устаревшая раздельная) ───────────────────────
  static pw.Page raftersPage({
    required HouseProject project,
    required FloorPlan topPlan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КД-2',
    OrganizationSettings? organization,
  }) {
    final roofType = (project.roof.type ?? 'gable').toLowerCase();
    final isHip = roofType.contains('hip') || roofType.contains('вальм');
    final isFlat = roofType.contains('flat') || roofType.contains('плос');
    final isMansard = roofType.contains('mansard') || roofType.contains('мансар');
    final schemaTitle = isHip
        ? 'Схема деревянных наслонных стропил с упором на один прогон для '
            'вальмовой крыши'
        : isFlat
            ? 'Схема несущих балок плоской кровли'
            : isMansard
                ? 'Схема деревянных наслонных стропил мансардной крыши'
                : 'Схема деревянных наслонных стропил двускатной крыши';
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
                    _planHeader(
                      project,
                      schemaTitle,
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) => _paintRaftersScheme(
                                  canvas, size, topPlan, pdfFont, project),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструкции деревянные',
                sheetTitle: 'Схема расположения стропил',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────── РАЗРЕЗ СТРОПИЛЬНОЙ СИСТЕМЫ (КД-2.1) ─────────
  /// Разрез по стропильной системе: стена → мауэрлат → стропила →
  /// конёк → обрешётка → кровельный пирог. Размеры синхронизированы с
  /// расчётами (СП 64.13330): сечение стропил по пролёту, шаг 600 мм,
  /// угол ската из project.roof.slopeAngle.
  ///
  /// Добавлен в v40 п.7. Для плоской кровли разрез не нужен — лист
  /// не выводится.
  static pw.Page raftersSectionPage({
    required HouseProject project,
    required FloorPlan topPlan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'КД-2.1',
    OrganizationSettings? organization,
  }) {
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
                    _planHeader(
                      project,
                      'Разрез по стропильной системе (СП 64.13330, СП 17.13330)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Expanded(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) {
                          return pw.SizedBox(
                            width: constraints!.maxWidth,
                            height: constraints.maxHeight,
                            child: pw.CustomPaint(
                              size: PdfPoint(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: (canvas, size) =>
                                  _paintRaftersSection(
                                canvas,
                                size,
                                topPlan,
                                pdfFont,
                                project,
                              ),
                            ),
                          );
                        },
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
                sectionTitle: 'Конструкции деревянные',
                sheetTitle: 'Разрез стропильной системы',
                sheetCode: sheetCode,
                sheetNumber: sheetNumber,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Рисует разрез стропильной системы.
  ///
  /// Стропильный треугольник вписывается в окно ~70 % ширины × 80 %
  /// высоты канвы; справа — спецификация и примечания (как и в
  /// raftersPage). Размеры:
  ///   • span/2 (горизонтальный пролёт стропила),
  ///   • высота конька от мауэрлата (h = (span/2) · tan α),
  ///   • длина стропила (span/2 / cos α),
  ///   • высота этажа стены (project.walls.height ?? 2.7 м),
  ///   • высота мауэрлата (150 мм по сечению М 100×150),
  ///   • вынос карнизного свеса (свес = 500 мм по умолчанию).
  static void _paintRaftersSection(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan topPlan,
    PdfFont font,
    HouseProject project,
  ) {
    final w = size.x;
    final h = size.y;
    final roofType = (project.roof.type ?? 'gable').toLowerCase();
    final isFlat = roofType.contains('flat') || roofType.contains('плос');
    if (isFlat) {
      _drawText(canvas, font, 12,
          'Кровля — плоская. Разрез по стропилам не требуется.', 30, h - 30);
      return;
    }
    final ridgeAlongX = topPlan.width >= topPlan.height;
    final spanM = ridgeAlongX ? topPlan.height : topPlan.width;
    final halfSpanM = spanM / 2;
    final slopeDeg = project.roof.slopeAngle ?? 30.0;
    final slopeRad = slopeDeg * math.pi / 180;
    final ridgeRiseM = halfSpanM * math.tan(slopeRad);
    final rafterLengthM = halfSpanM / math.cos(slopeRad);
    // §27.2: Высота стены: walls.height → staircase.floorHeight → 2.8 м
    // (унифицировано с pdf_builder/pdf_catalog_card/pdf_a1_placard).
    final wallHeightM = project.walls.height ??
        project.staircase.floorHeight ??
        2.8;
    // Толщина стены: walls.thickness (мм) → 200 мм по умолчанию.
    final wallThickM = (project.walls.thickness ?? 200.0) / 1000.0;
    const eaveOverhangM = 0.5; // вынос свеса (по умолчанию 500 мм)
    const mauerlatHM = 0.15; // высота сечения 100×150 мм
    // Сечение стропил подбирается по фактическим нагрузкам:
    // снеговой район из brief.snowZone, угол ската из roof.slopeAngle,
    // вес кровли из roof.roofingMaterial. См. RafterSectionPicker
    // (СП 20.13330.2016 + СП 64.13330.2017). Это устраняет хардкод
    // «полупролёт ≤ 4.5 → 50×150» из v42.
    final pick = RafterSectionPicker.pickFor(project);
    final rafterSection = pick.sectionLabel;

    // Окно чертежа: левые 70 % × вся высота - 30 для подписей.
    final drawW = w * 0.66;
    final drawH = h - 30;
    // Геометрия в метрах: стена + мауэрлат + конёк.
    final totalWm = spanM + 2 * eaveOverhangM;
    final totalHm = wallHeightM + mauerlatHM + ridgeRiseM + 0.3; // запас
    // Масштаб: вписываем в (drawW-100) × (drawH-100) для подписей.
    final sx = (drawW - 110) / totalWm;
    final sy = (drawH - 110) / totalHm;
    final scale = sx < sy ? sx : sy;
    // Опорная точка: левый нижний угол стены.
    final wallLeft = 60.0 + eaveOverhangM * scale;
    final wallBottom = 80.0;
    final wallRight = wallLeft + spanM * scale;
    final wallTop = wallBottom + wallHeightM * scale;
    final mauerlatTop = wallTop + mauerlatHM * scale;
    final ridgeY = mauerlatTop + ridgeRiseM * scale;
    final ridgeX = (wallLeft + wallRight) / 2;
    final eaveLx = wallLeft - eaveOverhangM * scale;
    final eaveRx = wallRight + eaveOverhangM * scale;

    // 1. Стены — два узких прямоугольника. Толщина из walls.thickness.
    final wallThickPx = wallThickM * scale;
    canvas.setFillColor(const PdfColor(0.93, 0.93, 0.93));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawRect(wallLeft, wallBottom, wallThickPx, wallTop - wallBottom);
    canvas.fillAndStrokePath();
    canvas.drawRect(wallRight - wallThickPx, wallBottom, wallThickPx,
        wallTop - wallBottom);
    canvas.fillAndStrokePath();

    // 2. Мауэрлат — оранжевые прямоугольники 150×100 мм поверх стен.
    final maW = 0.15 * scale;
    final maH = mauerlatHM * scale;
    canvas.setFillColor(const PdfColor(0.85, 0.55, 0.2));
    canvas.drawRect(wallLeft - 0.025 * scale, wallTop, maW, maH);
    canvas.fillAndStrokePath();
    canvas.drawRect(wallRight - maW + 0.025 * scale, wallTop, maW, maH);
    canvas.fillAndStrokePath();

    // 3. Стропила — две наклонные доски (50×200 мм для среднего пролёта).
    final rafterDpx = 0.2 * scale; // высота сечения
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setFillColor(const PdfColor(0.80, 0.62, 0.42));
    canvas.setLineWidth(0.5);
    // Левая стропилина: от eaveLx (низ) до ridgeX,ridgeY (верх).
    final lx0 = eaveLx;
    final ly0 = mauerlatTop;
    final lx1 = ridgeX;
    final ly1 = ridgeY;
    final dxL = lx1 - lx0;
    final dyL = ly1 - ly0;
    final lenL = math.sqrt(dxL * dxL + dyL * dyL);
    final nxL = -dyL / lenL; // нормаль к скату
    final nyL = dxL / lenL;
    canvas.moveTo(lx0, ly0);
    canvas.lineTo(lx1, ly1);
    canvas.lineTo(lx1 + nxL * rafterDpx, ly1 + nyL * rafterDpx);
    canvas.lineTo(lx0 + nxL * rafterDpx, ly0 + nyL * rafterDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();
    // Правая стропилина (зеркально). Нормаль вычисляется так, чтобы
    // «толщина» уходила вверх (в небо) — как и у левой стропилины:
    // у левой dxL>0, dyL>0 ⇒ (nxL=-dyL/L, nyL=dxL/L) = (-,+); на правой
    // dxR<0, dyR>0 ⇒ нужно (+, +), поэтому нормаль = (dyR/L, -dxR/L).
    final rx0 = eaveRx;
    final ry0 = mauerlatTop;
    final rx1 = ridgeX;
    final ry1 = ridgeY;
    final dxR = rx1 - rx0;
    final dyR = ry1 - ry0;
    final lenR = math.sqrt(dxR * dxR + dyR * dyR);
    final nxR = dyR / lenR;
    final nyR = -dxR / lenR;
    canvas.moveTo(rx0, ry0);
    canvas.lineTo(rx1, ry1);
    canvas.lineTo(rx1 + nxR * rafterDpx, ry1 + nyR * rafterDpx);
    canvas.lineTo(rx0 + nxR * rafterDpx, ry0 + nyR * rafterDpx);
    canvas.closePath();
    canvas.fillAndStrokePath();

    // 4. Коньковый прогон — квадрат 150×150 на ridge.
    final kRpx = 0.075 * scale;
    canvas.setFillColor(const PdfColor(0.65, 0.45, 0.25));
    canvas.drawRect(ridgeX - kRpx, ridgeY, 2 * kRpx, 2 * kRpx);
    canvas.fillAndStrokePath();

    // 5. Обрешётка — серия точек на спинке стропил (~10 шагов).
    canvas.setFillColor(PdfColors.grey600);
    final obStepM = 0.35;
    final obSteps = (lenL / scale / obStepM).floor();
    for (var k = 1; k < obSteps; k++) {
      // Точка на левом скате — отступаем по нормали на rafterDpx + 6 мм.
      final t = k / obSteps;
      final ox = lx0 + dxL * t + nxL * (rafterDpx + 0.04 * scale);
      final oy = ly0 + dyL * t + nyL * (rafterDpx + 0.04 * scale);
      _drawCircle(canvas, ox, oy, 1.5, fill: PdfColors.grey700);
      final ox2 = rx0 + dxR * t + nxR * (rafterDpx + 0.04 * scale);
      final oy2 = ry0 + dyR * t + nyR * (rafterDpx + 0.04 * scale);
      _drawCircle(canvas, ox2, oy2, 1.5, fill: PdfColors.grey700);
    }

    // 6. Кровельное покрытие — тонкая линия выше обрешётки.
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(1.0);
    final coverOffM = 0.06; // 60 мм над обрешёткой
    final coverNxL = nxL * (rafterDpx + coverOffM * scale);
    final coverNyL = nyL * (rafterDpx + coverOffM * scale);
    final coverNxR = nxR * (rafterDpx + coverOffM * scale);
    final coverNyR = nyR * (rafterDpx + coverOffM * scale);
    canvas.drawLine(lx0 + coverNxL, ly0 + coverNyL, lx1 + coverNxL,
        ly1 + coverNyL);
    canvas.strokePath();
    canvas.drawLine(rx0 + coverNxR, ry0 + coverNyR, rx1 + coverNxR,
        ry1 + coverNyR);
    canvas.strokePath();

    // 7. Размеры и подписи.
    canvas.setFillColor(PdfColors.black);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Размер "пролёт" внизу.
    final dimY = wallBottom - 22;
    canvas.drawLine(wallLeft, dimY, wallRight, dimY);
    canvas.strokePath();
    canvas.drawLine(wallLeft, dimY - 4, wallLeft, dimY + 4);
    canvas.drawLine(wallRight, dimY - 4, wallRight, dimY + 4);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 9.5,
        '${(spanM * 1000).toStringAsFixed(0)} мм (пролёт)',
        (wallLeft + wallRight) / 2, dimY - 12);
    // Размер "вынос свеса" слева.
    final eaveDimY = wallBottom - 8;
    canvas.drawLine(eaveLx, eaveDimY, wallLeft, eaveDimY);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 8.5,
        '${(eaveOverhangM * 1000).toStringAsFixed(0)}',
        (eaveLx + wallLeft) / 2, eaveDimY - 9);
    canvas.drawLine(wallRight, eaveDimY, eaveRx, eaveDimY);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 8.5,
        '${(eaveOverhangM * 1000).toStringAsFixed(0)}',
        (eaveRx + wallRight) / 2, eaveDimY - 9);
    // Высота от 0.000 (низ стены) до конька — справа.
    final rdx = eaveRx + 26;
    canvas.drawLine(rdx, wallBottom, rdx, ridgeY);
    canvas.strokePath();
    canvas.drawLine(rdx - 4, wallBottom, rdx + 4, wallBottom);
    canvas.drawLine(rdx - 4, ridgeY, rdx + 4, ridgeY);
    canvas.strokePath();
    final totalRiseMm =
        (wallHeightM + mauerlatHM + ridgeRiseM) * 1000;
    _drawText(canvas, font, 9, '${totalRiseMm.toStringAsFixed(0)} мм',
        rdx + 6, (wallBottom + ridgeY) / 2);
    // Высота этажа стены.
    final wdx = wallLeft - 26;
    canvas.drawLine(wdx, wallBottom, wdx, wallTop);
    canvas.strokePath();
    canvas.drawLine(wdx - 4, wallBottom, wdx + 4, wallBottom);
    canvas.drawLine(wdx - 4, wallTop, wdx + 4, wallTop);
    canvas.strokePath();
    _drawText(canvas, font, 8, '${(wallHeightM * 1000).toStringAsFixed(0)}',
        wdx - 32, (wallBottom + wallTop) / 2);
    // Угол ската.
    _drawText(canvas, font, 9, '${slopeDeg.toStringAsFixed(0)}°',
        ridgeX + 18, ridgeY - 18);
    // Длина стропилины — на спинке.
    final midL = PdfPoint(
      (lx0 + lx1) / 2 + nxL * (rafterDpx + 0.12 * scale),
      (ly0 + ly1) / 2 + nyL * (rafterDpx + 0.12 * scale),
    );
    _drawText(canvas, font, 8.5,
        'L = ${(rafterLengthM * 1000).toStringAsFixed(0)} мм',
        midL.x - 36, midL.y);

    // Маркировки:
    _drawText(canvas, font, 8.5, 'С-1 ($rafterSection)',
        (lx0 + lx1) / 2 - 10, (ly0 + ly1) / 2 - 8);
    _drawText(canvas, font, 8, 'К-1 (Ц 150×150)', ridgeX + 20, ridgeY + 8);
    _drawText(canvas, font, 8, 'М-1 (Ц 100×150)', wallLeft + 4, mauerlatTop + 4);
    _drawText(canvas, font, 8, 'обрешётка Об-1 (доска 25×100, шаг 350)',
        ridgeX + 6, mauerlatTop + 30);
    _drawText(canvas, font, 8, 'Кровля', ridgeX + 6, ridgeY + 26);

    // Правая 30 % полосы — таблица «Спецификация и расчёт» с переносом
    // в столбце «Прим.». Все числа берутся из тех же входных данных,
    // что и сам чертёж + RafterSectionPicker (СП 20 + СП 64) — никаких
    // расхождений между чертежом, ПЗ и сметой.
    final tableX = drawW + 14;
    final tableW = w - tableX - 16;
    final c1 = tableW * 0.30;
    final c2 = tableW * 0.30;
    final c3 = tableW - c1 - c2;
    final muValue = pick.snowSgKnPerM2 == 0
        ? 0.0
        : pick.snowS0KnPerM2 / pick.snowSgKnPerM2;
    final passLabel =
        pick.passes ? 'проходит' : 'НЕ проходит — нужна ферма';
    _drawWrappedTable(
      canvas,
      font,
      tableX,
      h - 24,
      tableW,
      title: 'Спецификация и расчёт стропил',
      headers: const ['Параметр', 'Значение', 'Прим.'],
      colWidths: [c1, c2, c3],
      rows: [
        ['Сечение С-1', rafterSection, 'СП 64.13330, табл. Е.1'],
        [
          'Шаг стропил',
          '${(pick.stepM * 1000).round()} мм',
          'СП 17.13330.2017',
        ],
        ['Угол ската', '${slopeDeg.toStringAsFixed(0)}°', 'из брифа проекта'],
        [
          'Длина стропилины',
          '${(rafterLengthM * 1000).round()} мм',
          'L = (пролёт/2) / cos α',
        ],
        [
          'Высота конька',
          '${(ridgeRiseM * 1000).round()} мм',
          'h = (пролёт/2) · tan α',
        ],
        [
          'Высота стены',
          '${(wallHeightM * 1000).round()} мм',
          'из brief.walls.height',
        ],
        [
          'Вынос свеса',
          '${(eaveOverhangM * 1000).round()} мм',
          'СП 17 п. 6.1.4',
        ],
        [
          'Снег. район',
          'район ${pick.snowZone}',
          'Sg = ${pick.snowSgKnPerM2.toStringAsFixed(1)} кН/м²',
        ],
        [
          'S₀ = Sg·μ',
          '${pick.snowS0KnPerM2.toStringAsFixed(2)} кН/м²',
          'μ(α=${slopeDeg.toStringAsFixed(0)}°) = '
              '${muValue.toStringAsFixed(2)}',
        ],
        [
          'g (постоянная)',
          '${pick.permKnPerM2.toStringAsFixed(2)} кН/м²',
          'кровля + обрешётка + утеплитель',
        ],
        [
          'q расч.',
          '${pick.qDesignKnPerM2.toStringAsFixed(2)} кН/м²',
          'γg·g + γs·S₀',
        ],
        [
          'q линейн.',
          '${pick.qKnPerM.toStringAsFixed(2)} кН/м',
          'q·шаг',
        ],
        [
          'M = q·L²/8',
          '${pick.momentKnm.toStringAsFixed(2)} кН·м',
          'расчётный изгиб',
        ],
        [
          'σ = M/Wx',
          '${pick.sigmaNmm2.toStringAsFixed(1)} Н/мм²',
          '≤ 14 Н/мм² (2 сорт)',
        ],
        [
          'f',
          '${pick.deflectionMm.toStringAsFixed(1)} мм',
          '≤ L/200 = ${(pick.spanM * 1000 / 200).round()} мм',
        ],
        [
          'R',
          '${pick.reactionKn.toStringAsFixed(2)} кН',
          'на мауэрлат и конёк',
        ],
        [
          'Проверка',
          passLabel,
          'СП 64.13330.2017',
        ],
      ],
      headerHeight: 16,
      minRowHeight: 14,
      lineHeight: 8.5,
      bodyFontSize: 6.5,
      headerFontSize: 7.0,
      wrapColumns: const {2},
    );
  }

  // ═════════════════════════ ОБЩИЙ ЗАГОЛОВОК ════════════════════════════
  static pw.Widget _planHeader(
    HouseProject project,
    String title,
    int versionNumber,
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
              project.name,
              style: pw.TextStyle(
                fontSize: 14,
                font: fontBold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 10, font: font),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Версия №$versionNumber',
              style: pw.TextStyle(fontSize: 10, font: font),
            ),
          ],
        ),
      ],
    );
  }

  // ═════════════════ ОБЩАЯ ГЕОМЕТРИЯ ПЯТНА ЗАСТРОЙКИ ════════════════════
  static _PlanLayout _layout(PdfPoint size, FloorPlan plan,
      {double rightSidebar = 230}) {
    final w = size.x;
    final h = size.y;
    const marginLeft = 90.0;
    const marginTop = 28.0;
    const marginBottom = 30.0;
    final marginRight = rightSidebar;
    final scaleX = (w - marginLeft - marginRight) / plan.width;
    final scaleY = (h - marginTop - marginBottom) / plan.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final planW = plan.width * scale;
    final planH = plan.height * scale;
    final ox = marginLeft + ((w - marginLeft - marginRight) - planW) / 2;
    final oy = marginTop + ((h - marginTop - marginBottom) - planH) / 2;
    // Правый край боковых таблиц = правый край листа (внутреннего
    // контура). Поля и таблицы выравниваются по правому краю канвы,
    // которая совпадает с внутренним контуром листа (отступ 14 pt).
    const sidebarRightOffset = 0.0;
    final sidebarRight = w - sidebarRightOffset;
    final sidebarLeft = ox + planW + 18;
    return _PlanLayout(
      ox: ox,
      oy: oy,
      planW: planW,
      planH: planH,
      scale: scale,
      sidebarLeft: sidebarLeft,
      sidebarTop: oy + planH,
      sidebarWidth: sidebarRight - sidebarLeft,
    );
  }

  // ─────────────────────── ОТРИСОВКА ОСНОВЫ ПЛАНА ──────────────────────
  /// Рисует наружный контур (несущие стены толстой линией) и внутренние
  /// перегородки (по разбиению на комнаты).
  static void _paintBasePlan(
    PdfGraphics canvas,
    _PlanLayout L,
    FloorPlan plan, {
    bool drawRoomLabels = true,
    PdfFont? font,
  }) {
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Phase-3b §17.2.1: для полигонального footprint строим контур по
    // outline + holes; для прямоугольника — старый drawRect-путь.
    final isPoly = plan.hasPolygonalFootprint;
    void buildFootprintPath() {
      final fp = plan.effectiveFootprint;
      void appendRing(List<Vec2> ring) {
        if (ring.isEmpty) return;
        final first = pp(ring.first.x, ring.first.y);
        canvas.moveTo(first.x, first.y);
        for (var i = 1; i < ring.length; i++) {
          final p = pp(ring[i].x, ring[i].y);
          canvas.lineTo(p.x, p.y);
        }
        canvas.closePath();
      }
      appendRing(fp.outline);
      for (final h in fp.holes) {
        appendRing(h);
      }
    }

    // Заливка внутренней области пятна.
    canvas.setFillColor(PdfColors.white);
    final tl = pp(0, 0);
    if (isPoly) {
      buildFootprintPath();
      canvas.fillPath(evenOdd: true);
    } else {
      canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
      canvas.fillPath();
    }

    // Несущий контур пятна — толстая линия 1.4 pt.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    if (isPoly) {
      buildFootprintPath();
      canvas.strokePath();
    } else {
      canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
      canvas.strokePath();
    }

    // Внутренние перегородки = тонкие границы помещений (тоньше).
    canvas.setLineWidth(0.5);
    for (final r in plan.rooms) {
      final p = pp(r.x, r.y);
      canvas.drawRect(p.x, p.y - r.height * L.scale, r.width * L.scale,
          r.height * L.scale);
      canvas.strokePath();
    }

    if (drawRoomLabels && font != null) {
      canvas.setFillColor(PdfColors.black);
      for (final r in plan.rooms) {
        final cx = L.ox + (r.x + r.width / 2) * L.scale;
        final cy = L.oy + L.planH - (r.y + r.height / 2) * L.scale;
        _drawCenteredText(
          canvas,
          font,
          7.0,
          r.label.isEmpty ? '—' : r.label,
          cx,
          cy + 3,
        );
        _drawCenteredText(
          canvas,
          font,
          6.5,
          '${r.area.toStringAsFixed(1)} м²',
          cx,
          cy - 5,
        );
      }
    }
  }

  // ═════════════════════════ ПЛАН ПЕРЕГОРОДОК ═══════════════════════════
  static void _paintPartitions(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
  ) {
    final L = _layout(size, plan, rightSidebar: 230);
    _paintBasePlan(canvas, L, plan, drawRoomLabels: true, font: font);

    // Маркируем перегородки (внутренние стены) кружками ПГ-1.
    // Условно: все внутренние стены — каркасные ГКЛ 100 мм.
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Идентификатор по типам комнат: для санузла → ПГ-2 (влагостойкий),
    // для остальных → ПГ-1.
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    int markerIdx = 0;
    for (final r in plan.rooms) {
      if (markerIdx >= 16) break;
      final mark = _markForRoom(r);
      // Маркер ПГ — в правый-верхний угол комнаты (минимум 0,5 м от
      // стен), чтобы не пересекаться с подписью «название комнаты + S».
      final markX = r.x + r.width - math.min<double>(0.5, r.width / 4);
      final markY = r.y + math.min<double>(0.5, r.height / 4);
      final p = pp(markX, markY);
      const markFs = 7.0;
      // Радиус круга авто-увеличиваем, если ширина текста больше
      // диаметра. Минимум — 9, плюс 2 pt запас на полях.
      final tw = font.stringMetrics(mark).width * markFs;
      final radius = math.max<double>(9, tw / 2 + 2.4);
      _drawCircle(canvas, p.x, p.y, radius, fill: PdfColors.white);
      canvas.setFillColor(PdfColors.black);
      // Текст по центру круга: baseline = p.y - 0.35*fontSize.
      _drawCenteredText(canvas, font, markFs, mark, p.x,
          p.y - markFs * 0.35);
      canvas.setFillColor(PdfColors.white);
      markerIdx++;
    }

    // Спецификация перегородок справа. Используем версию с автопереносом
    // во втором столбце «Конструкция», чтобы текст не выходил за границу
    // колонки и таблицы.
    final tableBottomY = _drawWrappedTable(
      canvas,
      font,
      L.sidebarLeft,
      L.oy + L.planH - 8,
      L.sidebarWidth,
      title: 'Спецификация перегородок',
      headers: const ['Марка', 'Конструкция', 'Толщ., мм'],
      colWidths: const [44, 130, 56],
      rows: const [
        ['ПГ-1', 'Каркас 50×50 + ГКЛ 12,5 в 2 слоя + утеплитель', '100'],
        ['ПГ-2', 'Каркас + ГКЛВ влагостойкий + пароизоляция', '120'],
        ['ПГ-3', 'Кладка пенобетон D500, армировка 50×50', '100'],
        ['ПГ-4', 'Кирпич полнотелый ГОСТ 530-2012', '120'],
      ],
      headerHeight: 15,
      minRowHeight: 15,
      lineHeight: 9,
      bodyFontSize: 6.5,
      headerFontSize: 7,
      wrapColumns: const {1},
    );

    // «Примечания» располагаются СТРОГО ниже таблицы спецификации —
    // используем фактическую нижнюю Y таблицы (с учётом переносов
    // в колонке «Конструкция»). Ранее был жёстко прибитый offset
    // -110, который при росте таблицы накладывался на её строки.
    canvas.setFillColor(PdfColors.black);
    final notesY = tableBottomY - 18;
    _drawText(canvas, font, 8.0, 'Примечания', L.sidebarLeft, notesY,
        bold: true);
    final notes = const <String>[
      '1. Высота перегородок — до перекрытия (h ≈ 2,7 м).',
      '2. Зазор по периметру 10 мм с уплотнением минватой.',
      '3. В мокрых зонах (ПГ-2) — гидроизоляционная обмазка.',
      '4. Класс пож. опасности — К0 (СП 2.13130).',
      '5. Дверные проёмы усилить горизонт. перемычкой.',
      '6. Армировать каждый 3-й ряд кирпичной перегородки.',
    ];
    var ny = notesY - 13;
    for (final note in notes) {
      _drawText(canvas, font, 7.0, note, L.sidebarLeft, ny);
      ny -= 11;
    }
  }

  static String _markForRoom(PlanRoom r) {
    final n = (r.roomKindName ?? '').toLowerCase();
    if (n.contains('bath') || n.contains('toilet') || n == 'санузел') {
      return 'ПГ-2';
    }
    if (n.contains('kitchen') || n == 'кухня') return 'ПГ-1';
    return 'ПГ-1';
  }

  // ═════════════════════════════ ПЛАН ПОЛОВ ═════════════════════════════
  static void _paintFloorTypes(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
  ) {
    final L = _layout(size, plan, rightSidebar: 240);
    _paintBasePlan(canvas, L, plan, drawRoomLabels: true, font: font);

    // Маркируем тип пола в каждой комнате — в нижнем-левом углу.
    for (final r in plan.rooms) {
      final mark = _floorMarkForRoom(r);
      final markX = r.x + math.min<double>(0.5, r.width / 4);
      final markY = r.y + r.height - math.min<double>(0.5, r.height / 4);
      final cx = L.ox + markX * L.scale;
      final cy = L.oy + L.planH - markY * L.scale;
      const fs = 7.0;
      final tw = font.stringMetrics(mark).width * fs;
      final radius = math.max<double>(9.5, tw / 2 + 2.4);
      _drawCircle(canvas, cx, cy, radius, fill: PdfColors.grey200);
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(canvas, font, fs, mark, cx, cy - fs * 0.35);
    }

    // Таблица типов полов.
    // Таблица «Экспликация типов полов» с многострочным
    // автопереносом во втором столбце «Помещения», чтобы текст
    // никогда не вылезал за границы колонки и таблицы.
    _drawWrappedTable(
      canvas,
      font,
      L.sidebarLeft,
      L.oy + L.planH - 8,
      L.sidebarWidth,
      title: 'Экспликация типов полов',
      headers: const ['Тип', 'Помещения', 'Толщ.'],
      colWidths: const [26, 138, 36],
      rows: const [
        ['П1', 'Жилые: спальня, гостиная, прихожая', '90'],
        ['П2', 'Санузел, кухня, тамбур (мокрые)', '110'],
        ['П3', 'Парадные: гостиная, кабинет', '105'],
        ['П4', 'Нежилые / тех. помещения', '160'],
      ],
      headerHeight: 16,
      minRowHeight: 16,
      lineHeight: 9,
      bodyFontSize: 6.5,
      headerFontSize: 7,
      wrapColumns: const {1},
    );
    // Узел У-1 и условные обозначения с этого листа удалены по запросу.
  }

  static String _floorMarkForRoom(PlanRoom r) {
    final n = (r.roomKindName ?? r.label).toLowerCase();
    if (n.contains('bath') ||
        n.contains('toilet') ||
        n.contains('kitchen') ||
        n.contains('санузел') ||
        n.contains('кухня')) {
      return 'П2';
    }
    if (n.contains('living') ||
        n.contains('cabinet') ||
        n.contains('study') ||
        n.contains('гостиная') ||
        n.contains('кабинет')) {
      return 'П3';
    }
    if (n.contains('storage') ||
        n.contains('boiler') ||
        n.contains('garage') ||
        n.contains('terrace') ||
        n.contains('porch') ||
        n.contains('крыльцо')) {
      return 'П4';
    }
    return 'П1';
  }

  // _drawFloorPieNode удалён: «Узел У-1» и условные обозначения с листа
  // полов убраны по запросу.

  // ═════════════════════════════ ПЛАН ПОДВАЛА ═══════════════════════════
  static void _paintBasement(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
    HouseProject project,
  ) {
    final L = _layout(size, plan, rightSidebar: 230);
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Толщина стены подвала: из walls.thickness (если задана) → 400 мм.
    // Это связывает чертёж подвала с тем же значением, что используется
    // в 3D и на сечении КЖ-1.
    final wallThickMm = project.walls.thickness ?? 400.0;
    final innerInset = wallThickMm / 1000.0;
    // Высота этажа подвала — из walls.height (или staircase.floorHeight).
    final basementHeightM = project.walls.height ??
        project.staircase.floorHeight ??
        2.5;

    // Контур пятна (стены подвала — толще наружных, бетон).
    canvas.setFillColor(PdfColors.grey200);
    final tl = pp(0, 0);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.6);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.strokePath();

    // Внутреннее свободное пространство.
    final inX = innerInset, inY = innerInset;
    final inW = plan.width - 2 * innerInset;
    final inH = plan.height - 2 * innerInset;
    canvas.setFillColor(PdfColors.white);
    final inTL = pp(inX, inY);
    canvas.drawRect(inTL.x, inTL.y - inH * L.scale, inW * L.scale,
        inH * L.scale);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(inTL.x, inTL.y - inH * L.scale, inW * L.scale,
        inH * L.scale);
    canvas.strokePath();

    // Деление подвала на 3 помещения: 1 — котельная, 2 — кладовая, 3 —
    // хозблок. Простое вертикальное деление.
    final divider1 = inX + inW * 0.35;
    final divider2 = inX + inW * 0.7;
    canvas.setLineWidth(0.5);
    final d1Top = pp(divider1, inY);
    final d1Bot = pp(divider1, inY + inH);
    canvas.drawLine(d1Top.x, d1Top.y, d1Bot.x, d1Bot.y);
    canvas.strokePath();
    final d2Top = pp(divider2, inY);
    final d2Bot = pp(divider2, inY + inH);
    canvas.drawLine(d2Top.x, d2Top.y, d2Bot.x, d2Bot.y);
    canvas.strokePath();

    canvas.setFillColor(PdfColors.black);
    final lc1 = pp(inX + (divider1 - inX) / 2, inY + inH / 2);
    _drawCenteredText(canvas, font, 8, '1. Котельная', lc1.x, lc1.y);
    _drawCenteredText(canvas, font, 7,
        '8,0 м² · СП 60.13330', lc1.x, lc1.y - 9);
    final lc2 = pp((divider1 + divider2) / 2, inY + inH / 2);
    _drawCenteredText(canvas, font, 8, '2. Кладовая', lc2.x, lc2.y);
    _drawCenteredText(canvas, font, 7,
        '${(inW * (divider2 - divider1) / inW * inH * 0.5).toStringAsFixed(1)} м²',
        lc2.x, lc2.y - 9);
    final lc3 = pp(divider2 + (inX + inW - divider2) / 2, inY + inH / 2);
    _drawCenteredText(canvas, font, 8, '3. Хозяйственный блок',
        lc3.x, lc3.y);
    _drawCenteredText(canvas, font, 7,
        'погреб / гардероб', lc3.x, lc3.y - 9);

    // Лестница в подвал — двухмаршевая в углу первого помещения
    // (котельной). Ширина марша 1,0 м (СП 54.13330 п. 4.2.10),
    // 14 поступей по 178 мм для этажа 2,5–2,8 м (СП 55.13330).
    final stairsX = inX + 0.2;
    final stairsY = inY + 0.2;
    final stairsW = 1.0;
    final stairsH = 2.6; // 14 поступей × 0.18 ≈ 2.5 м, плюс площадка
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    final st = pp(stairsX, stairsY);
    canvas.drawRect(
        st.x, st.y - stairsH * L.scale, stairsW * L.scale, stairsH * L.scale);
    canvas.strokePath();
    // Поступи (14 шт.) — горизонтальные линии тоньше.
    canvas.setLineWidth(0.35);
    final steps = 14;
    for (int i = 1; i < steps; i++) {
      final yStep = stairsY + (stairsH * i / steps);
      final s1 = pp(stairsX, yStep);
      final s2 = pp(stairsX + stairsW, yStep);
      canvas.drawLine(s1.x, s1.y, s2.x, s2.y);
      canvas.strokePath();
    }
    // Линия обрыва марша (поперёк, по середине, ГОСТ 21.501-2018).
    canvas.setLineWidth(0.6);
    final cutoffY = stairsY + stairsH * 0.5;
    final cf1 = pp(stairsX - 0.05, cutoffY - 0.08);
    final cf2 = pp(stairsX + stairsW + 0.05, cutoffY + 0.08);
    canvas.drawLine(cf1.x, cf1.y, cf2.x, cf2.y);
    canvas.strokePath();
    // Стрелка подъёма от низа к верху, с наконечником-треугольником.
    final arr1 = pp(stairsX + stairsW / 2, stairsY + stairsH * 0.95);
    final arr2 = pp(stairsX + stairsW / 2, stairsY + stairsH * 0.05);
    canvas.setLineWidth(0.6);
    canvas.drawLine(arr1.x, arr1.y, arr2.x, arr2.y);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.moveTo(arr2.x, arr2.y);
    canvas.lineTo(arr2.x - 2.5, arr2.y - 5);
    canvas.lineTo(arr2.x + 2.5, arr2.y - 5);
    canvas.lineTo(arr2.x, arr2.y);
    canvas.fillPath();
    // Подпись «14×178» (поступей × подъём, мм) — стандарт ГОСТ.
    final lblP = pp(stairsX + stairsW + 0.1, stairsY + stairsH * 0.5);
    _drawText(canvas, font, 7, 'Лестница 14×178', lblP.x, lblP.y);
    _drawText(canvas, font, 7, 'из подвала', lblP.x, lblP.y - 8);

    // Текстовая легенда справа.
    canvas.setFillColor(PdfColors.black);
    final tx = L.sidebarLeft;
    var ty = L.oy + L.planH - 10;
    _drawText(canvas, font, 9, 'Условия', tx, ty, bold: true);
    ty -= 14;
    // Цифры в легенде синхронизированы с реальными параметрами
    // проекта: высота подвала = walls.height (или fallback 2.5 м),
    // толщина стены = walls.thickness (или 400 мм).
    final floorElev = -basementHeightM;
    final lines = <String>[
      'Отметка чистого пола: ${floorElev.toStringAsFixed(3)} м',
      'Высота этажа: ${basementHeightM.toStringAsFixed(2)} м',
      'Стены: монолитный ж/б, ${wallThickMm.toStringAsFixed(0)} мм',
      '   класс бетона B25 W6 F100',
      'Гидроизоляция стен:',
      '   обмазка цементно-полимерная',
      'Утепление: ЭППС 100 мм',
      'Полы: бетон М200, h = 80 мм',
      '   с гидроизоляцией ТехноЭласт',
      'Вентиляция: естественная',
      '   через продухи Ø 250 мм',
      'Освещение: искусственное',
      '   (СП 256.1325800)',
      '',
      'Помещения:',
      '   1 — Котельная (СП 60.13330)',
      '   2 — Кладовая',
      '   3 — Хозблок (погреб)',
      '',
      'Соответствие:',
      '   СП 54.13330.2022 п. 6.5',
      '   СП 50.13330.2024',
    ];
    for (final l in lines) {
      _drawText(canvas, font, 7, l, tx, ty);
      ty -= 11;
    }
  }

  // ═════════════════════ ПЛАН ТЕХНИЧЕСКОГО ПОДПОЛЬЯ ═════════════════════
  static void _paintSubfloor(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
    HouseProject project,
  ) {
    final L = _layout(size, plan, rightSidebar: 230);
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Контур цоколя.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    final tl = pp(0, 0);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.strokePath();

    // Опоры — точки опор фундамента (сваи / столбы) по углам и серединам стен.
    final type = project.foundation.type;
    final supports = <_Pt>[];
    if (type == FoundationType.pile ||
        type == FoundationType.pileWithGrillage ||
        type == FoundationType.columnar) {
      // Раскладка 3×3 минимум.
      const stepX = 3.0; // м
      const stepY = 3.0;
      final nx = math.max(2, (plan.width / stepX).round() + 1);
      final ny = math.max(2, (plan.height / stepY).round() + 1);
      for (int i = 0; i < nx; i++) {
        for (int j = 0; j < ny; j++) {
          final x = plan.width * i / (nx - 1);
          final y = plan.height * j / (ny - 1);
          supports.add(_Pt(x, y));
        }
      }
    }

    canvas.setFillColor(PdfColors.grey400);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    for (final s in supports) {
      final p = pp(s.x, s.y);
      final r = type == FoundationType.columnar ? 7.0 : 4.5;
      canvas.drawEllipse(p.x, p.y, r, r);
      canvas.fillPath();
      canvas.drawEllipse(p.x, p.y, r, r);
      canvas.strokePath();
    }

    // Продухи в наружных стенах — каждые 3 м. По СП 50.13330.2024.
    canvas.setStrokeColor(PdfColors.blue700);
    canvas.setLineWidth(0.6);
    final ventStep = 3.0;
    final ventCount = (plan.width / ventStep).floor();
    for (int i = 0; i < ventCount; i++) {
      final mx = ventStep * (i + 0.5);
      // Низ стены (внешний).
      final v1 = pp(mx - 0.15, 0);
      final v2 = pp(mx + 0.15, 0);
      canvas.drawLine(v1.x, v1.y - 4, v2.x, v2.y - 4);
      canvas.strokePath();
      canvas.drawLine(v1.x, v1.y, v2.x, v2.y);
      canvas.strokePath();
      // Верх стены.
      final v3 = pp(mx - 0.15, plan.height);
      final v4 = pp(mx + 0.15, plan.height);
      canvas.drawLine(v3.x, v3.y, v4.x, v4.y);
      canvas.strokePath();
      canvas.drawLine(v3.x, v3.y + 4, v4.x, v4.y + 4);
      canvas.strokePath();
    }

    // Люк доступа.
    final hatchX = 0.5;
    final hatchY = 0.5;
    canvas.setStrokeColor(PdfColors.red700);
    canvas.setLineWidth(0.8);
    final h1 = pp(hatchX, hatchY);
    final hatchSize = 0.8 * L.scale;
    canvas.drawRect(h1.x, h1.y - hatchSize, hatchSize, hatchSize);
    canvas.strokePath();
    final h2 = pp(hatchX + 0.8, hatchY);
    canvas.drawLine(h1.x, h1.y, h2.x, h2.y - hatchSize);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.red700);
    _drawText(canvas, font, 6.5, 'Л-1', h1.x + 2, h1.y - hatchSize / 2 - 2);

    // Северная стрелка.
    canvas.setFillColor(PdfColors.black);

    // Легенда.
    final tx = L.sidebarLeft;
    var ty = L.oy + L.planH - 10;
    _drawText(canvas, font, 9, 'Условия', tx, ty, bold: true);
    ty -= 14;
    final lines = <String>[
      'Отметка низа техподполья:',
      '   −0.500 м (от ±0.000)',
      'Высота: 0,8 — 1,2 м',
      'Тип фундамента: ${type?.title ?? '—'}',
      '',
      'Опоры:',
      '   точки = сваи / столбы',
      '   шаг ≈ 3000 мм',
      '',
      'Вентиляция (СП 50.13330):',
      '   продухи ⌀250 мм через 3 м,',
      '   с двух противоп. стен',
      '   общая площадь ≥ 1/400 от',
      '   площади подполья',
      '',
      'Гидроизоляция: рулонная (2 слоя)',
      'Грунт под подпольем: ПГС',
      '   с уплотнением до 1,65 т/м³',
      '',
      'Доступ: Л-1 — люк 800×800 мм',
      'из помещения 1-го этажа.',
      '',
      'Соответствие:',
      '   СП 24.13330.2021',
      '   СП 50.13330.2024',
    ];
    for (final l in lines) {
      _drawText(canvas, font, 7, l, tx, ty);
      ty -= 11;
    }
  }

  // ════════════════════════════ ПЛАН ЧЕРДАКА ════════════════════════════
  static void _paintAttic(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan topPlan,
    PdfFont font,
    HouseProject project,
  ) {
    final L = _layout(size, topPlan, rightSidebar: 230);
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Контур чердака — внутренний контур стен верхнего этажа.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    final tl = pp(0, 0);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.strokePath();

    // Конёк (для двускатной/вальмовой) — горизонтально по центру.
    final ridgeY = topPlan.height / 2;
    canvas.setStrokeColor(PdfColors.red700);
    canvas.setLineWidth(1.0);
    final r1 = pp(0, ridgeY);
    final r2 = pp(topPlan.width, ridgeY);
    canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.red700);
    _drawText(canvas, font, 7, 'Конёк', r1.x + 6, r1.y + 4);

    // Скаты — пунктир, направление уклона вниз.
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    final dashCount = 12;
    for (int i = 0; i < dashCount; i++) {
      final t = i / dashCount;
      final mx = topPlan.width * t;
      // Север (выше конька): стрелка вниз к нижней грани.
      final n1 = pp(mx, ridgeY);
      final n2 = pp(mx, 0);
      _drawDashedLine(canvas, n1.x, n1.y, n2.x, n2.y, 4);
      // Юг (ниже конька): стрелка вниз.
      final s1 = pp(mx, ridgeY);
      final s2 = pp(mx, topPlan.height);
      _drawDashedLine(canvas, s1.x, s1.y, s2.x, s2.y, 4);
    }

    // Стрелки уклона (по 1 на скат).
    final slope = project.roof.slopeAngle ?? 30;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    final slopeText = '${slope.toStringAsFixed(0)}°';
    final aN1 = pp(topPlan.width * 0.5, ridgeY + 0.5);
    final aN2 = pp(topPlan.width * 0.5, 0.4);
    canvas.drawLine(aN1.x, aN1.y, aN2.x, aN2.y);
    canvas.strokePath();
    // Стрелка вниз
    canvas.drawLine(aN2.x - 3, aN2.y + 4, aN2.x, aN2.y);
    canvas.strokePath();
    canvas.drawLine(aN2.x + 3, aN2.y + 4, aN2.x, aN2.y);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 7, slopeText, aN2.x + 4, aN2.y + 4);
    final aS1 = pp(topPlan.width * 0.5, ridgeY - 0.5);
    final aS2 = pp(topPlan.width * 0.5, topPlan.height - 0.4);
    canvas.drawLine(aS1.x, aS1.y, aS2.x, aS2.y);
    canvas.strokePath();
    canvas.drawLine(aS2.x - 3, aS2.y - 4, aS2.x, aS2.y);
    canvas.strokePath();
    canvas.drawLine(aS2.x + 3, aS2.y - 4, aS2.x, aS2.y);
    canvas.strokePath();
    _drawText(canvas, font, 7, slopeText, aS2.x + 4, aS2.y - 8);

    // Люк доступа.
    canvas.setStrokeColor(PdfColors.blue700);
    canvas.setLineWidth(0.8);
    final hatchX = 1.0;
    final hatchY = 1.0;
    final hatchSize = 0.7 * L.scale;
    final hp = pp(hatchX, hatchY);
    canvas.drawRect(hp.x, hp.y - hatchSize, hatchSize, hatchSize);
    canvas.strokePath();
    canvas.drawLine(
        hp.x, hp.y, hp.x + hatchSize, hp.y - hatchSize);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.blue700);
    _drawText(canvas, font, 6.5, 'Л-1', hp.x + 1, hp.y - hatchSize - 8);

    // Вентиляционные выходы — кружки по краю конька.
    canvas.setFillColor(PdfColors.grey400);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    for (int i = 1; i <= 2; i++) {
      final vx = pp(topPlan.width * (i / 3), ridgeY);
      canvas.drawEllipse(vx.x, vx.y, 4, 4);
      canvas.fillPath();
      canvas.drawEllipse(vx.x, vx.y, 4, 4);
      canvas.strokePath();
    }
    canvas.setFillColor(PdfColors.black);
    _drawText(
        canvas, font, 6.5, 'В1, В2 — вентвыходы', r1.x + 6, r1.y - 6);

    // Легенда.
    final tx = L.sidebarLeft;
    var ty = L.oy + L.planH - 10;
    _drawText(canvas, font, 9, 'Условия', tx, ty, bold: true);
    ty -= 14;
    // §27.2: высота этажа теперь берётся из project.walls.height,
    // как и на разрезах/фасадах. Раньше было хардкодное 2.7 м, что
    // не соответствовало пользовательскому выбору.
    final floorH = project.walls.height ??
        project.staircase.floorHeight ?? 2.8;
    final atticFloorElev = floorH * (project.brief.floors ?? 1);
    final lines = <String>[
      'Отметка пола чердака:',
      '   ${atticFloorElev.toStringAsFixed(3)} м',
      'Высота в коньке: 1,8 м',
      'Высота у карниза: 0,5 м',
      '',
      'Конструкции:',
      '   пол — балки перекрытия',
      '      (см. КД-1) с заполнением',
      '      минватой 200 мм',
      '   стены чердака — фронтоны',
      '      по выбранному материалу',
      '   кровля — стропильная система',
      '      (см. КД-2)',
      '',
      'Утеплитель чердачного перекр.:',
      '   минвата 200 мм + пароизол.',
      '   снизу + ветрозащита сверху',
      '',
      'Вентиляция чердака:',
      '   через слуховые окна и',
      '   коньковые продухи',
      '   (СП 17.13330)',
      '',
      'Доступ: Л-1 — складная',
      '   лестница 700×1200 мм',
    ];
    for (final l in lines) {
      _drawText(canvas, font, 7, l, tx, ty);
      ty -= 11;
    }
  }

  // ═══════════════════════ СХЕМА БАЛОК ПЕРЕКРЫТИЯ ═══════════════════════
  static void _paintBeams(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
    HouseProject project,
  ) {
    final L = _layout(size, plan, rightSidebar: 230);
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Контур пятна.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    final tl = pp(0, 0);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.strokePath();

    // Тип перекрытия — определяет шаг и материал балок:
    //   wood_beams (хвоя 1с)        → шаг 0.6 м, СП 64.13330.2017
    //   metal_beams (двутавр 20Б1)  → шаг 0.8 м, СП 16.13330.2017
    //   precast (плита ПК)          → шаг 1.2 м (ширина плиты)
    //   monolith                    → шаг 0.5 м (ось рёбер) — условно
    final floorType = project.floorSlabs.type ?? 'wood_beams';
    final double step;
    final PdfColor beamColor;
    switch (floorType) {
      case 'metal_beams':
        step = 0.8;
        beamColor = PdfColors.blueGrey700;
        break;
      case 'precast':
        step = 1.2;
        beamColor = PdfColors.grey700;
        break;
      case 'monolith':
        step = 0.5;
        beamColor = PdfColors.blueGrey900;
        break;
      case 'wood_beams':
      default:
        step = 0.6;
        beamColor = PdfColors.brown700;
        break;
    }

    // Балки укладываются перпендикулярно длинным стенам, т.е.
    // параллельно короткой стороне здания.
    final shortSpanM = math.min(plan.width, plan.height);
    final longSpanM = math.max(plan.width, plan.height);
    final shortSideIsWidth = plan.width <= plan.height;
    final beams = <_LineSeg>[];
    final beamCount = (longSpanM / step).floor() - 1;

    // Визуализация перекрытия меняется в зависимости от выбранного
    // пользователем типа (project.floorSlabs.type):
    //   • wood_beams / metal_beams — отдельные тонкие линии-балки;
    //   • precast — широкие плиты ПК шириной 1.2 м, со стыками;
    //   • monolith — сплошное серое поле с диагональной штриховкой.
    if (floorType == 'monolith') {
      // Монолит — заливаем поле плана и наносим штриховку 45°.
      final origin = pp(0, 0);
      final left = origin.x;
      final top = origin.y;
      canvas.setColor(const PdfColor(0.93, 0.93, 0.95));
      canvas.drawRect(left, top - L.planH, L.planW, L.planH);
      canvas.fillPath();
      canvas.setStrokeColor(beamColor);
      canvas.setLineWidth(0.4);
      const hatchStep = 12.0;
      for (var d = -L.planH; d < L.planW; d += hatchStep) {
        final x1 = left + math.max(0.0, d);
        final y1 = top - math.max(0.0, -d);
        final x2 = left + math.min(L.planW, d + L.planH);
        final y2 = top - L.planH + math.max(0.0, L.planH - (d - 0));
        canvas.drawLine(x1, y1, x2, y2.clamp(top - L.planH, top));
      }
      canvas.strokePath();
      // Условные оси рёбер (ориентация — вдоль короткой стороны).
      canvas.setStrokeColor(beamColor);
      canvas.setLineWidth(0.7);
      if (shortSideIsWidth) {
        for (int i = 1; i <= beamCount; i++) {
          final my = step * i;
          final p1 = pp(0.1, my);
          final p2 = pp(plan.width - 0.1, my);
          _drawDashedLine(canvas, p1.x, p1.y, p2.x, p2.y, 5);
          beams.add(_LineSeg(p1.x, p1.y, p2.x, p2.y));
        }
      } else {
        for (int i = 1; i <= beamCount; i++) {
          final mx = step * i;
          final p1 = pp(mx, 0.1);
          final p2 = pp(mx, plan.height - 0.1);
          _drawDashedLine(canvas, p1.x, p1.y, p2.x, p2.y, 5);
          beams.add(_LineSeg(p1.x, p1.y, p2.x, p2.y));
        }
      }
    } else if (floorType == 'precast') {
      // Плиты пустотного настила: параллельные полосы шириной step.
      // Стыки отмечаются короткими поперечными засечками.
      canvas.setStrokeColor(beamColor);
      canvas.setLineWidth(0.5);
      canvas.setFillColor(const PdfColor(0.95, 0.95, 0.95));
      if (shortSideIsWidth) {
        for (int i = 0; i < beamCount + 1; i++) {
          final my = step * i;
          final p1 = pp(0.0, my);
          final p2 = pp(plan.width, my + step);
          final rectX = math.min(p1.x, p2.x);
          final rectY = math.min(p1.y, p2.y);
          final rectW = (p2.x - p1.x).abs();
          final rectH = (p2.y - p1.y).abs();
          canvas.drawRect(rectX, rectY, rectW, rectH);
          canvas.fillPath();
          canvas.drawRect(rectX, rectY, rectW, rectH);
          canvas.strokePath();
          if (i > 0) {
            beams.add(_LineSeg(p1.x, p1.y, p2.x, p1.y));
          }
        }
      } else {
        for (int i = 0; i < beamCount + 1; i++) {
          final mx = step * i;
          final p1 = pp(mx, 0.0);
          final p2 = pp(mx + step, plan.height);
          final rectX = math.min(p1.x, p2.x);
          final rectY = math.min(p1.y, p2.y);
          final rectW = (p2.x - p1.x).abs();
          final rectH = (p2.y - p1.y).abs();
          canvas.drawRect(rectX, rectY, rectW, rectH);
          canvas.fillPath();
          canvas.drawRect(rectX, rectY, rectW, rectH);
          canvas.strokePath();
          if (i > 0) {
            beams.add(_LineSeg(p1.x, p1.y, p1.x, p2.y));
          }
        }
      }
    } else {
      // wood_beams / metal_beams — обычные одиночные балки.
      canvas.setStrokeColor(beamColor);
      canvas.setLineWidth(1.6);
      if (shortSideIsWidth) {
        for (int i = 1; i <= beamCount; i++) {
          final my = step * i;
          final p1 = pp(0.1, my);
          final p2 = pp(plan.width - 0.1, my);
          canvas.drawLine(p1.x, p1.y, p2.x, p2.y);
          canvas.strokePath();
          beams.add(_LineSeg(p1.x, p1.y, p2.x, p2.y));
        }
      } else {
        for (int i = 1; i <= beamCount; i++) {
          final mx = step * i;
          final p1 = pp(mx, 0.1);
          final p2 = pp(mx, plan.height - 0.1);
          canvas.drawLine(p1.x, p1.y, p2.x, p2.y);
          canvas.strokePath();
          beams.add(_LineSeg(p1.x, p1.y, p2.x, p2.y));
        }
      }
    }

    // Маркировка Б-1 на одну выбранную балку.
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.brown700);
    canvas.setLineWidth(0.5);
    if (beams.isNotEmpty) {
      final b = beams[beams.length ~/ 2];
      final mx = (b.x1 + b.x2) / 2;
      final my = (b.y1 + b.y2) / 2;
      _drawCircle(canvas, mx, my, 10, fill: PdfColors.white);
      canvas.setFillColor(PdfColors.brown700);
      _drawCenteredText(canvas, font, 7.5, 'Б-1', mx, my - 2.6);
    }

    // Оси (А-Б по короткой стороне, 1-2 по длинной) и размерные цепи —
    // схема балок должна координироваться с планом этажа и общими
    // чертежами (СП 21.501-2018, ГОСТ 21.501-2018 п. 5.10). Оси
    // размещаем СВЕРХУ (для цифр) и СЛЕВА (для букв) — т.к. снизу/справа
    // мало места до штампа.
    final tlA = pp(0, 0);
    final brC = pp(plan.width, plan.height);
    final planLeft = math.min(tlA.x, brC.x);
    final planRight = math.max(tlA.x, brC.x);
    final planTop = math.max(tlA.y, brC.y);
    final planBottom = math.min(tlA.y, brC.y);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    // Размерная цепь СВЕРХУ — длина по X.
    final dimYTop = planTop + 14;
    canvas.drawLine(planLeft, dimYTop, planRight, dimYTop);
    canvas.strokePath();
    canvas.drawLine(planLeft, dimYTop - 4, planLeft, dimYTop + 4);
    canvas.drawLine(planRight, dimYTop - 4, planRight, dimYTop + 4);
    canvas.strokePath();
    final widthMm = (plan.width * 1000).toStringAsFixed(0);
    _drawCenteredText(canvas, font, 7.5, widthMm,
        (planLeft + planRight) / 2, dimYTop + 4);
    // Размерная цепь СЛЕВА — высота по Y.
    final dimXLeft = planLeft - 14;
    canvas.drawLine(dimXLeft, planBottom, dimXLeft, planTop);
    canvas.strokePath();
    canvas.drawLine(dimXLeft - 4, planBottom, dimXLeft + 4, planBottom);
    canvas.drawLine(dimXLeft - 4, planTop, dimXLeft + 4, planTop);
    canvas.strokePath();
    final heightMm = (plan.height * 1000).toStringAsFixed(0);
    _drawCenteredText(canvas, font, 7.5, heightMm,
        dimXLeft - 14, (planBottom + planTop) / 2);
    // Кружки осей — СВЕРХУ 1 / 2 и СЛЕВА А / Б.
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.black);
    const axisR = 7.0;
    final axisYTop = dimYTop + 22;
    canvas.drawLine(planLeft, dimYTop, planLeft, axisYTop - axisR);
    canvas.drawLine(planRight, dimYTop, planRight, axisYTop - axisR);
    canvas.strokePath();
    _drawCircle(canvas, planLeft, axisYTop, axisR, fill: PdfColors.white);
    _drawCircle(canvas, planRight, axisYTop, axisR, fill: PdfColors.white);
    canvas.setFillColor(PdfColors.black);
    _drawCenteredText(canvas, font, 8, '1', planLeft, axisYTop - 2.7);
    _drawCenteredText(canvas, font, 8, '2', planRight, axisYTop - 2.7);
    // Слева — буквы А / Б.
    final axisXLeft = dimXLeft - 22;
    canvas.setFillColor(PdfColors.white);
    canvas.drawLine(dimXLeft, planBottom, axisXLeft + axisR, planBottom);
    canvas.drawLine(dimXLeft, planTop, axisXLeft + axisR, planTop);
    canvas.strokePath();
    _drawCircle(canvas, axisXLeft, planBottom, axisR,
        fill: PdfColors.white);
    _drawCircle(canvas, axisXLeft, planTop, axisR, fill: PdfColors.white);
    canvas.setFillColor(PdfColors.black);
    _drawCenteredText(canvas, font, 8, 'А', axisXLeft, planTop - 2.7);
    _drawCenteredText(canvas, font, 8, 'Б', axisXLeft, planBottom - 2.7);

    // Шаг балок — короткая размерная цепь у первых двух балок (показывает
    // одинаковое расстояние, остальные обозначаются «и далее по 600 мм»).
    if (beamCount >= 2 && beams.length >= 2) {
      canvas.setStrokeColor(PdfColors.grey700);
      canvas.setLineWidth(0.3);
      final b0 = beams[0];
      final b1 = beams[1];
      if (shortSideIsWidth) {
        // Балки горизонтальные: шаг по Y.
        final y0 = b0.y1;
        final y1 = b1.y1;
        final dimX = math.max(b0.x1, b0.x2) + 12;
        canvas.drawLine(dimX, y0, dimX, y1);
        canvas.strokePath();
        canvas.drawLine(dimX - 3, y0, dimX + 3, y0);
        canvas.drawLine(dimX - 3, y1, dimX + 3, y1);
        canvas.strokePath();
        canvas.setFillColor(PdfColors.grey700);
        _drawText(canvas, font, 6.5, '${(step * 1000).toStringAsFixed(0)}',
            dimX + 4, (y0 + y1) / 2 - 3);
      } else {
        final x0 = b0.x1;
        final x1 = b1.x1;
        final dimY = math.min(b0.y1, b0.y2) - 12;
        canvas.drawLine(x0, dimY, x1, dimY);
        canvas.strokePath();
        canvas.drawLine(x0, dimY - 3, x0, dimY + 3);
        canvas.drawLine(x1, dimY - 3, x1, dimY + 3);
        canvas.strokePath();
        canvas.setFillColor(PdfColors.grey700);
        _drawCenteredText(canvas, font, 6.5,
            '${(step * 1000).toStringAsFixed(0)}', (x0 + x1) / 2, dimY - 8);
      }
      canvas.setFillColor(PdfColors.black);
    }

    // Опирания на стены — кружки на концах балок.
    canvas.setFillColor(PdfColors.black);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    final supports = <_Pt>[];
    if (shortSideIsWidth) {
      for (int i = 1; i <= beamCount; i++) {
        final my = step * i;
        supports.add(_Pt(0, my));
        supports.add(_Pt(plan.width, my));
      }
    } else {
      for (int i = 1; i <= beamCount; i++) {
        final mx = step * i;
        supports.add(_Pt(mx, 0));
        supports.add(_Pt(mx, plan.height));
      }
    }
    for (final s in supports) {
      final p = pp(s.x, s.y);
      canvas.drawEllipse(p.x, p.y, 1.4, 1.4);
      canvas.fillPath();
    }

    // Сечение балки — зависит от выбранного типа перекрытия и
    // фактического пролёта (синхронизируется с floorSlabs.type на
    // этапе «Перекрытия»).
    String beamSection;
    String beamNote;
    if (floorType == 'metal_beams') {
      // Прокатные двутавры по СП 16.13330.2017 / ГОСТ Р 57837-2017.
      if (shortSpanM <= 3.0) {
        beamSection = 'I 16Б1';
        beamNote = 'двутавр горячекатаный';
      } else if (shortSpanM <= 4.5) {
        beamSection = 'I 20Б1';
        beamNote = 'двутавр горячекатаный';
      } else if (shortSpanM <= 6.0) {
        beamSection = 'I 25Б1';
        beamNote = 'двутавр горячекатаный';
      } else {
        beamSection = 'I 30Б1';
        beamNote = 'двутавр / при > 7 м — ферма';
      }
    } else if (floorType == 'precast') {
      // Плиты пустотного настила ПК (ГОСТ 9561-2016).
      final lenMm = (shortSpanM * 100).round() * 10;
      beamSection = 'ПК ${lenMm}-12';
      beamNote = 'пустотная плита';
    } else if (floorType == 'monolith') {
      // Монолит — рёбра/арматура (для условной схемы).
      final hMm = project.floorSlabs.thickness?.toStringAsFixed(0) ?? '200';
      beamSection = 'Ребро 200×$hMm';
      beamNote = 'монолит ж/б B25';
    } else {
      // wood_beams — хвоя 1с (СП 64.13330.2017).
      if (shortSpanM <= 3.0) {
        beamSection = 'Ц 50×150';
        beamNote = 'хвоя 1с';
      } else if (shortSpanM <= 4.0) {
        beamSection = 'Ц 50×200';
        beamNote = 'хвоя 1с';
      } else if (shortSpanM <= 5.0) {
        beamSection = 'Ц 100×200';
        beamNote = 'хвоя 1с';
      } else {
        beamSection = 'LVL 80×240';
        beamNote = 'LVL/двутавр';
      }
    }
    final beamLengthMm = (shortSpanM * 1000).toStringAsFixed(0);
    final perimeterM = (plan.width + plan.height) * 2;
    final mauerlatPieces = (perimeterM / 3.0).ceil();

    // Спецификация перекрытий (название по ГОСТ 21.501-2018, ф. 7
    // — указывается состав перекрытия, а не только балки).
    final beamsTableBottomY = _drawWrappedTable(
      canvas,
      font,
      L.sidebarLeft,
      L.oy + L.planH - 8,
      L.sidebarWidth,
      title: 'Спецификация перекрытий',
      headers: const ['Марка', 'Сечение', 'Длина, мм', 'Кол.', 'Прим.'],
      colWidths: const [30, 50, 50, 26, 56],
      rows: [
        ['Б-1', beamSection, beamLengthMm, '$beamCount', beamNote],
        ['Б-2', beamSection, 'L = пролёт', '4', 'над проёмами'],
        ['М-1', 'Ц 100×100', '3000', '$mauerlatPieces', 'мауэрлат'],
      ],
      headerHeight: 18,
      minRowHeight: 14,
      lineHeight: 8,
      bodyFontSize: 6.5,
      headerFontSize: 7.0,
      wrapColumns: const {1, 2, 4},
    );

    // Примечания — строго ниже фактической нижней Y таблицы спецификации,
    // чтобы при росте таблицы (переносы текста) не было наложения.
    final tx = L.sidebarLeft;
    var ty = beamsTableBottomY - 18;
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, 'Примечания', tx, ty, bold: true);
    ty -= 12;
    final notes = <String>[
      '1. Шаг балок — 600 мм по СП 64.13330.',
      '2. Сечение $beamSection принято по расчёту',
      '   для пролёта L = ${shortSpanM.toStringAsFixed(2)} м.',
      '3. Опирание на стены — через мауэрлат',
      '   М-1 (брус 100×100 мм).',
      '4. Антисептик «Senezh» (ГОСТ Р 53292) +',
      '   огнезащита I группы.',
      '5. Конструкция класса К0 (СП 2.13130).',
      '6. Подкладка из 2-х слоёв рубероида',
      '   между балкой и стеной.',
    ];
    for (final n in notes) {
      _drawText(canvas, font, 7, n, tx, ty);
      ty -= 11;
    }
  }

  // ════════════════════════════ СХЕМА СТРОПИЛ ═══════════════════════════
  // ────────── СХЕМА СТРОПИЛ — НОВАЯ ВЕРСИЯ С 3 ПРОЕКЦИЯМИ + ЛЕГЕНДОЙ ──────
  /// Отрисовывает лист КД-2 «Схема деревянных наслонных стропил» по
  /// образцу типовой серии: Разрез 1-1, Разрез 2-2, План стропил
  /// и 17-позиционная легенда справа. Геометрия и сечения берутся из
  /// проекта (`RafterSectionPicker`, `project.roof.slopeAngle`,
  /// `topPlan` пятно), поэтому чертёж согласован с расчётами и
  /// другими листами комплекта.
  static void _paintRaftersScheme(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan topPlan,
    PdfFont font,
    HouseProject project,
  ) {
    final roofType = (project.roof.type ?? 'gable').toLowerCase();
    final isFlat = roofType.contains('flat') || roofType.contains('плос');
    if (isFlat) {
      // Для плоской кровли — упрощённая схема: контур + размеры
      // (подробный наслонный каркас не требуется).
      _paintRafters(canvas, size, topPlan, font, project);
      return;
    }
    final isHip = roofType.contains('hip') || roofType.contains('вальм');

    final pick = RafterSectionPicker.pickFor(project);
    final slopeDeg = project.roof.slopeAngle ?? 30.0;
    final slopeRad = slopeDeg * math.pi / 180.0;
    final ridgeAlongX = topPlan.width >= topPlan.height;
    final spanM = ridgeAlongX ? topPlan.height : topPlan.width;
    final ridgeLengthM = ridgeAlongX ? topPlan.width : topPlan.height;
    final raftersStep =
        RafterSectionPicker.rafterStep(project.roof.roofingMaterial);

    // ── РАЗМЕТКА ЛИСТА ────────────────────────────────────────────────
    // Делим доступную область на 4 квадранта:
    //   [Разрез 1-1] [Разрез 2-2]
    //   [План стропил     ] [Легенда]
    final w = size.x;
    final h = size.y;
    const gap = 12.0;
    final legendW = 260.0;
    final topRowH = (h - gap) * 0.46;
    final botRowH = (h - gap) - topRowH;
    final secLeftW = (w - legendW - gap) * 0.55;
    final secRightW = (w - legendW - gap) - secLeftW - gap;
    final panel11 = _Rect(0, h - topRowH, secLeftW, topRowH);
    final panel22 = _Rect(secLeftW + gap, h - topRowH, secRightW, topRowH);
    final panelPlan = _Rect(0, 0, w - legendW - gap, botRowH);
    final panelLegend = _Rect(w - legendW, 0, legendW, h);

    // Рамка для легенды + заголовок «Условные обозначения».
    _drawPanelFrame(canvas, panelLegend, hairline: true);
    _drawRaftersLegend(canvas, font, panelLegend, isHip: isHip);

    // ── РАЗРЕЗ 1-1 (поперечный) ─────────────────────────────────────
    _drawPanelFrame(canvas, panel11, hairline: true);
    _drawCenteredText(canvas, font, 9.5, 'Разрез 1-1',
        panel11.cx, panel11.top - 12);
    _drawSection11(
      canvas,
      font,
      panel11.shrink(top: 18, bottom: 6, left: 14, right: 14),
      spanM: spanM,
      slopeRad: slopeRad,
      slopeDeg: slopeDeg,
      pick: pick,
    );

    // ── РАЗРЕЗ 2-2 (продольный, торец вальмы) ───────────────────────
    _drawPanelFrame(canvas, panel22, hairline: true);
    _drawCenteredText(canvas, font, 9.5, 'Разрез 2-2',
        panel22.cx, panel22.top - 12);
    _drawSection22(
      canvas,
      font,
      panel22.shrink(top: 18, bottom: 6, left: 14, right: 14),
      hipSpanM: ridgeAlongX ? topPlan.height : topPlan.width,
      slopeRad: slopeRad,
      slopeDeg: slopeDeg,
      pick: pick,
      isHip: isHip,
    );

    // ── ПЛАН СТРОПИЛ ─────────────────────────────────────────────────
    _drawPanelFrame(canvas, panelPlan, hairline: true);
    _drawCenteredText(canvas, font, 9.5, 'План стропил',
        panelPlan.cx, panelPlan.top - 12);
    _drawRaftersPlanView(
      canvas,
      font,
      panelPlan.shrink(top: 18, bottom: 8, left: 14, right: 14),
      topPlan: topPlan,
      isHip: isHip,
      ridgeAlongX: ridgeAlongX,
      raftersStep: raftersStep,
      pick: pick,
      spanM: spanM,
      ridgeLengthM: ridgeLengthM,
    );
  }

  /// Отрисовка Разреза 1-1 (поперечный): стропильный треугольник
  /// с центральным прогоном, стойкой, подкосами и ригелем-затяжкой.
  static void _drawSection11(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required double spanM,
    required double slopeRad,
    required double slopeDeg,
    required RafterPickResult pick,
  }) {
    // Высота конька в метрах = (span / 2) * tan(slope).
    final apexHm = (spanM / 2) * math.tan(slopeRad);
    final totalH = apexHm + 0.4; // + чердачное перекрытие
    final scaleX = (r.w * 0.9) / spanM;
    final scaleY = (r.h * 0.78) / totalH;
    final s = math.min(scaleX, scaleY);
    // Центрирование по нижней линии.
    final cx = r.cx;
    final baseY = r.top - r.h * 0.92; // PDF Y-up; baseY — низ чертежа
    final wallTopY = baseY + 0.4 * s;
    final apexY = wallTopY + apexHm * s;
    final leftX = cx - (spanM / 2) * s;
    final rightX = cx + (spanM / 2) * s;
    final apexX = cx;

    canvas.setStrokeColor(PdfColors.black);

    // 17 — верхний уровень чердачного перекрытия (горизонтальная линия снизу).
    canvas.setLineWidth(0.5);
    canvas.drawLine(leftX - 30, baseY, rightX + 30, baseY);
    canvas.strokePath();
    // Штриховка перекрытия.
    for (double xx = leftX - 24; xx < rightX + 30; xx += 6) {
      canvas.drawLine(xx, baseY, xx + 4, baseY - 4);
    }
    canvas.strokePath();

    // 15 — наружные несущие стены (две прямоугольные колонны по краям).
    canvas.setLineWidth(0.9);
    final wallW = 18.0;
    canvas.drawRect(leftX - wallW / 2, baseY, wallW, wallTopY - baseY);
    canvas.strokePath();
    canvas.drawRect(rightX - wallW / 2, baseY, wallW, wallTopY - baseY);
    canvas.strokePath();
    // 16 — внутренняя несущая стена под центральной стойкой.
    canvas.drawRect(apexX - wallW / 2, baseY,
        wallW, wallTopY - baseY);
    canvas.strokePath();

    // 1 — мауэрлат (узкий прямоугольник на наружных стенах).
    canvas.setFillColor(PdfColors.grey300);
    final mauerW = wallW + 4;
    final mauerH = 5.0;
    canvas.drawRect(leftX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.fillPath();
    canvas.drawRect(leftX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.strokePath();
    canvas.drawRect(rightX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.fillPath();
    canvas.drawRect(rightX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.strokePath();

    // 2 — лежень под центральной стойкой.
    canvas.drawRect(apexX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.fillPath();
    canvas.drawRect(apexX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.strokePath();

    // 3 — стойка под прогон (центральная вертикальная).
    final postW = 6.0;
    final purlinY = wallTopY + (apexY - wallTopY) * 0.55;
    canvas.setFillColor(PdfColors.brown100);
    canvas.drawRect(apexX - postW / 2, wallTopY + mauerH,
        postW, purlinY - wallTopY - mauerH);
    canvas.fillPath();
    canvas.setLineWidth(0.7);
    canvas.drawRect(apexX - postW / 2, wallTopY + mauerH,
        postW, purlinY - wallTopY - mauerH);
    canvas.strokePath();

    // 12 — стропильные ноги (от конька через мауэрлат к свесу).
    // Свес 500 мм за наружную стену (по СП 17.13330) — продлеваем
    // ось стропилы по уклону за мауэрлат на eaveM·s в плане. 13 —
    // кобылки = эта же продлённая часть стропилы за мауэрлатом.
    final eaveM = 0.5;
    final eaveDX = eaveM * math.cos(slopeRad) * s;
    final eaveDY = eaveM * math.sin(slopeRad) * s;
    final eaveLeftX = leftX - eaveDX;
    final eaveRightX = rightX + eaveDX;
    final eaveLeftY = wallTopY + mauerH - eaveDY;
    final eaveRightY = wallTopY + mauerH - eaveDY;
    canvas.setLineWidth(1.4);
    canvas.drawLine(eaveLeftX, eaveLeftY, apexX, apexY);
    canvas.drawLine(eaveRightX, eaveRightY, apexX, apexY);
    canvas.strokePath();

    // 14 — коньковый брус (точка апекса).
    canvas.setFillColor(PdfColors.white);
    _drawCircle(canvas, apexX, apexY, 4, fill: PdfColors.white);
    canvas.setLineWidth(0.7);
    canvas.drawEllipse(apexX, apexY, 4, 4);
    canvas.strokePath();

    // 5 — прогон под стропилами (горизонтальный над стойкой).
    canvas.setLineWidth(1.2);
    canvas.setFillColor(PdfColors.grey400);
    final purlinW = 28.0;
    final purlinH = 6.0;
    canvas.drawRect(apexX - purlinW / 2, purlinY - purlinH / 2,
        purlinW, purlinH);
    canvas.fillPath();
    canvas.drawRect(apexX - purlinW / 2, purlinY - purlinH / 2,
        purlinW, purlinH);
    canvas.strokePath();

    // 4 — подкосы под стойки (от стойки в обе стороны под 45°).
    canvas.setLineWidth(1.0);
    final brace = 0.35; // длина подкоса в долях полупролёта
    final braceLeftEndX = apexX - (rightX - apexX) * brace;
    final braceRightEndX = apexX + (rightX - apexX) * brace;
    final braceY = wallTopY + mauerH + 4;
    canvas.drawLine(apexX, purlinY - purlinH / 2,
        braceLeftEndX, braceY);
    canvas.drawLine(apexX, purlinY - purlinH / 2,
        braceRightEndX, braceY);
    canvas.strokePath();

    // 8 — ригель-затяжка по подкосам (горизонтальная).
    canvas.drawLine(braceLeftEndX, braceY, braceRightEndX, braceY);
    canvas.strokePath();

    // 6 — распорки под стойки (две короткие горизонтальные у мауэрлата).
    canvas.setLineWidth(0.7);
    canvas.drawLine(leftX + 12, wallTopY + mauerH + 2,
        apexX - postW / 2 - 6, wallTopY + mauerH + 2);
    canvas.drawLine(apexX + postW / 2 + 6, wallTopY + mauerH + 2,
        rightX - 12, wallTopY + mauerH + 2);
    canvas.strokePath();

    // Размерная цепь снизу — пролёт.
    canvas.setLineWidth(0.4);
    final dimY = baseY - 18;
    canvas.drawLine(leftX, dimY, rightX, dimY);
    canvas.drawLine(leftX, dimY - 3, leftX, dimY + 3);
    canvas.drawLine(rightX, dimY - 3, rightX, dimY + 3);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7,
        '${(spanM * 1000).round()}', cx, dimY - 9);

    // Размерная цепь справа — высота конька.
    final dimX = rightX + 22;
    canvas.drawLine(dimX, wallTopY, dimX, apexY);
    canvas.drawLine(dimX - 3, wallTopY, dimX + 3, wallTopY);
    canvas.drawLine(dimX - 3, apexY, dimX + 3, apexY);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${(apexHm * 1000).round()}', dimX + 4,
        (wallTopY + apexY) / 2);

    // Угол ската.
    _drawText(canvas, font, 7, '∠ ${slopeDeg.toStringAsFixed(0)}°',
        leftX + 24, wallTopY + 14);

    // ── ПОЗИЦИИ ИЗ ЛЕГЕНДЫ (кружки с цифрами 1..17) ────────────────
    // 1 — мауэрлат (левый и правый).
    _drawPosCallout(canvas, font, leftX - mauerW / 2, wallTopY + mauerH / 2,
        1, leftX - 28, wallTopY + 6);
    // 2 — лежень под центральной стойкой.
    _drawPosCallout(canvas, font, apexX + mauerW / 2, wallTopY + mauerH / 2,
        2, apexX + 24, wallTopY - 8);
    // 3 — стойка под прогон.
    _drawPosCallout(canvas, font, apexX + postW / 2,
        wallTopY + mauerH + (purlinY - wallTopY - mauerH) * 0.5,
        3, apexX + 28, wallTopY + (purlinY - wallTopY) * 0.4);
    // 4 — подкосы.
    _drawPosCallout(canvas, font, (apexX + braceLeftEndX) / 2,
        (purlinY + braceY) / 2,
        4, (apexX + braceLeftEndX) / 2 - 24,
        (purlinY + braceY) / 2 - 6);
    // 5 — прогон под стойки.
    _drawPosCallout(canvas, font, apexX - purlinW / 2 + 4, purlinY,
        5, apexX - 36, purlinY + 12);
    // 6 — распорки под стойки.
    _drawPosCallout(canvas, font,
        (leftX + 12 + apexX - postW / 2 - 6) / 2,
        wallTopY + mauerH + 2,
        6, (leftX + apexX) / 2 - 12, wallTopY - 12);
    // 8 — ригель-затяжка по подкосам.
    _drawPosCallout(canvas, font, (braceLeftEndX + braceRightEndX) / 2,
        braceY, 8, apexX, braceY - 14);
    // 12 — стропильная нога.
    final rfMidX = (leftX + apexX) / 2 - eaveDX / 2;
    final rfMidY = (eaveLeftY + apexY) / 2;
    _drawPosCallout(canvas, font, rfMidX, rfMidY,
        12, rfMidX - 26, rfMidY + 12);
    // 13 — кобылки (свес).
    _drawPosCallout(canvas, font,
        (eaveLeftX + leftX) / 2,
        (eaveLeftY + wallTopY + mauerH) / 2,
        13, eaveLeftX - 18, eaveLeftY - 12);
    // 14 — коньковый брус.
    _drawPosCallout(canvas, font, apexX, apexY,
        14, apexX + 22, apexY + 14);
    // 15 — наружная несущая стена.
    _drawPosCallout(canvas, font, rightX + wallW / 2,
        baseY + (wallTopY - baseY) * 0.5,
        15, rightX + 36, baseY + (wallTopY - baseY) * 0.5);
    // 16 — внутренняя несущая стена.
    _drawPosCallout(canvas, font, apexX - wallW / 2,
        baseY + (wallTopY - baseY) * 0.5,
        16, apexX - 32, baseY - 4);
    // 17 — верхний уровень чердачного перекрытия.
    _drawPosCallout(canvas, font, leftX - 10, baseY,
        17, leftX - 38, baseY - 10);

    // Ссылки на узлы (тонкие подчёркнутые лейблы).
    _drawNodeCallout(canvas, font, apexX, apexY,
        'Узлы 79-81', apexX - 80, apexY + 22);
    _drawNodeCallout(canvas, font, rightX, wallTopY + mauerH,
        'Узлы 51-54', rightX + 30, wallTopY + 38);

    // Подпись Рис. 2 в правом нижнем углу панели.
    _drawText(canvas, font, 7, 'Рис. 2', r.right - 28, r.bottom + 4);
  }

  /// Отрисовка Разреза 2-2 (продольный, торец вальмы): диагональная
  /// стропильная нога + распорки + штрепель.
  static void _drawSection22(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required double hipSpanM,
    required double slopeRad,
    required double slopeDeg,
    required RafterPickResult pick,
    required bool isHip,
  }) {
    final apexHm = (hipSpanM / 2) * math.tan(slopeRad);
    final totalH = apexHm + 0.4;
    final scaleX = (r.w * 0.9) / hipSpanM;
    final scaleY = (r.h * 0.78) / totalH;
    final s = math.min(scaleX, scaleY);
    final cx = r.cx;
    final baseY = r.top - r.h * 0.92;
    final wallTopY = baseY + 0.4 * s;
    final apexY = wallTopY + apexHm * s;
    final leftX = cx - (hipSpanM / 2) * s;
    final rightX = cx + (hipSpanM / 2) * s;
    final apexX = cx;

    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawLine(leftX - 30, baseY, rightX + 30, baseY);
    canvas.strokePath();
    for (double xx = leftX - 24; xx < rightX + 30; xx += 6) {
      canvas.drawLine(xx, baseY, xx + 4, baseY - 4);
    }
    canvas.strokePath();

    final wallW = 18.0;
    canvas.setLineWidth(0.9);
    canvas.drawRect(leftX - wallW / 2, baseY, wallW, wallTopY - baseY);
    canvas.strokePath();
    canvas.drawRect(rightX - wallW / 2, baseY, wallW, wallTopY - baseY);
    canvas.strokePath();

    final mauerW = wallW + 4;
    final mauerH = 5.0;
    canvas.setFillColor(PdfColors.grey300);
    canvas.drawRect(leftX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.fillPath();
    canvas.drawRect(leftX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.strokePath();
    canvas.drawRect(rightX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.fillPath();
    canvas.drawRect(rightX - mauerW / 2, wallTopY, mauerW, mauerH);
    canvas.strokePath();

    // 10/12 — диагональная стропильная нога (для вальмы) или обычная
    // стропильная нога (для двускатной), со свесом 500 мм за мауэрлат.
    final eaveM2 = 0.5;
    final eaveDX2 = eaveM2 * math.cos(slopeRad) * s;
    final eaveDY2 = eaveM2 * math.sin(slopeRad) * s;
    final eaveLeftX2 = leftX - eaveDX2;
    final eaveRightX2 = rightX + eaveDX2;
    final eaveYbase = wallTopY + mauerH - eaveDY2;
    canvas.setLineWidth(1.4);
    canvas.drawLine(eaveLeftX2, eaveYbase, apexX, apexY);
    canvas.drawLine(eaveRightX2, eaveYbase, apexX, apexY);
    canvas.strokePath();

    // 9 — штрепель-распорка (горизонтальная под диагональными ногами).
    canvas.setLineWidth(0.9);
    final ringY = wallTopY + mauerH + (apexY - wallTopY - mauerH) * 0.4;
    final ringHalf = (rightX - leftX) * 0.32;
    canvas.drawLine(apexX - ringHalf, ringY, apexX + ringHalf, ringY);
    canvas.strokePath();

    // 8 — ригель-затяжка (вторая горизонталь).
    final tieY = wallTopY + mauerH + 4;
    canvas.drawLine(leftX + 14, tieY, rightX - 14, tieY);
    canvas.strokePath();

    // 14 — коньковый брус.
    canvas.setFillColor(PdfColors.white);
    _drawCircle(canvas, apexX, apexY, 4, fill: PdfColors.white);
    canvas.setLineWidth(0.7);
    canvas.drawEllipse(apexX, apexY, 4, 4);
    canvas.strokePath();

    // Размерная цепь снизу.
    canvas.setLineWidth(0.4);
    final dimY = baseY - 18;
    canvas.drawLine(leftX, dimY, rightX, dimY);
    canvas.drawLine(leftX, dimY - 3, leftX, dimY + 3);
    canvas.drawLine(rightX, dimY - 3, rightX, dimY + 3);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7,
        '${(hipSpanM * 1000).round()}', cx, dimY - 9);

    // Угол.
    _drawText(canvas, font, 7, '∠ ${slopeDeg.toStringAsFixed(0)}°',
        leftX + 24, wallTopY + 14);

    // ── ПОЗИЦИИ ИЗ ЛЕГЕНДЫ ────────────────────────────────────────
    _drawPosCallout(canvas, font, leftX - mauerW / 2, wallTopY + mauerH / 2,
        1, leftX - 28, wallTopY + 6);
    _drawPosCallout(canvas, font, (leftX + rightX) / 2, tieY,
        8, (leftX + rightX) / 2 - 30, tieY - 12);
    if (isHip) {
      _drawPosCallout(canvas, font, apexX, ringY,
          9, apexX + ringHalf + 14, ringY - 14);
      _drawPosCallout(canvas, font,
          (eaveLeftX2 + apexX) / 2,
          (eaveYbase + apexY) / 2,
          10,
          (eaveLeftX2 + apexX) / 2 - 26,
          (eaveYbase + apexY) / 2 + 14);
    } else {
      _drawPosCallout(canvas, font,
          (eaveLeftX2 + apexX) / 2,
          (eaveYbase + apexY) / 2,
          12,
          (eaveLeftX2 + apexX) / 2 - 24,
          (eaveYbase + apexY) / 2 + 14);
    }
    _drawPosCallout(canvas, font,
        (eaveLeftX2 + leftX) / 2,
        (eaveYbase + wallTopY + mauerH) / 2,
        13, eaveLeftX2 - 18, eaveYbase - 10);
    _drawPosCallout(canvas, font, apexX, apexY,
        14, apexX + 22, apexY + 14);
    _drawPosCallout(canvas, font, rightX + wallW / 2,
        baseY + (wallTopY - baseY) * 0.5,
        15, rightX + 36, baseY + (wallTopY - baseY) * 0.5);
    _drawPosCallout(canvas, font, leftX - 10, baseY,
        17, leftX - 38, baseY - 10);

    // Ссылки на узлы.
    _drawNodeCallout(canvas, font, apexX, apexY,
        isHip ? 'Узлы 79-81' : 'Узел 67',
        apexX + 12, apexY + 22);
    _drawNodeCallout(canvas, font, leftX, wallTopY + mauerH,
        'Узлы 43-44', leftX - 60, wallTopY + 36);
  }

  /// Отрисовка плана стропил: контур пятна, мауэрлат, прогон, лежень,
  /// стропильные ноги, диагональные стропила (для вальмы), нарожники,
  /// размерные цепи и выноски Узлы.
  static void _drawRaftersPlanView(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required FloorPlan topPlan,
    required bool isHip,
    required bool ridgeAlongX,
    required double raftersStep,
    required RafterPickResult pick,
    required double spanM,
    required double ridgeLengthM,
  }) {
    final scaleX = (r.w * 0.84) / topPlan.width;
    final scaleY = (r.h * 0.84) / topPlan.height;
    final s = math.min(scaleX, scaleY);
    final planW = topPlan.width * s;
    final planH = topPlan.height * s;
    final ox = r.left + (r.w - planW) / 2;
    final oy = r.top - r.h - 4 + (r.h - planH) / 2;
    PdfPoint pp(double mx, double my) =>
        PdfPoint(ox + mx * s, oy + planH - my * s);

    canvas.setStrokeColor(PdfColors.black);
    // 1 — мауэрлат: контур пятна (толстая линия).
    canvas.setLineWidth(1.6);
    canvas.drawRect(ox, oy, planW, planH);
    canvas.strokePath();

    if (isHip) {
      // Вальма: 4 диагональных стропилы (10) от углов к точкам перелома
      // конька (на расстоянии полупролёта от каждого торца).
      final hipInsetM = math.min(topPlan.height, topPlan.width) / 2;
      // Конёк (по длинной оси).
      canvas.setLineWidth(1.2);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final r1 = pp(hipInsetM, ridgeY);
        final r2 = pp(topPlan.width - hipInsetM, ridgeY);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
        canvas.strokePath();
        // Диагональные стропила.
        canvas.setLineWidth(1.0);
        canvas.drawLine(pp(0, 0).x, pp(0, 0).y, r1.x, r1.y);
        canvas.drawLine(pp(0, topPlan.height).x, pp(0, topPlan.height).y,
            r1.x, r1.y);
        canvas.drawLine(pp(topPlan.width, 0).x, pp(topPlan.width, 0).y,
            r2.x, r2.y);
        canvas.drawLine(pp(topPlan.width, topPlan.height).x,
            pp(topPlan.width, topPlan.height).y, r2.x, r2.y);
        canvas.strokePath();
        // Стропильные ноги (12) — от длинных сторон к коньку, между r1 и r2.
        final n = ((topPlan.width - 2 * hipInsetM) / raftersStep).floor();
        for (int i = 1; i <= n; i++) {
          final mx = hipInsetM + raftersStep * i;
          final ridge = pp(mx, ridgeY);
          canvas.drawLine(pp(mx, 0).x, pp(mx, 0).y, ridge.x, ridge.y);
          canvas.drawLine(pp(mx, topPlan.height).x,
              pp(mx, topPlan.height).y, ridge.x, ridge.y);
        }
        canvas.strokePath();
        // Нарожники (11) — короткие, от длинных сторон к диагональной ноге.
        final nh = (hipInsetM / raftersStep).floor();
        for (int i = 1; i <= nh; i++) {
          final mx = raftersStep * i;
          // Левый торец: к диагонали (0,0)→r1.
          final t = mx / hipInsetM; // 0..1
          final hipPtY = topPlan.height * (0.5 - 0.5 * (1 - t));
          canvas.drawLine(pp(mx, 0).x, pp(mx, 0).y,
              pp(mx, hipPtY).x, pp(mx, hipPtY).y);
          final hipPtY2 = topPlan.height * (0.5 + 0.5 * (1 - t));
          canvas.drawLine(pp(mx, topPlan.height).x,
              pp(mx, topPlan.height).y, pp(mx, hipPtY2).x,
              pp(mx, hipPtY2).y);
          // Правый торец.
          final mxR = topPlan.width - raftersStep * i;
          canvas.drawLine(pp(mxR, 0).x, pp(mxR, 0).y,
              pp(mxR, hipPtY).x, pp(mxR, hipPtY).y);
          canvas.drawLine(pp(mxR, topPlan.height).x,
              pp(mxR, topPlan.height).y,
              pp(mxR, hipPtY2).x, pp(mxR, hipPtY2).y);
        }
        canvas.strokePath();
      } else {
        final ridgeX = topPlan.width / 2;
        final r1 = pp(ridgeX, hipInsetM);
        final r2 = pp(ridgeX, topPlan.height - hipInsetM);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
        canvas.strokePath();
        canvas.setLineWidth(1.0);
        canvas.drawLine(pp(0, 0).x, pp(0, 0).y, r1.x, r1.y);
        canvas.drawLine(pp(topPlan.width, 0).x, pp(topPlan.width, 0).y,
            r1.x, r1.y);
        canvas.drawLine(pp(0, topPlan.height).x, pp(0, topPlan.height).y,
            r2.x, r2.y);
        canvas.drawLine(pp(topPlan.width, topPlan.height).x,
            pp(topPlan.width, topPlan.height).y, r2.x, r2.y);
        canvas.strokePath();
        final n = ((topPlan.height - 2 * hipInsetM) / raftersStep).floor();
        for (int i = 1; i <= n; i++) {
          final my = hipInsetM + raftersStep * i;
          final ridge = pp(ridgeX, my);
          canvas.drawLine(pp(0, my).x, pp(0, my).y, ridge.x, ridge.y);
          canvas.drawLine(pp(topPlan.width, my).x,
              pp(topPlan.width, my).y, ridge.x, ridge.y);
        }
        canvas.strokePath();
      }
      // 5 — прогон под коньком + 2 — лежень: пунктирные линии вдоль
      // длинной оси, на отметке между серединой и краем.
      canvas.setLineWidth(0.6);
      if (ridgeAlongX) {
        final purlinY = topPlan.height / 2;
        final p1 = pp(hipInsetM + 0.4, purlinY);
        final p2 = pp(topPlan.width - hipInsetM - 0.4, purlinY);
        _drawDashedLine(canvas, p1.x, p1.y - 4, p2.x, p2.y - 4, 4);
      } else {
        final purlinX = topPlan.width / 2;
        final p1 = pp(purlinX, hipInsetM + 0.4);
        final p2 = pp(purlinX, topPlan.height - hipInsetM - 0.4);
        _drawDashedLine(canvas, p1.x - 4, p1.y, p2.x - 4, p2.y, 4);
      }
    } else {
      // Двускатная: рисуем то же, что и было раньше — конёк по середине,
      // стропила парами от конька к мауэрлату.
      canvas.setLineWidth(1.2);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final r1 = pp(0, ridgeY);
        final r2 = pp(topPlan.width, ridgeY);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
        canvas.strokePath();
        canvas.setLineWidth(0.9);
        final n = (topPlan.width / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final mx = raftersStep * i;
          canvas.drawLine(pp(mx, ridgeY).x, pp(mx, ridgeY).y,
              pp(mx, 0).x, pp(mx, 0).y);
          canvas.drawLine(pp(mx, ridgeY).x, pp(mx, ridgeY).y,
              pp(mx, topPlan.height).x, pp(mx, topPlan.height).y);
        }
        canvas.strokePath();
      } else {
        final ridgeX = topPlan.width / 2;
        final r1 = pp(ridgeX, 0);
        final r2 = pp(ridgeX, topPlan.height);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
        canvas.strokePath();
        canvas.setLineWidth(0.9);
        final n = (topPlan.height / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final my = raftersStep * i;
          canvas.drawLine(pp(ridgeX, my).x, pp(ridgeX, my).y,
              pp(0, my).x, pp(0, my).y);
          canvas.drawLine(pp(ridgeX, my).x, pp(ridgeX, my).y,
              pp(topPlan.width, my).x, pp(topPlan.width, my).y);
        }
        canvas.strokePath();
      }
    }

    // Размерные цепи: габариты пятна.
    canvas.setLineWidth(0.4);
    final dimY = oy - 12;
    canvas.drawLine(ox, dimY, ox + planW, dimY);
    canvas.drawLine(ox, dimY - 3, ox, dimY + 3);
    canvas.drawLine(ox + planW, dimY - 3, ox + planW, dimY + 3);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7,
        '${(topPlan.width * 1000).round()}', ox + planW / 2, dimY - 9);
    final dimX = ox - 14;
    canvas.drawLine(dimX, oy, dimX, oy + planH);
    canvas.drawLine(dimX - 3, oy, dimX + 3, oy + planH);
    canvas.drawLine(dimX - 3, oy + planH, dimX + 3, oy + planH);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${(topPlan.height * 1000).round()}',
        dimX - 24, oy + planH / 2);

    // ── ПОЗИЦИИ ИЗ ЛЕГЕНДЫ НА ПЛАНЕ ────────────────────────────────
    // 1 — мауэрлат (контур пятна).
    _drawPosCallout(canvas, font, pp(0, topPlan.height / 2).x,
        pp(0, topPlan.height / 2).y,
        1, ox - 36, oy + planH * 0.5);
    // 2 — лежень (под прогоном, вдоль конька).
    if (ridgeAlongX) {
      _drawPosCallout(canvas, font,
          pp(topPlan.width * 0.25, topPlan.height / 2).x - 6,
          pp(topPlan.width * 0.25, topPlan.height / 2).y + 6,
          2, ox + planW * 0.18, oy + planH * 0.62);
    } else {
      _drawPosCallout(canvas, font,
          pp(topPlan.width / 2, topPlan.height * 0.25).x - 6,
          pp(topPlan.width / 2, topPlan.height * 0.25).y,
          2, ox + planW * 0.32, oy + planH * 0.78);
    }
    // 5 — прогон (пунктирная линия вдоль конька).
    if (ridgeAlongX) {
      _drawPosCallout(canvas, font,
          pp(topPlan.width * 0.7, topPlan.height / 2).x,
          pp(topPlan.width * 0.7, topPlan.height / 2).y - 4,
          5, ox + planW * 0.78, oy + planH * 0.62);
    } else {
      _drawPosCallout(canvas, font,
          pp(topPlan.width / 2, topPlan.height * 0.7).x - 4,
          pp(topPlan.width / 2, topPlan.height * 0.7).y,
          5, ox + planW * 0.62, oy + planH * 0.22);
    }
    // 12 — стропильные ноги (в середине одной из них).
    final rfX = ridgeAlongX
        ? pp(raftersStep * 3, topPlan.height * 0.25).x
        : pp(topPlan.width * 0.25, raftersStep * 3).x;
    final rfY = ridgeAlongX
        ? pp(raftersStep * 3, topPlan.height * 0.25).y
        : pp(topPlan.width * 0.25, raftersStep * 3).y;
    _drawPosCallout(canvas, font, rfX, rfY,
        12, rfX - 8, rfY + 18);
    // 14 — коньковый брус (на ребре конька).
    if (isHip) {
      final hipInsetM = math.min(topPlan.height, topPlan.width) / 2;
      final ridgeMidM = ridgeLengthM / 2;
      final ridgeMid = ridgeAlongX
          ? pp(ridgeMidM, topPlan.height / 2)
          : pp(topPlan.width / 2, ridgeMidM);
      _drawPosCallout(canvas, font, ridgeMid.x, ridgeMid.y,
          14, ridgeMid.x, ridgeMid.y - 22);
      // 10 — диагональная стропильная нога (в середине одной из).
      final r1 = ridgeAlongX
          ? pp(hipInsetM, topPlan.height / 2)
          : pp(topPlan.width / 2, hipInsetM);
      final mid10 = PdfPoint((pp(0, 0).x + r1.x) / 2,
          (pp(0, 0).y + r1.y) / 2);
      _drawPosCallout(canvas, font, mid10.x, mid10.y,
          10, mid10.x - 18, mid10.y + 12);
      // 11 — нарожник.
      final mid11X = pp(raftersStep, 0).x;
      final mid11Y = pp(raftersStep, 0).y - 8;
      _drawPosCallout(canvas, font, mid11X, mid11Y,
          11, mid11X + 8, mid11Y + 18);
    } else {
      final ridgeMid = ridgeAlongX
          ? pp(topPlan.width / 2, topPlan.height / 2)
          : pp(topPlan.width / 2, topPlan.height / 2);
      _drawPosCallout(canvas, font, ridgeMid.x, ridgeMid.y,
          14, ridgeMid.x + 24, ridgeMid.y - 16);
    }
    // 15 — наружная несущая стена (середина левой стороны).
    _drawPosCallout(canvas, font,
        ox, oy + planH * 0.85,
        15, ox - 36, oy + planH * 0.92);

    // Ссылки на узлы (тонкие подчёркнутые лейблы) в углах плана.
    _drawNodeCallout(canvas, font, pp(0, 0).x, pp(0, 0).y,
        'Узлы 84-85', pp(0, 0).x - 70, pp(0, 0).y - 18);
    _drawNodeCallout(canvas, font, pp(topPlan.width, 0).x,
        pp(topPlan.width, 0).y, 'Узлы 75-76',
        pp(topPlan.width, 0).x + 24, pp(topPlan.width, 0).y - 16);
    _drawNodeCallout(canvas, font, pp(0, topPlan.height).x,
        pp(0, topPlan.height).y, 'Узел 86',
        pp(0, topPlan.height).x - 60, pp(0, topPlan.height).y + 16);
    _drawNodeCallout(canvas, font, pp(topPlan.width, topPlan.height).x,
        pp(topPlan.width, topPlan.height).y, 'Узлы 87-88',
        pp(topPlan.width, topPlan.height).x + 22,
        pp(topPlan.width, topPlan.height).y + 16);

    // Подпись «Рис. 2» снизу справа.
    _drawText(canvas, font, 7, 'Рис. 2', r.right - 28, r.bottom + 4);
  }

  /// 17-позиционная легенда с условными обозначениями.
  static void _drawRaftersLegend(
    PdfGraphics canvas,
    PdfFont font,
    _Rect r, {
    required bool isHip,
  }) {
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, 'Условные обозначения',
        r.left + 8, r.top - 14, bold: true);
    final items = <String>[
      '1 — мауэрлат;',
      '2 — лежень под стойки прогона;',
      '3 — стойки под прогон;',
      '4 — подкосы под стойки и прогон;',
      '5 — прогон под стойки;',
      '6 — распорки под стойки;',
      '7 — распорки под прогон;',
      '8 — ригель-затяжка по подкосам;',
      if (isHip) '9 — штрепель-распорка под диагональные',
      if (isHip) '       стропильные ноги;',
      if (isHip) '10 — диагональные стропильные ноги;',
      if (isHip) '11 — нарожники (короткие угловые стропила);',
      '12 — стропильные ноги;',
      '13 — кобылки стропильных ног;',
      '14 — коньковый брус;',
      '15 — наружные несущие стены;',
      '16 — внутренние несущие стены;',
      '17 — верхний уровень чердачного перекрытия.',
    ];
    var ty = r.top - 30;
    for (final line in items) {
      _drawText(canvas, font, 7.5, line, r.left + 8, ty);
      ty -= 11;
    }
  }

  /// Выноска позиции из легенды: маленькая точка на якорной элементе +
  /// тонкая лидер-линия + белый кружок с номером (1..17). Используется
  /// одновременно с «Узел NN», так что у одного и того же элемента
  /// могут быть и номер позиции, и ссылка на лист с узлом.
  static void _drawPosCallout(
    PdfGraphics canvas,
    PdfFont font,
    double anchorX,
    double anchorY,
    int num,
    double labelX,
    double labelY, {
    double radius = 6.5,
  }) {
    // Якорная точка.
    canvas.setFillColor(PdfColors.black);
    canvas.drawEllipse(anchorX, anchorY, 1.2, 1.2);
    canvas.fillPath();
    // Лидер-линия от якоря к кружку.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawLine(anchorX, anchorY, labelX, labelY);
    canvas.strokePath();
    // Кружок с цифрой.
    canvas.setFillColor(PdfColors.white);
    canvas.drawEllipse(labelX, labelY, radius, radius);
    canvas.fillPath();
    canvas.setLineWidth(0.4);
    canvas.drawEllipse(labelX, labelY, radius, radius);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    _drawCenteredText(canvas, font, 7, '$num', labelX, labelY - 2.3);
  }

  /// Линия-выноска «Узел NN»: тонкая линия от якорной точки к лейблу,
  /// подчёркивание лейбла. Используется на каждом из 3 видов схемы.
  static void _drawNodeCallout(
    PdfGraphics canvas,
    PdfFont font,
    double anchorX,
    double anchorY,
    String label,
    double labelX,
    double labelY,
  ) {
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.3);
    canvas.drawLine(anchorX, anchorY, labelX, labelY);
    canvas.strokePath();
    // Маленькая точка на якоре.
    canvas.setFillColor(PdfColors.grey700);
    canvas.drawEllipse(anchorX, anchorY, 1.2, 1.2);
    canvas.fillPath();
    // Лейбл (одна или несколько строк через \n).
    canvas.setFillColor(PdfColors.black);
    var ty = labelY;
    for (final line in label.split('\n')) {
      _drawText(canvas, font, 6.5, line, labelX, ty);
      // Подчёркивание (как в типовой серии).
      final m = font.stringMetrics(line);
      final w = m.width * 6.5;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.3);
      canvas.drawLine(labelX, ty - 1, labelX + w, ty - 1);
      canvas.strokePath();
      ty -= 9;
    }
  }

  /// Тонкая рамка вокруг панели (для разрезов и легенды).
  static void _drawPanelFrame(
    PdfGraphics canvas,
    _Rect r, {
    bool hairline = false,
  }) {
    canvas.setStrokeColor(PdfColors.grey500);
    canvas.setLineWidth(hairline ? 0.3 : 0.5);
    canvas.drawRect(r.left, r.bottom, r.w, r.h);
    canvas.strokePath();
  }

  static void _paintRafters(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan topPlan,
    PdfFont font,
    HouseProject project,
  ) {
    final L = _layout(size, topPlan, rightSidebar: 230);
    PdfPoint pp(double mx, double my) =>
        PdfPoint(L.ox + mx * L.scale, L.oy + L.planH - my * L.scale);

    // Контур кровли в плане.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    final tl = pp(0, 0);
    canvas.drawRect(tl.x, tl.y - L.planH, L.planW, L.planH);
    canvas.strokePath();

    // Двускатная крыша: конёк всегда параллельно длинной стороне; для
    // плоской — конька нет (просто контур + парапет). Тип берём из
    // project.roof.type (gable/hip/flat/mansard), угол — из slopeAngle.
    final roofType = (project.roof.type ?? 'gable').toLowerCase();
    final isFlat = roofType.contains('flat') || roofType.contains('плос');
    final ridgeAlongX = topPlan.width >= topPlan.height;
    final spanM = ridgeAlongX ? topPlan.height : topPlan.width;
    // Шаг стропил берём из RafterSectionPicker — он зависит от материала
    // кровли (СП 17.13330.2017). Для металлочерепицы 0.6 м, для
    // керамической — 0.9 м, для гибкой — 0.6 м, для шифера — 0.7 м.
    final raftersStep = RafterSectionPicker.rafterStep(
        project.roof.roofingMaterial);

    if (!isFlat) {
      // Конёк по середине, параллельно длинной стороне.
      canvas.setStrokeColor(PdfColors.red700);
      canvas.setLineWidth(1.4);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final r1 = pp(0, ridgeY);
        final r2 = pp(topPlan.width, ridgeY);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
      } else {
        final ridgeX = topPlan.width / 2;
        final r1 = pp(ridgeX, 0);
        final r2 = pp(ridgeX, topPlan.height);
        canvas.drawLine(r1.x, r1.y, r2.x, r2.y);
      }
      canvas.strokePath();

      // Стропильные ноги — пары, шаг raftersStep.
      canvas.setStrokeColor(PdfColors.brown700);
      canvas.setLineWidth(0.9);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final n = (topPlan.width / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final mx = raftersStep * i;
          final s1 = pp(mx, ridgeY);
          final s2 = pp(mx, 0);
          canvas.drawLine(s1.x, s1.y, s2.x, s2.y);
          canvas.strokePath();
          final s3 = pp(mx, ridgeY);
          final s4 = pp(mx, topPlan.height);
          canvas.drawLine(s3.x, s3.y, s4.x, s4.y);
          canvas.strokePath();
        }
      } else {
        final ridgeX = topPlan.width / 2;
        final n = (topPlan.height / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final my = raftersStep * i;
          final s1 = pp(ridgeX, my);
          final s2 = pp(0, my);
          canvas.drawLine(s1.x, s1.y, s2.x, s2.y);
          canvas.strokePath();
          final s3 = pp(ridgeX, my);
          final s4 = pp(topPlan.width, my);
          canvas.drawLine(s3.x, s3.y, s4.x, s4.y);
          canvas.strokePath();
        }
      }
    }

    // Мауэрлат вдоль наружных стен (по всему периметру).
    canvas.setStrokeColor(PdfColors.deepOrange);
    canvas.setLineWidth(2.0);
    final m1 = pp(0, 0);
    final m2 = pp(topPlan.width, 0);
    canvas.drawLine(m1.x, m1.y, m2.x, m2.y);
    canvas.strokePath();
    final m3 = pp(0, topPlan.height);
    final m4 = pp(topPlan.width, topPlan.height);
    canvas.drawLine(m3.x, m3.y, m4.x, m4.y);
    canvas.strokePath();

    // Объёмное обозначение стропил: рядом с каждой стропильной линией
    // рисуем «тень» толщиной = ширина сечения, чтобы было видно, что это
    // не просто чертёжная линия, а реальный брус. Цвет — светло-коричневый.
    final rafterPick = RafterSectionPicker.pickFor(project);
    if (!isFlat) {
      final widthMm = rafterPick.widthMm;
      final widthPx = (widthMm / 1000.0) * L.scale;
      canvas.setFillColor(PdfColors.brown200);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final n = (topPlan.width / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final mx = raftersStep * i;
          final s1 = pp(mx, ridgeY);
          final s2 = pp(mx, 0);
          canvas.drawRect(s1.x - widthPx / 2, math.min(s1.y, s2.y),
              widthPx, (s2.y - s1.y).abs());
          canvas.fillPath();
          final s3 = pp(mx, ridgeY);
          final s4 = pp(mx, topPlan.height);
          canvas.drawRect(s3.x - widthPx / 2, math.min(s3.y, s4.y),
              widthPx, (s4.y - s3.y).abs());
          canvas.fillPath();
        }
      } else {
        final ridgeX = topPlan.width / 2;
        final n = (topPlan.height / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final my = raftersStep * i;
          final s1 = pp(ridgeX, my);
          final s2 = pp(0, my);
          canvas.drawRect(math.min(s1.x, s2.x), s1.y - widthPx / 2,
              (s2.x - s1.x).abs(), widthPx);
          canvas.fillPath();
          final s3 = pp(ridgeX, my);
          final s4 = pp(topPlan.width, my);
          canvas.drawRect(math.min(s3.x, s4.x), s3.y - widthPx / 2,
              (s4.x - s3.x).abs(), widthPx);
          canvas.fillPath();
        }
      }
      // Стропильные ноги поверх «тени» — тонкая чёрная осевая линия.
      canvas.setStrokeColor(PdfColors.brown700);
      canvas.setLineWidth(0.7);
      if (ridgeAlongX) {
        final ridgeY = topPlan.height / 2;
        final n = (topPlan.width / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final mx = raftersStep * i;
          canvas.drawLine(pp(mx, ridgeY).x, pp(mx, ridgeY).y,
              pp(mx, 0).x, pp(mx, 0).y);
          canvas.drawLine(pp(mx, ridgeY).x, pp(mx, ridgeY).y,
              pp(mx, topPlan.height).x, pp(mx, topPlan.height).y);
        }
      } else {
        final ridgeX = topPlan.width / 2;
        final n = (topPlan.height / raftersStep).floor();
        for (int i = 1; i < n; i++) {
          final my = raftersStep * i;
          canvas.drawLine(pp(ridgeX, my).x, pp(ridgeX, my).y,
              pp(0, my).x, pp(0, my).y);
          canvas.drawLine(pp(ridgeX, my).x, pp(ridgeX, my).y,
              pp(topPlan.width, my).x, pp(topPlan.width, my).y);
        }
      }
      canvas.strokePath();
    }

    // Маркировка С-1.
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.brown700);
    canvas.setLineWidth(0.5);
    final mark = pp(topPlan.width / 2, topPlan.height * 0.25);
    _drawCircle(canvas, mark.x, mark.y, 10, fill: PdfColors.white);
    canvas.setFillColor(PdfColors.brown700);
    _drawCenteredText(canvas, font, 7.5, 'С-1', mark.x, mark.y - 2.6);

    // Подпись конька / парапета.
    final slopeAngle = project.roof.slopeAngle ?? 30.0;
    final rafterLengthMm = isFlat
        ? 0.0
        : (spanM / 2 / math.cos(slopeAngle * math.pi / 180) * 1000);
    // Сечение стропил подбирается по фактическим нагрузкам через
    // RafterSectionPicker (СП 20 + СП 64), п.2 v43.
    final rafterSection = rafterPick.sectionLabel;
    final ridgeLengthM = ridgeAlongX ? topPlan.width : topPlan.height;
    final mauerlatPieces = ((topPlan.width + topPlan.height) * 2 / 3.0).ceil();
    final raftersPerSide = (ridgeLengthM / raftersStep).floor() - 1;
    final rafterCount = raftersPerSide * 2;
    final eaveOverhangMm = 500.0;
    canvas.setFillColor(PdfColors.red700);
    if (!isFlat) {
      final ridgePos = ridgeAlongX
          ? pp(topPlan.width * 0.1, topPlan.height / 2)
          : pp(topPlan.width / 2, topPlan.height * 0.1);
      _drawText(canvas, font, 7, 'Конёк ($rafterSection)',
          ridgePos.x + 6, ridgePos.y + 3);
    }

    // Размерные цепи: длина ската, шаг стропил, общий габарит вдоль конька,
    // длина свеса. Размеры берутся из тех же входных, что используются
    // в `RafterSectionPicker` и в смете — этим достигается синхронизация
    // чертежа и расчёта.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.setFillColor(PdfColors.black);
    final pTL = pp(0, 0);
    final pTR = pp(topPlan.width, 0);
    final pBL = pp(0, topPlan.height);
    // Внешняя цепь снизу — общая длина пятна / длина конька.
    final dimY1 = pBL.y - 14;
    canvas.drawLine(pBL.x, dimY1, pp(topPlan.width, topPlan.height).x, dimY1);
    canvas.strokePath();
    canvas.drawLine(pBL.x, dimY1 - 3, pBL.x, dimY1 + 3);
    canvas.drawLine(pp(topPlan.width, topPlan.height).x, dimY1 - 3,
        pp(topPlan.width, topPlan.height).x, dimY1 + 3);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7,
        '${(topPlan.width * 1000).round()}',
        (pBL.x + pp(topPlan.width, topPlan.height).x) / 2,
        dimY1 - 9);
    // Цепь слева — пролёт / длина ската.
    final dimX1 = pTL.x - 18;
    canvas.drawLine(dimX1, pTL.y, dimX1, pBL.y);
    canvas.strokePath();
    canvas.drawLine(dimX1 - 3, pTL.y, dimX1 + 3, pTL.y);
    canvas.drawLine(dimX1 - 3, pBL.y, dimX1 + 3, pBL.y);
    canvas.strokePath();
    _drawCenteredText(canvas, font, 7,
        '${(topPlan.height * 1000).round()}',
        dimX1 - 12, (pTL.y + pBL.y) / 2);
    // Подпись «полупролёт / длина ската» — выноска поверх ската.
    if (!isFlat) {
      final cx = (pTL.x + pTR.x) / 2;
      final cy = ridgeAlongX
          ? (pTL.y + pp(0, topPlan.height / 2).y) / 2
          : (pTL.y + pp(0, topPlan.height).y) / 2;
      _drawText(canvas, font, 7,
          'L ${(spanM / 2).toStringAsFixed(2)} м · '
          'Lст ${(rafterLengthMm / 1000).toStringAsFixed(2)} м · '
          'свес ${eaveOverhangMm.toStringAsFixed(0)} мм',
          cx - 60, cy);
    }

    // Метка разреза «1-1» по середине плана — указывает на лист 17.
    if (!isFlat) {
      final cutX1 = ridgeAlongX
          ? pp(topPlan.width * 0.5, -0.0).x
          : pp(0, topPlan.height / 2).x;
      final cutY1 = ridgeAlongX
          ? pp(0, 0).y + 10
          : pp(0, topPlan.height / 2).y;
      final cutX2 = ridgeAlongX
          ? cutX1
          : pp(topPlan.width, topPlan.height / 2).x;
      final cutY2 = ridgeAlongX
          ? pp(0, topPlan.height).y - 10
          : cutY1;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      _drawDashedLine(canvas, cutX1, cutY1, cutX2, cutY2, 4);
      // Стрелки на концах + кружки с цифрой 1.
      for (final pt in [PdfPoint(cutX1, cutY1), PdfPoint(cutX2, cutY2)]) {
        canvas.setFillColor(PdfColors.white);
        canvas.drawEllipse(pt.x, pt.y, 7, 7);
        canvas.fillPath();
        canvas.setStrokeColor(PdfColors.black);
        canvas.drawEllipse(pt.x, pt.y, 7, 7);
        canvas.strokePath();
        canvas.setFillColor(PdfColors.black);
        _drawCenteredText(canvas, font, 8, '1', pt.x, pt.y - 2.5);
      }
    }

    // Спецификация — с переносом текста в колонке «Прим.» (`_drawWrappedTable`),
    // чтобы текст не выходил за рамки. Используется тот же подход, что
    // на л.13 (Спецификация перекрытий) — тестировано и стабильно.
    final mauerlatLabel =
        rafterPick.widthMm >= 100 ? 'Брус 100×150' : 'Брус 100×100';
    final raftersTableBottomY = _drawWrappedTable(
      canvas,
      font,
      L.sidebarLeft,
      L.oy + L.planH - 8,
      L.sidebarWidth,
      title: 'Спецификация стропил',
      headers: const ['Марка', 'Сечение', 'Длина, мм', 'Кол.', 'Прим.'],
      colWidths: const [28, 56, 48, 22, 76],
      rows: [
        [
          'С-1',
          rafterSection,
          isFlat ? '—' : rafterLengthMm.toStringAsFixed(0),
          isFlat ? '0' : '$rafterCount',
          'Хвоя 1с, влажн. ≤18%; шаг '
              '${(raftersStep * 1000).round()} мм',
        ],
        [
          'К-1',
          rafterSection,
          (ridgeLengthM * 1000).toStringAsFixed(0),
          isFlat ? '0' : '1',
          'Коньковый прогон',
        ],
        [
          'М-1',
          mauerlatLabel,
          '3000',
          '$mauerlatPieces',
          'Мауэрлат, антисептик',
        ],
        const [
          'Об-1',
          'Доска 25×100',
          '1000',
          'по л.',
          'Обрешётка шаг 350 мм (СП 17.13330)',
        ],
      ],
      headerHeight: 16,
      minRowHeight: 16,
      lineHeight: 8.5,
      bodyFontSize: 6.5,
      headerFontSize: 7.0,
      wrapColumns: const {1, 4},
    );

    // Примечания — все значения ссылаются на те же входы, что и
    // спецификация выше: `RafterSectionPicker.pickFor(project)`. При
    // изменении кровельного материала / угла / снегового района цифры
    // ниже автоматически обновятся (в смете и в ПЗ — те же значения).
    final tx = L.sidebarLeft;
    var ty = raftersTableBottomY - 18;
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, 'Примечания', tx, ty, bold: true);
    ty -= 12;
    final roofTypeRu = isFlat
        ? 'плоская'
        : roofType.contains('hip') || roofType.contains('вальм')
            ? 'вальмовая'
            : roofType.contains('mansard') || roofType.contains('мансар')
                ? 'мансардная'
                : 'двускатная';
    final notes = <String>[
      '1. Тип кровли: $roofTypeRu, уклон '
          '${slopeAngle.toStringAsFixed(0)}°.',
      '2. Шаг стропил '
          '${(raftersStep * 1000).round()} мм '
          '(СП 17.13330).',
      '3. Сечение $rafterSection — пролёт '
          '${(spanM / 2).toStringAsFixed(2)} м.',
      '4. Снеговой район ${rafterPick.snowZone}, '
          'Sg = ${rafterPick.snowSgKnPerM2.toStringAsFixed(1)} кН/м²',
      '   (СП 20.13330, табл. 10.1).',
      '5. q расч. = '
          '${rafterPick.qDesignKnPerM2.toStringAsFixed(2)} кН/м², '
          'R = ${rafterPick.reactionKn.toStringAsFixed(2)} кН',
      '   (на мауэрлат и конёк).',
      '6. Древесина: хвойные 1с, влажн. ≤18%,',
      '   ГОСТ 8486-86; огнезащита I гр. (СП 2.13130).',
      '7. Разрез по «1-1» см. лист 17.',
    ];
    for (final note in notes) {
      _drawText(canvas, font, 7, note, tx, ty);
      ty -= 10;
    }
  }

  // ═══════════════════════════ ХЕЛПЕРЫ ══════════════════════════════════
  static void _drawText(
    PdfGraphics canvas,
    PdfFont font,
    double size,
    String text,
    double x,
    double y, {
    bool bold = false,
  }) {
    canvas.drawString(font, size, text, x, y);
  }

  static void _drawCenteredText(
    PdfGraphics canvas,
    PdfFont font,
    double size,
    String text,
    double cx,
    double cy,
  ) {
    final m = font.stringMetrics(text);
    final w = m.width * size;
    canvas.drawString(font, size, text, cx - w / 2, cy);
  }

  static void _drawCircle(
    PdfGraphics canvas,
    double cx,
    double cy,
    double r, {
    PdfColor? fill,
  }) {
    if (fill != null) {
      canvas.setFillColor(fill);
      canvas.drawEllipse(cx, cy, r, r);
      canvas.fillPath();
    }
    canvas.drawEllipse(cx, cy, r, r);
    canvas.strokePath();
  }

  static void _drawDashedLine(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    double dash,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    final cnt = (len / (dash * 2)).floor();
    for (int i = 0; i <= cnt; i++) {
      final t1 = (i * 2 * dash) / len;
      final t2 = ((i * 2 + 1) * dash) / len;
      if (t1 > 1) break;
      final t2c = t2 > 1 ? 1 : t2;
      canvas.drawLine(
        x1 + dx * t1,
        y1 + dy * t1,
        x1 + dx * t2c,
        y1 + dy * t2c,
      );
      canvas.strokePath();
    }
  }

  /// Разбивает строку на слова и переносит их по словам так, чтобы
  /// каждая строка укладывалась в `maxWidth` при заданном шрифте.
  /// Если одно слово длиннее `maxWidth`, оно разрезается посимвольно.
  static List<String> _wrapText(
    String text,
    PdfFont font,
    double fontSize,
    double maxWidth,
  ) {
    if (text.isEmpty) return const [''];
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';

    double widthOf(String s) => font.stringMetrics(s).width * fontSize;

    void flushCurrent() {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
    }

    for (final w in words) {
      if (w.isEmpty) continue;
      if (widthOf(w) > maxWidth) {
        // Слово шире колонки → режем по символам.
        flushCurrent();
        var buf = '';
        for (final ch in w.split('')) {
          if (widthOf(buf + ch) > maxWidth && buf.isNotEmpty) {
            lines.add(buf);
            buf = ch;
          } else {
            buf += ch;
          }
        }
        if (buf.isNotEmpty) {
          current = buf;
        }
        continue;
      }
      final next = current.isEmpty ? w : '$current $w';
      if (widthOf(next) <= maxWidth) {
        current = next;
      } else {
        flushCurrent();
        current = w;
      }
    }
    flushCurrent();
    if (lines.isEmpty) lines.add('');
    return lines;
  }

  /// Таблица с автопереносом текста по словам в указанных колонках.
  /// Для остальных колонок текст центрируется в одну строку.
  /// Высота строки определяется максимальным числом строк среди
  /// колонок с включённым переносом и [minRowHeight].
  static double _drawWrappedTable(
    PdfGraphics canvas,
    PdfFont font,
    double x,
    double yTop,
    double maxWidth, {
    required String title,
    required List<String> headers,
    required List<double> colWidths,
    required List<List<String>> rows,
    required double headerHeight,
    required double minRowHeight,
    required double lineHeight,
    required double bodyFontSize,
    required double headerFontSize,
    required Set<int> wrapColumns,
  }) {
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 9, title, x, yTop - 9, bold: true);
    final tableTop = yTop - 13;
    final totalWidth = colWidths.fold<double>(0, (a, b) => a + b);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);

    // Заголовок.
    canvas.setFillColor(PdfColors.grey200);
    canvas.drawRect(x, tableTop - headerHeight, totalWidth, headerHeight);
    canvas.fillPath();
    canvas.setFillColor(PdfColors.black);
    double hx = x;
    for (var i = 0; i < headers.length; i++) {
      _drawCenteredText(
        canvas,
        font,
        headerFontSize,
        headers[i],
        hx + colWidths[i] / 2,
        tableTop - headerHeight / 2 - headerFontSize * 0.35,
      );
      hx += colWidths[i];
    }
    canvas.drawRect(x, tableTop - headerHeight, totalWidth, headerHeight);
    canvas.strokePath();

    // Строки. Сначала рассчитываем перенос и высоту каждой строки.
    var ry = tableTop - headerHeight;
    for (final row in rows) {
      // Подготовим раскладку каждой ячейки.
      final wrapped = <List<String>>[];
      var maxLines = 1;
      for (var i = 0; i < colWidths.length; i++) {
        final cell = i < row.length ? row[i] : '';
        if (wrapColumns.contains(i)) {
          final lines = _wrapText(
            cell,
            font,
            bodyFontSize,
            colWidths[i] - 6,
          );
          wrapped.add(lines);
          if (lines.length > maxLines) maxLines = lines.length;
        } else {
          wrapped.add([cell]);
        }
      }
      final rowH = math.max<double>(
        minRowHeight,
        4 + lineHeight * maxLines,
      );
      ry -= rowH;
      canvas.drawRect(x, ry, totalWidth, rowH);
      canvas.strokePath();
      double rx = x;
      for (var i = 0; i < colWidths.length; i++) {
        final lines = wrapped[i];
        if (wrapColumns.contains(i) && lines.length > 1) {
          // Многострочная ячейка — выравниваем по верху, со
          // смещением, чтобы блок текста смотрелся центрированным.
          final blockH = lineHeight * lines.length;
          double ly = ry + rowH / 2 + blockH / 2 - lineHeight;
          for (final ln in lines) {
            _drawText(
              canvas,
              font,
              bodyFontSize,
              ln,
              rx + 3,
              ly,
            );
            ly -= lineHeight;
          }
        } else {
          // Одна строка — центрируем по горизонтали и вертикали.
          _drawCenteredText(
            canvas,
            font,
            bodyFontSize,
            lines.first,
            rx + colWidths[i] / 2,
            ry + rowH / 2 - bodyFontSize * 0.35,
          );
        }
        rx += colWidths[i];
      }
    }
    // Вертикальные разделители.
    var vx = x;
    for (var i = 0; i < colWidths.length - 1; i++) {
      vx += colWidths[i];
      canvas.drawLine(vx, ry, vx, tableTop);
      canvas.strokePath();
    }
    return ry;
  }
}

/// Прямоугольник в координатах PDF (Y растёт вверх). `top` — верхняя
/// граница, `bottom` — нижняя; `left`/`right` — соответствующие
/// горизонтальные границы. Используется для разметки многопанельных
/// схем (КД-2 «Схема стропил» с 3 проекциями + легендой).
class _Rect {
  const _Rect(this.left, this.bottom, this.w, this.h);
  final double left;
  final double bottom;
  final double w;
  final double h;
  double get right => left + w;
  double get top => bottom + h;
  double get cx => left + w / 2;
  double get cy => bottom + h / 2;
  _Rect shrink({
    double top = 0,
    double bottom = 0,
    double left = 0,
    double right = 0,
  }) =>
      _Rect(this.left + left, this.bottom + bottom,
          w - left - right, h - top - bottom);
}

class _PlanLayout {
  const _PlanLayout({
    required this.ox,
    required this.oy,
    required this.planW,
    required this.planH,
    required this.scale,
    required this.sidebarLeft,
    required this.sidebarTop,
    required this.sidebarWidth,
  });
  final double ox;
  final double oy;
  final double planW;
  final double planH;
  final double scale;
  final double sidebarLeft;
  final double sidebarTop;
  final double sidebarWidth;
}

class _LineSeg {
  const _LineSeg(this.x1, this.y1, this.x2, this.y2);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

class _DetailAnchors {
  const _DetailAnchors({this.eaveAnchor, this.ridgeAnchor});
  final _Pt? eaveAnchor;
  final _Pt? ridgeAnchor;
}

class _Pt {
  const _Pt(this.x, this.y);
  final double x;
  final double y;
}
