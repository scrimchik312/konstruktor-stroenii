import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/wall_materials.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'pdf_builder.dart';
import 'pdf_title_block.dart';

/// Одна запись в «Ведомости рабочих чертежей основного комплекта АР».
class SheetIndexEntry {
  const SheetIndexEntry({
    required this.code,
    required this.title,
    this.note = '',
  });

  /// Обозначение листа («АР-1», «АР-2», …).
  final String code;

  /// Наименование листа.
  final String title;

  /// Примечание (как правило пусто).
  final String note;
}

/// Титульный лист альбома (без штампа и без номера) — оформляется по
/// ГОСТ Р 21.101-2020, прил. Б. Содержит наименование объекта, шифр,
/// наименование альбома, стадию, город и год. Рендерится первой
/// страницей PDF, поэтому размер штампа и сквозная нумерация листов
/// его не касаются.
pw.Page buildTitlePage({
  required HouseProject project,
  required pw.Font font,
  required pw.Font fontBold,
}) {
  final t = project.titlePage;
  return pw.Page(
    pageFormat: PdfPageFormat.a3.landscape,
    margin: pw.EdgeInsets.zero,
    build: (context) {
      return pw.Stack(
        children: [
          // Простая внешняя рамка по краю листа (двойная: тонкий
          // внешний контур + толще внутренний).
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(20),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColors.black, width: 0.5),
                ),
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: PdfColors.black, width: 1.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Содержимое — три блока: наименование объекта, шифр+альбом,
          // стадия (по центру, между ними воздух); внизу — город и год.
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(80, 80, 80, 80),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Spacer(flex: 2),
                  pw.Text(
                    t.objectTitle,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 22,
                      font: fontBold,
                    ),
                  ),
                  pw.Spacer(flex: 2),
                  pw.Text(
                    'ЧЕРТЕЖИ   ШИФР: ${t.code}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 16, font: font),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Альбом — ${t.albumName}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 16, font: font),
                  ),
                  pw.Spacer(flex: 2),
                  pw.Text(
                    t.stage,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 16, font: font),
                  ),
                  pw.Spacer(flex: 3),
                  pw.Text(
                    '${t.city} ${t.year} г.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 16, font: font),
                  ),
                  pw.Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Построитель листов «Общие данные» комплекта АР по ГОСТ Р 21.101-2020.
///
/// Первый лист (АР-1) содержит ведомость чертежей комплекта, ведомость
/// основных комплектов рабочих чертежей марки АС и основные
/// технико-экономические показатели (ТЭП). Штамп — форма 3.
///
/// Второй лист (АР-2) — общие указания и расход материалов (если есть).
class PdfGeneralData {
  PdfGeneralData._();

  /// Генерит список страниц «Общие данные» для комплекта [sheets].
  /// Возвращает 1 или 2 листа (в зависимости от объёма примечаний).
  static List<pw.Page> buildPages({
    required HouseProject project,
    required List<SheetIndexEntry> sheets,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    return <pw.Page>[
      _firstPage(
        project: project,
        sheets: sheets,
        totalSheets: totalSheets,
        font: font,
        fontBold: fontBold,
        organization: organization,
      ),
      _secondPage(
        project: project,
        totalSheets: totalSheets,
        font: font,
        fontBold: fontBold,
        organization: organization,
      ),
      _legendPage(
        project: project,
        totalSheets: totalSheets,
        font: font,
        fontBold: fontBold,
        pdfFont: pdfFont,
        organization: organization,
      ),
      _referencesPage(
        project: project,
        totalSheets: totalSheets,
        font: font,
        fontBold: fontBold,
        organization: organization,
      ),
    ];
  }

  static pw.Page _firstPage({
    required HouseProject project,
    required List<SheetIndexEntry> sheets,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                // bottom = высота штампа (~117 pt при scale 0.75) + 33 pt
                // запаса (отступ + рамка), чтобы фраза «Рабочая документация…»
                // и таблицы НИКОГДА не залазили на штамп (форма 3).
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 150),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: _sheetIndexTable(sheets, font, fontBold),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Expanded(
                          flex: 4,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _marksTable(font, fontBold),
                              pw.SizedBox(height: 12),
                              _tepTable(project, font, fontBold),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.Spacer(),
                    // Контейнер с примечанием — В ШИРИНУ контента слева,
                    // но ОБРЕЗАН справа на ширину штампа + запас, чтобы
                    // фраза не уходила в зону штампа даже визуально
                    // (требование заказчика «не должно накладываться никогда»).
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                width: 0.5,
                                color: PdfColors.grey700,
                              ),
                            ),
                            child: pw.Text(
                              'Рабочая документация выполнена в соответствии с '
                              'действующими нормами и правилами, и предусматривает '
                              'мероприятия, обеспечивающие пожарную безопасность при '
                              'эксплуатации здания при соблюдении их заказчиком и '
                              'подрядчиком.',
                              style: pw.TextStyle(fontSize: 8, font: font),
                            ),
                          ),
                        ),
                        // Резерв под штамп (185×0.75 ≈ 393 pt) + 4 pt
                        // зазор между фразой и левой границей штампа.
                        pw.SizedBox(width: 397),
                      ],
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
                sheetTitle: 'Общие данные (начало)',
                sheetCode: 'АР-1',
                sheetNumber: 1,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  static pw.Page _secondPage({
    required HouseProject project,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                // bottom = высота штампа (форма 3) + запас (≥150 pt),
                // чтобы текст НИКОГДА не наезжал на форму 3.
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 150),
                child: _guidelinesContent(project, font, fontBold),
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
                sheetTitle: 'Общие указания. Объёмно-планировочные '
                    'и пожарные решения',
                sheetCode: 'АР-2',
                sheetNumber: 2,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================
  //  АР-3 — «Условные обозначения» (УГО) по ГОСТ Р 21.501-2018
  // ===========================================================

  static pw.Page _legendPage({
    required HouseProject project,
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
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 150),
                child: _legendContent(font, fontBold, pdfFont),
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
                sheetTitle: 'Условные обозначения',
                sheetCode: 'АР-3',
                sheetNumber: 3,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================
  //  АР-4 — «Перечень ссылочных документов»
  // ===========================================================

  static pw.Page _referencesPage({
    required HouseProject project,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: PdfBuilder.drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 150),
                child: _referencesContent(font, fontBold),
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
                sheetTitle: 'Перечень ссылочных документов',
                sheetCode: 'АР-4',
                sheetNumber: 4,
                totalSheets: totalSheets,
                organization: organization,
              ),
            ),
          ],
        );
      },
    );
  }

  // ---- Разделы первой страницы ----

  static pw.Widget _sheetIndexTable(
    List<SheetIndexEntry> sheets,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = pw.TextStyle(fontSize: 9, font: font);
    const border = pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(width: 0.5),
        left: pw.BorderSide(width: 0.5),
        right: pw.BorderSide(width: 0.5),
        bottom: pw.BorderSide(width: 0.5),
      ),
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            'Ведомость рабочих чертежей основного комплекта АР',
            style: headerStyle,
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(65),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _c('Лист', headerStyle, align: pw.TextAlign.center),
                _c('Наименование', headerStyle, align: pw.TextAlign.center),
                _c('Прим.', headerStyle, align: pw.TextAlign.center),
              ],
            ),
            for (final s in sheets)
              pw.TableRow(
                children: [
                  _c(s.code, cellStyle, align: pw.TextAlign.center),
                  _c(s.title, cellStyle),
                  _c(s.note, cellStyle, align: pw.TextAlign.center),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          decoration: border,
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            'Примечание. Без штампа к производству работ технадзора заказчика '
            'данный комплект чертежей не имеет силы и может использоваться '
            'только для подготовительных работ.',
            style: cellStyle,
          ),
        ),
      ],
    );
  }

  static pw.Widget _marksTable(pw.Font font, pw.Font fontBold) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = pw.TextStyle(fontSize: 9, font: font);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            'Ведомость основных комплектов рабочих чертежей марки АС',
            style: headerStyle,
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _c('Обозначение', headerStyle, align: pw.TextAlign.center),
                _c('Наименование', headerStyle, align: pw.TextAlign.center),
              ],
            ),
            for (final m in const [
              ('– АР', 'Архитектурные решения'),
              ('– КЖ', 'Конструкции железобетонные'),
              ('– КД', 'Конструкции деревянные'),
            ])
              pw.TableRow(
                children: [
                  _c(m.$1, cellStyle, align: pw.TextAlign.center),
                  _c(m.$2, cellStyle),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tepTable(
    HouseProject project,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = pw.TextStyle(fontSize: 9, font: font);

    final brief = project.brief;
    final rows = <(String, String, String)>[];

    final totalArea = brief.targetArea;
    if (totalArea != null) {
      rows.add(('Общая площадь', 'м²', totalArea.toStringAsFixed(2)));
    }
    final fw = brief.footprintWidth;
    final fl = brief.footprintLength;
    if (fw != null && fl != null) {
      rows.add((
        'Площадь застройки',
        'м²',
        (fw * fl).toStringAsFixed(2),
      ));
    }
    if (brief.floors != null) {
      rows.add(('Этажность', 'эт.', '${brief.floors}'));
    }
    if (rows.isEmpty) {
      rows.add(('Данные ТЭП', '—', 'заполнятся после ТЗ'));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            'Основные технико-экономические показатели*',
            style: headerStyle,
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FixedColumnWidth(40),
            2: pw.FixedColumnWidth(60),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _c('Наименование', headerStyle, align: pw.TextAlign.center),
                _c('Ед. изм.', headerStyle, align: pw.TextAlign.center),
                _c('Количество', headerStyle, align: pw.TextAlign.center),
              ],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  _c(r.$1, cellStyle),
                  _c(r.$2, cellStyle, align: pw.TextAlign.center),
                  _c(r.$3, cellStyle, align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '* СП 54.13330.2022 Приложение А',
          style: pw.TextStyle(fontSize: 8, font: font),
        ),
      ],
    );
  }

  // ---- Вторая страница: общие указания + объёмно-планировочные +
  //      пожарные решения ----

  static pw.Widget _guidelinesContent(
    HouseProject project,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final secStyle = pw.TextStyle(
      fontSize: 10,
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final para = pw.TextStyle(fontSize: 8.5, font: font);

    final brief = project.brief;
    final material = WallMaterial.fromName(project.walls.material);
    final thickness = project.walls.thickness;
    final height = project.walls.height;
    final wallsText = material == null
        ? 'Материал и толщина наружных стен уточняются на этапе «Стены».'
        : 'Наружные стены — ${material.title}, толщина '
            '${(thickness ?? 0).toStringAsFixed(0)} мм, высота этажа '
            '${(height ?? 0).toStringAsFixed(2)} м.';

    // Этажность (целое + мансарда + подвал).
    final floors = brief.floors;
    final hasMansard = brief.hasMansard == true;
    final hasBasement = brief.hasBasement == true;
    final floorsText = floors == null
        ? 'этажность уточняется на этапе ТЗ'
        : '$floors надземн. эт.${hasMansard ? ' + мансарда' : ''}'
            '${hasBasement ? ' + цокольный/подвальный' : ''}';
    // Площадь.
    final totalArea = brief.targetArea;
    final fw = brief.footprintWidth;
    final fl = brief.footprintLength;
    final builtArea =
        (fw != null && fl != null) ? (fw * fl).toStringAsFixed(1) : '—';
    // Состав комнат (из brief.rooms).
    final roomsList = brief.rooms.entries
        .where((e) => e.value > 0)
        .map((e) => '${_roomTitleByName(e.key)} — ${e.value}')
        .join(', ');
    final roomsText =
        roomsList.isEmpty ? 'состав уточняется на этапе ТЗ' : roomsList;
    // Класс конструктивной пожарной опасности — упрощённо по
    // материалу стен (СП 2.13130.2020 п. 5.4.2).
    final fireClass = _structuralFireClass(material);
    final fireRating = _fireRating(material);

    final clim = brief.region == null
        ? 'климатический район уточняется по ТЗ (СП 131.13330)'
        : 'климатический район — ${brief.region}, '
            'снеговой район ${brief.snowZone ?? '—'}, '
            'ветровой район ${brief.windZone ?? '—'}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(
            'Общие указания. Объёмно-планировочные и пожарные решения',
            style: pw.TextStyle(
              fontSize: 12,
              font: fontBold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // === 1. Общие указания ===
                  pw.Text('1. Общие указания', style: secStyle),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '1.1. Проект разработан в соответствии с действующими '
                    'нормативными документами (см. лист АР-4 «Перечень '
                    'ссылочных документов»).',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '1.2. Все размеры на чертежах в миллиметрах, если не '
                    'указано иное. Отметки в метрах от условного нуля '
                    '±0.000, соответствующего уровню чистого пола '
                    '1-го этажа.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '1.3. Условные обозначения и графические символы — '
                    'см. лист АР-3.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '1.4. Любые отступления от настоящего проекта согласуются '
                    'с автором проекта в соответствии с ГК РФ ст. 1229, 1250.',
                    style: para,
                  ),
                  pw.SizedBox(height: 8),
                  // === 2. Объёмно-планировочные решения ===
                  pw.Text(
                    '2. Объёмно-планировочные решения',
                    style: secStyle,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '2.1. Назначение здания — жилой одноквартирный '
                    '(СП 55.13330.2016). Класс функциональной пожарной '
                    'опасности — Ф1.4 (СП 1.13130.2020 п. 5.1, '
                    '123-ФЗ ст. 32).',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.2. Этажность: $floorsText.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.3. Площадь застройки — $builtArea м²; общая площадь — '
                    '${totalArea?.toStringAsFixed(1) ?? '—'} м².',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.4. Состав помещений: $roomsText.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.5. $wallsText',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.6. Высоты помещений приняты не менее 2,5 м '
                    '(СП 55.13330 п. 6.1). Минимальные площади жилых '
                    'комнат: общая жилая ≥ 12 м², спальня ≥ 8 м², '
                    'кухня ≥ 6 м², санузел ≥ 1,8 м².',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '2.7. Естественное освещение и инсоляция жилых комнат '
                    'обеспечивается оконными проёмами в наружных стенах '
                    '(СП 52.13330, СанПиН 1.2.3685-21).',
                    style: para,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // === 3. Пожарные решения ===
                  pw.Text(
                    '3. Пожарно-технические решения',
                    style: secStyle,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '3.1. Класс функциональной пожарной опасности — Ф1.4 '
                    '(одноквартирные жилые дома, 123-ФЗ ст. 32).',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.2. Степень огнестойкости — $fireRating '
                    '(123-ФЗ ст. 87, СП 2.13130.2020 табл. 21).',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.3. Класс конструктивной пожарной опасности — '
                    '$fireClass (СП 2.13130.2020 п. 5.4).',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.4. Эвакуационные пути и выходы предусмотрены в '
                    'соответствии с СП 1.13130.2020 (раздел 4): '
                    'не менее одного эвакуационного выхода с каждого '
                    'этажа; ширина дверей по пути эвакуации ≥ 0,8 м, '
                    'высота ≥ 1,9 м; ширина лестничных маршей '
                    '≥ 0,9 м.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.5. Противопожарные расстояния от наружных стен '
                    'здания до соседних строений принимаются по '
                    'СП 4.13130.2013 табл. 1: для зданий III/IV/V '
                    'степени огнестойкости — 8…15 м.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.6. Дымовые трубы (печные/каминные) выводятся выше '
                    'конька кровли на ≥ 500 мм при удалении ≤ 1,5 м от '
                    'конька; в зоне ветрового подпора (СП 7.13130). '
                    'Места прохода через перекрытия и кровлю обрабатываются '
                    'противопожарной разделкой ≥ 380 мм.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '3.7. Деревянные конструкции (стропила, обрешётка, '
                    'мауэрлат) обрабатываются антипиренами I группы '
                    'огнезащитной эффективности по ГОСТ Р 53292-2009.',
                    style: para,
                  ),
                  pw.SizedBox(height: 8),
                  // === 4. Климатические условия ===
                  pw.Text(
                    '4. Климатические условия',
                    style: secStyle,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '4.1. Объект расположен — $clim.',
                    style: para,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '4.2. Тепловая защита и сопротивление теплопередаче '
                    'наружных ограждающих конструкций — по СП 50.13330.2024 '
                    '(см. отдельный расчёт «Теплотехнический расчёт»).',
                    style: para,
                  ),
                  pw.SizedBox(height: 8),
                  // === 5. Инженерное оборудование (краткая ссылка) ===
                  pw.Text(
                    '5. Инженерное оборудование',
                    style: secStyle,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Отопление, вентиляция, водоснабжение, канализация и '
                    'электроснабжение — выполняются отдельными разделами '
                    '(ОВ, ВК, ЭО) по СП 60.13330, СП 30.13330, '
                    'СП 31.13330, СП 32.13330, СП 256.1325800.',
                    style: para,
                  ),
                  pw.SizedBox(height: 8),
                  // §17.2.3 — блок предупреждений из Project.warnings.
                  if (project.warnings.isNotEmpty) ...[
                    pw.Text(
                      '6. Предупреждения проектировщика',
                      style: secStyle,
                    ),
                    pw.SizedBox(height: 3),
                    for (final w in project.warnings)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1),
                        child: pw.Text('• $w', style: para),
                      ),
                    pw.SizedBox(height: 8),
                  ],
                  pw.Text(
                    '* Настоящий комплект является рабочим проектом '
                    '(стадия РП) и предназначен для производства '
                    'строительно-монтажных работ.',
                    style: pw.TextStyle(
                      fontSize: 8,
                      font: font,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Степень огнестойкости по материалу стен (упрощённо
  /// по СП 2.13130.2020 табл. 21).
  static String _fireRating(WallMaterial? m) {
    if (m == null) return 'III–V (уточняется)';
    switch (m) {
      case WallMaterial.brick:
        return 'II (несущие — кирпич, негорючие)';
      case WallMaterial.aerated:
        return 'III (несущие — газобетон, негорючие)';
      case WallMaterial.expandedClay:
        return 'III (керамзитобетонные блоки, негорючие)';
      case WallMaterial.timber:
        return 'V (брус/бревно, горючие)';
      case WallMaterial.frame:
        return 'V (каркас деревянный, горючие)';
    }
  }

  /// Класс конструктивной пожарной опасности по материалу стен
  /// (СП 2.13130.2020 п. 5.4).
  static String _structuralFireClass(WallMaterial? m) {
    if (m == null) return 'С0–С3 (уточняется)';
    switch (m) {
      case WallMaterial.brick:
      case WallMaterial.aerated:
      case WallMaterial.expandedClay:
        return 'С0';
      case WallMaterial.timber:
        return 'С2';
      case WallMaterial.frame:
        return 'С3';
    }
  }

  /// Перевод служебного имени комнаты («kitchen» / «bedroom» / …)
  /// в человекочитаемое название на русском.
  static String _roomTitleByName(String name) {
    const map = <String, String>{
      'bedroom': 'спальня',
      'livingRoom': 'гостиная',
      'kitchen': 'кухня',
      'kitchenLiving': 'кухня-гостиная',
      'bathroom': 'санузел',
      'wc': 'санузел',
      'washroom': 'санузел',
      'corridor': 'коридор',
      'hall': 'прихожая',
      'wardrobe': 'гардероб',
      'pantry': 'кладовая',
      'study': 'кабинет',
      'nursery': 'детская',
      'utility': 'хозблок',
      'boiler': 'котельная',
      'staircase': 'лестница',
      'garage': 'гараж',
      'terrace': 'терраса',
      'balcony': 'балкон',
    };
    return map[name] ?? name;
  }

  // ---- АР-3: содержимое листа «Условные обозначения» ----

  static pw.Widget _legendContent(
    pw.Font font,
    pw.Font fontBold,
    PdfFont pdfFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'Условные графические обозначения '
            '(ГОСТ Р 21.501-2018, ГОСТ 21.201-2011)',
            style: pw.TextStyle(
              fontSize: 12,
              font: fontBold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Expanded(
          child: pw.LayoutBuilder(
            builder: (ctx, constraints) {
              return pw.SizedBox(
                width: constraints!.maxWidth,
                height: constraints.maxHeight,
                child: pw.CustomPaint(
                  size: PdfPoint(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  painter: (canvas, size) =>
                      _paintLegend(canvas, size, pdfFont),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Рисует все УГО на полотне листа АР-3 в 3 колонках.
  static void _paintLegend(
    PdfGraphics canvas,
    PdfPoint size,
    PdfFont pdfFont,
  ) {
    final w = size.x;
    final h = size.y;
    // 3 колонки одинаковой ширины с межколонным зазором 12pt.
    const gap = 12.0;
    final colW = (w - 2 * gap) / 3;

    // Список секций (заголовок, список строк-обозначений).
    final sections = <_LegendSection>[
      _LegendSection(
        title: 'Координационные оси и размеры',
        items: [
          _LegendItem('axisDigit', 'Цифровая ось (по горизонтали)'),
          _LegendItem('axisLetter', 'Буквенная ось (по вертикали)'),
          _LegendItem('dimChain', 'Размерная цепь'),
          _LegendItem('elevation', 'Высотная отметка (м)'),
          _LegendItem('sectionMark', 'Линия и направление сечения'),
        ],
      ),
      _LegendSection(
        title: 'Маркировка проёмов',
        items: [
          _LegendItem('windowMark', 'Окно — марка ОК-N (размер мм)'),
          _LegendItem('doorMark', 'Дверь — марка Д-N (размер мм)'),
          _LegendItem('windowOnPlan', 'Окно на плане (с четвертями)'),
          _LegendItem('doorOnPlan', 'Дверь на плане (распашная)'),
        ],
      ),
      _LegendSection(
        title: 'Штриховки материалов',
        items: [
          _LegendItem('hatchConcrete', 'Бетон / железобетон'),
          _LegendItem('hatchBrick', 'Кладка кирпичная'),
          _LegendItem('hatchAerated', 'Газобетон / пенобетон'),
          _LegendItem('hatchTimber', 'Древесина (продольно)'),
          _LegendItem('hatchSand', 'Песок'),
          _LegendItem('hatchGravel', 'Щебень / гравий'),
          _LegendItem('hatchSoil', 'Грунт ненарушенной структуры'),
          _LegendItem('hatchInsul', 'Утеплитель (минвата/ЭППС)'),
          _LegendItem('hatchWaterproof', 'Гидроизоляция'),
        ],
      ),
    ];

    // Раскладываем секции по 3 колонкам.
    var x0 = 0.0;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      _paintLegendSection(
        canvas,
        x0,
        h,
        colW,
        section,
        pdfFont,
      );
      x0 += colW + gap;
    }
  }

  static void _paintLegendSection(
    PdfGraphics canvas,
    double x0,
    double pageH,
    double colW,
    _LegendSection section,
    PdfFont pdfFont,
  ) {
    // Заголовок секции (10pt, по центру колонки).
    const titleFs = 10.0;
    final titleY = pageH - titleFs - 4;
    final titleW =
        pdfFont.stringMetrics(section.title).width * titleFs;
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(
      pdfFont,
      titleFs,
      section.title,
      x0 + (colW - titleW) / 2,
      titleY,
    );
    // Подчёркивание заголовка.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawLine(x0, titleY - 4, x0 + colW, titleY - 4);
    canvas.strokePath();

    // Строки обозначений.
    // rowH ↑ 26 → 32 pt, чтобы условные обозначения с овалами проёмов
    // (ОК-1, Д-1) и метками сечений (со стрелкой направления взгляда) не
    // накладывались по вертикали на соседние строки.
    const rowH = 32.0;
    const symW = 70.0;
    var y = titleY - 14;
    for (final item in section.items) {
      // Зона символа: x0..x0+symW, y..y-rowH.
      final symCx = x0 + symW / 2;
      final symCy = y - rowH / 2;
      _paintLegendSymbol(
          canvas, item.kind, symCx, symCy, symW - 8, rowH - 8, pdfFont);
      // Подпись справа от символа (8pt, по вертикальному центру строки).
      const labelFs = 8.5;
      canvas.setFillColor(PdfColors.black);
      canvas.drawString(
        pdfFont,
        labelFs,
        item.label,
        x0 + symW + 4,
        symCy - labelFs * 0.35,
      );
      // Тонкая разделительная линия.
      canvas.setStrokeColor(PdfColors.grey400);
      canvas.setLineWidth(0.3);
      canvas.drawLine(x0, y - rowH, x0 + colW, y - rowH);
      canvas.strokePath();
      y -= rowH;
    }
    // Левая и правая внешние границы колонки.
    canvas.setStrokeColor(PdfColors.grey600);
    canvas.setLineWidth(0.5);
    canvas.drawLine(x0, titleY - 4, x0, y);
    canvas.drawLine(x0 + colW, titleY - 4, x0 + colW, y);
    canvas.strokePath();
  }

  static void _paintLegendSymbol(
    PdfGraphics canvas,
    String kind,
    double cx,
    double cy,
    double w,
    double h,
    PdfFont pdfFont,
  ) {
    final font = pdfFont;
    final fontBold = pdfFont;
    final left = cx - w / 2;
    final right = cx + w / 2;
    final top = cy + h / 2;
    final bottom = cy - h / 2;

    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.6);

    switch (kind) {
      case 'axisDigit':
        // Горизонтальная штрих-пунктирная линия + кружок с цифрой «1».
        _dashLine(canvas, left, cy, right - 14, cy);
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.7);
        canvas.drawEllipse(right - 7, cy, 7, 7);
        canvas.strokePath();
        const fs = 8.0;
        final tw = fontBold.stringMetrics('1').width * fs;
        canvas.drawString(
            fontBold, fs, '1', right - 7 - tw / 2, cy - fs * 0.35);
        break;
      case 'axisLetter':
        _dashLine(canvas, cx - 10, top - 4, cx - 10, bottom + 4);
        canvas.drawEllipse(cx - 10, bottom + 4, 7, 7);
        canvas.strokePath();
        const fs = 8.0;
        final tw = fontBold.stringMetrics('А').width * fs;
        canvas.drawString(
            fontBold, fs, 'А', cx - 10 - tw / 2, bottom + 4 - fs * 0.35);
        break;
      case 'dimChain':
        // Линия с засечками на концах.
        canvas.drawLine(left + 4, cy, right - 4, cy);
        canvas.drawLine(left + 4, cy - 3, left + 4, cy + 3);
        canvas.drawLine(right - 4, cy - 3, right - 4, cy + 3);
        canvas.strokePath();
        const fs = 8.0;
        canvas.drawString(font, fs, '1500', cx - 9, cy + 2);
        break;
      case 'elevation':
        // Треугольник-стрелка вниз + горизонтальная полка с подписью.
        final sx = cx - 14;
        final sy = cy;
        canvas.moveTo(sx, sy);
        canvas.lineTo(sx + 5, sy + 5);
        canvas.lineTo(sx - 5, sy + 5);
        canvas.lineTo(sx, sy);
        canvas.fillPath();
        canvas.drawLine(sx - 8, sy + 5, sx + 22, sy + 5);
        canvas.strokePath();
        const fs = 8.0;
        canvas.drawString(font, fs, '+0.000', sx + 0, sy + 7);
        break;
      case 'sectionMark':
        // Линия и направление сечения по ГОСТ 21.101-2020:
        // короткий вертикальный жирный штрих с засечками сверху/снизу,
        // перпендикулярная стрелка-треугольник в направлении взгляда
        // и цифра-номер сечения сбоку.
        final markCx = left + w * 0.35;
        const markH = 18.0;
        const tickW = 5.0;
        // Толстая вертикаль (ось разреза).
        canvas.setLineWidth(1.6);
        canvas.drawLine(markCx, cy - markH / 2, markCx, cy + markH / 2);
        canvas.strokePath();
        // Засечки-перпендикуляры (узкие штрихи) сверху и снизу.
        canvas.setLineWidth(1.0);
        canvas.drawLine(
            markCx - tickW, cy + markH / 2, markCx + tickW, cy + markH / 2);
        canvas.drawLine(
            markCx - tickW, cy - markH / 2, markCx + tickW, cy - markH / 2);
        canvas.strokePath();
        // Стрелка-треугольник вправо (направление взгляда).
        canvas.setLineWidth(0.6);
        final arrowX0 = markCx + tickW;
        final arrowX1 = markCx + tickW + 9;
        canvas.moveTo(arrowX1, cy + markH / 2);
        canvas.lineTo(arrowX0, cy + markH / 2 + 3);
        canvas.lineTo(arrowX0, cy + markH / 2 - 3);
        canvas.lineTo(arrowX1, cy + markH / 2);
        canvas.fillPath();
        // Подпись «1» (цифра сечения), жирный.
        const fs = 9.0;
        canvas.drawString(fontBold, fs, '1', arrowX1 + 3,
            cy + markH / 2 - fs * 0.35);
        break;
      case 'windowMark':
        _drawMarkOval(canvas, font, fontBold, cx, cy,
            mark: 'ОК-1', size: '1500×1500', maxRy: h / 2);
        break;
      case 'doorMark':
        _drawMarkOval(canvas, font, fontBold, cx, cy,
            mark: 'Д-1', size: '900×2100', maxRy: h / 2);
        break;
      case 'windowOnPlan':
        // 2 параллельные горизонтальные линии в стене (стене 12pt толщ).
        canvas.setStrokeColor(PdfColors.grey700);
        canvas.setLineWidth(0.5);
        canvas.drawRect(left + 4, cy - 5, right - left - 8, 10);
        canvas.strokePath();
        canvas.setStrokeColor(PdfColors.blue700);
        canvas.setLineWidth(0.6);
        canvas.drawLine(left + 6, cy - 1.5, right - 6, cy - 1.5);
        canvas.drawLine(left + 6, cy + 1.5, right - 6, cy + 1.5);
        canvas.strokePath();
        break;
      case 'doorOnPlan':
        // Дуга открывания двери + полотно.
        canvas.setStrokeColor(PdfColors.grey700);
        canvas.setLineWidth(0.5);
        canvas.drawRect(left + 4, cy - 5, right - left - 8, 10);
        canvas.strokePath();
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.6);
        // Полотно — линия от левого края проёма под 60°.
        final px = left + 6;
        final py = cy - 5 + 10; // верх стены
        final dx = (right - 6 - px) * 0.5;
        final dy = -(right - 6 - px) * 0.866;
        canvas.drawLine(px, py, px + dx, py + dy);
        // Дуга 90° (приблизим тремя сегментами).
        final r = (right - 6 - px);
        canvas.moveTo(px + r, py);
        canvas.lineTo(px + r * 0.92, py - r * 0.38);
        canvas.lineTo(px + r * 0.71, py - r * 0.71);
        canvas.lineTo(px + dx, py + dy);
        canvas.strokePath();
        break;
      case 'hatchConcrete':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchDiagonal(canvas, x1, y1, x2, y2,
                spacing: 4, angleDeg: 45));
        // Точки железобетона.
        canvas.setFillColor(PdfColors.black);
        for (var i = 0; i < 6; i++) {
          final px = left + 4 + (i * (w - 8) / 6);
          final py = cy + (i.isEven ? 2 : -2);
          canvas.drawEllipse(px, py, 0.6, 0.6);
        }
        canvas.fillPath();
        break;
      case 'hatchBrick':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchBrick(canvas, x1, y1, x2, y2));
        break;
      case 'hatchAerated':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchBlock(canvas, x1, y1, x2, y2));
        break;
      case 'hatchTimber':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchTimber(canvas, x1, y1, x2, y2));
        break;
      case 'hatchSand':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchDots(canvas, x1, y1, x2, y2));
        break;
      case 'hatchGravel':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchGravel(canvas, x1, y1, x2, y2));
        break;
      case 'hatchSoil':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchSoil(canvas, x1, y1, x2, y2));
        break;
      case 'hatchInsul':
        _drawCellWithHatch(canvas, left, bottom, right, top,
            (x1, y1, x2, y2) => _hatchInsulation(canvas, x1, y1, x2, y2));
        break;
      case 'hatchWaterproof':
        // Зигзаг.
        canvas.setStrokeColor(PdfColors.blue700);
        canvas.setLineWidth(0.7);
        const step = 4.0;
        var px = left + 2;
        var up = true;
        canvas.moveTo(px, cy);
        while (px < right - 2) {
          px += step;
          canvas.lineTo(px, up ? cy + 3 : cy - 3);
          up = !up;
        }
        canvas.strokePath();
        break;
    }
  }

  static void _dashLine(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = dx / len;
    final uy = dy / len;
    const dash = 4.0;
    const gap = 2.0;
    var t = 0.0;
    while (t < len) {
      final t2 = math.min(t + dash, len);
      canvas.drawLine(x1 + ux * t, y1 + uy * t, x1 + ux * t2, y1 + uy * t2);
      t = t2 + gap;
    }
    canvas.strokePath();
  }

  /// Рисует овал-марку проёма с двумя строками текста (марка + размер)
  /// и автоматически увеличивает овал, если строки шире его контура.
  ///
  /// Если задан [maxRy] — вертикальная полуось обрезается этим значением
  /// (так овал гарантированно влезает в свою строку легенды), а размер
  /// шрифта при необходимости снижается, чтобы текст оставался внутри.
  static void _drawMarkOval(
    PdfGraphics canvas,
    PdfFont font,
    PdfFont fontBold,
    double cx,
    double cy, {
    required String mark,
    required String size,
    double? maxRy,
  }) {
    // Подбираем размер шрифта так, чтобы две строки + межстрочный 1 pt +
    // 1.5 pt запас по верху/низу влезали в 2*ry.
    var fs = 7.0;
    final ryLimit = maxRy ?? double.infinity;
    if (2 * (fs + 4) > 2 * ryLimit) {
      fs = math.max(5.0, ryLimit - 1.5);
    }
    final t1w = fontBold.stringMetrics(mark).width * fs;
    final t2w = font.stringMetrics(size).width * fs;
    // Полуоси овала: горизонтальная — по самой широкой строке + 6 pt
    // (запас 15 % перекрывает кернинг и неточности stringMetrics);
    // вертикальная — под две строки + межстрочный + zазор.
    final rx = math.max(20.0, math.max(t1w, t2w) * 1.15 / 2 + 6);
    final ry = math.min(ryLimit, math.max(11.0, fs + 4));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.white);
    canvas.setLineWidth(0.7);
    canvas.drawEllipse(cx, cy, rx, ry);
    canvas.fillPath();
    canvas.drawEllipse(cx, cy, rx, ry);
    canvas.strokePath();
    // Горизонтальный разделитель между марками и размером.
    canvas.drawLine(cx - rx, cy, cx + rx, cy);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(fontBold, fs, mark, cx - t1w / 2, cy + 1.4);
    canvas.drawString(font, fs, size, cx - t2w / 2, cy - fs - 1.2);
  }

  static void _drawCellWithHatch(
    PdfGraphics canvas,
    double left,
    double bottom,
    double right,
    double top,
    void Function(double, double, double, double) hatch,
  ) {
    // Рамка.
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.5);
    canvas.drawRect(left, bottom, right - left, top - bottom);
    canvas.strokePath();
    hatch(left, bottom, right, top);
  }

  static void _hatchDiagonal(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2, {
    double spacing = 4,
    double angleDeg = 45,
  }) {
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    final w = x2 - x1;
    final h = y2 - y1;
    final ang = angleDeg * math.pi / 180;
    final tan = math.tan(ang);
    // Линии под углом angleDeg идут от нижней стороны к правой.
    for (var off = -h; off < w + h; off += spacing) {
      final sx = x1 + off;
      final sy = y1;
      final ex = sx + h / tan;
      final ey = y2;
      // Обрежем по rect.
      final cs = _clipLine(sx, sy, ex, ey, x1, y1, x2, y2);
      if (cs != null) {
        canvas.drawLine(cs[0], cs[1], cs[2], cs[3]);
      }
    }
    canvas.strokePath();
  }

  static List<double>? _clipLine(
    double x1,
    double y1,
    double x2,
    double y2,
    double xmin,
    double ymin,
    double xmax,
    double ymax,
  ) {
    // Очень простой Cohen-Sutherland для прямоугольника.
    int code(double x, double y) {
      var c = 0;
      if (x < xmin) c |= 1;
      if (x > xmax) c |= 2;
      if (y < ymin) c |= 4;
      if (y > ymax) c |= 8;
      return c;
    }

    var c1 = code(x1, y1);
    var c2 = code(x2, y2);
    while (true) {
      if ((c1 | c2) == 0) return [x1, y1, x2, y2];
      if ((c1 & c2) != 0) return null;
      final c = c1 != 0 ? c1 : c2;
      double x = 0;
      double y = 0;
      if ((c & 8) != 0) {
        x = x1 + (x2 - x1) * (ymax - y1) / (y2 - y1);
        y = ymax;
      } else if ((c & 4) != 0) {
        x = x1 + (x2 - x1) * (ymin - y1) / (y2 - y1);
        y = ymin;
      } else if ((c & 2) != 0) {
        y = y1 + (y2 - y1) * (xmax - x1) / (x2 - x1);
        x = xmax;
      } else if ((c & 1) != 0) {
        y = y1 + (y2 - y1) * (xmin - x1) / (x2 - x1);
        x = xmin;
      }
      if (c == c1) {
        x1 = x;
        y1 = y;
        c1 = code(x1, y1);
      } else {
        x2 = x;
        y2 = y;
        c2 = code(x2, y2);
      }
    }
  }

  static void _hatchBrick(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.4);
    const rowH = 4.0;
    const brickW = 8.0;
    var y = y1 + 1;
    var rowIdx = 0;
    while (y < y2 - 1) {
      canvas.drawLine(x1, y, x2, y);
      var x = x1 + (rowIdx.isEven ? 0 : brickW / 2);
      while (x < x2) {
        canvas.drawLine(x, y, x, y + rowH);
        x += brickW;
      }
      y += rowH;
      rowIdx++;
    }
    canvas.strokePath();
  }

  static void _hatchBlock(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.4);
    const rowH = 6.0;
    const blkW = 14.0;
    var y = y1 + 2;
    var rowIdx = 0;
    while (y < y2 - 1) {
      canvas.drawLine(x1, y, x2, y);
      var x = x1 + (rowIdx.isEven ? 0 : blkW / 2);
      while (x < x2) {
        canvas.drawLine(x, y, x, y + rowH);
        x += blkW;
      }
      y += rowH;
      rowIdx++;
    }
    canvas.strokePath();
  }

  static void _hatchTimber(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    // Горизонтальные доски.
    const step = 3.5;
    var y = y1 + 2;
    while (y < y2 - 1) {
      canvas.drawLine(x1, y, x2, y);
      y += step;
    }
    canvas.strokePath();
    // Кольцо/дуга на одной доске для имитации годичного кольца.
    canvas.setStrokeColor(PdfColors.grey900);
    canvas.setLineWidth(0.5);
    final cx = (x1 + x2) / 2;
    final cy = (y1 + y2) / 2;
    canvas.drawEllipse(cx, cy, 6, 1.6);
    canvas.strokePath();
  }

  static void _hatchDots(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setFillColor(PdfColors.grey700);
    final rng = math.Random(42);
    final n = ((x2 - x1) * (y2 - y1) / 12).round();
    for (var i = 0; i < n; i++) {
      final px = x1 + 1 + rng.nextDouble() * (x2 - x1 - 2);
      final py = y1 + 1 + rng.nextDouble() * (y2 - y1 - 2);
      canvas.drawEllipse(px, py, 0.5, 0.5);
    }
    canvas.fillPath();
  }

  static void _hatchGravel(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.4);
    final rng = math.Random(7);
    final n = ((x2 - x1) * (y2 - y1) / 24).round();
    for (var i = 0; i < n; i++) {
      final px = x1 + 1 + rng.nextDouble() * (x2 - x1 - 2);
      final py = y1 + 1 + rng.nextDouble() * (y2 - y1 - 2);
      final r = 0.6 + rng.nextDouble() * 0.8;
      canvas.drawEllipse(px, py, r, r * 0.7);
    }
    canvas.strokePath();
  }

  static void _hatchSoil(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    // Засечки 45° короткими штрихами в верхней половине ячейки.
    const step = 4.0;
    var x = x1 + 2;
    while (x < x2 - 2) {
      canvas.drawLine(x, y2 - 1, x + 2.5, y2 - 4);
      x += step;
    }
    canvas.strokePath();
  }

  static void _hatchInsulation(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    canvas.setStrokeColor(PdfColors.grey800);
    canvas.setLineWidth(0.4);
    // Имитация минваты — волнистая линия по горизонтали.
    final cy = (y1 + y2) / 2;
    var x = x1 + 1;
    canvas.moveTo(x, cy);
    var up = true;
    while (x < x2 - 1) {
      x += 2.0;
      canvas.lineTo(x, up ? cy + 1.6 : cy - 1.6);
      up = !up;
    }
    canvas.strokePath();
    // Точки-зерна.
    canvas.setFillColor(PdfColors.grey700);
    final rng = math.Random(13);
    final n = ((x2 - x1) * (y2 - y1) / 18).round();
    for (var i = 0; i < n; i++) {
      final px = x1 + 1 + rng.nextDouble() * (x2 - x1 - 2);
      final py = y1 + 1 + rng.nextDouble() * (y2 - y1 - 2);
      canvas.drawEllipse(px, py, 0.4, 0.4);
    }
    canvas.fillPath();
  }

  // ---- АР-4: «Перечень ссылочных документов» ----

  static pw.Widget _referencesContent(pw.Font font, pw.Font fontBold) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = pw.TextStyle(fontSize: 9, font: font);

    final groups = <_RefGroup>[
      _RefGroup(
        title: 'Технические регламенты',
        rows: [
          (
            '123-ФЗ',
            'Технический регламент о требованиях пожарной безопасности'
          ),
          (
            '384-ФЗ',
            'Технический регламент о безопасности зданий и сооружений'
          ),
        ],
      ),
      _RefGroup(
        title: 'Архитектурно-строительные решения',
        rows: [
          ('СП 54.13330.2022', 'Здания жилые многоквартирные'),
          ('СП 55.13330.2016', 'Дома жилые одноквартирные'),
          ('СП 17.13330.2017', 'Кровли'),
          ('СП 50.13330.2024', 'Тепловая защита зданий'),
          ('СП 70.13330.2012',
              'Несущие и ограждающие конструкции'),
          ('СП 71.13330.2017', 'Изоляционные и отделочные покрытия'),
        ],
      ),
      _RefGroup(
        title: 'Несущие конструкции и нагрузки',
        rows: [
          ('СП 20.13330.2016', 'Нагрузки и воздействия'),
          ('СП 22.13330.2016', 'Основания зданий и сооружений'),
          ('СП 24.13330.2021', 'Свайные фундаменты'),
          ('СП 63.13330.2018', 'Бетонные и железобетонные конструкции'),
          ('СП 64.13330.2017', 'Деревянные конструкции'),
          ('СП 16.13330.2017', 'Стальные конструкции'),
          ('СП 14.13330.2018', 'Строительство в сейсмических районах'),
        ],
      ),
      _RefGroup(
        title: 'Климатология и инженерные изыскания',
        rows: [
          ('СП 131.13330.2020', 'Строительная климатология'),
          ('СП 47.13330.2016', 'Инженерные изыскания для строительства'),
        ],
      ),
      _RefGroup(
        title: 'Пожарная безопасность',
        rows: [
          ('СП 1.13130.2020', 'Эвакуационные пути и выходы'),
          ('СП 2.13130.2020', 'Обеспечение огнестойкости'),
          ('СП 4.13130.2013',
              'Ограничение распространения пожара'),
          ('СП 7.13130.2013', 'Отопление, вентиляция и кондиционирование'),
          ('ГОСТ Р 53292-2009',
              'Огнезащита материалов и конструкций'),
        ],
      ),
      _RefGroup(
        title: 'Инженерные системы',
        rows: [
          ('СП 30.13330.2020', 'Внутренний водопровод и канализация'),
          ('СП 31.13330.2021', 'Водоснабжение. Наружные сети'),
          ('СП 32.13330.2018', 'Канализация. Наружные сети'),
          ('СП 60.13330.2020', 'Отопление, вентиляция и кондиционирование'),
          ('СП 256.1325800.2016',
              'Электрооборудование жилых и общественных зданий'),
        ],
      ),
      _RefGroup(
        title: 'Оформление и материалы',
        rows: [
          ('ГОСТ Р 21.101-2020',
              'Основные требования к проектной и рабочей документации'),
          ('ГОСТ Р 21.501-2018',
              'Правила выполнения архитектурно-строительных рабочих чертежей'),
          ('ГОСТ 21.201-2011',
              'Условные графические изображения элементов зданий'),
          ('ГОСТ 26633-2015', 'Бетоны тяжёлые и мелкозернистые'),
          ('ГОСТ 34028-2016', 'Прокат арматурный для железобетонных '
              'конструкций'),
          ('ГОСТ 530-2012', 'Кирпич и камень керамические'),
          ('ГОСТ 31108-2020', 'Цементы общестроительные'),
          ('ГОСТ 8239-89',
              'Сталь горячекатаная. Двутавры с уклоном внутренних граней'),
        ],
      ),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'Перечень ссылочных нормативных документов',
            style: pw.TextStyle(
              fontSize: 12,
              font: fontBold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        // Раскладываем группы в 2 колонки.
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < groups.length; i += 2)
                      _refGroupTable(groups[i], headerStyle, cellStyle),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 1; i < groups.length; i += 2)
                      _refGroupTable(groups[i], headerStyle, cellStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _refGroupTable(
    _RefGroup group,
    pw.TextStyle headerStyle,
    pw.TextStyle cellStyle,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            child: pw.Text(group.title, style: headerStyle),
          ),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
            columnWidths: const {
              0: pw.FixedColumnWidth(110),
              1: pw.FlexColumnWidth(3),
            },
            children: [
              for (final row in group.rows)
                pw.TableRow(
                  children: [
                    _c(row.$1, cellStyle),
                    _c(row.$2, cellStyle),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _c(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }
}

class _LegendSection {
  const _LegendSection({required this.title, required this.items});
  final String title;
  final List<_LegendItem> items;
}

class _LegendItem {
  const _LegendItem(this.kind, this.label);
  final String kind;
  final String label;
}

class _RefGroup {
  const _RefGroup({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;
}
