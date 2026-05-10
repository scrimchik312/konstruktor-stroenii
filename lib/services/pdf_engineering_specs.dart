import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/rooms_catalog.dart';
import '../data/wall_materials.dart';
import '../models/floor_plan.dart';
import '../models/foundation.dart';
import '../models/foundation_plan.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'pdf_builder.dart';
import 'pdf_title_block.dart';

/// Итерация 4 — инженерно-сметные ведомости.
///
/// Четыре табличных листа, формируемых из расчётных данных проекта:
///   * КЖ-2 — ведомость расхода стали на монолитные конструкции
///     (ГОСТ Р 21.501-2018, форма 1; СП 63.13330.2018, СП 70.13330.2012).
///   * КД-3 — спецификация лестниц (ГОСТ Р 21.501-2018, форма 7).
///   * АР-N — ведомость отделки помещений (ГОСТ Р 21.501-2018, форма 4).
///   * ОР-N — перечень видов работ, подлежащих освидетельствованию
///     (СП 48.13330.2019, СП 70.13330.2012, РД 11-02-2006).
///
/// Все четыре листа строятся в формате A3 landscape, рамка ГОСТ 2.301-68
/// и штамп формы 3 ГОСТ Р 21.101-2020 ставятся через
/// [PdfBuilder.drawingPageTheme] и [PdfTitleBlock.build].
class PdfEngineeringSpecs {
  PdfEngineeringSpecs._();

  // ─────────────────────── общие константы вёрстки ───────────────────────
  static const double _rowH = 16;
  static const double _headerH = 22;
  static const double _cellPadH = 4;
  // Внутренний вертикальный отступ ячеек таблицы — гарантирует, что
  // текст не «прилипает» к границе ячейки.
  static const double _cellPadV = 3;
  // Нижний отступ 220 pt — выше штампа (55 мм ≈ 156 pt + 18 pt снизу
  // + 46 pt запаса) и ширина штампа ~393 pt по правому краю. Это
  // гарантирует, что блок «Примечания» при многострочном тексте не
  // налезает на штамп ни по вертикали, ни по правому полю (ранее были
  // случаи на л. 30+ при больших таблицах скрытых работ).
  static const pw.EdgeInsets _contentPadding =
      pw.EdgeInsets.fromLTRB(70, 16, 14, 220);

  // Поля для MultiPage-листов (ведомости, акты). Отступы точнее
  // следуют внутренней рамке ГОСТ (20 мм слева, 5 мм остальное),
  // нижний отступ — чуть выше штампа 0.75×55 мм ≈ 117 pt + 14 pt
  // позиция штампа + 19 pt запас = 150 pt.
  static const pw.EdgeInsets _multiPagePadding =
      pw.EdgeInsets.fromLTRB(62, 18, 18, 150);

  /// PageTheme для многостраничной ведомости. Содержит рамку чертежа
  /// и штамп ГОСТ Р 21.101-2020 (форма 3) в нижнем правом углу — штамп
  /// отрисовывается на каждом листе автоматически. Поля документа
  /// выставлены так, чтобы основной контент не накладывался на штамп.
  static pw.PageTheme _drawingThemeWithTitleBlock({
    required HouseProject project,
    required pw.Font font,
    required pw.Font fontBold,
    required String sectionTitle,
    required String sheetTitle,
    required String sheetCode,
    required int sheetNumber,
    required int totalSheets,
    OrganizationSettings? organization,
  }) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: _multiPagePadding,
      buildBackground: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(child: PdfBuilder.drawingFrame()),
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

  // ─────────────────────── общие хелперы таблиц ──────────────────────────

