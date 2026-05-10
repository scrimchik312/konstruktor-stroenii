// Лист «Планшет А1» — свод ключевых архитектурных видов на одном листе
// формата А1 (Phase-3b §17.2.4). Маркетинговый материал для заказчика.
//
// Подход: не дублируем существующие painters, а собираем `pw.Stack`
// из мини-видов (см. `pdf_catalog_card.dart::paintMiniAxono` /
// `paintMiniPlan` / `paintMiniFacade`) и стандартного штампа ГОСТ
// (`PdfTitleBlock.build`). Документ — отдельный standalone PDF
// на одном листе А1 ландшафтной ориентации.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/rooms_catalog.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'pdf_catalog_card.dart';
import 'pdf_title_block.dart';

/// Лист «Планшет А1» — свод архитектурных видов проекта на одном А1
/// (Phase-3b §17.2.4).
class PdfA1Placard {
  PdfA1Placard._();

  /// Формат А1: 594 × 841 мм (по ГОСТ 2.301-68). Ландшафтный —
  /// 841 × 594 мм. Поля минимальные, под рамку и штамп.
  static const PdfPageFormat _a1Landscape = PdfPageFormat(
    84.1 * PdfPageFormat.cm,
    59.4 * PdfPageFormat.cm,
    marginAll: 0,
  );

