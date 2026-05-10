import 'dart:typed_data';

import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/house_project.dart';

/// Генерация пояснительной записки (ПЗ) к расчёту фундамента в PDF.
///
/// Структура документа (по ГОСТ 21.501 / СП 22):
///   1. Титульный лист.
///   2. Исходные данные (с пометкой источника каждой величины).
///   3. Расчёт нагрузок (формулы, подстановка, журнал по СП 20).
///   4. Сопротивление грунта основания.
///   5. Подбор сечения ленточного фундамента.
///   6. Армирование.
///   7. Выводы.
///
/// PDF строится **из тех же CalcStep + CalcInput**, которые показаны
/// на экранах расчётов. Это значит: данные в ПЗ всегда совпадают с
/// тем, что видит пользователь на экране — нет повторного запуска
/// расчёта и нет риска расхождения.
class FoundationExplanationPdf {
  FoundationExplanationPdf._();

  static Future<Uint8List> build({
    required HouseProject project,
    required FoundationLoadsResult loads,
    required StripFootingDesign design,
    required Map<String, String> inputDataRows,
  }) async {
    final regularData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final pdf = pw.Document(
      title: 'Пояснительная записка — фундамент — ${project.name}',
      author: 'Construction Calculator',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        header: (ctx) => _header(ctx, project, regular),
        footer: (ctx) => _footer(ctx, regular),
        build: (ctx) => [
          _title(project, bold, regular),
          pw.SizedBox(height: 16),
          _sectionTitle('1. Исходные данные', bold),
          _inputDataTable(inputDataRows, regular, bold),
          pw.SizedBox(height: 12),
          _sectionTitle('2. Расчёт снеговой нагрузки', bold),
          ..._stepsBlock(loads.snow.steps, regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('3. Расчёт ветровой нагрузки', bold),
          ..._stepsBlock(loads.wind.steps, regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('4. Постоянная и полезная нагрузки. Сводка',
              bold),
          ..._stepsBlock(loads.summary, regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('5. Сопротивление грунта и подбор сечения',
              bold),
          ..._stepsBlock(design.steps, regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('6. Принятые параметры фундамента', bold),
          _resultTable(design, regular, bold),
          pw.SizedBox(height: 12),
          _sectionTitle('7. Выводы', bold),
          _conclusion(loads, design, regular),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _header(
      pw.Context ctx, HouseProject project, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(project.name,
              style: pw.TextStyle(fontSize: 9, font: font)),
          pw.Text('Пояснительная записка. Фундамент',
              style: pw.TextStyle(fontSize: 9, font: font)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Сгенерировано Construction Calculator',
              style: pw.TextStyle(fontSize: 8, font: font)),
          pw.Text(
              'Лист ${ctx.pageNumber} из ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, font: font)),
        ],
      ),
    );
  }

  static pw.Widget _title(
      HouseProject project, pw.Font bold, pw.Font regular) {
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, "0")}.'
        '${now.month.toString().padLeft(2, "0")}.${now.year}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ПОЯСНИТЕЛЬНАЯ ЗАПИСКА',
            style: pw.TextStyle(fontSize: 16, font: bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'к расчёту фундамента жилого дома',
          style: pw.TextStyle(fontSize: 12, font: regular),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Объект: ${project.name}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Дата: $date',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.SizedBox(height: 6),
        pw.Text(
          'Расчёт выполнен по СП 20.13330.2016, СП 22.13330.2016, '
          'СП 63.13330.2018, СП 131.13330.2020.',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 12, font: bold)),
    );
  }

  static pw.Widget _inputDataTable(
      Map<String, String> rows, pw.Font regular, pw.Font bold) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        for (final entry in rows.entries)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(entry.key,
                    style: pw.TextStyle(fontSize: 10, font: regular)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(entry.value,
                    style: pw.TextStyle(fontSize: 10, font: bold)),
              ),
            ],
          ),
      ],
    );
  }

  static List<pw.Widget> _stepsBlock(
      List<CalcStep> steps, pw.Font regular, pw.Font bold) {
    return [
      for (final s in steps)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s.title,
                  style: pw.TextStyle(fontSize: 10.5, font: bold)),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius:
                      pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Формула: ${s.formula}',
                        style: pw.TextStyle(fontSize: 10, font: regular)),
                    pw.Text('Подстановка: ${s.substitution}',
                        style: pw.TextStyle(fontSize: 10, font: regular)),
                    pw.Text('Результат: ${s.formattedResult}',
                        style: pw.TextStyle(fontSize: 10, font: bold)),
                  ],
                ),
              ),
              if (s.reference != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(s.reference!,
                      style: pw.TextStyle(
                          fontSize: 9,
                          font: regular,
                          color: PdfColors.blueGrey700)),
                ),
              if (s.note != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(s.note!,
                      style: pw.TextStyle(
                          fontSize: 9, font: regular)),
                ),
              if (s.inputs.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4, left: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Откуда взяты значения:',
                          style: pw.TextStyle(
                              fontSize: 9,
                              font: bold,
                              color: PdfColors.blueGrey700)),
                      for (final inp in s.inputs)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1),
                          child: pw.Text(
                            '• ${inp.symbol} = ${inp.value} — ${inp.origin}'
                            '${inp.reference != null ? " (${inp.reference})" : ""}',
                            style: pw.TextStyle(
                                fontSize: 9, font: regular),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  static pw.Widget _resultTable(
      StripFootingDesign d, pw.Font regular, pw.Font bold) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Ширина подошвы b', '${d.widthM.toStringAsFixed(2)} м'),
      MapEntry('Высота ленты h', '${d.heightM.toStringAsFixed(2)} м'),
      MapEntry('Глубина заложения d', '${d.depthM.toStringAsFixed(2)} м'),
      MapEntry('Класс бетона', d.concreteClass.title),
      MapEntry(
          'Продольная арматура',
          '${d.longitudinalCount}⌀${d.longitudinalDiameterMm} '
              '${d.longitudinalClass.title}'),
      MapEntry(
          'Поперечная арматура (хомуты)',
          '⌀${d.stirrupDiameterMm} ${d.stirrupClass.title}, '
              'шаг ${d.stirrupSpacingMm} мм'),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        for (final r in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(r.key,
                    style: pw.TextStyle(fontSize: 10, font: regular)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(r.value,
                    style: pw.TextStyle(fontSize: 10, font: bold)),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _conclusion(
    FoundationLoadsResult loads,
    StripFootingDesign design,
    pw.Font font,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Принят ленточный монолитный железобетонный фундамент '
          'шириной b = ${design.widthM.toStringAsFixed(2)} м, '
          'высотой h = ${design.heightM.toStringAsFixed(2)} м, '
          'с глубиной заложения d = ${design.depthM.toStringAsFixed(2)} м.',
          style: pw.TextStyle(fontSize: 10, font: font),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Расчётная вертикальная нагрузка на фундамент составляет '
          '${loads.totalVerticalKnPerM2.toStringAsFixed(2)} кН/м². '
          'Нагрузки определены по СП 20.13330.2016, сопротивление '
          'грунта основания — по табл. В.3 СП 22.13330.2016 '
          '(предварительные значения).',
          style: pw.TextStyle(fontSize: 10, font: font),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Армирование принято конструктивно по СП 63.13330.2018: '
          '${design.longitudinalCount}⌀${design.longitudinalDiameterMm} '
          '${design.longitudinalClass.title} (продольная) + '
          '⌀${design.stirrupDiameterMm} ${design.stirrupClass.title} '
          'с шагом ${design.stirrupSpacingMm} мм (поперечная). '
          'Класс бетона ${design.concreteClass.title}, морозостойкость '
          'F100, водонепроницаемость W4.',
          style: pw.TextStyle(fontSize: 10, font: font),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Примечание: расчёт является предварительным. Для '
          'итогового проекта следует выполнить расчёт по формуле '
          '(5.7) СП 22.13330.2016 с учётом инженерно-геологических '
          'изысканий по СП 47.13330.2016 и проверку на изгиб по СП 63.',
          style: pw.TextStyle(
              fontSize: 9, font: font, fontStyle: pw.FontStyle.italic),
        ),
      ],
    );
  }
}