  /// Оценка высоты ячейки с переносом по словам. PDF-библиотека не имеет
  /// `IntrinsicHeight`, поэтому строки строим как `pw.Row` с явно
  /// заданными высотами — наибольшая по строке. Метод приближённо
  /// рассчитывает, сколько строк займёт текст в ячейке шириной [width]
  /// при шрифте [fontSize] (DejaVu Sans, среднее значение глифа ≈
  /// 0.55·fontSize).
  static double _measureCellHeight(
    String text,
    double width, {
    double fontSize = 7.5,
    double padH = _cellPadH,
    double padV = _cellPadV,
    double minHeight = _rowH,
  }) {
    if (text.isEmpty) return minHeight;
    final usableW = width - 2 * padH;
    if (usableW <= 0) return minHeight;
    // Средняя ширина глифа DejaVu Sans @ 7.5 pt ≈ 4.1 pt; берём
    // консервативно 0.55·fontSize, чтобы перестраховаться от обрезки.
    final avgGlyph = fontSize * 0.55;
    final charsPerLine = (usableW / avgGlyph).floor().clamp(4, 1000);

    // Разбиваем по жёстким переносам (\n) и по словам — имитируем
    // word-wrap. Каждая строка \n считается отдельной строкой.
    var totalLines = 0;
    for (final paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        totalLines += 1;
        continue;
      }
      final words = paragraph.split(' ');
      var curLen = 0;
      var lines = 1;
      for (final w in words) {
        final next = curLen == 0 ? w.length : curLen + 1 + w.length;
        if (next <= charsPerLine) {
          curLen = next;
        } else {
          // Слово не влезает — переносим. Если само слово длиннее
          // строки — рвём его на куски (имитация overflow по символам).
          if (w.length > charsPerLine) {
            final extraLines = (w.length / charsPerLine).ceil();
            lines += extraLines;
            curLen = w.length % charsPerLine;
          } else {
            lines += 1;
            curLen = w.length;
          }
        }
      }
      totalLines += lines;
    }
    final lineH = fontSize * 1.30; // межстрочный интервал ~1.3
    final h = totalLines * lineH + 2 * padV;
    return h < minHeight ? minHeight : h;
  }

  static pw.Widget _headerCell(
    String text,
    double width,
    pw.Font fontBold,
    double height,
  ) {
    return pw.Container(
      width: width,
      height: height,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: _cellPadH,
        vertical: _cellPadV,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(width: 0.4, color: PdfColors.black),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        overflow: pw.TextOverflow.visible,
        style: pw.TextStyle(
          fontSize: 7.5,
          font: fontBold,
          lineSpacing: 0.5,
        ),
      ),
    );
  }

  /// Ячейка таблицы фиксированной высоты [height]. Высота вычисляется
  /// заранее по самому длинному тексту в строке, чтобы все ячейки строки
  /// имели одинаковую итоговую высоту и не было «дыр» / наездов текста.
  /// Внутренние отступы — `_cellPadH` горизонтально и `_cellPadV`
  /// вертикально, текст переносится по словам, не обрезается.
  static pw.Widget _bodyCell(
    String text,
    double width,
    pw.Font font,
    double height, {
    pw.Alignment alignment = pw.Alignment.centerLeft,
    bool bold = false,
    pw.Font? fontBold,
  }) {
    return pw.Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: _cellPadH,
        vertical: _cellPadV,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.3, color: PdfColors.black),
      ),
      child: pw.Text(
        text,
        textAlign: alignment == pw.Alignment.center
            ? pw.TextAlign.center
            : pw.TextAlign.left,
        overflow: pw.TextOverflow.visible,
        style: pw.TextStyle(
          fontSize: 7.5,
          font: bold && fontBold != null ? fontBold : font,
          lineSpacing: 0.5,
        ),
      ),
    );
  }

  /// Строка таблицы — все ячейки имеют одинаковую высоту, равную
  /// максимуму из расчётных высот текстов ячеек строки. Это убирает
  /// «дыры» в коротких ячейках и не даёт длинному тексту вылезать за
  /// границы соседних столбцов.
  static pw.Widget _row(
    List<({String text, double width, pw.Alignment? align})> cells,
    pw.Font font, {
    bool bold = false,
    pw.Font? fontBold,
  }) {
    var maxH = _rowH;
    for (final c in cells) {
      final h = _measureCellHeight(c.text, c.width);
      if (h > maxH) maxH = h;
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final c in cells)
          _bodyCell(
            c.text,
            c.width,
            font,
            maxH,
            alignment: c.align ?? pw.Alignment.centerLeft,
            bold: bold,
            fontBold: fontBold,
          ),
      ],
    );
  }

  static pw.Widget _headerRow(
    List<({String label, double width})> cells,
    pw.Font fontBold,
  ) {
    var maxH = _headerH;
    for (final c in cells) {
      final h = _measureCellHeight(c.label, c.width, padV: _cellPadV);
      if (h > maxH) maxH = h;
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final c in cells) _headerCell(c.label, c.width, fontBold, maxH),
      ],
    );
  }

  /// Шапка листа (название проекта слева, версия / норматив справа).
  static pw.Widget _sheetHeader({
    required String projectName,
    required String sheetTitle,
    required String reference,
    required int versionNumber,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              projectName,
              style: pw.TextStyle(
                fontSize: 14,
                font: fontBold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              sheetTitle,
              style: pw.TextStyle(
                fontSize: 10,
                font: font,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              reference,
              style: pw.TextStyle(fontSize: 9, font: font),
            ),
            pw.Text(
              'Версия №$versionNumber',
              style: pw.TextStyle(fontSize: 10, font: font),
            ),
          ],
        ),
      ],
    );
  }

  // ═════════════════════════ КЖ-2: ведомость стали ═════════════════════════

  static pw.Page steelBillPage({
    required HouseProject project,
    FoundationPlanModel? foundationPlan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    final rebarRows = _buildRebarRows(project, foundationPlan);
    final totalMass =
        rebarRows.fold<double>(0, (s, r) => s + r.totalMassKg);

    // Группировка по элементу для итоговой сводки.
    final byElement = <String, double>{};
    for (final r in rebarRows) {
      byElement[r.element] = (byElement[r.element] ?? 0) + r.totalMassKg;
    }

    // Разметка таблицы (всего ширина ≈ 980 pt — это работает на A3-landscape
    // с padding 70+28).
    const widths = <double>[
      36, // № поз.
      72, // Марка элемента
      72, // Эскиз/обозн.
      48, // ⌀ (мм)
      54, // Класс
      66, // Длина 1 шт., мм
      54, // Кол-во
      66, // Масса 1 пог.м, кг
      66, // Общая длина, м
      72, // Общая масса, кг
      300, // Примечание
    ];
    final headers = <({String label, double width})>[
      (label: '№\nпоз.', width: widths[0]),
      (label: 'Марка элемента', width: widths[1]),
      (label: 'Обозн.', width: widths[2]),
      (label: 'Ø, мм', width: widths[3]),
      (label: 'Класс', width: widths[4]),
      (label: 'Длина 1 шт., мм', width: widths[5]),
      (label: 'Кол-во', width: widths[6]),
      (label: 'Масса 1 пог.м, кг', width: widths[7]),
      (label: 'Σ длина, м', width: widths[8]),
      (label: 'Σ масса, кг', width: widths[9]),
      (label: 'Примечание', width: widths[10]),
    ];

    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: _contentPadding,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      projectName: project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      sheetTitle:
                          'Ведомость расхода стали на монолитные конструкции',
                      reference:
                          'ГОСТ Р 21.501-2018, ф.1 · СП 63.13330.2018',
                      versionNumber: versionNumber,
                      font: font,
                      fontBold: fontBold,
                    ),
                    pw.SizedBox(height: 8),
                    _headerRow(headers, fontBold),
                    if (rebarRows.isEmpty)
                      _row(
                        [
                          (
                            text:
                                'Монолитные ж/б конструкции в проекте отсутствуют '
                                '— ведомость расхода стали не составляется.',
                            width: widths.reduce((a, b) => a + b),
                            align: pw.Alignment.centerLeft,
                          )
                        ],
                        font,
                      )
                    else
                      ...rebarRows.asMap().entries.map((e) {
                        final i = e.key;
                        final r = e.value;
                        return _row(
                          [
                            (
                              text: '${i + 1}',
                              width: widths[0],
                              align: pw.Alignment.center,
                            ),
                            (
                              text: r.element,
                              width: widths[1],
                              align: pw.Alignment.centerLeft
                            ),
                            (
                              text: r.position,
                              width: widths[2],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.diameterMm.toString(),
                              width: widths[3],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.steelClass,
                              width: widths[4],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.lengthMm.toStringAsFixed(0),
                              width: widths[5],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.qty.toStringAsFixed(0),
                              width: widths[6],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.massPerMKg.toStringAsFixed(3),
                              width: widths[7],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.totalLengthM.toStringAsFixed(1),
                              width: widths[8],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.totalMassKg.toStringAsFixed(1),
                              width: widths[9],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.note,
                              width: widths[10],
                              align: pw.Alignment.centerLeft
                            ),
                          ],
                          font,
                        );
                      }),
                    if (rebarRows.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      // Итоговая строка (общая масса).
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          border: pw.Border.all(
                              width: 0.4, color: PdfColors.black),
                        ),
                        height: _headerH,
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: _cellPadH),
                        alignment: pw.Alignment.centerRight,
                        width: widths.reduce((a, b) => a + b),
                        child: pw.Text(
                          'ИТОГО на проект: '
                          '${totalMass.toStringAsFixed(0)} кг '
                          '(${(totalMass / 1000).toStringAsFixed(2)} т)',
                          style: pw.TextStyle(
                              fontSize: 9, font: fontBold),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Распределение массы по элементам:',
                        style: pw.TextStyle(fontSize: 9, font: fontBold),
                      ),
                      for (final entry in byElement.entries)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            '  • ${entry.key}: '
                            '${entry.value.toStringAsFixed(0)} кг '
                            '(${(entry.value / totalMass * 100).toStringAsFixed(0)}%)',
                            style: pw.TextStyle(fontSize: 8, font: font),
                          ),
                        ),
                    ],
                    pw.Spacer(),
                    _notesBlock(
                      title: 'Примечания.',
                      lines: const [
                        '1. Класс рабочей арматуры — А500С (ГОСТ 34028-2016), '
                            'класс хомутов и поперечных стержней — А240 (А-I).',
                        '2. Защитный слой бетона: для рабочей арматуры '
                            'фундаментных конструкций при бетонировании по '
                            'грунту — 70 мм; при наличии подбетонки B7,5 '
                            'толщиной не менее 100 мм — 35 мм '
                            '(СП 63.13330.2018, п. 10.3).',
                        '3. Сварка и стыки арматуры — по ГОСТ 14098-2014, '
                            'нахлёст — не менее 40·d рабочей арматуры.',
                        '4. Хомуты вязать проволокой Ø1,2…1,6 мм по ГОСТ '
                            '3282-74; шаг вязки — каждый второй узел сетки.',
                        '5. Расход арматуры приведён без 5–7 % надбавки на '
                            'нахлёсты и отходы; в смете надбавку учитывать '
                            'отдельно (МДС 81-35.2004).',
                        '6. Контроль арматурных каркасов до бетонирования — '
                            'актом скрытых работ (РД 11-02-2006).',
                      ],
                      font: font,
                      fontBold: fontBold,
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
                sectionTitle: 'Конструкции железобетонные',
                sheetTitle: 'Ведомость расхода стали (КЖ-2)',
                sheetCode: 'КЖ-2',
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

  /// Строит список строк ведомости стали из реальных параметров фундамента.
  ///
  /// Количество и диаметр рабочей арматуры подбирается по сечению
  /// элемента (СП 63.13330.2018, п. 10.3.6 — минимальный процент
  /// армирования 0.1–0.25 %, максимальный шаг поперечных — 0.5 h):
  ///   * для лент/ростверка:
  ///       Ø продольных — 10/12/14 от высоты сечения,
  ///       кол-во ниток — 4/6/8 (2+2 / 3+3 / 4+4) от ширины ленты;
  ///       шаг хомутов — 200 мм для h ≤ 600, 250 мм для h > 600;
  ///   * для плиты: шаг сетки 200/150 от толщины, Ø 12/14;
  ///   * для свай: 4–6 Ø10/12 + спираль Ø6/8;
  ///   * для столбов: 4Ø10/12 + хомуты Ø6.
  static List<_RebarRow> _buildRebarRows(
    HouseProject project,
    FoundationPlanModel? fp,
  ) {
    if (fp == null) return const [];
    // Для сборных фундаментов (ФБС) ведомость расхода стали
    // не составляется (блоки изгатовлены с завода).
    if (project.foundation.device == FoundationDevice.prefabricated) {
      return const [];
    }
    // Удельные массы по ГОСТ 34028-2016 (теоретическая масса 1 пог.м).
    const massPerM = <int, double>{
      6: 0.222,
      8: 0.395,
      10: 0.617,
      12: 0.888,
      14: 1.21,
      16: 1.58,
      18: 2.00,
      20: 2.47,
    };

    final rows = <_RebarRow>[];

    double bandsLength() {
      double total = 0;
      for (final b in fp.bands) {
        final dx = b.x2 - b.x1;
        final dy = b.y2 - b.y1;
        total += math.sqrt(dx * dx + dy * dy);
      }
      return total;
    }

    // Подборы арматуры в зависимости от сечения.
    int longBars(double bandT) {
      // Ширина ленты: < 400 — 4 стержня, 400…600 — 6, > 600 — 8.
      if (bandT < 0.40) return 4;
      if (bandT < 0.60) return 6;
      return 8;
    }

    int longDia(double bandH) {
      // Высота ленты: < 0.5 м — Ø10; 0.5–1.0 — Ø12; > 1.0 — Ø14.
      if (bandH < 0.50) return 10;
      if (bandH < 1.00) return 12;
      return 14;
    }

    int slabDia(double t) {
      if (t < 0.20) return 10;
      if (t < 0.30) return 12;
      return 14;
    }

    double slabStep(double t) {
      // Шаг сетки: для тонких плит (< 250) — 150, иначе 200.
      return t < 0.25 ? 0.15 : 0.20;
    }

    double stirrupStep(double bandH) {
      // СП 63.13330, п. 10.3.13: шаг поперечных ≤ 0.5 h и ≤ 300 мм.
      if (bandH <= 0.6) return 0.20;
      if (bandH <= 1.0) return 0.25;
      return 0.30;
    }

    switch (fp.type) {
      case FoundationType.strip:
        final l = bandsLength();
        // Высота ленты ≈ глубина заложения (ориентировочно: depthM
        // включает видимую часть цоколя).
        final bandH = fp.depthM;
        final bandT = fp.bands.isEmpty ? 0.4 : fp.bands.first.thicknessM;
        final n = longBars(bandT);
        final d = longDia(bandH);
        rows.add(_RebarRow(
          element: 'ФЛ-1 (лента ${(bandT * 1000).toStringAsFixed(0)}×'
              '${(bandH * 1000).toStringAsFixed(0)} мм)',
          position: 'L1',
          diameterMm: d,
          steelClass: 'А500С',
          lengthMm: l * 1000,
          qty: n.toDouble(),
          massPerMKg: massPerM[d]!,
          totalLengthM: l * n,
          totalMassKg: l * n * massPerM[d]!,
          note: 'Продольная рабочая (${n ~/ 2}×верх + '
              '${n ~/ 2}×низ)',
        ));
        // Хомуты Ø8 А240 с расчётным шагом.
        final step = stirrupStep(bandH);
        final stirrupCount = (l / step).round();
        const c = 0.05; // защитный слой 50 мм
        final stirrupLen =
            2 * (bandT - 2 * c) + 2 * (bandH - 2 * c) + 0.20;
        rows.add(_RebarRow(
          element: 'ФЛ-1 (лента)',
          position: 'L2',
          diameterMm: 8,
          steelClass: 'А240',
          lengthMm: stirrupLen * 1000,
          qty: stirrupCount.toDouble(),
          massPerMKg: massPerM[8]!,
          totalLengthM: stirrupCount * stirrupLen,
          totalMassKg: stirrupCount * stirrupLen * massPerM[8]!,
          note: 'Хомуты с шагом '
              '${(step * 1000).toStringAsFixed(0)} мм',
        ));
        break;

      case FoundationType.slab:
        final t = fp.slab?.thicknessM ?? 0.3;
        final w = fp.buildingWidth;
        final ll = fp.buildingLength;
        final d = slabDia(t);
        final step = slabStep(t);
        final nX = (ll / step).floor() + 1;
        final nY = (w / step).floor() + 1;
        final stepMm = (step * 1000).toStringAsFixed(0);
        rows.add(_RebarRow(
          element: 'ПФ-1 (плита δ='
              '${(t * 1000).toStringAsFixed(0)} мм)',
          position: 'L1',
          diameterMm: d,
          steelClass: 'А500С',
          lengthMm: w * 1000,
          qty: nX.toDouble(),
          massPerMKg: massPerM[d]!,
          totalLengthM: nX * w,
          totalMassKg: nX * w * massPerM[d]!,
          note: 'Нижняя сетка, шаг $stepMm мм (поперёк)',
        ));
        rows.add(_RebarRow(
          element: 'ПФ-1 (плита)',
          position: 'L2',
          diameterMm: d,
          steelClass: 'А500С',
          lengthMm: ll * 1000,
          qty: nY.toDouble(),
          massPerMKg: massPerM[d]!,
          totalLengthM: nY * ll,
          totalMassKg: nY * ll * massPerM[d]!,
          note: 'Нижняя сетка, шаг $stepMm мм (вдоль)',
        ));
        rows.add(_RebarRow(
          element: 'ПФ-1 (плита)',
          position: 'L3',
          diameterMm: d,
          steelClass: 'А500С',
          lengthMm: w * 1000,
          qty: nX.toDouble(),
          massPerMKg: massPerM[d]!,
          totalLengthM: nX * w,
          totalMassKg: nX * w * massPerM[d]!,
          note: 'Верхняя сетка, шаг $stepMm мм (поперёк)',
        ));
        rows.add(_RebarRow(
          element: 'ПФ-1 (плита)',
          position: 'L4',
          diameterMm: d,
          steelClass: 'А500С',
          lengthMm: ll * 1000,
          qty: nY.toDouble(),
          massPerMKg: massPerM[d]!,
          totalLengthM: nY * ll,
          totalMassKg: nY * ll * massPerM[d]!,
          note: 'Верхняя сетка, шаг $stepMm мм (вдоль)',
        ));
        // Связи между сетками.
        final ties = ((w / 0.4).floor() + 1) * ((ll / 0.4).floor() + 1);
        final tieLen = math.max(0.15, t - 2 * 0.04);
        rows.add(_RebarRow(
          element: 'ПФ-1 (плита)',
          position: 'L5',
          diameterMm: 8,
          steelClass: 'А240',
          lengthMm: tieLen * 1000,
          qty: ties.toDouble(),
          massPerMKg: massPerM[8]!,
          totalLengthM: ties * tieLen,
          totalMassKg: ties * tieLen * massPerM[8]!,
          note: 'Шпильки между сетками, шаг 400×400 мм',
        ));
        break;

      case FoundationType.pileWithGrillage:
        // Ростверк (высота 0.4 м типовая).
        final l = bandsLength();
        final bandH = 0.4;
        final bandT = fp.bands.isEmpty ? 0.4 : fp.bands.first.thicknessM;
        // Ростверк может быть сборным — в этом случае пропускаем
        // арматуру ростверка.
        final monolithicGrillage = project.foundation.grillageMaterial !=
            GrillageMaterial.prefabricated;
        if (monolithicGrillage) {
          final n = longBars(bandT);
          final d = longDia(bandH);
          rows.add(_RebarRow(
            element: 'Р-1 (ростверк '
                '${(bandT * 1000).toStringAsFixed(0)}×'
                '${(bandH * 1000).toStringAsFixed(0)} мм)',
            position: 'L1',
            diameterMm: d,
            steelClass: 'А500С',
            lengthMm: l * 1000,
            qty: n.toDouble(),
            massPerMKg: massPerM[d]!,
            totalLengthM: l * n,
            totalMassKg: l * n * massPerM[d]!,
            note: 'Продольная рабочая (${n ~/ 2}×верх + '
                '${n ~/ 2}×низ)',
          ));
          final step = stirrupStep(bandH);
          final stCount = (l / step).round();
          const c = 0.05;
          final stLen = 2 * (bandT - 2 * c) + 2 * (bandH - 2 * c) + 0.20;
          rows.add(_RebarRow(
            element: 'Р-1 (ростверк)',
            position: 'L2',
            diameterMm: 8,
            steelClass: 'А240',
            lengthMm: stLen * 1000,
            qty: stCount.toDouble(),
            massPerMKg: massPerM[8]!,
            totalLengthM: stCount * stLen,
            totalMassKg: stCount * stLen * massPerM[8]!,
            note: 'Хомуты ростверка, шаг '
                '${(step * 1000).toStringAsFixed(0)} мм',
          ));
        }
        // Сваи буронабивные — арматура зависит от диаметра сваи.
        final pileCount = fp.piles.length;
        final pileLen = fp.depthM + 0.2;
        final pileDia =
            fp.piles.isNotEmpty ? fp.piles.first.diameterM : 0.30;
        // Для свай Ø≤0.30 — 4Ø10/12, для >0.30 — 6Ø12.
        final pileBars = pileDia <= 0.30 ? 4 : 6;
        final pileBarDia = pileDia <= 0.30 ? 10 : 12;
        rows.add(_RebarRow(
          element: 'С-1 (свая буронабивная Ø'
              '${(pileDia * 1000).toStringAsFixed(0)})',
          position: 'L3',
          diameterMm: pileBarDia,
          steelClass: 'А500С',
          lengthMm: pileLen * 1000,
          qty: (pileCount * pileBars).toDouble(),
          massPerMKg: massPerM[pileBarDia]!,
          totalLengthM: pileCount * pileBars * pileLen,
          totalMassKg: pileCount * pileBars * pileLen * massPerM[pileBarDia]!,
          note: '$pileBars стержней на сваю; '
              '$pileCount свай',
        ));
        // Спираль Ø8 шаг 250.
        final spirCount = (pileLen / 0.25).round();
        final loopLen = math.pi * (pileDia - 2 * 0.05);
        rows.add(_RebarRow(
          element: 'С-1 (свая буронабивная)',
          position: 'L4',
          diameterMm: 8,
          steelClass: 'А240',
          lengthMm: loopLen * 1000,
          qty: (pileCount * spirCount).toDouble(),
          massPerMKg: massPerM[8]!,
          totalLengthM: pileCount * spirCount * loopLen,
          totalMassKg: pileCount * spirCount * loopLen * massPerM[8]!,
          note: 'Спираль / кольца Ø8 А240, шаг 250 мм',
        ));
        break;

      case FoundationType.columnar:
        // Каждый столб: 4Ø10/12 + хомуты Ø6 шаг 200 мм.
        final colCount = fp.piles.length;
        final colLen = fp.depthM + 0.2;
        const c = 0.04;
        final colSide = fp.piles.isNotEmpty
            ? fp.piles.first.diameterM
            : 0.4;
        // Для столбов ≤ 0.4 м — Ø10, для > 0.4 — Ø12.
        final colBarDia = colSide <= 0.40 ? 10 : 12;
        final hoopLen = 4 * (colSide - 2 * c) + 0.10;
        final hoopsPerCol = (colLen / 0.2).round();
        rows.add(_RebarRow(
          element: 'СТ-1 (столб '
              '${(colSide * 1000).toStringAsFixed(0)}×'
              '${(colSide * 1000).toStringAsFixed(0)} мм)',
          position: 'L1',
          diameterMm: colBarDia,
          steelClass: 'А500С',
          lengthMm: colLen * 1000,
          qty: (colCount * 4).toDouble(),
          massPerMKg: massPerM[colBarDia]!,
          totalLengthM: colCount * 4 * colLen,
          totalMassKg: colCount * 4 * colLen * massPerM[colBarDia]!,
          note: '4 продольных стержня на столб; '
              '$colCount столбов',
        ));
        rows.add(_RebarRow(
          element: 'СТ-1 (столб)',
          position: 'L2',
          diameterMm: 6,
          steelClass: 'А240',
          lengthMm: hoopLen * 1000,
          qty: (colCount * hoopsPerCol).toDouble(),
          massPerMKg: massPerM[6]!,
          totalLengthM: colCount * hoopsPerCol * hoopLen,
          totalMassKg:
              colCount * hoopsPerCol * hoopLen * massPerM[6]!,
          note: 'Хомуты Ø6 А240, шаг 200 мм',
        ));
        break;

      case FoundationType.pile:
        // Винтовые сваи — не армируются (стальной ствол).
        break;
    }

    return rows;
  }

  // ═════════════════════════ КД-3: Спецификация лестниц ═══════════════════

  static pw.Page staircaseSpecPage({
    required HouseProject project,
    required List<FloorPlan> plans,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    final rows = _buildStaircaseRows(project, plans);

    const widths = <double>[
      36, // № поз.
      96, // Обозначение
      280, // Наименование
      54, // Кол-во
      66, // Ед. изм.
      78, // Размеры, мм
      78, // Масса, кг
      258, // Примечание / материал
    ];
    final headers = <({String label, double width})>[
      (label: '№\nпоз.', width: widths[0]),
      (label: 'Обозн.', width: widths[1]),
      (label: 'Наименование', width: widths[2]),
      (label: 'Кол-во', width: widths[3]),
      (label: 'Ед. изм.', width: widths[4]),
      (label: 'Размеры, мм', width: widths[5]),
      (label: 'Масса 1 шт., кг', width: widths[6]),
      (label: 'Примечание / материал', width: widths[7]),
    ];

    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: _contentPadding,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      projectName: project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      sheetTitle:
                          'Спецификация элементов лестницы (марш ЛМ-1)',
                      reference:
                          'ГОСТ Р 21.501-2018, ф.7 · СП 1.13130.2020',
                      versionNumber: versionNumber,
                      font: font,
                      fontBold: fontBold,
                    ),
                    pw.SizedBox(height: 8),
                    _headerRow(headers, fontBold),
                    if (rows.isEmpty)
                      _row(
                        [
                          (
                            text:
                                'Лестница в проекте не предусмотрена (одноэтажный '
                                'объект без подвала / чердачного пространства).',
                            width: widths.reduce((a, b) => a + b),
                            align: pw.Alignment.centerLeft
                          )
                        ],
                        font,
                      )
                    else
                      ...rows.asMap().entries.map((e) {
                        final i = e.key;
                        final r = e.value;
                        return _row(
                          [
                            (
                              text: '${i + 1}',
                              width: widths[0],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.code,
                              width: widths[1],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.name,
                              width: widths[2],
                              align: pw.Alignment.centerLeft
                            ),
                            (
                              text: r.qty,
                              width: widths[3],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.unit,
                              width: widths[4],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.size,
                              width: widths[5],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.mass,
                              width: widths[6],
                              align: pw.Alignment.center
                            ),
                            (
                              text: r.note,
                              width: widths[7],
                              align: pw.Alignment.centerLeft
                            ),
                          ],
                          font,
                        );
                      }),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 6,
                          child: _staircaseSummaryBlock(
                              project, plans, font, fontBold),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          flex: 5,
                          child: _staircaseDetailDrawing(
                              project, plans, font, fontBold, pdfFont),
                        ),
                      ],
                    ),
                    pw.Spacer(),
                    _notesBlock(
                      title: 'Примечания.',
                      lines: const [
                        '1. Размеры ступеней приняты по СП 1.13130.2020 '
                            '(п. 4.4.4): высота подступенка 150…200 мм, '
                            'ширина проступи 250…300 мм.',
                        '2. Ширина марша принята не менее 0,9 м '
                            '(СП 1.13130.2020, п. 4.4.1, для жилых ИЖС).',
                        '3. Высота ограждения 0,9 м (СП 1.13130.2020, '
                            'п. 4.4.2); для лестниц с маршами на отметке '
                            '+5 м и выше — 1,2 м.',
                        '4. Сборка маршей и площадок — на резьбовых соединениях '
                            'или сварке (для металлических конструкций — '
                            'по ГОСТ 23118-2019).',
                        '5. Древесина — хвойных пород 1 сорта, влажность '
                            'не более 12 % (ГОСТ 8486-86); пропитка '
                            'огнебиозащитным составом — ГОСТ Р 53292-2009.',
                        '6. Покрытие проступей — лакокрасочное противоскользящее '
                            'или пвх-накладки (СП 29.13330.2011).',
                      ],
                      font: font,
                      fontBold: fontBold,
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
                sectionTitle: 'Конструкции деревянные / металлические',
                sheetTitle: 'Спецификация лестниц (КД-3)',
                sheetCode: 'КД-3',
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

  static pw.Widget _staircaseSummaryBlock(
    HouseProject project,
    List<FloorPlan> plans,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final p = _staircaseParams(project, plans);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.4, color: PdfColors.grey700),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Расчётные параметры марша ЛМ-1:',
            style: pw.TextStyle(fontSize: 9, font: fontBold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '  • Тип: ${p.kindLabel};',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
          pw.Text(
            '  • Высота этажа h = ${(p.floorHeightMm / 1000).toStringAsFixed(2)} м '
            '(${p.floorHeightMm.toStringAsFixed(0)} мм);',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
          pw.Text(
            '  • Кол-во ступеней n = ${p.steps}; '
            'высота подступенка a = ${p.riserMm.toStringAsFixed(0)} мм '
            '(СП 1.13130: 150…200 мм);',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
          pw.Text(
            '  • Ширина проступи b = ${p.treadMm.toStringAsFixed(0)} мм '
            '(СП 1.13130: 250…300 мм); правило 2a + b = '
            '${(2 * p.riserMm + p.treadMm).toStringAsFixed(0)} мм '
            '(ориентир 600…640);',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
          pw.Text(
            '  • Ширина марша B = ${p.marchWidthMm.toStringAsFixed(0)} мм; '
            'длина проекции марша L = ${p.runProjectionMm.toStringAsFixed(0)} мм '
            '(${(p.runProjectionMm / 1000).toStringAsFixed(2)} м);',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
          pw.Text(
            '  • Длина косоура (наклонная) L_к = '
            '${p.stringerLengthMm.toStringAsFixed(0)} мм '
            '(угол подъёма ≈ ${p.angleDeg.toStringAsFixed(1)}°).',
            style: pw.TextStyle(fontSize: 8, font: font),
          ),
        ],
      ),
    );
  }

  /// Подробный чертёж лестницы — боковой вид (вид сбоку) с прорисовкой
  /// каждой ступени, размерными цепями (ширина проступи, высота
  /// подступенка, длина пробега, высота этажа) и углом подъёма. Все
  /// размеры берутся из `_staircaseParams` и совпадают с цифрами в
  /// «Расчётных параметрах марша» и в спецификации.
  static pw.Widget _staircaseDetailDrawing(
    HouseProject project,
    List<FloorPlan> plans,
    pw.Font font,
    pw.Font fontBold,
    PdfFont pdfFont,
  ) {
    final p = _staircaseParams(project, plans);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.4, color: PdfColors.grey700),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Подробный чертёж марша ЛМ-1 (вид сбоку):',
            style: pw.TextStyle(fontSize: 9, font: fontBold),
          ),
          pw.SizedBox(height: 4),
          pw.SizedBox(
            height: 200,
            child: pw.LayoutBuilder(
              builder: (ctx, c) => pw.CustomPaint(
                size: PdfPoint(c!.maxWidth, c.maxHeight),
                painter: (canvas, size) =>
                    _paintStaircaseSideElevation(canvas, size, p, pdfFont),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _paintStaircaseSideElevation(
    PdfGraphics canvas,
    PdfPoint size,
    _StairParams p,
    PdfFont font,
  ) {
    // Выбор подачи зависит от типа лестницы. Раньше всегда рисовали
    // прямой марш на косоуре — для винтовой/поворотной это было неверно
    // (правка по листу 27).
    if (p.kindLabel.contains('винт')) {
      _paintSpiralStaircasePlan(canvas, size, p, font);
      return;
    }
    if (p.kindLabel.contains('пов')) {
      _paintTurningStaircasePlan(canvas, size, p, font);
      return;
    }
    _paintStraightStaircaseSide(canvas, size, p, font);
  }

  /// Прямая маршевая лестница — вид сбоку с косоуром (как и раньше).
  static void _paintStraightStaircaseSide(
    PdfGraphics canvas,
    PdfPoint size,
    _StairParams p,
    PdfFont font,
  ) {
    final w = size.x;
    final h = size.y;
    final totalRunMm = p.runProjectionMm + p.treadMm;
    final totalRiseMm = p.floorHeightMm + 100;
    const padL = 38.0;
    const padR = 12.0;
    const padT = 14.0;
    const padB = 28.0;
    final drawW = w - padL - padR;
    final drawH = h - padT - padB;
    final sx = drawW / totalRunMm;
    final sy = drawH / totalRiseMm;
    final s = sx < sy ? sx : sy;
    final ox = padL;
    final oy = h - padB;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawLine(ox - 8, oy, ox + drawW + 4, oy);
    canvas.strokePath();
    canvas.setFillColor(const PdfColor(0.92, 0.85, 0.74));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    for (var i = 0; i < p.steps; i++) {
      final x0 = ox + i * p.treadMm * s;
      final y0 = oy - (i + 1) * p.riserMm * s;
      final x1 = x0 + p.treadMm * s;
      final y1 = y0 + p.riserMm * s;
      canvas.drawRect(x0, y0, p.treadMm * s, 4);
      canvas.fillAndStrokePath();
      if (i < p.steps - 1) {
        canvas.drawLine(x1, y0, x1, y1);
        canvas.strokePath();
      }
      if (i == 0) {
        canvas.drawLine(x0, y0 + 4, x0, oy);
        canvas.strokePath();
      }
    }
    final stringerEndX = ox + p.runProjectionMm * s;
    final stringerEndY = oy - p.floorHeightMm * s;
    canvas.setStrokeColor(PdfColors.brown800);
    canvas.setLineWidth(1.2);
    canvas.drawLine(ox, oy, stringerEndX, stringerEndY);
    canvas.strokePath();
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.6);
    final railOff = 900 * s;
    canvas.drawLine(ox, oy - railOff, stringerEndX, stringerEndY - railOff);
    canvas.strokePath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    canvas.drawLine(stringerEndX, stringerEndY,
        ox + drawW + 4, stringerEndY);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.setStrokeColor(PdfColors.black);
    final dimY = oy + 12;
    canvas.drawLine(ox, dimY, ox + p.runProjectionMm * s, dimY);
    canvas.drawLine(ox, dimY - 3, ox, dimY + 3);
    canvas.drawLine(ox + p.runProjectionMm * s, dimY - 3,
        ox + p.runProjectionMm * s, dimY + 3);
    canvas.strokePath();
    final lblRun = '${p.runProjectionMm.toStringAsFixed(0)}';
    final mw = font.stringMetrics(lblRun).width * 7;
    canvas.drawString(font, 7, lblRun,
        ox + p.runProjectionMm * s / 2 - mw / 2, dimY + 3);
    final dimX = ox - 16;
    canvas.drawLine(dimX, oy, dimX, stringerEndY);
    canvas.drawLine(dimX - 3, oy, dimX + 3, oy);
    canvas.drawLine(dimX - 3, stringerEndY, dimX + 3, stringerEndY);
    canvas.strokePath();
    canvas.drawString(font, 7,
        '${p.floorHeightMm.toStringAsFixed(0)}',
        dimX - 32, (oy + stringerEndY) / 2);
    canvas.drawString(font, 7,
        '${p.angleDeg.toStringAsFixed(1)}°',
        ox + 18, oy - 14);
    canvas.drawString(font, 6.5,
        'a=${p.riserMm.toStringAsFixed(0)} мм '
        'b=${p.treadMm.toStringAsFixed(0)} мм',
        ox + drawW * 0.45, oy + 22);
    canvas.drawString(font, 6.5, '±0.000', ox + drawW + 6, oy - 2);
    canvas.drawString(font, 6.5,
        '+${(p.floorHeightMm / 1000).toStringAsFixed(2)}',
        ox + drawW + 6, stringerEndY - 2);
  }

  /// Винтовая лестница — план сверху с подписями радиусов и шага.
  /// Конструктив — центральная стойка (труба Ø 100 мм) с консольно
  /// заделанными ступенями, БЕЗ косоура (по СП 1.13130 п. 4.4.5).
  static void _paintSpiralStaircasePlan(
    PdfGraphics canvas,
    PdfPoint size,
    _StairParams p,
    PdfFont font,
  ) {
    final w = size.x;
    final h = size.y;
    // Радиус лестницы = ширина проступи + 100 мм (центральная стойка).
    // По СП 1.13130 п.4.4.5: ширина проступи в средней линии не менее
    // 200 мм. Берём ширину марша как наружный радиус.
    final outerR = p.marchWidthMm; // наружный радиус, мм
    const innerR = 100.0; // радиус центральной стойки, мм
    // Поля под размерные цепи.
    const padL = 24.0;
    const padR = 24.0;
    const padT = 18.0;
    const padB = 28.0;
    final drawW = w - padL - padR;
    final drawH = h - padT - padB;
    final sx = drawW / (2 * outerR);
    final sy = drawH / (2 * outerR);
    final s = sx < sy ? sx : sy;
    final cx = padL + drawW / 2;
    final cy = padT + drawH / 2;
    final rOut = outerR * s;
    final rIn = innerR * s;
    // Кольцо (контур).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawEllipse(cx, cy, rOut, rOut);
    canvas.strokePath();
    canvas.drawEllipse(cx, cy, rIn, rIn);
    canvas.strokePath();
    // Заливка центральной стойки.
    canvas.setFillColor(PdfColors.grey400);
    canvas.drawEllipse(cx, cy, rIn, rIn);
    canvas.fillPath();
    // Радиальные грани ступеней. На один полный виток винтовой лестницы
    // обычно укладывают 12…16 ступеней; строго берём из расчётных
    // параметров: общее число ступеней `p.steps`, угол на ступень
    // ≈ 360° / 12.
    final stepsPerTurn = (12).clamp(8, 18);
    final stepAngle = 2 * math.pi / stepsPerTurn;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.setFillColor(const PdfColor(0.96, 0.92, 0.84));
    for (var i = 0; i < p.steps && i < stepsPerTurn * 2; i++) {
      final a0 = -math.pi / 2 + i * stepAngle;
      final a1 = a0 + stepAngle;
      // Грань ступени = два радиуса из центра.
      final p0x = cx + rIn * math.cos(a0);
      final p0y = cy + rIn * math.sin(a0);
      final p1x = cx + rOut * math.cos(a0);
      final p1y = cy + rOut * math.sin(a0);
      final p2x = cx + rOut * math.cos(a1);
      final p2y = cy + rOut * math.sin(a1);
      // Проступь как трапеция (заливка).
      canvas.moveTo(p0x, p0y);
      canvas.lineTo(p1x, p1y);
      // Дуга по наружному радиусу — приблизим хордой (для крупного
      // масштаба разница незаметна).
      canvas.lineTo(p2x, p2y);
      final p3x = cx + rIn * math.cos(a1);
      final p3y = cy + rIn * math.sin(a1);
      canvas.lineTo(p3x, p3y);
      canvas.lineTo(p0x, p0y);
      canvas.fillAndStrokePath();
    }
    // Стрелка-направление подъёма (ВВЕРХ по часовой).
    final aStart = -math.pi / 2 + 0.2;
    final aMid = aStart + stepAngle * (p.steps / 4);
    final mx = cx + (rIn + (rOut - rIn) * 0.6) * math.cos(aMid);
    final my = cy + (rIn + (rOut - rIn) * 0.6) * math.sin(aMid);
    canvas.setStrokeColor(PdfColors.red);
    canvas.setLineWidth(0.8);
    canvas.drawLine(
      cx + (rIn + (rOut - rIn) * 0.6) * math.cos(aStart),
      cy + (rIn + (rOut - rIn) * 0.6) * math.sin(aStart),
      mx, my,
    );
    canvas.strokePath();
    canvas.setFillColor(PdfColors.red);
    canvas.drawString(font, 7, 'ВВЕРХ', mx + 4, my - 2);
    // Размерные цепи: наружный диаметр + внутренний диаметр.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    final dimY = cy - rOut - 14;
    canvas.drawLine(cx - rOut, dimY, cx + rOut, dimY);
    canvas.drawLine(cx - rOut, dimY - 3, cx - rOut, dimY + 3);
    canvas.drawLine(cx + rOut, dimY - 3, cx + rOut, dimY + 3);
    canvas.strokePath();
    final lblOut = 'Ø${(2 * outerR).toStringAsFixed(0)} мм '
        '(наружный)';
    canvas.drawString(font, 7, lblOut, cx - rOut, dimY - 10);
    final lblIn = 'Стойка Ø${(2 * innerR).toStringAsFixed(0)} мм';
    canvas.drawString(font, 6.5, lblIn, cx - rIn, cy + rIn + 8);
    // Подпись общей высоты + угла на ступень.
    canvas.drawString(font, 7,
        'h этажа = ${(p.floorHeightMm / 1000).toStringAsFixed(2)} м, '
        'n = ${p.steps} ст.',
        padL, padT - 6);
    canvas.drawString(font, 6.5,
        'Δφ на ступень = '
        '${(360 / stepsPerTurn).toStringAsFixed(1)}°',
        padL, padT + 6);
    canvas.drawString(font, 6.5,
        'a = ${p.riserMm.toStringAsFixed(0)} мм, '
        'b = ${p.treadMm.toStringAsFixed(0)} мм по средней линии',
        padL, padT + 18);
  }

  /// Поворотная лестница (с забежной площадкой) — Г-образная схема
  /// в плане + размерные цепи нижнего и верхнего марша.
  static void _paintTurningStaircasePlan(
    PdfGraphics canvas,
    PdfPoint size,
    _StairParams p,
    PdfFont font,
  ) {
    final w = size.x;
    final h = size.y;
    // Делим марши пополам — типичная схема Г-образной лестницы.
    final stepsLow = p.steps ~/ 2;
    final stepsUp = p.steps - stepsLow;
    final lowRunMm = stepsLow * p.treadMm;
    final upRunMm = stepsUp * p.treadMm;
    final marchW = p.marchWidthMm;
    // План: нижний марш идёт вправо, потом площадка, потом марш вверх.
    final totalWmm = lowRunMm + marchW;
    final totalHmm = upRunMm + marchW;
    const padL = 32.0;
    const padR = 28.0;
    const padT = 20.0;
    const padB = 28.0;
    final drawW = w - padL - padR;
    final drawH = h - padT - padB;
    final sx = drawW / totalWmm;
    final sy = drawH / totalHmm;
    final s = sx < sy ? sx : sy;
    final ox = padL;
    final oy = h - padB;
    // Нижний марш: прямоугольник lowRunMm × marchW.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.setFillColor(const PdfColor(0.96, 0.92, 0.84));
    canvas.drawRect(ox, oy - marchW * s, lowRunMm * s, marchW * s);
    canvas.fillAndStrokePath();
    // Подступенки нижнего марша (вертикальные линии).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    for (var i = 1; i < stepsLow; i++) {
      final x = ox + i * p.treadMm * s;
      canvas.drawLine(x, oy, x, oy - marchW * s);
      canvas.strokePath();
    }
    // Площадка.
    canvas.setFillColor(const PdfColor(0.88, 0.84, 0.74));
    canvas.drawRect(ox + lowRunMm * s, oy - marchW * s,
        marchW * s, marchW * s);
    canvas.fillAndStrokePath();
    // Верхний марш: marchW × upRunMm, выход вверх.
    canvas.setFillColor(const PdfColor(0.96, 0.92, 0.84));
    canvas.drawRect(ox + lowRunMm * s, oy - marchW * s - upRunMm * s,
        marchW * s, upRunMm * s);
    canvas.fillAndStrokePath();
    // Подступенки верхнего марша (горизонтальные линии).
    for (var i = 1; i < stepsUp; i++) {
      final y = oy - marchW * s - i * p.treadMm * s;
      canvas.drawLine(ox + lowRunMm * s, y,
          ox + lowRunMm * s + marchW * s, y);
      canvas.strokePath();
    }
    // Стрелка ВВЕРХ — диагональ через нижний марш и площадку.
    canvas.setStrokeColor(PdfColors.red);
    canvas.setLineWidth(0.8);
    canvas.drawLine(ox + 6, oy - marchW * s / 2,
        ox + lowRunMm * s + marchW * s / 2, oy - marchW * s / 2);
    canvas.drawLine(ox + lowRunMm * s + marchW * s / 2, oy - marchW * s / 2,
        ox + lowRunMm * s + marchW * s / 2,
        oy - marchW * s - upRunMm * s + 6);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.red);
    canvas.drawString(font, 7, 'ВВЕРХ', ox + 8, oy - marchW * s / 2 - 12);
    // Размерные цепи.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    final dimYBottom = oy + 12;
    canvas.drawLine(ox, dimYBottom, ox + (lowRunMm + marchW) * s, dimYBottom);
    canvas.drawLine(ox, dimYBottom - 3, ox, dimYBottom + 3);
    canvas.drawLine(ox + lowRunMm * s, dimYBottom - 3,
        ox + lowRunMm * s, dimYBottom + 3);
    canvas.drawLine(ox + (lowRunMm + marchW) * s, dimYBottom - 3,
        ox + (lowRunMm + marchW) * s, dimYBottom + 3);
    canvas.strokePath();
    canvas.drawString(font, 7,
        '${lowRunMm.toStringAsFixed(0)} (марш ${stepsLow} ст.)',
        ox + 4, dimYBottom + 3);
    canvas.drawString(font, 7,
        '${marchW.toStringAsFixed(0)}',
        ox + lowRunMm * s + 4, dimYBottom + 3);
    // Подписи.
    canvas.drawString(font, 7,
        'h этажа = ${(p.floorHeightMm / 1000).toStringAsFixed(2)} м, '
        'n = ${p.steps} ст. (${stepsLow} + площадка + ${stepsUp})',
        padL, padT - 6);
    canvas.drawString(font, 6.5,
        'a = ${p.riserMm.toStringAsFixed(0)} мм, '
        'b = ${p.treadMm.toStringAsFixed(0)} мм, '
        'B = ${marchW.toStringAsFixed(0)} мм',
        padL, padT + 6);
  }

  static List<_StaircaseRow> _buildStaircaseRows(
    HouseProject project,
    List<FloorPlan> plans,
  ) {
    final hasStaircase = project.staircase.isFilled ||
        project.brief.hasStaircase == true ||
        (project.brief.floors ?? 1) > 1;
    if (!hasStaircase) return const [];

    final p = _staircaseParams(project, plans);
    // Материал определяется в _staircaseParams по стенам и этажности.
    final isWood = p.stringerMaterial.toLowerCase().contains('брус') ||
        p.stringerMaterial.toLowerCase().contains('дерев');
    final isConcrete = p.stringerMaterial.toLowerCase().contains('ж/б') ||
        p.stringerMaterial.toLowerCase().contains('монолит');
    final isSteel = !isWood && !isConcrete; // металлические косоуры

    final treads = p.steps - 1; // последняя ступень = пол второго этажа
    final treadAreaM2 = (p.treadMm / 1000) * (p.marchWidthMm / 1000);
    // Масса ступени:
    //   ж/б 30 мм × 2500 кг/м³ → ~75 кг/м²;
    //   рифлёный лист 4 мм × 7850 × 0.5 (рёбра) ≈ 16 кг/м²;
    //   доска 40 мм × 500 кг/м³ → 20 кг/м².
    double treadMass;
    if (isConcrete) {
      treadMass = treadAreaM2 * 75;
    } else if (isSteel) {
      treadMass = treadAreaM2 * 16;
    } else {
      treadMass = treadAreaM2 * 20;
    }
    // Косоур:
    //   дерево — брус 50×200, 500 кг/м³;
    //   металл — швеллер [10, 8.59 кг/м или [20 = 18.4 кг/м;
    //   ж/б — монолит 0.16 м² сечение × 2500 = 400 кг/м.
    final stringerLengthM = p.stringerLengthMm / 1000.0;
    double stringerMass;
    if (isConcrete) {
      stringerMass = stringerLengthM * 400;
    } else if (isSteel) {
      stringerMass = stringerLengthM * 18.4; // [20П
    } else {
      stringerMass = stringerLengthM * 0.05 * 0.20 * 500;
    }
    final balusters = treads + 1; // балясина на каждой ступени + сверху

    final rows = <_StaircaseRow>[
      _StaircaseRow(
        code: 'ЛМ-1',
        name: 'Марш лестничный (комплект: косоуры + ступени + крепёж)',
        qty: '1',
        unit: 'компл.',
        size:
            '${p.runProjectionMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}',
        mass: (treads * treadMass + 2 * stringerMass).toStringAsFixed(0),
        note: isConcrete
            ? 'Ж/б монолит B25, КМ0 (СП 112.13330)'
            : isSteel
                ? 'Сталь Ст3сп5, ГОСТ 27772-2015; антикор грунт + эмаль'
                : 'Сосна 1с, ГОСТ 8486-86; пропитка ОБЗС',
      ),
      _StaircaseRow(
        code: 'КС-1',
        name: 'Косоур (тетива)',
        qty: '2',
        unit: 'шт.',
        size: isConcrete
            ? '${p.stringerLengthMm.toStringAsFixed(0)}×400×160'
            : isSteel
                ? '${p.stringerLengthMm.toStringAsFixed(0)}×200×6'
                : '${p.stringerLengthMm.toStringAsFixed(0)}×200×50',
        mass: stringerMass.toStringAsFixed(0),
        note: p.stringerMaterial,
      ),
      _StaircaseRow(
        code: 'СТ-1',
        name: 'Ступень (проступь)',
        qty: '$treads',
        unit: 'шт.',
        size: isConcrete
            ? '${p.treadMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}×30'
            : isSteel
                ? '${p.treadMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}×4'
                : '${p.treadMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}×40',
        mass: treadMass.toStringAsFixed(1),
        note: p.stepMaterial,
      ),
      _StaircaseRow(
        code: 'ПС-1',
        name: 'Подступенок (закрытая лестница)',
        qty: '$treads',
        unit: 'шт.',
        size:
            '${p.riserMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}×20',
        mass: '2.5',
        note: 'Применяется при закрытом типе марша (без просветов)',
      ),
      _StaircaseRow(
        code: 'ПР-1',
        name: p.marchWidthMm >= 1250
            ? 'Поручень (с обеих сторон, ширина марша ≥ 1.25 м)'
            : 'Поручень (с одной стороны)',
        qty: p.marchWidthMm >= 1250 ? '2' : '1',
        unit: 'шт.',
        size: '${p.stringerLengthMm.toStringAsFixed(0)}×60×40',
        mass: ((p.stringerLengthMm / 1000) * 1.2).toStringAsFixed(1),
        note: '${p.railingMaterial}; высота 0,9 м '
            '(СП 1.13130.2020, п. 4.4.2)',
      ),
      _StaircaseRow(
        code: 'БЛ-1',
        name: 'Балясина',
        qty: '$balusters',
        unit: 'шт.',
        size: '900×40×40',
        mass: '1.4',
        note: 'Просвет между балясинами ≤ 100 мм '
            '(СП 1.13130, п. 4.4.2)',
      ),
      _StaircaseRow(
        code: 'ТП-1',
        name: 'Площадка лестничная (для поворотных схем)',
        qty: p.kindLabel.contains('поворотная') ||
                p.kindLabel.contains('винтовая')
            ? '1'
            : '0',
        unit: 'шт.',
        size:
            '${p.marchWidthMm.toStringAsFixed(0)}×${p.marchWidthMm.toStringAsFixed(0)}×40',
        mass: (p.marchWidthMm * p.marchWidthMm / 1e6 * 0.04 * 500)
            .toStringAsFixed(1),
        note: 'Если выбран поворотный/винтовой марш',
      ),
      _StaircaseRow(
        code: 'КП-1',
        name: 'Крепёж: уголки 50×50, шурупы 6×80, болты М10',
        qty: '1',
        unit: 'компл.',
        size: '—',
        mass: '3.0',
        note: 'Антикор. покрытие, ГОСТ 9870-61 / DIN 933',
      ),
    ];
    return rows;
  }

  // ═══════════════════════ Ведомость отделки помещений ════════════════════

  /// Ведомость отделки помещений (АР-N). Многостраничная: при большом
  /// числе помещений таблица автоматически переносится на следующий
  /// лист, а блок «Примечания» выводится после неё, не накладываясь на
  /// штамп.
  static pw.Page roomFinishSchedulePage({
    required HouseProject project,
    required List<FloorPlan> plans,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    final entries = _buildRoomFinishRows(plans);

    const widths = <double>[
      30, // № п/п
      52, // № помещ.
      170, // Наименование
      52, // Площадь, м²
      170, // Тип пола
      170, // Тип стен
      155, // Тип потолка
      80, // Плинтус
      230, // Примечание
    ];
    final headers = <({String label, double width})>[
      (label: '№', width: widths[0]),
      (label: '№\nпом.', width: widths[1]),
      (label: 'Наименование', width: widths[2]),
      (label: 'S, м²', width: widths[3]),
      (label: 'Пол', width: widths[4]),
      (label: 'Стены', width: widths[5]),
      (label: 'Потолок', width: widths[6]),
      (label: 'Плинтус', width: widths[7]),
      (label: 'Примечание', width: widths[8]),
    ];

    final tableHeaderRow = _headerRow(headers, fontBold);
    final sheetHdr = _sheetHeader(
      projectName: project.name.isEmpty
          ? 'Индивидуальный жилой дом'
          : project.name,
      sheetTitle: 'Ведомость отделки помещений',
      reference: 'ГОСТ Р 21.501-2018, ф.4 · СП 71.13330.2017',
      versionNumber: versionNumber,
      font: font,
      fontBold: fontBold,
    );
    final body = <pw.Widget>[
      if (entries.isEmpty)
        _row(
          [
            (
              text: 'Помещения в проекте не описаны — '
                  'ведомость отделки не составляется.',
              width: widths.reduce((a, b) => a + b),
              align: pw.Alignment.centerLeft,
            )
          ],
          font,
        )
      else
        ...entries.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return _row(
            [
              (text: '${i + 1}', width: widths[0], align: pw.Alignment.center),
              (text: r.roomNumber, width: widths[1], align: pw.Alignment.center),
              (text: r.name, width: widths[2], align: pw.Alignment.centerLeft),
              (
                text: r.areaM2.toStringAsFixed(1),
                width: widths[3],
                align: pw.Alignment.center
              ),
              (text: r.floor, width: widths[4], align: pw.Alignment.centerLeft),
              (text: r.walls, width: widths[5], align: pw.Alignment.centerLeft),
              (text: r.ceiling, width: widths[6], align: pw.Alignment.centerLeft),
              (text: r.skirting, width: widths[7], align: pw.Alignment.centerLeft),
              (text: r.note, width: widths[8], align: pw.Alignment.centerLeft),
            ],
            font,
          );
        }),
      pw.SizedBox(height: 14),
      _finishLegendBlock(font, fontBold),
      pw.SizedBox(height: 12),
      _notesBlock(
        title: 'Примечания.',
        lines: const [
          '1. Отделочные работы выполнять в соответствии с СП '
              '71.13330.2017 «Изоляционные и отделочные покрытия». '
              'Качество работ контролировать по СП 48.13330.2019.',
          '2. Для помещений с влажным режимом (санузлы, кухни, '
              'котельные) обязательна обмазочная гидроизоляция пола '
              'с заведением на стены 200 мм '
              '(СП 29.13330.2011, п. 5.3.5).',
          '3. Стены санузлов облицовывать керамической плиткой на '
              'высоту не менее 1,8 м (СП 54.13330.2022, п. 9.16).',
          '4. Зазор между плинтусом и облицовкой пола заполнять '
              'эластичным герметиком (СП 71.13330.2017, п. 7).',
          '5. Все материалы должны иметь сертификаты пожарной '
              'безопасности (ФЗ № 123-ФЗ): класс пожарной опасности '
              'отделочных материалов в путях эвакуации — не более '
              'КМ2 (СП 1.13130.2020, табл. 28).',
          '6. После завершения отделочных работ — предъявление '
              'помещения с актом приёмки (РД 11-02-2006).',
        ],
        font: font,
        fontBold: fontBold,
      ),
    ];

    return pw.MultiPage(
      pageTheme: _drawingThemeWithTitleBlock(
        project: project,
        font: font,
        fontBold: fontBold,
        sectionTitle: 'Архитектурные решения',
        sheetTitle: 'Ведомость отделки помещений',
        sheetCode: 'АР-$sheetNumber',
        sheetNumber: sheetNumber,
        totalSheets: totalSheets,
        organization: organization,
      ),
      header: (context) {
        if (context.pageNumber == 1) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sheetHdr,
              pw.SizedBox(height: 10),
              tableHeaderRow,
              pw.SizedBox(height: 4),
            ],
          );
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: tableHeaderRow,
        );
      },
      build: (context) => body,
    );
  }

  static pw.Widget _finishLegendBlock(pw.Font font, pw.Font fontBold) {
    pw.Widget item(String code, String desc) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 1),
        child: pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(fontSize: 8, font: font),
            children: [
              pw.TextSpan(
                text: code,
                style: pw.TextStyle(fontSize: 8, font: fontBold),
              ),
              pw.TextSpan(text: ' — $desc'),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Условные обозначения покрытий пола (П):',
                  style: pw.TextStyle(fontSize: 9, font: fontBold)),
              item('П1',
                  'ламинат 33 кл. δ=8 мм по подложке, СП 71.13330'),
              item('П2',
                  'керамогранит 600×600, шов 2 мм, СП 71.13330, п. 7.4'),
              item('П3',
                  'плитка керамическая для пола, ГОСТ 6787-2001'),
              item('П4',
                  'паркет / паркетная доска, ГОСТ 862.1-85 (по желанию)'),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Условные обозначения покрытий стен (С):',
                  style: pw.TextStyle(fontSize: 9, font: fontBold)),
              item('С1',
                  'обои виниловые на флизелиновой основе, ГОСТ 6810-2002'),
              item('С2',
                  'плитка керамическая глазурованная, ГОСТ 6141-91'),
              item('С3',
                  'окраска ВД-АК / силикатной краской, СП 71.13330'),
              item('С4',
                  'штукатурка + шпаклёвка под обои/окраску'),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Условные обозначения потолков (Т):',
                  style: pw.TextStyle(fontSize: 9, font: fontBold)),
              item('Т1', 'натяжной ПВХ матовый, ГОСТ Р ИСО 14644'),
              item('Т2',
                  'влагостойкий ГКЛ + окраска, СП 71.13330, п. 7.6'),
              item('Т3',
                  'окраска по штукатурке, ВД-АК'),
              item('Т4',
                  'подвесной модульный (Армстронг), ГОСТ 28415-89'),
            ],
          ),
        ),
      ],
    );
  }

  static List<_RoomFinishRow> _buildRoomFinishRows(List<FloorPlan> plans) {
    final rows = <_RoomFinishRow>[];
    int counter = 1;
    for (var f = 0; f < plans.length; f++) {
      final plan = plans[f];
      final floorPrefix = '${f + 1}';
      for (final room in plan.rooms) {
        if (room.kind == PlanRoomKind.staircase) {
          rows.add(_RoomFinishRow(
            roomNumber: '$floorPrefix.${counter++}',
            name: 'Лестничная клетка',
            areaM2: room.area,
            floor: 'П2 — керамогранит 600×600',
            walls: 'С3 — окраска / штукатурка',
            ceiling: 'Т3 — окраска по штукатурке',
            skirting: 'плинтус ПВХ 60 мм',
            note: 'СП 1.13130.2020 (КМ2)',
          ));
          continue;
        }
        if (room.kind == PlanRoomKind.free) {
          rows.add(_RoomFinishRow(
            roomNumber: '$floorPrefix.${counter++}',
            name: room.label.isNotEmpty ? room.label : 'Свободная зона',
            areaM2: room.area,
            floor: 'П1 — ламинат 33 кл.',
            walls: 'С1 — обои виниловые',
            ceiling: 'Т1 — натяжной матовый',
            skirting: 'плинтус ПВХ 60 мм',
            note: '—',
          ));
          continue;
        }
        final kind = RoomKind.values.firstWhere(
          (k) => k.name == room.roomKindName,
          orElse: () => RoomKind.bedroom,
        );
        final f0 = _finishFor(kind);
        rows.add(_RoomFinishRow(
          roomNumber: '$floorPrefix.${counter++}',
          name: room.label.isNotEmpty ? room.label : kind.title,
          areaM2: room.area,
          floor: f0.floor,
          walls: f0.walls,
          ceiling: f0.ceiling,
          skirting: f0.skirting,
          note: f0.note,
        ));
      }
    }
    return rows;
  }

  static _FinishSet _finishFor(RoomKind kind) {
    switch (kind) {
      case RoomKind.bathroom:
        return const _FinishSet(
          floor: 'П2 — керамогранит 600×600',
          walls: 'С2 — плитка керамическая 200×300',
          ceiling: 'Т2 — ГКЛВ + окраска влагостойкая',
          skirting: 'керамическая раскладка',
          note: 'Гидроизоляция пола обмазочная (СП 29.13330)',
        );
      case RoomKind.kitchen:
        return const _FinishSet(
          floor: 'П2 — керамогранит / П1 — ламинат',
          walls: 'С1 — обои + С2 — фартук плиткой 600 мм',
          ceiling: 'Т1 — натяжной матовый',
          skirting: 'плинтус ПВХ 60 мм',
          note: 'Класс пож. опасности — не выше КМ2',
        );
      case RoomKind.boilerRoom:
        return const _FinishSet(
          floor: 'П3 — плитка керамическая',
          walls: 'С3 — окраска ВД-АК (НГ)',
          ceiling: 'Т3 — окраска по штукатурке (НГ)',
          skirting: 'нет',
          note: 'Материалы НГ/Г1 (СП 7.13130.2013)',
        );
      case RoomKind.hallway:
        return const _FinishSet(
          floor: 'П2 — керамогранит',
          walls: 'С1 — обои виниловые',
          ceiling: 'Т1 — натяжной матовый',
          skirting: 'плинтус ПВХ 60 мм',
          note: '—',
        );
      case RoomKind.storage:
        return const _FinishSet(
          floor: 'П1 — ламинат 33 кл.',
          walls: 'С4 — штукатурка + окраска',
          ceiling: 'Т3 — окраска',
          skirting: 'плинтус ПВХ 60 мм',
          note: '—',
        );
      case RoomKind.wardrobe:
        return const _FinishSet(
          floor: 'П1 — ламинат 33 кл.',
          walls: 'С1 — обои виниловые',
          ceiling: 'Т1 — натяжной матовый',
          skirting: 'плинтус ПВХ 60 мм',
          note: 'Освещение от датчика движения',
        );
      case RoomKind.bedroom:
      case RoomKind.livingRoom:
      case RoomKind.study:
      case RoomKind.kidsRoom:
      case RoomKind.dining:
      case RoomKind.kitchenDining:
      case RoomKind.toilet:
      case RoomKind.laundry:
      case RoomKind.garage:
      case RoomKind.terrace:
      case RoomKind.balcony:
      case RoomKind.pantry:
      case RoomKind.technical:
        return const _FinishSet(
          floor: 'П1 — ламинат 33 кл.',
          walls: 'С1 — обои виниловые',
          ceiling: 'Т1 — натяжной матовый',
          skirting: 'плинтус ПВХ 60 мм',
          note: '—',
        );
    }
  }

  // ═══════════════════════ Перечень актов скрытых работ ═══════════════════

  /// Перечень видов работ, подлежащих освидетельствованию (акты скрытых
  /// работ). Многостраничная: при большом количестве позиций таблица
  /// автоматически переносится на следующий лист, штамп отрисовывается
  /// на каждой странице, блок «Примечания» не накладывается на штамп.
  static pw.MultiPage hiddenWorksActsPage({
    required HouseProject project,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    final acts = _buildHiddenWorks(project);

    const widths = <double>[
      30, // № п/п
      340, // Наименование работ
      210, // Этап / время выполнения
      210, // Норматив
      140, // Контролирующий
      180, // Документ освидетельствования
    ];
    final headers = <({String label, double width})>[
      (label: '№', width: widths[0]),
      (label: 'Наименование работ', width: widths[1]),
      (label: 'Этап / время выполнения', width: widths[2]),
      (label: 'Норматив', width: widths[3]),
      (label: 'Контролирующий орган', width: widths[4]),
      (label: 'Документ освидетельствования', width: widths[5]),
    ];

    final tableHeaderRow = _headerRow(headers, fontBold);
    final sheetHdr = _sheetHeader(
      projectName: project.name.isEmpty
          ? 'Индивидуальный жилой дом'
          : project.name,
      sheetTitle:
          'Перечень видов работ, подлежащих освидетельствованию '
          '(акты скрытых работ)',
      reference: 'СП 48.13330.2019 · РД-11-02-2006 · РД-11-05-2007',
      versionNumber: versionNumber,
      font: font,
      fontBold: fontBold,
    );
    final body = <pw.Widget>[
      ...acts.asMap().entries.map((e) {
        final i = e.key;
        final a = e.value;
        return _row(
          [
            (text: '${i + 1}', width: widths[0], align: pw.Alignment.center),
            (text: a.work, width: widths[1], align: pw.Alignment.centerLeft),
            (text: a.stage, width: widths[2], align: pw.Alignment.centerLeft),
            (
              text: a.reference,
              width: widths[3],
              align: pw.Alignment.centerLeft
            ),
            (
              text: a.controller,
              width: widths[4],
              align: pw.Alignment.centerLeft
            ),
            (text: a.doc, width: widths[5], align: pw.Alignment.centerLeft),
          ],
          font,
        );
      }),
      pw.SizedBox(height: 14),
      _notesBlock(
        title: 'Примечания.',
        lines: const [
          '1. Перечень составлен в соответствии с СП 48.13330.2019 '
              '«Организация строительства», РД-11-02-2006 «Требования '
              'к составу и порядку ведения исполнительной документации '
              'при строительстве, реконструкции, капитальном ремонте» '
              'и РД-11-05-2007 «Порядок ведения общего и (или) '
              'специального журнала учёта выполнения работ».',
          '2. На каждый этап скрытых работ оформляется акт '
              'освидетельствования скрытых работ по форме приложения 3 '
              'РД-11-02-2006. К акту прилагаются: рабочие чертежи с '
              'отметкой о выполнении, общий и специальные журналы работ, '
              'исполнительные геодезические схемы, паспорта (сертификаты) '
              'материалов и изделий, протоколы испытаний, ведомости '
              'результатов лабораторного контроля.',
          '3. До получения подписанного акта последующие работы, '
              'закрывающие проверяемые конструкции, не выполняются '
              '(СП 48.13330.2019, п. 7.4; ГрК РФ, ст. 53).',
          '4. Состав комиссии: представитель технического заказчика '
              '(застройщика), представитель подрядчика (производитель '
              'работ), представитель проектной организации '
              '(при осуществлении авторского надзора по СП 246.1325800.2016), '
              'представитель государственного строительного надзора '
              '(при поднадзорности объекта по ГрК РФ, ст. 54).',
          '5. Журналы работ ведутся по формам, утверждённым приказом '
              'Ростехнадзора: общий журнал работ (РД-11-05-2007, '
              'приложение 1) и специальные журналы (бетонных, сварочных, '
              'арматурных, монтажных, антикоррозионных работ).',
          '6. Документация ведётся в бумажном или электронном виде с '
              'квалифицированной электронной подписью '
              '(приказ Минстроя РФ от 16.05.2023 № 344/пр).',
          '7. По окончании строительства все акты освидетельствования '
              'скрытых работ передаются заказчику в составе '
              'исполнительной документации (ГОСТ Р 70108-2022).',
        ],
        font: font,
        fontBold: fontBold,
      ),
    ];

    return pw.MultiPage(
      pageTheme: _drawingThemeWithTitleBlock(
        project: project,
        font: font,
        fontBold: fontBold,
        sectionTitle: 'Организация строительства',
        sheetTitle: 'Перечень актов скрытых работ',
        sheetCode: 'ОР-$sheetNumber',
        sheetNumber: sheetNumber,
        totalSheets: totalSheets,
        organization: organization,
      ),
      header: (context) {
        if (context.pageNumber == 1) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sheetHdr,
              pw.SizedBox(height: 8),
              tableHeaderRow,
              pw.SizedBox(height: 4),
            ],
          );
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: tableHeaderRow,
        );
      },
      build: (context) => body,
    );
  }

  static List<_HiddenWorkRow> _buildHiddenWorks(HouseProject project) {
    final foundationType = project.foundation.type;
    final hasRoof = project.roof.isFilled;
    final hasBasement = project.brief.hasBasement == true;
    final isFrame = (project.walls.material ??
            project.brief.wallMaterial?.name ??
            '') ==
        'frame';

    final rows = <_HiddenWorkRow>[
      const _HiddenWorkRow(
        work: 'Геодезическая разбивка осей здания, разбивочный план',
        stage: 'До начала земляных работ',
        reference:
            'СП 126.13330.2017, СП 70.13330.2012, п. 5.6',
        controller: 'Геодезист, технадзор',
        doc: 'Акт разбивки осей',
      ),
      const _HiddenWorkRow(
        work: 'Земляные работы: устройство котлована / траншей под фундамент',
        stage: 'Подготовительный этап',
        reference: 'СП 45.13330.2017, СП 22.13330.2016',
        controller: 'Прораб, технадзор',
        doc: 'Акт приёмки земляных работ; журнал работ',
      ),
      const _HiddenWorkRow(
        work: 'Подготовка основания: песчаная подушка, уплотнение, '
            'геотекстиль',
        stage: 'Перед бетонированием подбетонки',
        reference: 'СП 45.13330.2017, п. 6.6; СП 22.13330.2016',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ),
    ];

    if (foundationType == FoundationType.strip ||
        foundationType == FoundationType.slab ||
        foundationType == FoundationType.columnar ||
        foundationType == FoundationType.pileWithGrillage) {
      rows.add(const _HiddenWorkRow(
        work:
            'Устройство подбетонки B7,5 толщиной 100 мм под монолитные '
                'конструкции',
        stage: 'После приёмки основания',
        reference: 'СП 70.13330.2012, п. 5.18',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ));
      rows.add(const _HiddenWorkRow(
        work:
            'Устройство опалубки: проверка геометрии, плотности и жёсткости',
        stage: 'Перед армированием',
        reference: 'СП 70.13330.2012, п. 5.16',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ));
      rows.add(const _HiddenWorkRow(
        work:
            'Армирование монолитных конструкций фундамента (сборка каркасов, '
                'проверка диаметров, шага, защитного слоя)',
        stage: 'Перед бетонированием',
        reference:
            'СП 63.13330.2018, п. 10; СП 70.13330.2012, п. 5.17',
        controller: 'Прораб, авторский надзор, технадзор',
        doc: 'Акт скрытых работ; журнал арматурных работ',
      ));
      rows.add(const _HiddenWorkRow(
        work:
            'Бетонирование монолитных конструкций (контроль класса бетона, '
                'отбор контрольных образцов)',
        stage: 'Этап монолитных работ',
        reference:
            'СП 63.13330.2018; СП 70.13330.2012, п. 5.18; ГОСТ 18105-2018',
        controller: 'Прораб, лаборатория, технадзор',
        doc: 'Акт скрытых работ; журнал бетонных работ; протоколы испытаний',
      ));
    }

    if (foundationType == FoundationType.pile ||
        foundationType == FoundationType.pileWithGrillage) {
      rows.add(_HiddenWorkRow(
        work: foundationType == FoundationType.pile
            ? 'Погружение винтовых свай (контроль глубины, момента вкручивания)'
            : 'Устройство буронабивных свай (контроль геометрии скважины, '
                'армокаркаса, бетонирование)',
        stage: 'До устройства ростверка/обвязки',
        reference:
            'СП 24.13330.2021, разд. 7; СП 45.13330.2017',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ; журнал свайных работ',
      ));
    }

    rows.add(const _HiddenWorkRow(
      work:
          'Устройство гидроизоляции фундамента (горизонтальной и вертикальной)',
      stage: 'После набора прочности бетона',
      reference: 'СП 28.13330.2017; СП 71.13330.2017',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ',
    ));
    rows.add(const _HiddenWorkRow(
      work: 'Обратная засыпка пазух фундамента (контроль уплотнения '
          'послойно)',
      stage: 'После гидроизоляции',
      reference: 'СП 45.13330.2017, п. 6.13',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ',
    ));

    if (hasBasement) {
      rows.add(const _HiddenWorkRow(
        work: 'Устройство дренажа и пристенного фильтрующего слоя '
            'вокруг подвала',
        stage: 'До обратной засыпки',
        reference: 'СП 22.13330.2016, СП 45.13330.2017',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ));
    }

    rows.add(_HiddenWorkRow(
      work: isFrame
          ? 'Устройство несущего каркаса: монтаж стоек, обвязок, '
              'связей жёсткости'
          : 'Кладка наружных и внутренних несущих стен, контроль '
              'геометрии, толщины швов',
      stage: 'Этап возведения коробки',
      reference: isFrame
          ? 'СП 64.13330.2017; СП 31-105-2002'
          : 'СП 15.13330.2020; СП 70.13330.2012, разд. 9',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ; журнал каменных/монтажных работ',
    ));

    rows.add(const _HiddenWorkRow(
      work:
          'Армирование монолитных перекрытий и поясов (если предусмотрено)',
      stage: 'Перед бетонированием перекрытия',
      reference: 'СП 63.13330.2018; СП 70.13330.2012',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ',
    ));

    if (hasRoof) {
      rows.add(const _HiddenWorkRow(
        work: 'Устройство стропильной системы (мауэрлат, стропила, '
            'обрешётка)',
        stage: 'Этап устройства кровли',
        reference: 'СП 64.13330.2017; СП 17.13330.2017',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ));
      rows.add(const _HiddenWorkRow(
        work: 'Устройство кровельного пирога: пароизоляция, '
            'утеплитель, гидроветрозащита',
        stage: 'До укладки кровельного покрытия',
        reference: 'СП 17.13330.2017; СП 50.13330.2012',
        controller: 'Прораб, технадзор',
        doc: 'Акт скрытых работ',
      ));
      rows.add(const _HiddenWorkRow(
        work: 'Устройство кровельного покрытия и водоотводной системы',
        stage: 'Завершение кровли',
        reference: 'СП 17.13330.2017',
        controller: 'Прораб, технадзор',
        doc: 'Акт приёмки кровли',
      ));
    }

    rows.add(const _HiddenWorkRow(
      work:
          'Устройство утепления и гидроизоляции наружных стен (фасадные системы)',
      stage: 'Перед облицовкой фасада',
      reference: 'СП 50.13330.2012; СП 71.13330.2017',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ',
    ));
    rows.add(const _HiddenWorkRow(
      work: 'Скрытая прокладка инженерных сетей: электрика, '
          'водопровод, канализация, отопление',
      stage: 'До чистовой отделки',
      reference: 'СП 31.13330.2012; СП 30.13330.2020; СП 60.13330.2020; '
          'СП 256.1325800.2016',
      controller: 'Прораб, технадзор; представитель ресурсоснабжающей '
          'организации',
      doc: 'Акты скрытых работ по разделам',
    ));
    rows.add(const _HiddenWorkRow(
      work: 'Устройство пароизоляции и утепления полов / межэтажных '
          'перекрытий',
      stage: 'До устройства стяжки и чистовых полов',
      reference: 'СП 50.13330.2012; СП 29.13330.2011',
      controller: 'Прораб, технадзор',
      doc: 'Акт скрытых работ',
    ));
    rows.add(const _HiddenWorkRow(
      work: 'Огнезащитная обработка деревянных конструкций (стропил, '
          'обрешётки, перекрытий)',
      stage: 'До закрытия конструкций',
      reference: 'ГОСТ Р 53292-2009; СП 2.13130.2020',
      controller: 'Прораб, технадзор; пожарная инспекция (выборочно)',
      doc: 'Акт обработки; протокол лаборатории',
    ));

    return rows;
  }

  // ─────────────────────── общие хелперы блоков ────────────────────────
  static pw.Widget _notesBlock({
    required String title,
    required List<String> lines,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.4, color: PdfColors.grey700),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontSize: 9, font: fontBold)),
          pw.SizedBox(height: 2),
          for (final l in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(l,
                  style: pw.TextStyle(fontSize: 7.5, font: font)),
            ),
        ],
      ),
    );
  }

  // ─────────────────────── расчёт параметров лестницы ──────────────────
  static _StairParams _staircaseParams(
    HouseProject project,
    List<FloorPlan> plans,
  ) {
    final s = project.staircase;
    final type = (s.type ?? '').toLowerCase();
    String kindLabel;
    if (type.contains('screw') || type.contains('винт')) {
      kindLabel = 'винтовая';
    } else if (type.contains('rotary') ||
        type.contains('пов') ||
        type.contains('turn')) {
      kindLabel = 'поворотная (с площадкой)';
    } else if (type.isEmpty || type.contains('marsh') || type.contains('маршев')) {
      kindLabel = 'маршевая прямая';
    } else {
      kindLabel = type;
    }

    final hM = s.floorHeight ?? project.walls.height ?? 2.8;
    final stepsCount = (s.stepsCount != null && s.stepsCount! >= 8)
        ? s.stepsCount!
        : math.max(8, (hM / 0.18).round());
    final riserMm = (hM * 1000) / stepsCount;
    final treadMm = math.max(250.0, (640.0 - 2 * riserMm));

    // Ширина марша — из реального лестничного проёма на плане. СП
    // 1.13130.2020: минимум для ИЖС — 0.9 м, рекомендуется 1.0 м.
    double marchWidthMm = 1000.0;
    for (final plan in plans) {
      PlanRoom? stair;
      for (final r in plan.rooms) {
        if (r.kind == PlanRoomKind.staircase) {
          stair = r;
          break;
        }
      }
      if (stair != null) {
        final shorter = math.min(stair.width, stair.height);
        marchWidthMm = math.max(900.0, math.min(1500.0, shorter * 1000));
        break;
      }
    }

    final runProjectionMm = (stepsCount - 1) * treadMm;
    final hMm = hM * 1000;
    final stringerLengthMm =
        math.sqrt(runProjectionMm * runProjectionMm + hMm * hMm);
    final angleDeg = math.atan2(hMm, runProjectionMm) * 180 / math.pi;

    // Материал лестницы по стенам и этажности.
    final wallMat = WallMaterial.fromName(project.walls.material) ??
        project.brief.wallMaterial;
    final floors = project.brief.floors ?? plans.length;
    String stringerMaterial;
    String stepMaterial;
    String railingMaterial;
    if (wallMat == WallMaterial.timber || wallMat == WallMaterial.frame) {
      stringerMaterial = 'Брус хв. пород, ГОСТ 8486-86';
      stepMaterial = 'Доска хв. пород, ГОСТ 8486-86';
      railingMaterial = 'Дерево';
    } else if (floors > 2) {
      stringerMaterial = 'Ж/б монолит B25 F100 W6';
      stepMaterial = 'Ж/б монолит B25, отд. плиткой';
      railingMaterial = 'Нерж. сталь AISI 304';
    } else {
      stringerMaterial = 'Металл. швеллер [10×100, ГОСТ 8240-97';
      stepMaterial = 'Доска дуб/сосна, ГОСТ 8486-86';
      railingMaterial = 'Металл + дерево';
    }

    return _StairParams(
      kindLabel: kindLabel,
      floorHeightMm: hMm,
      steps: stepsCount,
      riserMm: riserMm,
      treadMm: treadMm,
      marchWidthMm: marchWidthMm,
      runProjectionMm: runProjectionMm,
      stringerLengthMm: stringerLengthMm,
      angleDeg: angleDeg,
      stringerMaterial: stringerMaterial,
      stepMaterial: stepMaterial,
      railingMaterial: railingMaterial,
    );
  }
}

