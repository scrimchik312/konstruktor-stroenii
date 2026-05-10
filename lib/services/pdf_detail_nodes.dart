import 'dart:math' as math;

import 'package:cc_engine/cc_engine.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/foundation.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'foundation_plan_generator.dart';
import 'pdf_builder.dart';
import 'pdf_builder_materials.dart';
import 'pdf_title_block.dart';
import 'rafter_section_picker.dart';

/// Итерация 3 — узлы и детали (СПДС, СП 64/17/22/50).
///
/// 7 листов:
///   У-1 — карнизный свес (примыкание скатной кровли к стене);
///   У-2 — конёк скатной кровли;
///   У-3 — оконный откос (монтажный шов + утепление);
///   У-4 — опирание стропилины на мауэрлат;
///   У-5 — цоколь + отмостка + гидроизоляция;
///   У-6 — опирание балки перекрытия на стену;
///   ПК   — кровельный пирог (детально по слоям).
///
/// Все узлы рисуются на чистой канве A3-landscape:
///   слева ½ листа — деталь в масштабе 1:5 / 1:10 с поясняющими выносками,
///   справа ½ листа — пронумерованный перечень слоёв и примечания.
class PdfDetailNodes {
  PdfDetailNodes._();

  // ─────────────────────── общая структура листа узла ──────────────────
  static pw.Page _detailPage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    required String sheetCode,
    required String sectionTitle,
    required String sheetTitle,
    required String header,
    required String scaleLabel,
    required void Function(PdfGraphics canvas, _DetailRect area, PdfFont font) painter,
    required List<_DetailLayer> layers,
    required List<String> notes,
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
                    pw.Row(
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
                              header,
                              style:
                                  pw.TextStyle(fontSize: 10, font: font),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Масштаб: $scaleLabel',
                              style:
                                  pw.TextStyle(fontSize: 10, font: font),
                            ),
                            pw.Text(
                              'Версия №$versionNumber',
                              style:
                                  pw.TextStyle(fontSize: 10, font: font),
                            ),
                          ],
                        ),
                      ],
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
                                  _paintFrame(canvas, size, pdfFont,
                                      painter, layers, notes),
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
                sectionTitle: sectionTitle,
                sheetTitle: sheetTitle,
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

  static void _paintFrame(
    PdfGraphics canvas,
    PdfPoint size,
    PdfFont font,
    void Function(PdfGraphics canvas, _DetailRect area, PdfFont font)
        drawDetail,
    List<_DetailLayer> layers,
    List<String> notes,
  ) {
    final w = size.x;
    final h = size.y;

    // Деталь — слева, ширина ~55% полезной площади.
    final detailArea = _DetailRect(
      x: 30,
      y: 30,
      width: w * 0.50 - 30,
      height: h - 60,
    );
    // Рамка вокруг детали.
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setLineWidth(0.4);
    canvas.drawRect(
        detailArea.x, detailArea.y, detailArea.width, detailArea.height);
    canvas.strokePath();

    drawDetail(canvas, detailArea, font);

    // Правая часть — таблица слоёв + примечания.
    final rightX = w * 0.55;
    final rightW = w - rightX - 8;
    var ry = h - 30;

    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 11.0,
        'Состав конструкции (по выноскам)', rightX, ry - 11);
    ry -= 18;

    // Заголовок таблицы.
    final colNum = 28.0;
    final colMat = rightW - 28 - 70 - 70;
    final colThk = 70.0;
    final colNorm = 70.0;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.setFillColor(PdfColors.grey200);
    canvas.drawRect(rightX, ry - 16, rightW, 16);
    canvas.fillPath();
    canvas.setFillColor(PdfColors.black);
    _drawCenteredText(
        canvas, font, 7.5, '№', rightX + colNum / 2, ry - 11);
    _drawCenteredText(canvas, font, 7.5, 'Материал / описание',
        rightX + colNum + colMat / 2, ry - 11);
    _drawCenteredText(canvas, font, 7.5, 'Толщина',
        rightX + colNum + colMat + colThk / 2, ry - 11);
    _drawCenteredText(canvas, font, 7.5, 'Норматив',
        rightX + colNum + colMat + colThk + colNorm / 2, ry - 11);
    canvas.drawRect(rightX, ry - 16, rightW, 16);
    canvas.strokePath();
    ry -= 16;

    // Строки таблицы.
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i];
      const rh = 16.0;
      ry -= rh;
      canvas.drawRect(rightX, ry, rightW, rh);
      canvas.strokePath();
      // Маркер с цветом слоя.
      canvas.setFillColor(l.color);
      canvas.drawRect(rightX + 4, ry + 4, 8, 8);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.3);
      canvas.drawRect(rightX + 4, ry + 4, 8, 8);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(canvas, font, 7.5, '${i + 1}',
          rightX + colNum / 2 + 6, ry + rh / 2 - 2.4);
      _drawText(canvas, font, 7.0, l.name,
          rightX + colNum + 4, ry + rh / 2 - 2.0);
      _drawCenteredText(canvas, font, 7.0, l.thickness,
          rightX + colNum + colMat + colThk / 2, ry + rh / 2 - 2.4);
      _drawCenteredText(canvas, font, 6.5, l.standard,
          rightX + colNum + colMat + colThk + colNorm / 2,
          ry + rh / 2 - 2.0);
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
    }
    // Вертикальные разделители.
    final dividers = [
      rightX + colNum,
      rightX + colNum + colMat,
      rightX + colNum + colMat + colThk,
    ];
    final headerTop = h - 30 - 18;
    for (final dx in dividers) {
      canvas.drawLine(dx, ry, dx, headerTop);
      canvas.strokePath();
    }

    // Примечания.
    ry -= 16;
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 9.0, 'Примечания', rightX, ry, bold: true);
    ry -= 11;
    for (final n in notes) {
      _drawText(canvas, font, 7.0, n, rightX, ry);
      ry -= 10;
    }
  }

  // ═══════════════════════════ У-1 КАРНИЗ ════════════════════════════════
  static pw.Page eaveNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final pick = RafterSectionPicker.pickFor(project);
    final rafterSection =
        '${pick.widthMm.round()}×${pick.heightMm.round()}';
    final rafterDepthMm = pick.heightMm.round();
    final slopeDeg = (project.roof.slopeAngle ?? 30).toDouble();
    final wallThickness =
        (project.walls.thickness?.round() ?? 400);
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-1',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-1. Карнизный свес',
      header: 'Узел У-1. Примыкание скатной кровли к наружной стене (карниз)',
      scaleLabel: '1 : 10',
      painter: (canvas, area, fnt) =>
          _paintEaveNode(canvas, area, fnt,
              slopeDeg: slopeDeg, rafterDepthMm: rafterDepthMm.toDouble()),
      layers: [
        const _DetailLayer('Кровельный материал (металлочерепица/керам.)',
            '0,5–25 мм', 'СП 17.13330', PdfColors.brown600),
        const _DetailLayer('Обрешётка (доска 25×100)', '25 мм',
            'СП 64.13330', PdfColors.amber400),
        const _DetailLayer('Контробрешётка (брус 50×50)', '50 мм',
            'СП 64.13330', PdfColors.amber700),
        const _DetailLayer('Гидроветрозащитная мембрана', '0,3 мм',
            'СП 17.13330', PdfColors.cyan200),
        _DetailLayer('Стропильная нога (доска $rafterSection)',
            '$rafterDepthMm мм', 'СП 64.13330', PdfColors.amber800),
        _DetailLayer('Утеплитель минвата ROCKWOOL',
            '$rafterDepthMm мм', 'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Пароизоляция', '0,2 мм', 'СП 50.13330',
            PdfColors.blue200),
        const _DetailLayer('Подшивка карниза (вагонка/софит)', '15 мм',
            'СП 17.13330', PdfColors.brown300),
        const _DetailLayer('Капельник + желоб (оцинк. сталь)', '0,5 мм',
            'СП 17.13330', PdfColors.grey500),
        _DetailLayer('Стена наружная',
            '$wallThickness мм', 'СП 15/55/64', PdfColors.grey400),
      ],
      notes: const [
        '1. Свес карниза — не менее 500 мм от плоскости стены.',
        '2. Капельник заводится за желоб, перекрытие ≥ 80 мм.',
        '3. Контробрешётка обеспечивает вентилируемый зазор ≥ 50 мм',
        '   между мембраной и кровлей (СП 17.13330 п. 6.5).',
        '4. Подшивка с вентиляционными отверстиями ≥ 1/400 от площади',
        '   чердака (СП 17.13330).',
        '5. Снегозадержатели — выше карниза по СП 17.13330 п. 8.6.',
        '6. Все деревянные элементы антисептированы по ГОСТ Р 53292,',
        '   огнезащита I группы (СП 2.13130).',
        '7. Узел соответствует Альбому ТСН-2007.7 «Жилые здания».',
      ],
      organization: organization,
    );
  }

  static void _paintEaveNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double slopeDeg = 30,
    double rafterDepthMm = 200,
  }) {
    // Координатная система: x вправо, y вверх. Стена слева, кровля
    // сверху-справа уходит под углом, заданным `slopeDeg` (из проекта).
    final cx = area.x + area.width / 2;

    // Стена (грубо bricks).
    final wallX = cx - 70;
    final wallW = 50.0;
    final wallY = area.y + 40;
    final wallH = area.height * 0.45;
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.strokePath();
    // Кладочные швы.
    canvas.setLineWidth(0.2);
    for (int i = 1; i < (wallH / 12).floor(); i++) {
      final y = wallY + i * 12;
      canvas.drawLine(wallX, y, wallX + wallW, y);
      canvas.strokePath();
    }
    for (int i = 1; i < (wallH / 12).floor(); i++) {
      final y = wallY + i * 12;
      final off = (i % 2 == 0) ? wallW * 0.5 : 0.0;
      canvas.drawLine(wallX + off, y, wallX + off, y - 12);
      canvas.strokePath();
    }

    // Мауэрлат на верху стены.
    final mlX = wallX + 4;
    final mlY = wallY + wallH;
    final mlW = wallW - 8;
    final mlH = 20.0;
    canvas.setFillColor(PdfColors.amber800);
    canvas.drawRect(mlX, mlY, mlW, mlH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(mlX, mlY, mlW, mlH);
    canvas.strokePath();
    // Пунктирные диагонали древесины.
    canvas.setLineWidth(0.2);
    canvas.drawLine(mlX, mlY, mlX + mlW, mlY + mlH);
    canvas.strokePath();
    canvas.drawLine(mlX, mlY + mlH, mlX + mlW, mlY);
    canvas.strokePath();

    // Стропилина — линия под углом slopeDeg (из проекта) от мауэрлата.
    final angle = slopeDeg * math.pi / 180.0;
    final ridgeStart = PdfPoint(mlX + mlW / 2, mlY + mlH);
    final rafterLen = 130.0;
    final rEnd = PdfPoint(
      ridgeStart.x + rafterLen * math.cos(angle),
      ridgeStart.y + rafterLen * math.sin(angle),
    );
    // Толщина (по высоте сечения) — пропорционально rafterDepthMm
    // в масштабе 1:10 (10 мм → 1 пт), но не меньше 12 пт для
    // визуальной читабельности.
    final rafterThk = math.max(12.0, rafterDepthMm / 10.0);
    // Строим прямоугольник стропилины как заливаемый параллелограмм.
    final nx = -math.sin(angle) * rafterThk;
    final ny = math.cos(angle) * rafterThk;
    canvas.setFillColor(PdfColors.amber700);
    canvas.moveTo(ridgeStart.x, ridgeStart.y);
    canvas.lineTo(rEnd.x, rEnd.y);
    canvas.lineTo(rEnd.x + nx, rEnd.y + ny);
    canvas.lineTo(ridgeStart.x + nx, ridgeStart.y + ny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(ridgeStart.x, ridgeStart.y);
    canvas.lineTo(rEnd.x, rEnd.y);
    canvas.lineTo(rEnd.x + nx, rEnd.y + ny);
    canvas.lineTo(ridgeStart.x + nx, ridgeStart.y + ny);
    canvas.lineTo(ridgeStart.x, ridgeStart.y);
    canvas.strokePath();

    // Утеплитель в плоскости стропилин (заполнение между стропил).
    canvas.setFillColor(PdfColors.yellow200);
    final ux = ridgeStart.x + nx + 1;
    final uy = ridgeStart.y + ny + 1;
    final uEndX = rEnd.x + nx - 1;
    final uEndY = rEnd.y + ny - 1;
    final uThk = 24.0;
    final unx = -math.sin(angle) * uThk;
    final uny = math.cos(angle) * uThk;
    canvas.moveTo(ux, uy);
    canvas.lineTo(uEndX, uEndY);
    canvas.lineTo(uEndX + unx, uEndY + uny);
    canvas.lineTo(ux + unx, uy + uny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.amber);
    canvas.setLineWidth(0.3);
    canvas.moveTo(ux, uy);
    canvas.lineTo(uEndX, uEndY);
    canvas.lineTo(uEndX + unx, uEndY + uny);
    canvas.lineTo(ux + unx, uy + uny);
    canvas.lineTo(ux, uy);
    canvas.strokePath();

    // Гидроветрозащита (тонкая линия поверх утеплителя).
    canvas.setStrokeColor(PdfColors.cyan700);
    canvas.setLineWidth(0.7);
    canvas.drawLine(ux + unx, uy + uny, uEndX + unx, uEndY + uny);
    canvas.strokePath();

    // Контробрешётка (квадратики).
    canvas.setFillColor(PdfColors.amber700);
    const crSize = 6.0;
    for (double t = 0.05; t < 0.95; t += 0.18) {
      final cx0 = ux + (uEndX - ux) * t + unx;
      final cy0 = uy + (uEndY - uy) * t + uny;
      // Поверх — параллельно стропилине.
      canvas.drawRect(cx0 - crSize / 2, cy0, crSize, crSize);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.3);
      canvas.drawRect(cx0 - crSize / 2, cy0, crSize, crSize);
      canvas.strokePath();
    }

    // Обрешётка — линия параллельная стропилине, поверх контробрешётки.
    canvas.setStrokeColor(PdfColors.amber400);
    canvas.setLineWidth(2.0);
    canvas.drawLine(ux + unx, uy + uny + crSize + 1,
        uEndX + unx, uEndY + uny + crSize + 1);
    canvas.strokePath();

    // Кровельное покрытие (коричневая полоса поверх обрешётки).
    canvas.setFillColor(PdfColors.brown600);
    final rcThk = 6.0;
    final rcOffset = crSize + 4;
    final rnx = -math.sin(angle) * rcThk;
    final rny = math.cos(angle) * rcThk;
    final rcStart = PdfPoint(
        ux + unx + (-math.sin(angle) * rcOffset),
        uy + uny + (math.cos(angle) * rcOffset));
    final rcEnd = PdfPoint(
        uEndX + unx + (-math.sin(angle) * rcOffset),
        uEndY + uny + (math.cos(angle) * rcOffset));
    canvas.moveTo(rcStart.x, rcStart.y);
    canvas.lineTo(rcEnd.x, rcEnd.y);
    canvas.lineTo(rcEnd.x + rnx, rcEnd.y + rny);
    canvas.lineTo(rcStart.x + rnx, rcStart.y + rny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(0.4);
    canvas.moveTo(rcStart.x, rcStart.y);
    canvas.lineTo(rcEnd.x, rcEnd.y);
    canvas.lineTo(rcEnd.x + rnx, rcEnd.y + rny);
    canvas.lineTo(rcStart.x + rnx, rcStart.y + rny);
    canvas.lineTo(rcStart.x, rcStart.y);
    canvas.strokePath();

    // Капельник + желоб (на конце свеса слева внизу).
    final eaveX = ridgeStart.x - 60;
    final eaveY = ridgeStart.y + 8;
    canvas.setFillColor(PdfColors.grey500);
    canvas.drawEllipse(eaveX, eaveY - 8, 6, 6);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawEllipse(eaveX, eaveY - 8, 6, 6);
    canvas.strokePath();

    // Подшивка карниза — горизонтальная планка под стропилиной от стены
    // до конца свеса.
    canvas.setFillColor(PdfColors.brown300);
    final psY = mlY + mlH - 4;
    canvas.drawRect(eaveX - 5, psY - 4, ridgeStart.x - eaveX + 5, 4);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawRect(eaveX - 5, psY - 4, ridgeStart.x - eaveX + 5, 4);
    canvas.strokePath();

    // Выносные линии с номерами 1…10.
    final callouts = <_Callout>[
      _Callout(rcEnd.x - 15, rcEnd.y + 6, '1'),
      _Callout(uEndX + unx + 6, uEndY + uny - 4, '2'),
      _Callout(uEndX + unx - 18, uEndY + uny + 8, '3'),
      _Callout(uEndX - 24, uEndY + 10, '4'),
      _Callout(rEnd.x - 30, rEnd.y - 12, '5'),
      _Callout(rEnd.x - 60, rEnd.y - 24, '6'),
      _Callout(ridgeStart.x + 8, ridgeStart.y - 4, '7'),
      _Callout(eaveX - 4, psY - 12, '8'),
      _Callout(eaveX + 6, eaveY - 14, '9'),
      _Callout(wallX + 4, wallY + wallH * 0.5, '10'),
    ];
    _drawCallouts(canvas, font, callouts);
  }

  // ═══════════════════════════ У-2 КОНЁК ════════════════════════════════
  static pw.Page ridgeNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final pick = RafterSectionPicker.pickFor(project);
    final rafterSection =
        '${pick.widthMm.round()}×${pick.heightMm.round()}';
    final rafterDepthMm = pick.heightMm.round();
    final slopeDeg = (project.roof.slopeAngle ?? 30).toDouble();
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-2',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-2. Конёк скатной кровли',
      header:
          'Узел У-2. Конёк (∠${slopeDeg.toStringAsFixed(0)}°, ' 
          'стропила $rafterSection)',
      scaleLabel: '1 : 5',
      painter: (canvas, area, fnt) => _paintRidgeNode(canvas, area, fnt,
          slopeDeg: slopeDeg, rafterDepthMm: rafterDepthMm.toDouble()),
      layers: [
        const _DetailLayer('Коньковый элемент (черепица/металл)',
            '0,5–25 мм', 'СП 17.13330', PdfColors.brown800),
        const _DetailLayer('Аэратор коньковый с сеткой', '40 мм',
            'СП 17.13330', PdfColors.grey400),
        _DetailLayer(
            'Кровельный материал: ${PdfBuilderMaterials.facadeRoofLabel(project.roof.roofingMaterial)}',
            '0,5–25 мм',
            'СП 17.13330',
            PdfColors.brown600),
        const _DetailLayer('Контробрешётка', '50 мм', 'СП 64.13330',
            PdfColors.amber700),
        const _DetailLayer('Гидроветрозащитная мембрана', '0,3 мм',
            'СП 17.13330', PdfColors.cyan200),
        _DetailLayer('Коньковый брус ${pick.widthMm.round()}×${pick.heightMm.round()}',
            '$rafterDepthMm мм', 'СП 64.13330', PdfColors.amber800),
        _DetailLayer('Стропильные ноги $rafterSection',
            '$rafterDepthMm мм', 'СП 64.13330', PdfColors.amber700),
        const _DetailLayer('Утеплитель минвата', '200 мм',
            'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Пароизоляция', '0,2 мм', 'СП 50.13330',
            PdfColors.blue200),
      ],
      notes: const [
        '1. Стропильные ноги соединяются на коньковый брус через',
        '   врубку «вполдерева» или металлические уголки.',
        '2. Между стропилами с разных скатов — зазор для аэратора',
        '   ≥ 50 мм, перекрывается коньковым элементом.',
        '3. Аэратор обеспечивает выход воздуха из подкровельного',
        '   пространства (СП 17.13330 п. 6.5).',
        '4. Гидроветрозащитная мембрана не должна перекрывать аэратор.',
        '5. В случае «холодного чердака» пароизоляция укладывается',
        '   по чердачному перекрытию, а не под кровлей.',
        '6. Все соединения — гвозди оцинкованные ГОСТ 4028,',
        '   диаметр 4 мм, длина ≥ 2,5×толщины элемента.',
      ],
      organization: organization,
    );
  }

  static void _paintRidgeNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double slopeDeg = 30,
    double rafterDepthMm = 200,
  }) {
    final cx = area.x + area.width / 2;
    final cy = area.y + area.height / 2;
    // Угол ската — из проекта пользователя. Толщина бруска (по высоте
    // сечения) — пропорциональна выбранному сечению (RafterSectionPicker)
    // в масштабе 1:10 (10 мм → 1 пт), не меньше 14 пт для читабельности.
    final angle = slopeDeg * math.pi / 180.0;

    // Левая стропилина (идёт вниз-влево).
    final ridgeTop = PdfPoint(cx, cy + 30);
    final rafterLen = 180.0;
    final lEnd = PdfPoint(
      ridgeTop.x - rafterLen * math.cos(angle),
      ridgeTop.y - rafterLen * math.sin(angle),
    );
    final rEnd = PdfPoint(
      ridgeTop.x + rafterLen * math.cos(angle),
      ridgeTop.y - rafterLen * math.sin(angle),
    );
    final rafterThk = math.max(14.0, rafterDepthMm / 10.0);
    // Левая стропилина — параллелограмм.
    final lnx = math.sin(angle) * rafterThk;
    final lny = -math.cos(angle) * rafterThk;
    canvas.setFillColor(PdfColors.amber700);
    canvas.moveTo(ridgeTop.x, ridgeTop.y);
    canvas.lineTo(lEnd.x, lEnd.y);
    canvas.lineTo(lEnd.x - lnx, lEnd.y - lny);
    canvas.lineTo(ridgeTop.x - lnx, ridgeTop.y - lny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(ridgeTop.x, ridgeTop.y);
    canvas.lineTo(lEnd.x, lEnd.y);
    canvas.lineTo(lEnd.x - lnx, lEnd.y - lny);
    canvas.lineTo(ridgeTop.x - lnx, ridgeTop.y - lny);
    canvas.lineTo(ridgeTop.x, ridgeTop.y);
    canvas.strokePath();

    // Правая стропилина.
    final rnx = math.sin(angle) * rafterThk;
    final rny = math.cos(angle) * rafterThk;
    canvas.setFillColor(PdfColors.amber700);
    canvas.moveTo(ridgeTop.x, ridgeTop.y);
    canvas.lineTo(rEnd.x, rEnd.y);
    canvas.lineTo(rEnd.x + rnx, rEnd.y - rny);
    canvas.lineTo(ridgeTop.x + rnx, ridgeTop.y - rny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(ridgeTop.x, ridgeTop.y);
    canvas.lineTo(rEnd.x, rEnd.y);
    canvas.lineTo(rEnd.x + rnx, rEnd.y - rny);
    canvas.lineTo(ridgeTop.x + rnx, ridgeTop.y - rny);
    canvas.lineTo(ridgeTop.x, ridgeTop.y);
    canvas.strokePath();

    // Коньковый брус — вертикальный прямоугольник по центру.
    canvas.setFillColor(PdfColors.amber800);
    canvas.drawRect(ridgeTop.x - 10, ridgeTop.y - 35, 20, 35);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(ridgeTop.x - 10, ridgeTop.y - 35, 20, 35);
    canvas.strokePath();
    canvas.setLineWidth(0.2);
    canvas.drawLine(ridgeTop.x - 10, ridgeTop.y - 35,
        ridgeTop.x + 10, ridgeTop.y);
    canvas.strokePath();
    canvas.drawLine(ridgeTop.x - 10, ridgeTop.y,
        ridgeTop.x + 10, ridgeTop.y - 35);
    canvas.strokePath();

    // Утеплитель — между стропилами в нижней части.
    canvas.setFillColor(PdfColors.yellow200);
    final ulnx = math.sin(angle) * 24;
    final ulny = -math.cos(angle) * 24;
    canvas.moveTo(ridgeTop.x - lnx - 1, ridgeTop.y - lny - 1);
    canvas.lineTo(lEnd.x - lnx - 1, lEnd.y - lny - 1);
    canvas.lineTo(lEnd.x - lnx - ulnx, lEnd.y - lny - ulny);
    canvas.lineTo(ridgeTop.x - lnx - ulnx, ridgeTop.y - lny - ulny);
    canvas.fillPath();
    canvas.moveTo(ridgeTop.x + rnx + 1, ridgeTop.y - rny + 1);
    canvas.lineTo(rEnd.x + rnx + 1, rEnd.y - rny + 1);
    canvas.lineTo(rEnd.x + rnx + ulnx, rEnd.y - rny + ulny);
    canvas.lineTo(ridgeTop.x + rnx + ulnx, ridgeTop.y - rny + ulny);
    canvas.fillPath();

    // Кровельный материал — две полосы.
    canvas.setFillColor(PdfColors.brown600);
    final rcThk = 5.0;
    // Левый скат — поверх стропилины (наружная сторона).
    final lcStart = PdfPoint(ridgeTop.x, ridgeTop.y + 8);
    final lcEnd = PdfPoint(
        lEnd.x - math.cos(angle) * 5, lEnd.y + 8);
    final lcnx = math.sin(angle) * rcThk;
    final lcny = -math.cos(angle) * rcThk;
    canvas.moveTo(lcStart.x, lcStart.y);
    canvas.lineTo(lcEnd.x, lcEnd.y);
    canvas.lineTo(lcEnd.x + lcnx, lcEnd.y + lcny);
    canvas.lineTo(lcStart.x + lcnx, lcStart.y + lcny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(0.4);
    canvas.moveTo(lcStart.x, lcStart.y);
    canvas.lineTo(lcEnd.x, lcEnd.y);
    canvas.strokePath();
    final rcEnd2 = PdfPoint(rEnd.x + math.cos(angle) * 5, rEnd.y + 8);
    canvas.setFillColor(PdfColors.brown600);
    canvas.moveTo(lcStart.x, lcStart.y);
    canvas.lineTo(rcEnd2.x, rcEnd2.y);
    canvas.lineTo(rcEnd2.x - lcnx, rcEnd2.y + lcny);
    canvas.lineTo(lcStart.x - lcnx, lcStart.y + lcny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.drawLine(lcStart.x, lcStart.y, rcEnd2.x, rcEnd2.y);
    canvas.strokePath();

    // Коньковый элемент.
    canvas.setFillColor(PdfColors.brown800);
    canvas.moveTo(ridgeTop.x - 30, ridgeTop.y + 14);
    canvas.lineTo(ridgeTop.x, ridgeTop.y + 26);
    canvas.lineTo(ridgeTop.x + 30, ridgeTop.y + 14);
    canvas.lineTo(ridgeTop.x + 30, ridgeTop.y + 8);
    canvas.lineTo(ridgeTop.x - 30, ridgeTop.y + 8);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(ridgeTop.x - 30, ridgeTop.y + 14);
    canvas.lineTo(ridgeTop.x, ridgeTop.y + 26);
    canvas.lineTo(ridgeTop.x + 30, ridgeTop.y + 14);
    canvas.lineTo(ridgeTop.x + 30, ridgeTop.y + 8);
    canvas.lineTo(ridgeTop.x - 30, ridgeTop.y + 8);
    canvas.lineTo(ridgeTop.x - 30, ridgeTop.y + 14);
    canvas.strokePath();

    // Аэратор — серая линия с сеткой между двумя скатами под коньком.
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawRect(ridgeTop.x - 26, ridgeTop.y + 2, 52, 6);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    for (double xx = -24; xx <= 24; xx += 4) {
      canvas.drawLine(ridgeTop.x + xx, ridgeTop.y + 2,
          ridgeTop.x + xx, ridgeTop.y + 8);
      canvas.strokePath();
    }

    // Пароизоляция — на нижней стороне утеплителя.
    canvas.setStrokeColor(PdfColors.blue700);
    canvas.setLineWidth(0.7);
    canvas.drawLine(ridgeTop.x - lnx - ulnx, ridgeTop.y - lny - ulny,
        lEnd.x - lnx - ulnx, lEnd.y - lny - ulny);
    canvas.strokePath();
    canvas.drawLine(ridgeTop.x + rnx + ulnx, ridgeTop.y - rny + ulny,
        rEnd.x + rnx + ulnx, rEnd.y - rny + ulny);
    canvas.strokePath();

    // Якоря выносок — точки на самих элементах. Кружки расставит
    // _drawLeaderCallouts вне чертежа на правом поле.
    final anchors = <_Callout>[
      // 1 — коньковый элемент (вершина «крышечки»).
      _Callout(ridgeTop.x, ridgeTop.y + 26, '1'),
      // 2 — аэратор коньковый.
      _Callout(ridgeTop.x, ridgeTop.y + 5, '2'),
      // 3 — кровельный материал (середина левого ската).
      _Callout((ridgeTop.x + lEnd.x) / 2, (ridgeTop.y + lEnd.y) / 2 + 8, '3'),
      // 4 — контробрешётка (на скате чуть ниже кровли).
      _Callout((ridgeTop.x + lEnd.x) / 2 - 6,
          (ridgeTop.y + lEnd.y) / 2 + 4, '4'),
      // 5 — гидроветрозащита.
      _Callout((ridgeTop.x + lEnd.x) / 2 - 14,
          (ridgeTop.y + lEnd.y) / 2 - 2, '5'),
      // 6 — коньковый брус.
      _Callout(ridgeTop.x, ridgeTop.y - 17, '6'),
      // 7 — стропильная нога (середина правой стропилы).
      _Callout((ridgeTop.x + rEnd.x) / 2 + rnx / 2,
          (ridgeTop.y + rEnd.y) / 2 - rny / 2, '7'),
      // 8 — утеплитель (между стропилами слева).
      _Callout(ridgeTop.x - lnx - 12, ridgeTop.y - lny - 12, '8'),
      // 9 — пароизоляция (нижняя сторона утеплителя слева).
      _Callout(ridgeTop.x - lnx - 24, ridgeTop.y - lny - 24, '9'),
    ];
    _drawLeaderCallouts(canvas, font, area, anchors);

    // Размерные подписи: угол ската, длина стропилины, отметка конька.
    _drawText(canvas, font, 7,
        '∠ ${slopeDeg.toStringAsFixed(0)}°',
        ridgeTop.x - 80, ridgeTop.y - 6);
    _drawText(canvas, font, 7,
        'h сечения = ${rafterDepthMm.round()} мм',
        ridgeTop.x - 80, ridgeTop.y - 16);
  }

  // ═════════════════════════ У-3 ОКОННЫЙ ОТКОС ═══════════════════════════
  static pw.Page windowJambNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final wallThicknessMm = project.walls.thickness?.round() ?? 400;
    // Типовая ширина окна для жилого дома (СП 54.13330) — 1500 мм;
    // в проекте размеры окон варьируются, но для масштабного узла мы
    // показываем боковой откос — конкретное значение не критично.
    const windowWidthMm = 1500;
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-3',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-3. Оконный откос',
      header:
          'Узел У-3. Боковой откос оконного блока ' 
          '(стена $wallThicknessMm мм)',
      scaleLabel: '1 : 5',
      painter: (canvas, area, fnt) => _paintWindowJambNode(
          canvas, area, fnt,
          wallThicknessMm: wallThicknessMm.toDouble(),
          windowWidthMm: windowWidthMm.toDouble()),
      layers: [
        _DetailLayer('Стена наружная',
            '$wallThicknessMm мм', 'СП 15/55/64', PdfColors.grey400),
        const _DetailLayer('Четверть наружная (выступ ≥40 мм)',
            '40 мм', 'ГОСТ 30971', PdfColors.grey500),
        const _DetailLayer('ПСУЛ-лента наружная', '15 мм',
            'ГОСТ 30971', PdfColors.deepOrange),
        const _DetailLayer('Монтажная пена ПУ', '20–30 мм',
            'ГОСТ 30971', PdfColors.yellow100),
        const _DetailLayer('Пароизоляционная лента внутр.', '0,5 мм',
            'ГОСТ 30971', PdfColors.blue200),
        const _DetailLayer('Утеплитель ЭППС / минвата', '40 мм',
            'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Оконный профиль ПВХ / клеёный брус',
            '70 мм', 'ГОСТ 30674', PdfColors.grey700),
        const _DetailLayer('Стеклопакет двухкамерный', '40 мм',
            'ГОСТ 24866', PdfColors.cyan100),
        const _DetailLayer('Откос внутренний (ГКЛ + штукатурка)',
            '12,5 мм', 'СП 73.13330', PdfColors.grey200),
      ],
      notes: const [
        '1. Монтаж по ГОСТ 30971-2012 «Швы монтажные».',
        '2. Наружная ПСУЛ — паропроницаемая, защищает от влаги',
        '   и обеспечивает выход пара из шва наружу.',
        '3. Внутренняя пароизоляция — герметичная, предотвращает',
        '   увлажнение монтажной пены изнутри.',
        '4. Утеплитель откоса — обязательное условие предотвращения',
        '   «мостика холода» (СП 50.13330 п. 5.7).',
        '5. Зазор между блоком и четвертью — 20–30 мм',
        '   (под расширение/усадку).',
        '6. Точка росы при расчётной t = +20° / отн. влаж. 55%',
        '   должна находиться внутри утеплителя.',
        '7. Глубина установки от наружной грани — 1/3 толщины стены.',
      ],
      organization: organization,
    );
  }

  static void _paintWindowJambNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double wallThicknessMm = 400,
    double windowWidthMm = 1500,
  }) {
    // План откоса: горизонтальный разрез сверху вниз. Слева — наружная
    // часть стены (ниже на чертеже), справа — внутренняя.
    // Толщина стены — из проекта, в масштабе 1:2.5 (1 мм → 0.4 пт),
    // но не меньше 80 пт для читабельности; ширина окна — для подписи.
    final cx = area.x + area.width / 2;
    final cy = area.y + area.height / 2;
    final wallThk = math.max(80.0, wallThicknessMm * 0.4);
    final wallH = 200.0;
    final wallX = cx - wallThk / 2;
    final wallY = cy - wallH / 2;

    // Стена с кладочной штриховкой.
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawRect(wallX, wallY, wallThk, wallH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(wallX, wallY, wallThk, wallH);
    canvas.strokePath();
    // Наружная и внутренняя метки.
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 7.0, '↓ наружу',
        wallX + 6, wallY - 12);
    _drawText(canvas, font, 7.0, '↑ помещение',
        wallX + 6, wallY + wallH + 4);

    // Оконный проём — снизу, прорезает стену с четвертью.
    final qH = 30.0;
    final qW = wallThk * 0.65; // оконная ширина
    final qX = wallX + (wallThk - qW) / 2;
    final qY = wallY; // верхняя кромка стены = низ проёма (план сверху)
    canvas.setFillColor(PdfColors.white);
    canvas.drawRect(qX, qY - 1, qW, qH + 2);
    canvas.fillPath();
    // Наружная четверть — выступ внутрь проёма с улицы.
    canvas.setFillColor(PdfColors.grey500);
    final qrtW = 12.0;
    canvas.drawRect(qX - qrtW, qY, qrtW, qH);
    canvas.fillPath();
    canvas.drawRect(qX + qW, qY, qrtW, qH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(qX - qrtW, qY, qrtW, qH);
    canvas.strokePath();
    canvas.drawRect(qX + qW, qY, qrtW, qH);
    canvas.strokePath();

    // Оконный профиль (сам блок).
    canvas.setFillColor(PdfColors.grey700);
    final wpW = qW - 8;
    final wpX = qX + 4;
    final wpY = qY + 8;
    canvas.drawRect(wpX, wpY, wpW, 12);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(wpX, wpY, wpW, 12);
    canvas.strokePath();

    // Стеклопакет — голубая полоса.
    canvas.setFillColor(PdfColors.cyan100);
    canvas.drawRect(wpX + 3, wpY + 3, wpW - 6, 6);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.cyan700);
    canvas.setLineWidth(0.3);
    canvas.drawRect(wpX + 3, wpY + 3, wpW - 6, 6);
    canvas.strokePath();
    // Две стеклинки (двухкамерный).
    canvas.drawLine(wpX + 6, wpY + 3, wpX + 6, wpY + 9);
    canvas.strokePath();
    canvas.drawLine(wpX + wpW - 6, wpY + 3, wpX + wpW - 6, wpY + 9);
    canvas.strokePath();

    // Монтажная пена в зазоре — между четвертью и оконным профилем.
    canvas.setFillColor(PdfColors.yellow100);
    canvas.drawRect(qX, qY, 4, qH);
    canvas.fillPath();
    canvas.drawRect(qX + qW - 4, qY, 4, qH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.yellow700);
    canvas.setLineWidth(0.3);
    canvas.drawRect(qX, qY, 4, qH);
    canvas.strokePath();
    canvas.drawRect(qX + qW - 4, qY, 4, qH);
    canvas.strokePath();

    // ПСУЛ наружная — оранжевая лента у наружной четверти.
    canvas.setFillColor(PdfColors.deepOrange);
    canvas.drawRect(qX, qY, 4, 4);
    canvas.fillPath();
    canvas.drawRect(qX + qW - 4, qY, 4, 4);
    canvas.fillPath();

    // Пароизоляция внутренняя — синяя лента.
    canvas.setFillColor(PdfColors.blue700);
    canvas.drawRect(qX, qY + qH - 3, 4, 3);
    canvas.fillPath();
    canvas.drawRect(qX + qW - 4, qY + qH - 3, 4, 3);
    canvas.fillPath();

    // Утеплитель откоса (ЭППС) — жёлтая полоса вдоль четверти изнутри.
    canvas.setFillColor(PdfColors.yellow200);
    canvas.drawRect(qX - qrtW, qY + qH, qrtW, 16);
    canvas.fillPath();
    canvas.drawRect(qX + qW, qY + qH, qrtW, 16);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawRect(qX - qrtW, qY + qH, qrtW, 16);
    canvas.strokePath();
    canvas.drawRect(qX + qW, qY + qH, qrtW, 16);
    canvas.strokePath();

    // Откос внутренний (ГКЛ).
    canvas.setFillColor(PdfColors.grey200);
    canvas.drawRect(qX - qrtW - 4, qY + qH + 16, qrtW + 4, 4);
    canvas.fillPath();
    canvas.drawRect(qX + qW, qY + qH + 16, qrtW + 4, 4);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(qX - qrtW - 4, qY + qH + 16, qrtW + 4, 4);
    canvas.strokePath();
    canvas.drawRect(qX + qW, qY + qH + 16, qrtW + 4, 4);
    canvas.strokePath();

    // Размерная цепь по верху проёма (наружная сторона) — реальная
    // ширина окна из проекта (windowWidthMm), а не геометрическая
    // длина чертежа.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    final dimY = wallY - 22;
    canvas.drawLine(qX - qrtW, dimY, qX + qW + qrtW, dimY);
    canvas.strokePath();
    canvas.drawLine(qX - qrtW, dimY - 3, qX - qrtW, dimY + 3);
    canvas.strokePath();
    canvas.drawLine(qX + qW + qrtW, dimY - 3, qX + qW + qrtW, dimY + 3);
    canvas.strokePath();
    _drawText(canvas, font, 7.0,
        '${windowWidthMm.round()}', cx - 12, dimY + 4);

    // Размерная цепь по толщине стены (вертикальная справа от стены).
    final dimX2 = wallX + wallThk + 14;
    canvas.drawLine(dimX2, wallY, dimX2, wallY + wallH);
    canvas.strokePath();
    canvas.drawLine(dimX2 - 3, wallY, dimX2 + 3, wallY);
    canvas.strokePath();
    canvas.drawLine(dimX2 - 3, wallY + wallH, dimX2 + 3, wallY + wallH);
    canvas.strokePath();
    _drawText(canvas, font, 7.0,
        '${wallThicknessMm.round()}', dimX2 + 4, wallY + wallH / 2 - 2);

    // Якоря выносок — на самих элементах. Кружки разнесёт
    // _drawLeaderCallouts вне чертежа (на правом поле).
    final anchors = <_Callout>[
      // 1 — стена наружная (центр стены).
      _Callout(wallX + wallThk / 4, wallY + wallH * 0.7, '1'),
      // 2 — четверть (наружный выступ внутрь проёма).
      _Callout(qX - qrtW / 2, qY + qH * 0.5, '2'),
      // 3 — ПСУЛ (оранжевая лента у наружной четверти).
      _Callout(qX + 2, qY + 2, '3'),
      // 4 — монтажная пена.
      _Callout(qX + 2, qY + qH * 0.5, '4'),
      // 5 — пароизоляция (внутренняя сторона).
      _Callout(qX + 2, qY + qH - 1, '5'),
      // 6 — утеплитель откоса.
      _Callout(qX - qrtW / 2, qY + qH + 8, '6'),
      // 7 — оконный профиль.
      _Callout(wpX + wpW / 4, wpY + 6, '7'),
      // 8 — стеклопакет.
      _Callout(wpX + wpW / 2, wpY + 6, '8'),
      // 9 — откос внутренний (ГКЛ).
      _Callout(qX - qrtW - 2, qY + qH + 18, '9'),
    ];
    _drawLeaderCallouts(canvas, font, area, anchors);
  }

  // ═══════════════════════ У-4 СТРОПИЛО НА МАУЭРЛАТЕ ═════════════════════
  static pw.Page rafterMauerlatNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final pick = RafterSectionPicker.pickFor(project);
    final rafterSection =
        '${pick.widthMm.round()}×${pick.heightMm.round()}';
    final rafterDepthMm = pick.heightMm.round();
    final slopeDeg = (project.roof.slopeAngle ?? 30).toDouble();
    final wallThicknessMm = project.walls.thickness?.round() ?? 400;
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-4',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-4. Опирание стропилины на мауэрлат',
      header: 'Узел У-4. Опорный узел стропильной ноги на мауэрлат',
      scaleLabel: '1 : 5',
      painter: (canvas, area, fnt) =>
          _paintRafterMauerlatNode(canvas, area, fnt,
              slopeDeg: slopeDeg, rafterDepthMm: rafterDepthMm.toDouble()),
      layers: [
        _DetailLayer('Стропильная нога $rafterSection',
            '$rafterDepthMm мм', 'СП 64.13330', PdfColors.amber700),
        const _DetailLayer('Запил «зуб» в стропилине', 'h ≥ 50 мм',
            'СП 64.13330', PdfColors.amber900),
        const _DetailLayer('Мауэрлат — брус 100×150', '150 мм',
            'СП 64.13330', PdfColors.amber800),
        const _DetailLayer('Гидроизоляция (рубероид) 2 слоя',
            '6 мм', 'СП 17.13330', PdfColors.brown900),
        const _DetailLayer('Армопояс ж/б B25 200×200', '200 мм',
            'СП 63.13330', PdfColors.grey300),
        const _DetailLayer('Анкер фундаментный M12 шаг 1 м',
            'L=300 мм', 'ГОСТ 24379', PdfColors.grey700),
        const _DetailLayer('Уголок ст. ГОСТ 8509 50×50×4',
            '4 мм', 'ГОСТ 8509', PdfColors.blueGrey400),
        const _DetailLayer('Болт M10×120 с гайкой', '6 шт',
            'ГОСТ 7798', PdfColors.grey800),
        _DetailLayer('Стена наружная',
            '$wallThicknessMm мм', 'СП 15/55/64', PdfColors.grey400),
      ],
      notes: const [
        '1. Стропильная нога опирается на мауэрлат через запил',
        '   «зуб» (треугольный пропил) глубиной h ≥ 50 мм.',
        '2. Угол запила = углу наклона стропилины (СП 64).',
        '3. Скользящее соединение допустимо для лёгких кровель',
        '   (соединение «скоба»).',
        '4. Жёсткое соединение через стальной уголок —',
        '   обязательно для тяжёлых кровель (керамика, цемент-песк.).',
        '5. Между мауэрлатом и кладкой — 2 слоя рубероида',
        '   (отсечка капиллярной влаги).',
        '6. Мауэрлат заанкерён в армопояс с шагом 1000 мм.',
        '7. Огнезащита I группы (СП 2.13130).',
      ],
      organization: organization,
    );
  }

  static void _paintRafterMauerlatNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double slopeDeg = 30,
    double rafterDepthMm = 200,
  }) {
    final cx = area.x + area.width / 2;
    final cy = area.y + area.height / 2;

    // Кладка стены (внизу).
    final wallW = 180.0;
    final wallH = 100.0;
    final wallX = cx - wallW / 2;
    final wallY = cy - wallH;
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.strokePath();
    // Кладочные швы.
    canvas.setLineWidth(0.2);
    for (int i = 1; i < 7; i++) {
      final y = wallY + i * 12;
      canvas.drawLine(wallX, y, wallX + wallW, y);
      canvas.strokePath();
    }

    // Армопояс — серый прямоугольник на верху стены.
    final apY = wallY + wallH;
    canvas.setFillColor(PdfColors.grey300);
    canvas.drawRect(wallX, apY, wallW, 24);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(wallX, apY, wallW, 24);
    canvas.strokePath();
    // Точки арматуры (4 шт).
    canvas.setFillColor(PdfColors.black);
    for (final ax in [wallX + 6, wallX + wallW - 6]) {
      for (final ay in [apY + 6, apY + 18]) {
        canvas.drawEllipse(ax, ay, 1.6, 1.6);
        canvas.fillPath();
      }
    }
    _drawText(canvas, font, 6.0, '4Ø12 А500С',
        wallX + 4, apY + 11);

    // Гидроизоляция — две тонкие линии поверх армопояса.
    final hiY = apY + 24;
    canvas.setStrokeColor(PdfColors.brown900);
    canvas.setLineWidth(1.2);
    canvas.drawLine(wallX, hiY + 1, wallX + wallW, hiY + 1);
    canvas.strokePath();
    canvas.drawLine(wallX, hiY + 4, wallX + wallW, hiY + 4);
    canvas.strokePath();

    // Мауэрлат — деревянный брус поверх гидроизоляции.
    final mlW = 100.0;
    final mlH = 30.0;
    final mlX = cx - mlW / 2;
    final mlY = hiY + 6;
    canvas.setFillColor(PdfColors.amber800);
    canvas.drawRect(mlX, mlY, mlW, mlH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(mlX, mlY, mlW, mlH);
    canvas.strokePath();
    canvas.setLineWidth(0.2);
    canvas.drawLine(mlX, mlY, mlX + mlW, mlY + mlH);
    canvas.strokePath();
    canvas.drawLine(mlX, mlY + mlH, mlX + mlW, mlY);
    canvas.strokePath();

    // Анкер — вертикальная линия с шляпкой в армопоясе.
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(1.4);
    canvas.drawLine(cx, mlY + mlH - 4, cx, apY + 6);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.grey800);
    canvas.drawEllipse(cx, mlY + mlH - 4, 2.4, 2.4);
    canvas.fillPath();

    // Стропильная нога — поднимается от мауэрлата под углом slopeDeg
    // (значение из проекта пользователя, СП 17.13330).
    final angle = slopeDeg * math.pi / 180.0;
    final rfStart = PdfPoint(mlX + mlW * 0.55, mlY + mlH);
    // Запил «зуб»: вырезаем треугольник снизу стропилины.
    final rafterLen = 140.0;
    final rEnd = PdfPoint(
        rfStart.x + rafterLen * math.cos(angle),
        rfStart.y + rafterLen * math.sin(angle));
    // Толщина в масштабе 1:5 — высота сечения стропилы из расчёта
    // (RafterSectionPicker), 5 мм = 1 пт; не меньше 18 пт для
    // визуальной читабельности.
    final rafterThk = math.max(18.0, rafterDepthMm / 5.0);
    final nx = -math.sin(angle) * rafterThk;
    final ny = math.cos(angle) * rafterThk;
    canvas.setFillColor(PdfColors.amber700);
    canvas.moveTo(rfStart.x - 10, rfStart.y);
    canvas.lineTo(rfStart.x + 10, rfStart.y - 8);
    canvas.lineTo(rEnd.x, rEnd.y - 4);
    canvas.lineTo(rEnd.x + nx, rEnd.y + ny - 4);
    canvas.lineTo(rfStart.x + nx - 10, rfStart.y + ny);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(rfStart.x - 10, rfStart.y);
    canvas.lineTo(rfStart.x + 10, rfStart.y - 8);
    canvas.lineTo(rEnd.x, rEnd.y - 4);
    canvas.lineTo(rEnd.x + nx, rEnd.y + ny - 4);
    canvas.lineTo(rfStart.x + nx - 10, rfStart.y + ny);
    canvas.lineTo(rfStart.x - 10, rfStart.y);
    canvas.strokePath();

    // Стальной уголок — короткая линия снизу стропилины к мауэрлату.
    canvas.setStrokeColor(PdfColors.blueGrey400);
    canvas.setLineWidth(2.0);
    canvas.drawLine(rfStart.x - 4, rfStart.y - 4,
        rfStart.x + 14, rfStart.y - 12);
    canvas.strokePath();
    canvas.drawLine(rfStart.x - 4, rfStart.y - 4,
        rfStart.x - 14, rfStart.y - 4);
    canvas.strokePath();

    // Болт.
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.7);
    canvas.drawLine(rfStart.x + 8, rfStart.y - 10,
        rfStart.x + 8, mlY + mlH - 10);
    canvas.strokePath();

    // Размерные цепи и отметки. Все значения — реальные, из проекта:
    // угол (slopeDeg) и сечение стропилы, толщина стены wallW (показ),
    // высота армопояса (24 пт), глубина запила.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    // Цепь: высота армопояса.
    final dimXap = wallX - 18;
    canvas.drawLine(dimXap, apY, dimXap, apY + 24);
    canvas.strokePath();
    canvas.drawLine(dimXap - 3, apY, dimXap + 3, apY);
    canvas.strokePath();
    canvas.drawLine(dimXap - 3, apY + 24, dimXap + 3, apY + 24);
    canvas.strokePath();
    _drawText(canvas, font, 6.5, '200', dimXap - 16, apY + 11);
    _drawText(canvas, font, 6.5, '(армопояс)', dimXap - 22, apY + 24);
    // Отметка: уровень мауэрлата.
    canvas.drawLine(mlX - 36, mlY, mlX, mlY);
    canvas.strokePath();
    _drawText(canvas, font, 7,
        'отм. + ${(0.2 + 0.006 + 0.006).toStringAsFixed(3)}',
        mlX - 80, mlY - 2);
    // Метка угла.
    _drawText(canvas, font, 7,
        '∠ ${slopeDeg.toStringAsFixed(0)}°',
        rfStart.x + 30, rfStart.y - 18);
    // Сечение стропилы.
    _drawText(canvas, font, 7,
        '${rafterDepthMm.round()} мм (h)',
        rfStart.x + 80, rfStart.y - 6);

    // Якоря выносок — на самих элементах. Кружки разнесёт
    // _drawLeaderCallouts вне чертежа (на правом поле).
    final anchors = <_Callout>[
      // 1 — стропильная нога (середина бруса).
      _Callout((rfStart.x + rEnd.x) / 2 + nx / 2,
          (rfStart.y + rEnd.y) / 2 + ny / 2, '1'),
      // 2 — запил «зуб» в стропилине.
      _Callout(rfStart.x + 4, rfStart.y - 4, '2'),
      // 3 — мауэрлат.
      _Callout(mlX + mlW * 0.7, mlY + mlH / 2, '3'),
      // 4 — гидроизоляция.
      _Callout(wallX + wallW * 0.5, hiY + 2, '4'),
      // 5 — армопояс.
      _Callout(wallX + wallW * 0.5, apY + 12, '5'),
      // 6 — анкер.
      _Callout(cx, apY + 12, '6'),
      // 7 — стальной уголок.
      _Callout(rfStart.x + 4, rfStart.y - 8, '7'),
      // 8 — болт.
      _Callout(rfStart.x + 8, mlY + mlH / 2, '8'),
      // 9 — стена наружная.
      _Callout(wallX + wallW * 0.2, wallY + wallH * 0.6, '9'),
    ];
    _drawLeaderCallouts(canvas, font, area, anchors);
  }

  // ═════════════════════ У-5 ЦОКОЛЬ + ОТМОСТКА ═══════════════════════════
  static pw.Page plinthApronNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final fp = FoundationPlanGenerator.generate(project);
    final foundationLabel = fp?.typeLabel ?? 'Фундамент (по выбору)';
    // Цоколь зависит от типа фундамента: для свай/ростверка он
    // выше (0.5 м), для плиты — отсутствует, для ленты — 0.4 м.
    var plinthHeightM = 0.4;
    if (fp != null) {
      switch (fp.type) {
        case FoundationType.slab:
          plinthHeightM = 0.0;
          break;
        case FoundationType.pile:
        case FoundationType.pileWithGrillage:
        case FoundationType.columnar:
          plinthHeightM = 0.5;
          break;
        case FoundationType.strip:
          plinthHeightM = 0.4;
          break;
      }
    }
    final plinthMm = (plinthHeightM * 1000).round();
    final foundDepthM = (fp?.depthM ?? 1.5);
    final wallThicknessMm = project.walls.thickness?.round() ?? 400;
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-5',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-5. Цоколь и отмостка',
      header:
          'Узел У-5. Цоколь, отмостка, гидроизоляция (${foundationLabel.toLowerCase()})',
      scaleLabel: '1 : 10',
      painter: (canvas, area, fnt) => _paintPlinthApronNode(canvas, area, fnt,
          plinthHeightMm: plinthMm.toDouble(),
          foundDepthM: foundDepthM,
          foundationLabel: foundationLabel),
      layers: [
        _DetailLayer('Стена наружная',
            '$wallThicknessMm мм', 'СП 15/55/64', PdfColors.grey400),
        const _DetailLayer('Гидроизоляция горизонт. (рубероид 2 сл.)',
            '6 мм', 'СП 17.13330', PdfColors.brown900),
        _DetailLayer('Цоколь (бетон / кирпич полнотелый)',
            'h = $plinthMm мм', 'СП 22/63', PdfColors.grey500),
        const _DetailLayer('Гидроизоляция вертик. (обмазка)',
            '2 мм', 'СП 22.13330', PdfColors.blueGrey700),
        const _DetailLayer('Утеплитель ЭППС цоколя', '50 мм',
            'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Защитная штукатурка/панель',
            '20 мм', 'СП 73.13330', PdfColors.grey300),
        const _DetailLayer('Отмостка ж/б М200, уклон 3%',
            '80 мм', 'СП 22.13330', PdfColors.grey400),
        const _DetailLayer('Песчаная подготовка', '50 мм',
            'СП 22.13330', PdfColors.yellow100),
        const _DetailLayer('Щебневая подготовка',
            '100 мм', 'СП 22.13330', PdfColors.grey600),
        const _DetailLayer('Дренажная труба DN110 в геотекстиле',
            'Ø110', 'СП 104.13330', PdfColors.cyan700),
        _DetailLayer(foundationLabel,
            'h = ${foundDepthM.toStringAsFixed(1)} м',
            'СП 22.13330', PdfColors.brown400),
      ],
      notes: const [
        '1. Высота цоколя над землёй ≥ 400 мм (СП 54).',
        '2. Уклон отмостки 3–10% от стены, ширина ≥ 800 мм',
        '   (СП 22.13330 п. 6.10).',
        '3. Между отмосткой и цоколем — деформационный шов',
        '   с герметиком (предотвращает разрыв при пучении).',
        '4. Утеплитель цоколя обязателен для ленточных и плитных',
        '   фундаментов (СП 50.13330) — снижает теплопотери на 15%.',
        '5. Дренажная труба DN110 уложена ниже подошвы фундамента',
        '   с уклоном 0,5% к колодцу, обмотана геотекстилем.',
        '6. Глубина заложения подошвы ≥ глубины промерзания + 100 мм',
        '   (СП 22.13330 для региона по СП 131).',
        '7. Гидроизоляция вертикальная — мастика битумно-полимерная,',
        '   2 слоя, защищена ЭППС от механических повреждений.',
      ],
      organization: organization,
    );
  }

  static void _paintPlinthApronNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double plinthHeightMm = 400,
    double foundDepthM = 1.5,
    String foundationLabel = 'Фундамент',
  }) {
    final cx = area.x + area.width / 2;
    final cy = area.y + area.height / 2;

    // Земля — нижняя половина с коричневой заливкой.
    canvas.setFillColor(PdfColors.brown400);
    final groundY = cy - 30;
    canvas.drawRect(area.x, area.y, area.width, groundY - area.y);
    canvas.fillPath();
    // Точки грунта (штриховка из точек).
    canvas.setFillColor(PdfColors.brown900);
    final rng = math.Random(42);
    for (int i = 0; i < 80; i++) {
      final px = area.x + rng.nextDouble() * area.width;
      final py = area.y + rng.nextDouble() * (groundY - area.y);
      canvas.drawEllipse(px, py, 0.6, 0.6);
      canvas.fillPath();
    }

    // Стена + цоколь — справа от центра вверх. Высота цоколя
    // (от уровня земли до низа стены) — берётся из проекта пользователя
    // (тип фундамента → plinthHeightMm). Масштаб 1:10 (10 мм = 1 пт),
    // не меньше 12 пт для визуальной читабельности (даже для плиты,
    // где цоколь почти отсутствует, рисуем плоскость отметки).
    final wallX = cx - 30;
    final wallW = 60.0;
    final plinthBottom = groundY - 40;
    final plinthVisHeight = math.max(12.0, plinthHeightMm / 10.0);
    final plinthTop = groundY + plinthVisHeight;
    canvas.setFillColor(PdfColors.grey500);
    canvas.drawRect(wallX, plinthBottom, wallW, plinthTop - plinthBottom);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(wallX, plinthBottom, wallW, plinthTop - plinthBottom);
    canvas.strokePath();

    // Стена выше цоколя.
    final wallTop = area.y + area.height - 20;
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawRect(wallX, plinthTop, wallW, wallTop - plinthTop);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(wallX, plinthTop, wallW, wallTop - plinthTop);
    canvas.strokePath();
    // Кладочные швы.
    canvas.setLineWidth(0.2);
    for (double y = plinthTop + 12; y < wallTop; y += 12) {
      canvas.drawLine(wallX, y, wallX + wallW, y);
      canvas.strokePath();
    }

    // Гидроизоляция горизонт. между цоколем и стеной.
    canvas.setStrokeColor(PdfColors.brown900);
    canvas.setLineWidth(1.4);
    canvas.drawLine(wallX, plinthTop + 1, wallX + wallW, plinthTop + 1);
    canvas.strokePath();
    canvas.drawLine(wallX, plinthTop + 4, wallX + wallW, plinthTop + 4);
    canvas.strokePath();

    // Гидроизоляция вертик. (синяя полоса снаружи цоколя).
    canvas.setStrokeColor(PdfColors.blueGrey700);
    canvas.setLineWidth(2.0);
    canvas.drawLine(wallX - 1, plinthBottom, wallX - 1, plinthTop);
    canvas.strokePath();

    // Утеплитель ЭППС цоколя.
    canvas.setFillColor(PdfColors.yellow200);
    canvas.drawRect(wallX - 9, plinthBottom, 7, plinthTop - plinthBottom);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawRect(wallX - 9, plinthBottom, 7, plinthTop - plinthBottom);
    canvas.strokePath();

    // Защитная штукатурка цоколя.
    canvas.setFillColor(PdfColors.grey300);
    canvas.drawRect(wallX - 12, plinthBottom, 3, plinthTop - plinthBottom);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(wallX - 12, plinthBottom, 3, plinthTop - plinthBottom);
    canvas.strokePath();

    // Отмостка — слева от цоколя, наклон вниз-влево. По СП 22.13330
    // п. 6.10 уклон отмостки 3–10 % от стены, ширина ≥ 800 мм.
    // Принимаем 3 % (минимально допустимый — соответствует расчёту
    // тёплого цоколя без избыточного водоотвода).
    canvas.setFillColor(PdfColors.grey400);
    final apronY = groundY;
    final apronW = 100.0;
    const apronSlopePct = 3.0;
    final apronDrop = apronW * apronSlopePct / 100.0;
    final apronStart = PdfPoint(wallX - 12, apronY);
    final apronEnd = PdfPoint(apronStart.x - apronW, apronY - apronDrop);
    canvas.moveTo(apronStart.x, apronStart.y);
    canvas.lineTo(apronEnd.x, apronEnd.y);
    canvas.lineTo(apronEnd.x, apronEnd.y + 8);
    canvas.lineTo(apronStart.x, apronStart.y + 8);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.moveTo(apronStart.x, apronStart.y);
    canvas.lineTo(apronEnd.x, apronEnd.y);
    canvas.lineTo(apronEnd.x, apronEnd.y + 8);
    canvas.lineTo(apronStart.x, apronStart.y + 8);
    canvas.lineTo(apronStart.x, apronStart.y);
    canvas.strokePath();

    // Песчаная подготовка под отмосткой.
    canvas.setFillColor(PdfColors.yellow100);
    canvas.moveTo(apronStart.x, apronStart.y + 8);
    canvas.lineTo(apronEnd.x, apronEnd.y + 8);
    canvas.lineTo(apronEnd.x, apronEnd.y + 14);
    canvas.lineTo(apronStart.x, apronStart.y + 14);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.moveTo(apronStart.x, apronStart.y + 8);
    canvas.lineTo(apronEnd.x, apronEnd.y + 8);
    canvas.lineTo(apronEnd.x, apronEnd.y + 14);
    canvas.lineTo(apronStart.x, apronStart.y + 14);
    canvas.lineTo(apronStart.x, apronStart.y + 8);
    canvas.strokePath();

    // Щебневая подготовка.
    canvas.setFillColor(PdfColors.grey600);
    canvas.moveTo(apronStart.x, apronStart.y + 14);
    canvas.lineTo(apronEnd.x, apronEnd.y + 14);
    canvas.lineTo(apronEnd.x, apronEnd.y + 24);
    canvas.lineTo(apronStart.x, apronStart.y + 24);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.moveTo(apronStart.x, apronStart.y + 14);
    canvas.lineTo(apronEnd.x, apronEnd.y + 14);
    canvas.lineTo(apronEnd.x, apronEnd.y + 24);
    canvas.lineTo(apronStart.x, apronStart.y + 24);
    canvas.lineTo(apronStart.x, apronStart.y + 14);
    canvas.strokePath();

    // Дренажная труба — кружок ниже подошвы.
    final drainX = apronEnd.x - 14;
    final drainY = apronEnd.y + 30;
    canvas.setFillColor(PdfColors.cyan700);
    canvas.drawEllipse(drainX, drainY, 6, 6);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawEllipse(drainX, drainY, 6, 6);
    canvas.strokePath();
    // Перекрестие.
    canvas.drawLine(drainX - 4, drainY, drainX + 4, drainY);
    canvas.strokePath();
    canvas.drawLine(drainX, drainY - 4, drainX, drainY + 4);
    canvas.strokePath();

    // Уровень земли — линия со стрелкой; ниже — отметка верха
    // цоколя/пола 1-го этажа (плюс плинт от расчёта) и подпись типа
    // фундамента.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawLine(apronEnd.x - 30, groundY, apronEnd.x - 18, groundY);
    canvas.strokePath();
    _drawText(canvas, font, 7,
        '0.000', apronEnd.x - 38, groundY - 4);
    // Отметка пола 1-го этажа (= +plinthHeightMm).
    if (plinthHeightMm > 0) {
      canvas.drawLine(apronEnd.x - 30, plinthTop, apronEnd.x - 18, plinthTop);
      canvas.strokePath();
      final plinthM = plinthHeightMm / 1000.0;
      _drawText(canvas, font, 7,
          '+${plinthM.toStringAsFixed(3)}',
          apronEnd.x - 50, plinthTop - 4);
    }
    // Подпись типа фундамента и глубины заложения (под отмосткой).
    _drawText(canvas, font, 7,
        '$foundationLabel, h = ${foundDepthM.toStringAsFixed(2)} м',
        area.x + 6, area.y + 8);

    // Уклон отмостки.
    _drawText(canvas, font, 7,
        'i = ${apronSlopePct.toStringAsFixed(0)}% (СП 22.13330)',
        apronEnd.x + 6, apronEnd.y - 8);

    // Размерная цепь: высота цоколя.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    final dimXp = wallX + wallW + 14;
    canvas.drawLine(dimXp, groundY, dimXp, plinthTop);
    canvas.strokePath();
    canvas.drawLine(dimXp - 3, groundY, dimXp + 3, groundY);
    canvas.strokePath();
    canvas.drawLine(dimXp - 3, plinthTop, dimXp + 3, plinthTop);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${plinthHeightMm.round()}',
        dimXp + 4, (groundY + plinthTop) / 2 - 3);
    // Размерная цепь: ширина отмостки.
    final dimYa = groundY + 30;
    canvas.drawLine(apronEnd.x, dimYa, apronStart.x, dimYa);
    canvas.strokePath();
    canvas.drawLine(apronEnd.x, dimYa - 3, apronEnd.x, dimYa + 3);
    canvas.strokePath();
    canvas.drawLine(apronStart.x, dimYa - 3, apronStart.x, dimYa + 3);
    canvas.strokePath();
    _drawText(canvas, font, 7, '1000', apronEnd.x + apronW / 2 - 12, dimYa + 4);

    // Якоря выносок — на самих элементах.
    final anchors = <_Callout>[
      // 1 — стена.
      _Callout(wallX + wallW * 0.5, plinthTop + 60, '1'),
      // 2 — гидроизоляция горизонт.
      _Callout(wallX + wallW * 0.5, plinthTop + 2, '2'),
      // 3 — цоколь (бетон/кирпич).
      _Callout(wallX + wallW * 0.5, (plinthBottom + plinthTop) / 2, '3'),
      // 4 — гидроизоляция вертик.
      _Callout(wallX - 1, (plinthBottom + plinthTop) / 2, '4'),
      // 5 — утеплитель ЭППС.
      _Callout(wallX - 6, (plinthBottom + plinthTop) / 2, '5'),
      // 6 — защитная штукатурка.
      _Callout(wallX - 11, (plinthBottom + plinthTop) / 2, '6'),
      // 7 — отмостка ж/б.
      _Callout(apronStart.x - apronW / 2, apronStart.y + 2, '7'),
      // 8 — песчаная подготовка.
      _Callout(apronStart.x - apronW / 2, apronStart.y + 11, '8'),
      // 9 — щебневая подготовка.
      _Callout(apronStart.x - apronW / 2, apronStart.y + 19, '9'),
      // 10 — дренажная труба.
      _Callout(drainX, drainY, '10'),
      // 11 — фундамент (область с грунтом).
      _Callout(area.x + 20, area.y + 20, '11'),
    ];
    _drawLeaderCallouts(canvas, font, area, anchors);
  }

  // ═════════════════════ У-6 ОПИРАНИЕ БАЛКИ ПЕРЕКРЫТИЯ ═══════════════════
  static pw.Page floorBeamNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final wallThicknessMm = project.walls.thickness?.round() ?? 380;
    // Если пользователь выбрал перекрытие — берём его толщину как
    // высоту балки. Иначе подбираем по пролёту: H = L/24 (СП 64.13330,
    // условие прогиба ≤ L/250 для деревянной балки шага 600 мм).
    final fs = project.floorSlabs;
    final spanM = math.min(
        project.brief.footprintLength ?? 8.0,
        project.brief.footprintWidth ?? 6.0);
    final beamHmm =
        (fs.thickness ?? math.max(150.0, (spanM * 1000) / 24).roundToDouble())
            .round();
    final beamSection = '50×$beamHmm';
    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: 'У-6',
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-6. Опирание балки перекрытия на стену',
      header:
          'Узел У-6. Опорный узел балки перекрытия ' 
          '(${fs.summary}, $beamSection в стену $wallThicknessMm мм)',
      scaleLabel: '1 : 5',
      painter: (canvas, area, fnt) => _paintFloorBeamNode(canvas, area, fnt,
          wallThicknessMm: wallThicknessMm.toDouble(),
          beamHeightMm: beamHmm.toDouble()),
      layers: [
        _DetailLayer('Балка перекрытия $beamSection',
            '$beamHmm мм', 'СП 64.13330', PdfColors.amber700),
        const _DetailLayer('Концевая обработка балки антисептиком',
            '— ', 'ГОСТ Р 53292', PdfColors.amber900),
        const _DetailLayer('Прокладка из 2-х слоёв рубероида',
            '6 мм', 'СП 17.13330', PdfColors.brown900),
        _DetailLayer('Стена',
            '$wallThicknessMm мм', 'СП 15.13330', PdfColors.grey500),
        const _DetailLayer('Утеплитель торца балки минвата',
            '40 мм', 'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Воздушный зазор', '20 мм',
            'СП 17.13330', PdfColors.cyan100),
        const _DetailLayer('Доска чернового пола', '25 мм',
            'СП 64.13330', PdfColors.amber600),
        const _DetailLayer('Утеплитель междуэтажный (минвата)',
            '100 мм', 'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Подшивка ГКЛ + штукатурка',
            '12,5 мм', 'СП 73.13330', PdfColors.grey200),
      ],
      notes: const [
        '1. Глубина заделки балки в кладку ≥ 150 мм',
        '   (СП 15.13330 п. 9.27).',
        '2. Концы балок в каменных стенах обмазать антисептиком',
        '   и обернуть рубероидом (исключая торец).',
        '3. Торец балки оставить не закрытым — для воздухообмена',
        '   и предотвращения гниения.',
        '4. Между балкой и кладкой — воздушный зазор ≥ 20 мм',
        '   с утеплителем по периметру (СП 50.13330).',
        '5. Шаг балок принят по расчёту (как правило 600 мм).',
        '6. Минимальное сечение — по расчёту прогиба ≤ L/250',
        '   и прочности (СП 64.13330).',
        '7. При шаге опирания > 4 м — опирать через металлический',
        '   подбалочник или ригель (СП 64).',
      ],
      organization: organization,
    );
  }

  static void _paintFloorBeamNode(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font, {
    double wallThicknessMm = 380,
    double beamHeightMm = 200,
  }) {
    final cx = area.x + area.width / 2;
    final cy = area.y + area.height / 2;

    // Стена — слева. Масштаб: 1:3 (1 мм = 0.33 пт), но не меньше
    // 80 пт для читабельности.
    final wallW = math.max(80.0, wallThicknessMm * 0.33);
    final wallX = cx - wallW * 0.5;
    final wallH = 200.0;
    final wallY = cy - wallH / 2;
    canvas.setFillColor(PdfColors.grey500);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(wallX, wallY, wallW, wallH);
    canvas.strokePath();
    // Кирпичная кладка.
    canvas.setLineWidth(0.2);
    for (int i = 1; i < (wallH / 12).floor(); i++) {
      final y = wallY + i * 12;
      canvas.drawLine(wallX, y, wallX + wallW, y);
      canvas.strokePath();
    }

    // Гнездо в стене для балки. Высота балки — из проекта пользователя
    // (FloorSlabsDesign.thickness или расчётное H = L/24). Масштаб
    // 1:7 (1 мм = 0.14 пт), не меньше 22 пт для читабельности.
    final beamH = math.max(22.0, beamHeightMm * 0.14);
    final beamY = cy - beamH / 2;
    final pocketDepth = wallW * 0.6;
    canvas.setFillColor(PdfColors.white);
    canvas.drawRect(wallX + wallW * 0.4, beamY - 4,
        pocketDepth + 0.5, beamH + 8);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(wallX + wallW * 0.4, beamY - 4,
        pocketDepth, beamH + 8);
    canvas.strokePath();

    // Балка — заходит в гнездо.
    final beamX = wallX + wallW * 0.45;
    final beamLen = 200.0;
    canvas.setFillColor(PdfColors.amber700);
    canvas.drawRect(beamX, beamY, beamLen, beamH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(beamX, beamY, beamLen, beamH);
    canvas.strokePath();
    // Древесные слои (диагональ).
    canvas.setLineWidth(0.2);
    canvas.drawLine(beamX, beamY, beamX + beamLen, beamY + beamH);
    canvas.strokePath();
    canvas.drawLine(beamX, beamY + beamH, beamX + beamLen, beamY);
    canvas.strokePath();

    // Концевая обработка антисептиком (тёмная зона по концу).
    canvas.setFillColor(PdfColors.amber900);
    canvas.drawRect(beamX, beamY + 1, 30, beamH - 2);
    canvas.fillPath();

    // Рубероид — толстая полоса под концом балки.
    canvas.setStrokeColor(PdfColors.brown900);
    canvas.setLineWidth(1.2);
    canvas.drawLine(beamX, beamY + 1, beamX + 30, beamY + 1);
    canvas.strokePath();
    canvas.drawLine(beamX, beamY + 4, beamX + 30, beamY + 4);
    canvas.strokePath();

    // Утеплитель в гнезде — над и под концом балки.
    canvas.setFillColor(PdfColors.yellow200);
    canvas.drawRect(beamX - 1, beamY + beamH, 32, 4);
    canvas.fillPath();
    canvas.drawRect(beamX - 1, beamY - 4, 32, 4);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawRect(beamX - 1, beamY + beamH, 32, 4);
    canvas.strokePath();
    canvas.drawRect(beamX - 1, beamY - 4, 32, 4);
    canvas.strokePath();

    // Воздушный зазор — пунктир.
    canvas.setLineWidth(0.3);
    final dashY = beamY + beamH / 2 - 14;
    for (double xx = beamX; xx < beamX + 30; xx += 4) {
      canvas.drawLine(xx, dashY, xx + 2, dashY);
      canvas.strokePath();
    }

    // Чистовой и черновой пол — линии над балкой.
    canvas.setStrokeColor(PdfColors.amber600);
    canvas.setLineWidth(2.0);
    final floorY = beamY + beamH + 6;
    canvas.drawLine(beamX + 30, floorY, beamX + beamLen, floorY);
    canvas.strokePath();
    canvas.setStrokeColor(PdfColors.amber800);
    canvas.setLineWidth(2.0);
    canvas.drawLine(beamX + 30, floorY + 10, beamX + beamLen, floorY + 10);
    canvas.strokePath();

    // Утеплитель междуэтажный.
    canvas.setFillColor(PdfColors.yellow200);
    canvas.drawRect(beamX + 30, floorY - 30, beamLen - 30, 30);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawRect(beamX + 30, floorY - 30, beamLen - 30, 30);
    canvas.strokePath();

    // Подшивка ГКЛ.
    canvas.setFillColor(PdfColors.grey200);
    canvas.drawRect(beamX + 30, beamY - 4, beamLen - 30, 4);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(beamX + 30, beamY - 4, beamLen - 30, 4);
    canvas.strokePath();

    // Размерная цепь по высоте балки.
    canvas.setLineWidth(0.3);
    final dimX = beamX + beamLen + 12;
    canvas.drawLine(dimX, beamY, dimX, beamY + beamH);
    canvas.strokePath();
    canvas.drawLine(dimX - 3, beamY, dimX + 3, beamY);
    canvas.strokePath();
    canvas.drawLine(dimX - 3, beamY + beamH, dimX + 3, beamY + beamH);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${beamHeightMm.round()}',
        dimX + 4, beamY + beamH / 2 - 3);

    // Размерная цепь: глубина заделки в кладку (СП 15.13330 п. 9.27 — 
    // не менее 150 мм). Показываем фактическую длину опирания pocket.
    final dimYemb = beamY + beamH + 18;
    final embStart = wallX + wallW * 0.4 + 4;
    final embEnd = wallX + wallW;
    canvas.drawLine(embStart, dimYemb, embEnd, dimYemb);
    canvas.strokePath();
    canvas.drawLine(embStart, dimYemb - 3, embStart, dimYemb + 3);
    canvas.strokePath();
    canvas.drawLine(embEnd, dimYemb - 3, embEnd, dimYemb + 3);
    canvas.strokePath();
    _drawText(canvas, font, 7, '≥150',
        (embStart + embEnd) / 2 - 8, dimYemb + 4);

    // Размерная цепь: толщина стены.
    final dimYwall = wallY - 14;
    canvas.drawLine(wallX, dimYwall, wallX + wallW, dimYwall);
    canvas.strokePath();
    canvas.drawLine(wallX, dimYwall - 3, wallX, dimYwall + 3);
    canvas.strokePath();
    canvas.drawLine(wallX + wallW, dimYwall - 3, wallX + wallW, dimYwall + 3);
    canvas.strokePath();
    _drawText(canvas, font, 7, '${wallThicknessMm.round()}',
        wallX + wallW / 2 - 12, dimYwall + 4);

    // Якоря выносок — на самих элементах.
    final anchors = <_Callout>[
      // 1 — балка перекрытия (середина балки за пределами стены).
      _Callout(beamX + 80, beamY + beamH / 2, '1'),
      // 2 — антисептическая обработка.
      _Callout(beamX + 6, beamY + beamH * 0.5, '2'),
      // 3 — рубероид (полоса ниже балки).
      _Callout(beamX + 16, beamY + 2, '3'),
      // 4 — стена кладочная.
      _Callout(wallX + wallW * 0.2, wallY + wallH * 0.3, '4'),
      // 5 — утеплитель торца балки.
      _Callout(beamX + 6, beamY - 2, '5'),
      // 6 — воздушный зазор.
      _Callout(beamX + 16, dashY, '6'),
      // 7 — доска чернового пола.
      _Callout(beamX + 60, floorY, '7'),
      // 8 — утеплитель междуэтажный.
      _Callout(beamX + 60, floorY - 18, '8'),
      // 9 — подшивка ГКЛ.
      _Callout(beamX + 60, beamY - 4, '9'),
    ];
    _drawLeaderCallouts(canvas, font, area, anchors);
  }

  // ═══════════════════════════ ПИРОГ КРОВЛИ ══════════════════════════════
  static pw.Page roofPiePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'У-7',
    OrganizationSettings? organization,
  }) {
    final mat = (project.roof.roofingMaterial ?? '').toLowerCase();
    String roofingName = 'Кровельный материал по проекту';
    String roofingThickness = 'переменно';
    if (mat.contains('metal') || mat == 'metal_tile') {
      roofingName = 'Металлочерепица 0,5 мм с полиэстером';
      roofingThickness = '0,5 мм';
    } else if (mat.contains('ceramic') || mat == 'tile') {
      roofingName = 'Керамическая черепица';
      roofingThickness = '25 мм';
    } else if (mat.contains('soft') || mat == 'soft') {
      roofingName = 'Битумная черепица + подкладочный ковёр';
      roofingThickness = '5 мм';
    } else if (mat.contains('seam')) {
      roofingName = 'Фальцевая кровля (оцинк. сталь)';
      roofingThickness = '0,5 мм';
    } else if (mat.contains('membrane')) {
      roofingName = 'ПВХ-мембрана';
      roofingThickness = '1,5 мм';
    }

    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: sheetCode,
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'Кровельный пирог',
      header: 'Состав кровельного пирога (вертикальный разрез по скату)',
      scaleLabel: '1 : 5',
      painter: (canvas, area, font) =>
          _paintRoofPie(canvas, area, font, roofingName, roofingThickness),
      layers: [
        _DetailLayer(roofingName, roofingThickness,
            'СП 17.13330', PdfColors.brown600),
        const _DetailLayer('Обрешётка (доска 25×100, шаг по покрытию)',
            '25 мм', 'СП 64.13330', PdfColors.amber400),
        const _DetailLayer(
            'Контробрешётка (брус 50×50) — вентзазор',
            '50 мм',
            'СП 17.13330',
            PdfColors.amber700),
        const _DetailLayer('Гидроветрозащитная мембрана', '0,3 мм',
            'СП 17.13330', PdfColors.cyan200),
        const _DetailLayer('Стропильная нога (брус 50×200)', '200 мм',
            'СП 64.13330', PdfColors.amber800),
        const _DetailLayer('Утеплитель минвата (плотн. 35 кг/м³)',
            '200 мм', 'СП 50.13330', PdfColors.yellow200),
        const _DetailLayer('Пароизоляционная плёнка', '0,2 мм',
            'СП 50.13330', PdfColors.blue200),
        const _DetailLayer('Подшивка (ГКЛ или вагонка)', '12,5 мм',
            'СП 73.13330', PdfColors.brown300),
      ],
      notes: const [
        '1. Толщина утеплителя принята по расчёту',
        '   термосопротивления (СП 50.13330) — для региона',
        '   с расчётной t° наружного воздуха минимум',
        '   −28 °C — R ≥ 4,79 м²·°C/Вт.',
        '2. Между гидроветрозащитой и кровельным покрытием —',
        '   вентилируемый зазор ≥ 50 мм.',
        '3. Между пароизоляцией и подшивкой допускается',
        '   технологический зазор 30 мм для проводки.',
        '4. Стыки пароизоляции проклеить двусторонней',
        '   бутил-каучуковой лентой.',
        '5. Все деревянные элементы антисептированы',
        '   (ГОСТ Р 53292) и огнезащищены до I группы',
        '   (СП 2.13130).',
        '6. При снеговой нагрузке Sg ≥ 240 кг/м² (район III)',
        '   шаг стропил уменьшается до 600 мм.',
      ],
      organization: organization,
    );
  }

  static void _paintRoofPie(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font,
    String roofingName,
    String roofingThickness,
  ) {
    // Вертикальный разрез слоёв пирога — стыки слоёв горизонтальные.
    final cx = area.x + area.width / 2;
    final blockW = 220.0;
    final blockX = cx - blockW / 2;
    final layers = <(double, PdfColor, String)>[
      (12.0, PdfColors.brown600, roofingName),
      (5.0, PdfColors.amber400, 'Обрешётка 25×100'),
      (10.0, PdfColors.amber700, 'Контробрешётка 50×50 (вентзазор)'),
      (4.0, PdfColors.cyan200, 'Гидроветрозащита'),
      (45.0, PdfColors.amber800, 'Стропильная нога 50×200'),
      (45.0, PdfColors.yellow200, 'Утеплитель минвата 200 мм'),
      (4.0, PdfColors.blue200, 'Пароизоляция'),
      (8.0, PdfColors.brown300, 'Подшивка ГКЛ / вагонка'),
    ];
    final totalH = layers.fold<double>(0, (a, b) => a + b.$1);
    var cy = area.y + (area.height + totalH) / 2;

    int idx = 1;
    for (final l in layers) {
      cy -= l.$1;
      canvas.setFillColor(l.$2);
      canvas.drawRect(blockX, cy, blockW, l.$1);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawRect(blockX, cy, blockW, l.$1);
      canvas.strokePath();
      // Номер слоя слева.
      canvas.setFillColor(PdfColors.white);
      canvas.drawEllipse(blockX - 16, cy + l.$1 / 2, 7, 7);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawEllipse(blockX - 16, cy + l.$1 / 2, 7, 7);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(canvas, font, 7.0,
          '$idx', blockX - 16, cy + l.$1 / 2 - 2.4);
      idx++;
    }
    // Стрелка «вверх — наружу, вниз — помещение» справа.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    final arrX = blockX + blockW + 30;
    final arrTop = cy;
    final arrBottom = cy + totalH;
    canvas.drawLine(arrX, arrBottom + 8, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX - 3, arrTop - 4, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX + 3, arrTop - 4, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX - 3, arrBottom + 4, arrX, arrBottom + 8);
    canvas.strokePath();
    canvas.drawLine(arrX + 3, arrBottom + 4, arrX, arrBottom + 8);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, 'Наружу',
        arrX + 6, arrTop);
    _drawText(canvas, font, 8, 'В помещение',
        arrX + 6, arrBottom);
  }

  // ═════════════════════════ У-8 ПИРОГ ПОЛА 1-го этажа ════════════════════
  /// Подбор климата по региону проекта — повторяет логику
  /// [`ThermalExplanationPdf._climateForProject`], чтобы узел У-8 был
  /// синхронизирован с теплотехническим расчётом из ПЗ.
  static ClimateZone _floorPieClimate(HouseProject project) {
    final region = (project.brief.region ?? '').toLowerCase();
    if (region.contains('питер') || region.contains('петербург') ||
        region.contains('ленингр')) {
      return ClimateZones.spb;
    }
    if (region.contains('екатер') || region.contains('свердл')) {
      return ClimateZones.ekb;
    }
    if (region.contains('новосиб')) return ClimateZones.novosibirsk;
    if (region.contains('красно') && region.contains('краснод')) {
      return ClimateZones.krasnodar;
    }
    if (region.contains('казан') || region.contains('татарст')) {
      return ClimateZones.kazan;
    }
    if (region.contains('нижн') && region.contains('новг')) {
      return ClimateZones.nizhnyNovgorod;
    }
    if (region.contains('якут')) return ClimateZones.yakutsk;
    if (region.contains('сочи')) return ClimateZones.sochi;
    if (region.contains('мурм')) return ClimateZones.murmansk;
    if (region.contains('владивост') || region.contains('приморск')) {
      return ClimateZones.vladivostok;
    }
    if (region.contains('иркут')) return ClimateZones.irkutsk;
    return ClimateZones.moscow;
  }

  /// Подбор требуемой толщины утеплителя пола 1-го этажа: используем
  /// тот же `ThermalCalculator` и тот же климат, что и в ПЗ. λ = 0.034
  /// (ЭППС / Пеноплэкс по СП 50.13330 прил. Т) — наиболее распространённый
  /// материал для подпольной теплоизоляции (низкое водопоглощение,
  /// высокая прочность на сжатие). Толщина округляется вверх до 50 мм.
  static int _floorInsulationThicknessMm(HouseProject project) {
    final climate = _floorPieClimate(project);
    // Пробный расчёт без утеплителя — чтобы получить требуемое R.
    final probe = ThermalCalculator.compute(
      climate: climate,
      envelope: BuildingEnvelope.floorOverUnheated,
      layers: const [],
      alphaIn: 8.7,
      alphaOut: 6.0, // для пола снизу — пониженный αн (СП 50, табл. 4)
    );
    final rReq = probe.rReq;
    // Базовое сопротивление слоёв пола без утеплителя:
    // ламинат + подложка + стяжка ≈ 0.10 м²·°C/Вт; этого мало.
    const rBase = 0.10;
    const lambdaInsul = 0.034; // ЭППС
    final remaining = rReq - 1 / 8.7 - rBase - 1 / 6.0;
    if (remaining <= 0) return 50; // минимум 50 мм для гидроизоляционной роли
    final mm = remaining * lambdaInsul * 1000;
    return ((mm / 50).ceil() * 50).clamp(50, 400);
  }

  /// Узел У-8. Пирог пола 1-го этажа. Слои подбираются в зависимости от
  /// типа фундамента (плита/лента/сваи) и от регионального климата —
  /// толщина утеплителя берётся из теплотехнического расчёта.
  static pw.Page floorPieNodePage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    String sheetCode = 'У-8',
    OrganizationSettings? organization,
  }) {
    final foundationType = project.foundation.type ?? FoundationType.strip;
    final climate = _floorPieClimate(project);
    final insulMm = _floorInsulationThicknessMm(project);
    // Чистовой пол — по ведомости отделки (см. _floorMarkForRoom).
    // Для жилой комнаты (типовой случай 1-го этажа) — П1: ламинат 33 кл.
    const finishLayerName = 'Ламинат 33 класс';
    const finishLayerThickness = '8 мм';
    const underlayName = 'Подложка вспен. полиэтилен';
    const underlayThickness = '3 мм';
    const screedName = 'Стяжка ЦПС М150';
    const screedThickness = '50 мм';
    const filmName = 'ПЭ-плёнка (разделит. слой)';
    const filmThickness = '0,2 мм';
    const insulName = 'Утеплитель ЭППС (Пеноплэкс)';
    final insulThickness = '$insulMm мм';
    const waterproofName = 'Гидроизоляция оклеечная (рубероид 2 слоя)';
    const waterproofThickness = '6 мм';
    String baseName;
    String baseThickness;
    String baseRef;
    switch (foundationType) {
      case FoundationType.slab:
        baseName = 'Монолитная плита B25 W6 F100';
        // Толщина плиты для ИЖС типовая 250 мм (СП 22.13330,
        // п. 5.5.20). При наличии числовых данных — будет браться из
        // FoundationPlanModel.depthM.
        baseThickness = '250 мм';
        baseRef = 'СП 22.13330';
        break;
      case FoundationType.strip:
      case FoundationType.columnar:
      case FoundationType.pileWithGrillage:
        baseName = 'Бетонная подготовка по уплотнённому грунту';
        baseThickness = '100 мм';
        baseRef = 'СП 22.13330';
        break;
      case FoundationType.pile:
        baseName = 'Лаги дерев. (50×200) по балкам перекрытия';
        baseThickness = '200 мм';
        baseRef = 'СП 64.13330';
        break;
      // ignore: unreachable_switch_default
      default:
        baseName = 'Основание';
        baseThickness = '—';
        baseRef = '—';
    }

    final layers = <_DetailLayer>[
      const _DetailLayer(finishLayerName, finishLayerThickness,
          'СП 71.13330', PdfColors.amber600),
      const _DetailLayer(underlayName, underlayThickness,
          'СП 71.13330', PdfColors.blueGrey100),
      const _DetailLayer(screedName, screedThickness,
          'СП 71.13330', PdfColors.grey300),
      const _DetailLayer(filmName, filmThickness,
          'СП 50.13330', PdfColors.cyan100),
      _DetailLayer(insulName, insulThickness,
          'СП 50.13330', PdfColors.yellow200),
      const _DetailLayer(waterproofName, waterproofThickness,
          'СП 17.13330', PdfColors.brown900),
      _DetailLayer(baseName, baseThickness, baseRef, PdfColors.grey500),
    ];

    final notes = <String>[
      '1. Толщина утеплителя ЭППС δ = $insulMm мм принята по',
      '   расчёту требуемого сопротивления теплопередаче',
      '   R₀^тр для конструкции пола 1-го этажа над',
      '   неотапливаемым подпольем (СП 50.13330, табл. 3).',
      '2. Климат: ${climate.city}; ГСОП = ${climate.gsop.toStringAsFixed(0)}',
      '   °C·сут (СП 131.13330.2020 табл. 3.1).',
      '3. λ ЭППС = 0,034 Вт/(м·°C), ρ = 35 кг/м³,',
      '   водопоглощение ≤ 0,4% (СП 50.13330 прил. Т).',
      '4. Гидроизоляция оклеечная — 2 слоя рубероида с',
      '   нахлёстом 100 мм (СП 17.13330, п. 5.1.6).',
      '5. Стяжка ЦПС М150 ≥ 50 мм с армированием сеткой',
      '   Ø3 Вр-1 100×100 (СП 71.13330, п. 8.6).',
      '6. Зазор от чистового покрытия до стен 8…10 мм',
      '   с заполнением плинтусом (СП 71.13330, п. 8.14).',
      '7. Тип покрытия по помещениям — см. план полов и',
      '   ведомость отделки (П1…П4).',
    ];

    return _detailPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: sheetNumber,
      totalSheets: totalSheets,
      font: font,
      fontBold: fontBold,
      pdfFont: pdfFont,
      sheetCode: sheetCode,
      sectionTitle: 'Узлы и детали',
      sheetTitle: 'У-8. Пирог пола 1-го этажа',
      header:
          'Узел У-8. Пирог пола 1-го этажа '
          '(тип П1, ${climate.city}, ГСОП ${climate.gsop.toStringAsFixed(0)} °C·сут, '
          'утеплитель ЭППС $insulMm мм)',
      scaleLabel: '1 : 5',
      painter: (canvas, area, fnt) =>
          _paintFloorPie(canvas, area, fnt, layers, insulMm, foundationType),
      layers: layers,
      notes: notes,
      organization: organization,
    );
  }

  static void _paintFloorPie(
    PdfGraphics canvas,
    _DetailRect area,
    PdfFont font,
    List<_DetailLayer> layers,
    int insulMm,
    FoundationType foundationType,
  ) {
    // Вертикальный разрез пирога пола: сверху вниз — чистовой пол …
    // основание. Реальные пропорции толщин сжаты в пределах 8…45 пт
    // на слой для читабельности (масштаб «графический», в подписях
    // указаны фактические толщины из расчёта).
    final cx = area.x + area.width / 2;
    final blockW = 220.0;
    final blockX = cx - blockW / 2;
    // Графические толщины (пт), синхронизированы с порядком layers.
    final hList = <double>[
      8,   // ламинат
      4,   // подложка
      18,  // стяжка
      3,   // плёнка
      math.max(20.0, math.min(48.0, insulMm * 0.18)), // утеплитель — пропорц.
      4,   // гидроизоляция
      24,  // основание
    ];
    final totalH = hList.fold<double>(0, (a, b) => a + b);
    var cy = area.y + (area.height + totalH) / 2;

    final anchors = <_Callout>[];
    int idx = 1;
    for (var i = 0; i < layers.length; i++) {
      final h = hList[i];
      cy -= h;
      canvas.setFillColor(layers[i].color);
      canvas.drawRect(blockX, cy, blockW, h);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawRect(blockX, cy, blockW, h);
      canvas.strokePath();
      // Anchor — на правом краю слоя; кружок номера сам выносится за
      // правое поле детальной области через _drawLeaderCallouts.
      anchors.add(_Callout(
        blockX + blockW - 4,
        cy + h / 2,
        '$idx',
      ));
      idx++;
    }

    // Чистый пол — отметка ±0.000.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    final markY = cy + totalH; // верх стопки
    canvas.drawLine(blockX - 30, markY, blockX, markY);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, '±0.000', blockX - 60, markY - 3);
    _drawText(canvas, font, 7, 'у.ч.п.', blockX - 60, markY - 11);

    // Низ пирога — отметка с фактическим расстоянием в мм.
    final totalMm =
        8 + 3 + 50 + 0 + insulMm + 6 + (foundationType == FoundationType.pile ? 200 : 100);
    canvas.drawLine(blockX - 30, markY - totalH, blockX, markY - totalH);
    canvas.strokePath();
    _drawText(
      canvas,
      font,
      8,
      '−0.${totalMm.toString().padLeft(3, '0')}',
      blockX - 60,
      markY - totalH - 3,
    );
    _drawText(canvas, font, 7, 'низ пирога',
        blockX - 60, markY - totalH - 11);

    // Размерная цепь справа — толщины слоёв в мм.
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.3);
    final dimX = blockX + blockW + 22;
    final dimsMm = <int>[8, 3, 50, 0, insulMm, 6,
        foundationType == FoundationType.pile ? 200 : 100];
    var ay = markY;
    for (var i = 0; i < hList.length; i++) {
      final h = hList[i];
      final by = ay - h;
      canvas.drawLine(dimX, ay, dimX, by);
      canvas.strokePath();
      // Чёрточки.
      canvas.drawLine(dimX - 3, ay, dimX + 3, ay);
      canvas.strokePath();
      canvas.drawLine(dimX - 3, by, dimX + 3, by);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      _drawText(canvas, font, 7, '${dimsMm[i]}', dimX + 5, by + h / 2 - 2);
      ay = by;
    }

    // Стрелка «вверх — помещение, вниз — грунт/подполье».
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    final arrX = blockX + blockW + 60;
    final arrTop = cy;
    final arrBottom = cy + totalH;
    canvas.drawLine(arrX, arrBottom + 8, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX - 3, arrTop - 4, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX + 3, arrTop - 4, arrX, arrTop - 8);
    canvas.strokePath();
    canvas.drawLine(arrX - 3, arrBottom + 4, arrX, arrBottom + 8);
    canvas.strokePath();
    canvas.drawLine(arrX + 3, arrBottom + 4, arrX, arrBottom + 8);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    _drawText(canvas, font, 8, 'Помещение', arrX + 6, arrBottom);
    _drawText(canvas, font, 8,
        foundationType == FoundationType.pile
            ? 'Подполье / балки'
            : 'Грунт / основание',
        arrX + 6, arrTop);

    // Выноски — кружки за правым полем детальной области, без
    // наложений (по ГОСТ 21.501-2018, _drawLeaderCallouts).
    _drawLeaderCallouts(canvas, font, area, anchors);
  }

  // ═══════════════════════════ ХЕЛПЕРЫ ══════════════════════════════════
  static void _drawCallouts(
    PdfGraphics canvas,
    PdfFont font,
    List<_Callout> callouts,
  ) {
    for (final c in callouts) {
      // Кружок 8 пт + цифра.
      canvas.setFillColor(PdfColors.white);
      canvas.drawEllipse(c.x, c.y, 7, 7);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawEllipse(c.x, c.y, 7, 7);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(canvas, font, 7.0, c.label, c.x, c.y - 2.4);
    }
  }

  /// Выноски с линиями-указателями. Каждый anchor задаёт точку на самом
  /// элементе чертежа; кружок-номер ставится РЯДОМ с anchor (не на
  /// правом поле всего кадра!) — короткой выноской ~30 pt в свободном
  /// направлении. Кружки разводятся по сетке так, чтобы не перекрывали
  /// сам чертёж и друг друга. От кружка к anchor проводится короткая
  /// прямая выноска (СПДС — ГОСТ 21.501-2018 п. 7.3, п. 5.10.6).
  static void _drawLeaderCallouts(
    PdfGraphics canvas,
    PdfFont font,
    _DetailRect area,
    List<_Callout> anchors,
  ) {
    if (anchors.isEmpty) return;

    // 1) Найдём центр кластера элементов чертежа (средний anchor) —
    //    будем расставлять кружки от него по часовой стрелке, по мере
    //    отдаления к границе кадра. Это даёт КОРОТКИЕ выноски (≤ 60 pt)
    //    вместо длинных через весь кадр.
    var sx = 0.0, sy = 0.0;
    for (final a in anchors) {
      sx += a.x;
      sy += a.y;
    }
    final cx = sx / anchors.length;
    final cy = sy / anchors.length;

    final placed = <_Callout>[];
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    const radius = 7.0;
    const minDist = 18.0; // минимальное расстояние между кружками
    const minLeader = 22.0; // минимальная длина выноски (от anchor)
    const maxLeader = 90.0; // макс длина — короче, чем раньше

    for (final a in anchors) {
      // Базовое направление: от центра кластера к anchor (наружу),
      // т. е. кружок ставится «снаружи» от группы — там, где меньше
      // других элементов.
      var dx = a.x - cx;
      var dy = a.y - cy;
      final norm = math.sqrt(dx * dx + dy * dy);
      if (norm < 0.5) {
        dx = 1; // если anchor совпадает с центром — толкаем вправо
        dy = 0;
      } else {
        dx /= norm;
        dy /= norm;
      }

      // Подбираем расстояние от anchor так, чтобы кружок (а) лежал в
      // пределах кадра, (б) не пересекался с уже расставленными.
      double bestX = a.x;
      double bestY = a.y;
      var found = false;
      for (var d = minLeader; d <= maxLeader; d += 6) {
        final tryX = a.x + dx * d;
        final tryY = a.y + dy * d;
        // В пределах area + небольшой запас.
        if (tryX < area.x + radius + 2) continue;
        if (tryX > area.x + area.width - radius - 2) continue;
        if (tryY < area.y + radius + 2) continue;
        if (tryY > area.y + area.height - radius - 2) continue;
        var ok = true;
        for (final p in placed) {
          final ddx = p.x - tryX;
          final ddy = p.y - tryY;
          if (ddx * ddx + ddy * ddy < minDist * minDist) {
            ok = false;
            break;
          }
        }
        if (ok) {
          bestX = tryX;
          bestY = tryY;
          found = true;
          break;
        }
      }
      // Если не получилось — пробуем перпендикулярное направление.
      if (!found) {
        for (final mult in const [1.0, -1.0]) {
          for (var d = minLeader; d <= maxLeader; d += 6) {
            final tryX = a.x + (-dy) * d * mult;
            final tryY = a.y + dx * d * mult;
            if (tryX < area.x + radius + 2) continue;
            if (tryX > area.x + area.width - radius - 2) continue;
            if (tryY < area.y + radius + 2) continue;
            if (tryY > area.y + area.height - radius - 2) continue;
            var ok = true;
            for (final p in placed) {
              final ddx = p.x - tryX;
              final ddy = p.y - tryY;
              if (ddx * ddx + ddy * ddy < minDist * minDist) {
                ok = false;
                break;
              }
            }
            if (ok) {
              bestX = tryX;
              bestY = tryY;
              found = true;
              break;
            }
          }
          if (found) break;
        }
      }
      placed.add(_Callout(bestX, bestY, a.label));

      // Линия-выноска anchor → кружок.
      canvas.drawLine(a.x, a.y, bestX, bestY);
      canvas.strokePath();
      // Точка-«стрелка» на anchor.
      canvas.setFillColor(PdfColors.black);
      canvas.drawEllipse(a.x, a.y, 1.2, 1.2);
      canvas.fillPath();
      // Сам кружок 14 pt с номером.
      canvas.setFillColor(PdfColors.white);
      canvas.drawEllipse(bestX, bestY, radius, radius);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawEllipse(bestX, bestY, radius, radius);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(canvas, font, 7.0, a.label, bestX, bestY - 2.4);
    }
  }

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
}

class _DetailRect {
  const _DetailRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final double x;
  final double y;
  final double width;
  final double height;
}

class _DetailLayer {
  const _DetailLayer(this.name, this.thickness, this.standard, this.color);
  final String name;
  final String thickness;
  final String standard;
  final PdfColor color;
}

class _Callout {
  const _Callout(this.x, this.y, this.label);
  final double x;
  final double y;
  final String label;
}