  /// Собирает single-page A1 PDF и возвращает его байты. Это
  /// «marketing-export» — отдельный документ, не часть основного
  /// батча `PdfBuilder.buildBatch(...)`.
  static Future<Uint8List> buildDocument({
    required HouseProject project,
    required List<FloorPlan> plans,
    required int versionNumber,
    OrganizationSettings? organization,
  }) async {
    final regularData =
        await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final pdf = pw.Document(
      title: '${project.name} — Планшет А1',
      author: 'Konstruktor stroenii',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final pdfTtfRegular = PdfTtfFont(pdf.document, regularData);

    pdf.addPage(buildPage(
      project: project,
      plans: plans,
      font: regular,
      fontBold: bold,
      pdfTtfRegular: pdfTtfRegular,
      versionNumber: versionNumber,
      organization: organization,
    ));

    return pdf.save();
  }

  /// Возвращает `pw.Page` с планшетом А1 — можно вставлять в
  /// существующий документ или собирать отдельный (см. `buildDocument`).
  static pw.Page buildPage({
    required HouseProject project,
    required List<FloorPlan> plans,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
    required int versionNumber,
    OrganizationSettings? organization,
  }) {
    final firstPlan = plans.isNotEmpty ? plans.first : null;
    final tep = _PlacardTep.fromProject(project, plans);

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: _a1Landscape,
        margin: pw.EdgeInsets.zero,
      ),
      build: (context) {
        return pw.Stack(
          children: [
            // Внешняя рамка по ГОСТ 2.301: 20 мм слева под подшивку,
            // 5 мм с трёх остальных сторон.
            pw.Positioned(
              left: 20 * PdfPageFormat.mm,
              top: 5 * PdfPageFormat.mm,
              right: 5 * PdfPageFormat.mm,
              bottom: 5 * PdfPageFormat.mm,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.black,
                    width: 0.7,
                  ),
                ),
              ),
            ),
            // Содержимое: header + 3-колоночный grid + полоса под штамп.
            pw.Positioned.fill(
              child: pw.Padding(
                padding: pw.EdgeInsets.fromLTRB(
                  24 * PdfPageFormat.mm,
                  9 * PdfPageFormat.mm,
                  9 * PdfPageFormat.mm,
                  62 * PdfPageFormat.mm, // полоса штампа
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(project, tep, font, fontBold),
                    pw.SizedBox(height: 8),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // Левая колонка: 3D-аксонометрия (большая).
                          pw.Expanded(
                            flex: 5,
                            child: _miniBlock(
                              title: 'Общий вид (аксонометрия)',
                              font: font,
                              fontBold: fontBold,
                              child: pw.LayoutBuilder(
                                builder: (ctx, c) {
                                  final cc = c!;
                                  return pw.SizedBox(
                                    width: cc.maxWidth,
                                    height: cc.maxHeight,
                                    child: pw.CustomPaint(
                                      size: PdfPoint(
                                          cc.maxWidth, cc.maxHeight),
                                      painter: (canvas, size) {
                                        PdfCatalogCard.paintMiniAxono(
                                          canvas: canvas,
                                          size: size,
                                          project: project,
                                          plans: plans,
                                          pdfFont: pdfTtfRegular,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          // Средняя колонка: планы этажей сверху вниз.
                          pw.Expanded(
                            flex: 4,
                            child: _plansColumn(
                              plans: plans,
                              font: font,
                              fontBold: fontBold,
                              pdfTtfRegular: pdfTtfRegular,
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          // Правая колонка: фасады 2x2 + ТЭП.
                          pw.Expanded(
                            flex: 4,
                            child: _facadesAndTep(
                              project: project,
                              firstPlan: firstPlan,
                              tep: tep,
                              font: font,
                              fontBold: fontBold,
                              pdfTtfRegular: pdfTtfRegular,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Штамп ГОСТ Р 21.101-2020 в правом нижнем углу.
            pw.Positioned(
              right: 9 * PdfPageFormat.mm,
              bottom: 5 * PdfPageFormat.mm,
              child: PdfTitleBlock.build(
                font: font,
                fontBold: fontBold,
                projectName: project.name,
                sectionTitle: 'Архитектурные решения',
                sheetTitle: 'Планшет А1 — свод листов',
                sheetCode: 'АР-А1',
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

  // ─────────────────────────── Вёрстка ──────────────────────────────

  static pw.Widget _buildHeader(
    HouseProject project,
    _PlacardTep tep,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final d = brief.footprintLength ?? 0;
    final stories = brief.floors ?? 1;
    final mansard = brief.hasMansard == true ? ' + мансарда' : '';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.7),
        color: const PdfColor.fromInt(0xFFEEF2F7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ИНДИВИДУАЛЬНЫЙ ЖИЛОЙ ДОМ',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  project.name,
                  style: pw.TextStyle(font: fontBold, fontSize: 22),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Габариты: ${_fmt(w)} × ${_fmt(d)} м · '
                  'Этажность: $stories$mansard · '
                  'Общая площадь: ${_fmt(tep.totalAreaM2)} м²',
                  style: pw.TextStyle(font: font, fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.0),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'АРТИКУЛ',
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
                pw.Text(
                  'Т-${tep.totalAreaM2.round()}',
                  style: pw.TextStyle(font: fontBold, fontSize: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _plansColumn({
    required List<FloorPlan> plans,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
  }) {
    if (plans.isEmpty) {
      return _miniBlock(
        title: 'Планы этажей',
        font: font,
        fontBold: fontBold,
        child: pw.Center(
          child: pw.Text('Нет данных',
              style: pw.TextStyle(font: font, fontSize: 10)),
        ),
      );
    }
    final children = <pw.Widget>[];
    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      children.add(pw.Expanded(
        child: pw.Padding(
          padding: pw.EdgeInsets.only(bottom: i == plans.length - 1 ? 0 : 6),
          child: _miniBlock(
            title: i == 0
                ? 'План 1-го этажа'
                : (plan.floorLabel.isNotEmpty
                    ? 'План: ${plan.floorLabel}'
                    : 'План этажа ${i + 1}'),
            font: font,
            fontBold: fontBold,
            child: pw.LayoutBuilder(
              builder: (ctx, c) {
                final cc = c!;
                return pw.SizedBox(
                  width: cc.maxWidth,
                  height: cc.maxHeight,
                  child: pw.CustomPaint(
                    size: PdfPoint(cc.maxWidth, cc.maxHeight),
                    painter: (canvas, size) {
                      PdfCatalogCard.paintMiniPlan(
                        canvas: canvas,
                        size: size,
                        plan: plan,
                        pdfFont: pdfTtfRegular,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _facadesAndTep({
    required HouseProject project,
    required FloorPlan? firstPlan,
    required _PlacardTep tep,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // 2×2 фасады. Сейчас mini-facade рисует один обобщённый
        // силуэт (смотрит «в зрителя»); для всех 4 названий
        // используем один и тот же painter — это маркетинговый
        // материал, и силуэт остаётся читаемым.
        pw.Expanded(
          flex: 5,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: _facadeMini(
                  title: 'Главный фасад (южный)',
                  project: project,
                  plan: firstPlan,
                  font: font,
                  fontBold: fontBold,
                  pdfTtfRegular: pdfTtfRegular,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: _facadeMini(
                  title: 'Дворовой фасад (северный)',
                  project: project,
                  plan: firstPlan,
                  font: font,
                  fontBold: fontBold,
                  pdfTtfRegular: pdfTtfRegular,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Expanded(
          flex: 5,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: _facadeMini(
                  title: 'Боковой фасад (западный)',
                  project: project,
                  plan: firstPlan,
                  font: font,
                  fontBold: fontBold,
                  pdfTtfRegular: pdfTtfRegular,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: _facadeMini(
                  title: 'Боковой фасад (восточный)',
                  project: project,
                  plan: firstPlan,
                  font: font,
                  fontBold: fontBold,
                  pdfTtfRegular: pdfTtfRegular,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        // ТЭП — компактный список ключевых показателей.
        pw.Expanded(
          flex: 7,
          child: _miniBlock(
            title: 'Технико-экономические показатели',
            font: font,
            fontBold: fontBold,
            child: _tepList(tep, font, fontBold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _facadeMini({
    required String title,
    required HouseProject project,
    required FloorPlan? plan,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfTtfRegular,
  }) {
    return _miniBlock(
      title: title,
      font: font,
      fontBold: fontBold,
      child: pw.LayoutBuilder(
        builder: (ctx, c) {
          final cc = c!;
          return pw.SizedBox(
            width: cc.maxWidth,
            height: cc.maxHeight,
            child: pw.CustomPaint(
              size: PdfPoint(cc.maxWidth, cc.maxHeight),
              painter: (canvas, size) {
                PdfCatalogCard.paintMiniFacade(
                  canvas: canvas,
                  size: size,
                  project: project,
                  plan: plan,
                  pdfFont: pdfTtfRegular,
                );
              },
            ),
          );
        },
      ),
    );
  }

  static pw.Widget _tepList(
    _PlacardTep tep,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final rows = <(String, String)>[
      ('Площадь застройки', '${_fmt(tep.builtAreaM2)} м²'),
      ('Общая площадь', '${_fmt(tep.totalAreaM2)} м²'),
      ('Жилая площадь', '${_fmt(tep.livingAreaM2)} м²'),
      ('Полезная площадь', '${_fmt(tep.usableAreaM2)} м²'),
      ('Этажность', '${tep.floorsCount}'),
      ('Высота до конька', '${_fmt(tep.ridgeHeightM)} м'),
      ('Габариты в плане',
          '${_fmt(tep.plotWidthM)} × ${_fmt(tep.plotDepthM)} м'),
      ('Объём здания', '${_fmt(tep.volumeM3)} м³'),
      ('Стены', tep.wallMaterial),
      ('Фундамент', tep.foundationLabel),
      ('Кровля', tep.roofingLabel),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    r.$1,
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Text(
                    r.$2,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: fontBold, fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _miniBlock({
    required String title,
    required pw.Font font,
    required pw.Font fontBold,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE8EDF3),
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.4),
              ),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(font: fontBold, fontSize: 9),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(num v) {
    if (v == 0) return '0';
    if (v == v.toInt()) return v.toInt().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

/// Тех-эконом показатели для шапки и таблицы планшета. Это упрощённая
/// версия `_TepFigures` из `pdf_catalog_card.dart`; держим её локально,
/// чтобы не делать TEP-расчётчик публичным API.
class _PlacardTep {
  _PlacardTep({
    required this.builtAreaM2,
    required this.totalAreaM2,
    required this.livingAreaM2,
    required this.usableAreaM2,
    required this.floorsCount,
    required this.ridgeHeightM,
    required this.plotWidthM,
    required this.plotDepthM,
    required this.volumeM3,
    required this.wallMaterial,
    required this.foundationLabel,
    required this.roofingLabel,
  });

  final double builtAreaM2;
  final double totalAreaM2;
  final double livingAreaM2;
  final double usableAreaM2;
  final int floorsCount;
  final double ridgeHeightM;
  final double plotWidthM;
  final double plotDepthM;
  final double volumeM3;
  final String wallMaterial;
  final String foundationLabel;
  final String roofingLabel;

  static _PlacardTep fromProject(
      HouseProject project, List<FloorPlan> plans) {
    final brief = project.brief;
    final w = (brief.footprintWidth ?? 0).toDouble();
    final d = (brief.footprintLength ?? 0).toDouble();
    final builtArea = w * d;
    final floors = brief.floors ?? 1;
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

    final slopeDeg = project.roof.slopeAngle ?? 0;
    final slopeRise = (slopeDeg > 0 && slopeDeg < 89)
        ? (d / 2) * 0.5 // примерная высота конька через половину пролёта
        : 0.5;
    final ridge = floorH * floors + slopeRise;
    final volume = builtArea * floorH * floors;

    final wallMatRaw = brief.wallMaterial;
    final wallMat = wallMatRaw == null ? '—' : wallMatRaw.title;
    final foundLabel = project.foundation.type?.title ?? '—';
    final roofId = project.roof.roofingMaterial;
    final roofLabel = roofId == null
        ? 'не выбрана'
        : _roofLabel(roofId);

    return _PlacardTep(
      builtAreaM2: builtArea,
      totalAreaM2: total,
      livingAreaM2: living,
      usableAreaM2: usable,
      floorsCount: floors,
      ridgeHeightM: ridge,
      plotWidthM: w,
      plotDepthM: d,
      volumeM3: volume,
      wallMaterial: wallMat,
      foundationLabel: foundLabel,
      roofingLabel: roofLabel,
    );
  }

  static String _roofLabel(String id) {
    switch (id) {
      case 'metal_tile':
        return 'металлочерепица';
      case 'ceramic':
      case 'ceramic_tile':
        return 'керамическая черепица';
      case 'soft':
      case 'soft_tile':
      case 'bituminous':
        return 'мягкая (битумная) черепица';
      case 'membrane':
        return 'мембранная';
      case 'profnastil':
      case 'corrugated':
        return 'профнастил';
      case 'fold':
      case 'standing_seam':
        return 'фальцевая кровля';
      case 'slate':
        return 'шифер';
      default:
        return id;
    }
  }
}