// ─────────────────────── data-классы ────────────────────────────────────

class _RebarRow {
  final String element;
  final String position;
  final int diameterMm;
  final String steelClass;
  final double lengthMm;
  final double qty;
  final double massPerMKg;
  final double totalLengthM;
  final double totalMassKg;
  final String note;

  const _RebarRow({
    required this.element,
    required this.position,
    required this.diameterMm,
    required this.steelClass,
    required this.lengthMm,
    required this.qty,
    required this.massPerMKg,
    required this.totalLengthM,
    required this.totalMassKg,
    required this.note,
  });
}

class _StaircaseRow {
  final String code;
  final String name;
  final String qty;
  final String unit;
  final String size;
  final String mass;
  final String note;
  const _StaircaseRow({
    required this.code,
    required this.name,
    required this.qty,
    required this.unit,
    required this.size,
    required this.mass,
    required this.note,
  });
}

class _StairParams {
  final String kindLabel;
  final double floorHeightMm;
  final int steps;
  final double riserMm;
  final double treadMm;
  final double marchWidthMm;
  final double runProjectionMm;
  final double stringerLengthMm;
  final double angleDeg;
  final String stringerMaterial;
  final String stepMaterial;
  final String railingMaterial;

  const _StairParams({
    required this.kindLabel,
    required this.floorHeightMm,
    required this.steps,
    required this.riserMm,
    required this.treadMm,
    required this.marchWidthMm,
    required this.runProjectionMm,
    required this.stringerLengthMm,
    required this.angleDeg,
    required this.stringerMaterial,
    required this.stepMaterial,
    required this.railingMaterial,
  });
}

class _RoomFinishRow {
  final String roomNumber;
  final String name;
  final double areaM2;
  final String floor;
  final String walls;
  final String ceiling;
  final String skirting;
  final String note;
  const _RoomFinishRow({
    required this.roomNumber,
    required this.name,
    required this.areaM2,
    required this.floor,
    required this.walls,
    required this.ceiling,
    required this.skirting,
    required this.note,
  });
}

class _FinishSet {
  final String floor;
  final String walls;
  final String ceiling;
  final String skirting;
  final String note;
  const _FinishSet({
    required this.floor,
    required this.walls,
    required this.ceiling,
    required this.skirting,
    required this.note,
  });
}

class _HiddenWorkRow {
  final String work;
  final String stage;
  final String reference;
  final String controller;
  final String doc;
  const _HiddenWorkRow({
    required this.work,
    required this.stage,
    required this.reference,
    required this.controller,
    required this.doc,
  });
}
