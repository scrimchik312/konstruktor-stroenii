import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/house_project.dart';

/// Пояснительная записка по расчёту стропильной системы по
/// СП 64.13330.2017 «Деревянные конструкции» и СП 20.13330.2016
/// «Нагрузки и воздействия».
///
/// Цель — показать пользователю **реальный** расчёт по фактическим
/// исходным данным проекта (тип кровли, угол ската, материал кровли,
/// снеговой и ветровой районы, габариты дома) с подробным обоснованием
/// каждой формулы и пунктом СП, из которого она взята.
///
/// Структура записки:
///   1. Обозначения и источники (легенда).
///   2. Исходные данные (геометрия дома, тип/угол кровли, материалы,
///      снеговой/ветровой район).
///   3. Сбор постоянной нагрузки g (материал кровли + обрешётка + нога).
///   4. Сбор снеговой нагрузки S0 = Sg · μ.
///   5. Сбор ветровой нагрузки w0 (для информации).
///   6. Линейная нагрузка q на одну стропилу с учётом шага.
///   7. Геометрия сечения: Wx = b·h²/6, Ix = b·h³/12.
///   8. Проверка прочности (σ = M·10⁶/Wx ≤ Rи) и прогиба
///      (f = 5·qн·L⁴/(384·E·Ix) ≤ L/200).
///   9. Опорные реакции на мауэрлат и конёк R = q·L/2.
///  10. Выводы.
class RaftersExplanationPdf {
  RaftersExplanationPdf._();

  /// Sg — нормативное значение веса снегового покрова, кН/м²
  /// (СП 20.13330.2016 табл. 10.1).
  static double _snowSgPerZone(int? zone) {
    switch (zone ?? 3) {
      case 1:
        return 1.0;
      case 2:
        return 1.2;
      case 3:
        return 1.8;
      case 4:
        return 2.4;
      case 5:
        return 3.2;
      case 6:
        return 4.0;
      case 7:
        return 4.8;
      case 8:
        return 5.6;
      default:
        return 1.8;
    }
  }

  /// w0 — нормативное значение ветрового давления, кПа = кН/м²
  /// (СП 20.13330.2016 табл. 11.1, для районов Iа..VII).
  static double _windW0PerZone(String? zone) {
    switch (zone) {
      case 'Iа':
        return 0.17;
      case 'I':
        return 0.23;
      case 'II':
        return 0.30;
      case 'III':
        return 0.38;
      case 'IV':
        return 0.48;
      case 'V':
        return 0.60;
      case 'VI':
        return 0.73;
      case 'VII':
        return 0.85;
      default:
        return 0.30;
    }
  }

  /// Постоянная нагрузка g на 1 м² кровли (по горизонтальной проекции),
  /// в кН/м² — складывается из веса кровельного покрытия, обрешётки и
  /// собственного веса стропильной ноги.
  ///
  /// Веса кровельных материалов — реальные значения от производителей,
  /// согласованные с СП 17.13330.2017 «Кровли» прил. А.
  static _PermanentLoad _permanentLoad(String? roofingMaterial) {
    double roofingKnPerM2;
    String roofingTitle;
    switch (roofingMaterial) {
      case 'metal':
        roofingKnPerM2 = 0.05; // металлочерепица 0.5 мм ≈ 5 кгс/м²
        roofingTitle = 'Металлочерепица 0.5 мм';
        break;
      case 'tile':
        roofingKnPerM2 = 0.45; // керамическая черепица ≈ 45 кгс/м²
        roofingTitle = 'Керамическая черепица';
        break;
      case 'soft':
        roofingKnPerM2 = 0.10; // гибкая (битумная) черепица ≈ 10 кгс/м²
        roofingTitle = 'Гибкая (битумная) черепица';
        break;
      case 'corrugated':
        roofingKnPerM2 = 0.06; // профнастил
        roofingTitle = 'Профнастил';
        break;
      case 'slate':
        roofingKnPerM2 = 0.18; // шифер ≈ 18 кгс/м²
        roofingTitle = 'Асбестоцементный лист (шифер)';
        break;
      default:
        roofingKnPerM2 = 0.10;
        roofingTitle = 'Кровельное покрытие (типовое)';
    }
    // Обрешётка из доски 25 мм с шагом 350 мм + контробрешётка ≈
    // 0.10 кН/м². Стропильная нога 50×200 при шаге 0.6 м даёт
    // ≈ 0.12 кН/м². Утеплитель в скате (минвата 200 мм, ρ=35) —
    // ≈ 0.07 кН/м². Пароизоляция и мембрана — пренебрежимо мало.
    const sheathingKnPerM2 = 0.10;
    const rafterSelfWeightKnPerM2 = 0.12;
    const insulationKnPerM2 = 0.07;
    final total = roofingKnPerM2 +
        sheathingKnPerM2 +
        rafterSelfWeightKnPerM2 +
        insulationKnPerM2;
    return _PermanentLoad(
      roofingTitle: roofingTitle,
      roofingKn: roofingKnPerM2,
      sheathingKn: sheathingKnPerM2,
      rafterSelfWeightKn: rafterSelfWeightKnPerM2,
      insulationKn: insulationKnPerM2,
      totalKn: total,
    );
  }

  /// Шаг стропил (м) — типичные значения для разных кровельных
  /// материалов, СП 17.13330.2017.
  static double _rafterStepFor(String? roofingMaterial) {
    switch (roofingMaterial) {
      case 'tile':
        return 0.9;
      case 'metal':
      case 'corrugated':
        return 0.6;
      case 'soft':
        return 0.6;
      case 'slate':
        return 0.7;
      default:
        return 0.6;
    }
  }

  /// Коэффициент μ перехода от веса снегового покрова земли к снеговой
  /// нагрузке на покрытие (СП 20.13330.2016 п. 10.4):
  ///   • α ≤ 30°  → μ = 1.0
  ///   • α ≥ 60°  → μ = 0
  ///   • 30° < α < 60°  → μ = (60 − α) / 30 (линейная интерполяция).
  static double _snowMu(double angleDeg) {
    if (angleDeg <= 30) return 1.0;
    if (angleDeg >= 60) return 0.0;
    return (60 - angleDeg) / 30;
  }

  /// Угол ската: берём из roof.slopeAngle, иначе по типу кровли —
  /// типичное значение (двускатная — 30°, мансардная — 45°,
  /// односкатная — 15°, плоская — 0).
  static double _slopeAngleFor(HouseProject project) {
    final fromRoof = project.roof.slopeAngle;
    if (fromRoof != null) return fromRoof;
    final t = project.roof.type;
    switch (t) {
      case 'mansard':
        return 45.0;
      case 'shed':
        return 15.0;
      case 'flat':
        return 2.0;
      case 'gable':
      case 'hip':
      default:
        return 30.0;
    }
  }

  /// Полупролёт стропильной ноги (м) — для двускатной/вальмовой это
  /// W/2; для односкатной — W; для плоской — формально не считается
  /// (выпускается обрешётка, не стропила).
  static double _spanFor(HouseProject project, double footprintWidth) {
    final t = project.roof.type;
    switch (t) {
      case 'shed':
        return footprintWidth;
      case 'flat':
        return footprintWidth / 2;
      case 'mansard':
      case 'gable':
      case 'hip':
      default:
        return footprintWidth / 2;
    }
  }

  /// Человекочитаемое имя типа кровли.
  static String _roofTypeTitle(String? type) {
    switch (type) {
      case 'gable':
        return 'двускатная';
      case 'hip':
        return 'вальмовая';
      case 'shed':
        return 'односкатная';
      case 'mansard':
        return 'мансардная';
      case 'flat':
        return 'плоская';
      default:
        return type ?? 'двускатная (по умолчанию)';
    }
  }

  static Future<Uint8List> build({required HouseProject project}) async {
    final regularData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    // ----------------------------------------------------------------
    // ИСХОДНЫЕ ДАННЫЕ — все из проекта пользователя.
    // ----------------------------------------------------------------
    final width = project.brief.footprintWidth ?? 8.0;
    final length = project.brief.footprintLength ?? 10.0;
    final span = _spanFor(project, width);
    final angleDeg = _slopeAngleFor(project);
    final roofType = project.roof.type;
    final roofTypeTitle = _roofTypeTitle(roofType);
    final roofingMaterial = project.roof.roofingMaterial;
    final step = _rafterStepFor(roofingMaterial);
    final perm = _permanentLoad(roofingMaterial);
    final snowZone = project.brief.snowZone ?? 3;
    final sg = _snowSgPerZone(snowZone);
    final windZone = project.brief.windZone;
    final w0 = _windW0PerZone(windZone);
    final mu = _snowMu(angleDeg);
    final s0 = sg * mu; // нормативная снеговая на горизонт. проекцию

    // Коэффициенты надёжности по нагрузке (γf):
    //   • постоянная — 1.1 (СП 20.13330.2016 табл. 7.1)
    //   • снеговая — 1.4 (п. 10.12)
    //   • ветровая — 1.4 (п. 11.1.13)
    const gfPermanent = 1.1;
    const gfSnow = 1.4;
    // γf для ветра приведён в легенде (1.4); численно при поверочном
    // расчёте стропил на изгиб не используется — ветер не догружает
    // стропилы в схеме «равнонагруженная балка от снега и собственного
    // веса». Учитывается на узлах крепления.

    // Расчётная нагрузка на горизонтальную проекцию (кН/м²):
    final qHorizDesignKn =
        gfPermanent * perm.totalKn + gfSnow * s0; // ветер для стропил
    // не догружает (только на узлы крепления и опоры).

    // Линейная нагрузка на одну стропилу = q гор. × шаг (м).
    final qKnPerM = qHorizDesignKn * step;
    final qNormKnPerM = (perm.totalKn + s0) * step;

    // ----------------------------------------------------------------
    // Подбор сечения. Стартуем с типового 50×200, увеличиваем при
    // непрохождении. Сорт древесины — 2 (типовая сосна 1-2 сорт по СП 64).
    // ----------------------------------------------------------------
    var widthMm = 50.0;
    var heightMm = 200.0;
    RafterCheckResult result = RafterCheck.computeSimple(
      spanM: span,
      widthMm: widthMm,
      heightMm: heightMm,
      qKnPerM: qKnPerM,
      qNormKnPerM: qNormKnPerM,
      grade: WoodGrade.second,
    );
    if (!result.passes) {
      heightMm = 250;
      result = RafterCheck.computeSimple(
        spanM: span,
        widthMm: widthMm,
        heightMm: heightMm,
        qKnPerM: qKnPerM,
        qNormKnPerM: qNormKnPerM,
        grade: WoodGrade.second,
      );
    }
    if (!result.passes) {
      widthMm = 75;
      heightMm = 250;
      result = RafterCheck.computeSimple(
        spanM: span,
        widthMm: widthMm,
        heightMm: heightMm,
        qKnPerM: qKnPerM,
        qNormKnPerM: qNormKnPerM,
        grade: WoodGrade.second,
      );
    }

    // Опорные реакции на мауэрлат и конёк — для однопролётной
    // равнонагруженной балки R_A = R_B = q·L/2. Для проверки крепления.
    final reactionKn = qKnPerM * span / 2;

    final pdf = pw.Document(
      title: 'ПЗ. Стропильная система — ${project.name}',
      author: 'Construction Calculator',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      header: (ctx) => _header(project, regular, 'Стропильная система'),
      footer: (ctx) => _footer(ctx, regular),
      build: (ctx) => [
        _title(project, bold, regular),
        pw.SizedBox(height: 12),
        _section('1. Обозначения и источники', bold),
        _glossary(regular, bold),
        pw.SizedBox(height: 12),
        _section('2. Исходные данные', bold),
        _inputs(
          project: project,
          width: width,
          length: length,
          span: span,
          step: step,
          angleDeg: angleDeg,
          roofTypeTitle: roofTypeTitle,
          snowZone: snowZone,
          sg: sg,
          windZone: windZone,
          w0: w0,
          mu: mu,
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 12),
        _section('3. Сбор постоянной нагрузки g', bold),
        _permanentLoadTable(perm, regular, bold),
        pw.SizedBox(height: 12),
        _section('4. Сбор снеговой нагрузки S0', bold),
        _snowSection(snowZone, sg, mu, angleDeg, s0, regular, bold),
        pw.SizedBox(height: 12),
        _section('5. Ветровое давление w0 (информационно)', bold),
        pw.Text(
          'По СП 20.13330.2016 табл. 11.1 для ветрового района '
          '${windZone ?? "(не задан)"} нормативное значение ветрового '
          'давления w0 = ${w0.toStringAsFixed(2)} кН/м². '
          'На стропильную ногу ветер действует через узлы крепления к '
          'мауэрлату/коньку и в данной проверке прочности и прогиба '
          'не учитывается (стропила работают на изгиб от вертикальных '
          'нагрузок). Расчёт анкерных связей и связи с мауэрлатом — '
          'в отдельном узле.',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 12),
        _section('6. Расчётная линейная нагрузка q на стропилу', bold),
        _qBlock(
          gKn: perm.totalKn,
          s0: s0,
          gfPermanent: gfPermanent,
          gfSnow: gfSnow,
          step: step,
          qHorizDesignKn: qHorizDesignKn,
          qKnPerM: qKnPerM,
          qNormKnPerM: qNormKnPerM,
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 12),
        _section(
            '7. Геометрия сечения '
            '${widthMm.toStringAsFixed(0)}×${heightMm.toStringAsFixed(0)} мм '
            '(сорт 2)',
            bold),
        _crossSectionTable(widthMm, heightMm, regular, bold),
        pw.SizedBox(height: 12),
        _section('8. Проверка прочности и прогиба (СП 64.13330.2017)', bold),
        ..._stepsBlock(result.steps, regular, bold),
        pw.SizedBox(height: 12),
        _section('9. Опорные реакции на мауэрлат и конёк', bold),
        pw.Text(
          'Для однопролётной балки с равномерно распределённой '
          'нагрузкой опорные реакции одинаковы и равны q·L/2.',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 4),
        _formulaCell(
          formula: 'R = q · L / 2',
          substitution:
              'R = ${qKnPerM.toStringAsFixed(2)} · ${span.toStringAsFixed(2)} / 2 = ${reactionKn.toStringAsFixed(2)}',
          result: 'R = ${reactionKn.toStringAsFixed(2)} кН',
          reference: 'СП 20.13330.2016 — статика балки',
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Реакция передаётся на мауэрлат (низ ската) и коньковый прогон '
          '(верх). По этой нагрузке подбираются крепёж стропилы к '
          'мауэрлату (скользящая опора + закладной анкер) и узел опирания '
          'на конёк.',
          style: pw.TextStyle(fontSize: 9, font: regular),
        ),
        pw.SizedBox(height: 12),
        _section('10. Выводы', bold),
        _conclusion(result, widthMm, heightMm, span, step, regular, bold),
      ],
    ));

    return pdf.save();
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
        pw.Text('Расчёт стропильной системы',
            style: pw.TextStyle(fontSize: 12, font: regular)),
        pw.SizedBox(height: 8),
        pw.Text('Объект: ${project.name}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Дата: $date',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.SizedBox(height: 6),
        pw.Text(
          'Расчёт выполнен по СП 20.13330.2016 «Нагрузки и воздействия», '
          'СП 64.13330.2017 «Деревянные конструкции», '
          'СП 17.13330.2017 «Кровли».',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
      ],
    );
  }

  static pw.Widget _section(String text, pw.Font bold) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 12, font: bold)),
      );

  /// Расшифровка обозначений с указанием единиц измерения и источника.
  static pw.Widget _glossary(pw.Font regular, pw.Font bold) {
    final entries = <List<String>>[
      ['L', 'Расчётный пролёт стропильной ноги, м (полупролёт для двускатной)', 'из геометрии дома'],
      ['α', 'Угол наклона ската кровли, °', 'из проекта (raw из выбора пользователя)'],
      ['t', 'Шаг стропил, м', 'СП 17.13330.2017 — типовые значения по материалу кровли'],
      ['g', 'Постоянная нагрузка на покрытие (на гор. проекции), кН/м²', 'собственный вес кровельного пирога'],
      ['Sg', 'Нормативное значение веса снегового покрова земли, кН/м²', 'СП 20.13330.2016 табл. 10.1'],
      ['μ', 'Коэффициент перехода от Sg к снеговой нагрузке на покрытие', 'СП 20.13330.2016 п. 10.4'],
      ['S0', 'Нормативное значение снеговой нагрузки = Sg · μ, кН/м²', 'СП 20.13330.2016 формула (10.1)'],
      ['w0', 'Нормативное значение ветрового давления, кН/м²', 'СП 20.13330.2016 табл. 11.1'],
      ['γf', 'Коэффициент надёжности по нагрузке: 1.1 — постоянная, 1.4 — снег и ветер', 'СП 20.13330.2016 табл. 7.1, п.п. 10.12, 11.1.13'],
      ['γn', 'Коэффициент надёжности по ответственности (для ИЖС γn=1.0)', 'ГОСТ 27751-2014 п. 5.1'],
      ['γc', 'Коэффициент условий работы древесины (для стропил жилого дома γc=1.0)', 'СП 64.13330.2017 п. 6.9'],
      ['q', 'Расчётная линейная нагрузка на стропилу = (γf·g + γf·S0) · t, кН/м', 'СП 20.13330.2016 — суперпозиция'],
      ['qн', 'То же, но с нормативными нагрузками (для прогиба), кН/м', '—'],
      ['b, h', 'Ширина и высота прямоугольного сечения стропилы, мм', 'из подбора'],
      ['Wx', 'Момент сопротивления сечения, мм³ (Wx = b·h²/6)', 'СП 64.13330.2017 п. 7.1'],
      ['Ix', 'Момент инерции сечения, мм⁴ (Ix = b·h³/12)', 'сопромат'],
      ['M', 'Изгибающий момент в середине пролёта, кН·м (M = q·L²/8)', 'однопролётная балка'],
      ['σ', 'Нормальное напряжение в крайнем волокне = M·10⁶/Wx, Н/мм²', 'СП 64.13330.2017 формула (33)'],
      ['Rи', 'Расчётное сопротивление древесины изгибу, Н/мм² (для 2 сорта = 14)', 'СП 64.13330.2017 табл. 3'],
      ['E', 'Модуль упругости древесины при изгибе, Н/мм² (≈ 10000)', 'СП 64.13330.2017 п. 7.1'],
      ['f', 'Прогиб стропилы в середине пролёта, мм', 'формула 5·qн·L⁴/(384·E·Ix)'],
      ['fadm', 'Предельный прогиб = L/200', 'СП 20.13330.2016 табл. Д.1'],
      ['R', 'Опорная реакция на мауэрлат / конёк, кН (R = q·L/2)', 'статика балки'],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.9),
        1: pw.FlexColumnWidth(2.7),
        2: pw.FlexColumnWidth(3.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final h in const ['Обозн.', 'Что это', 'Источник / нормативный пункт'])
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(h,
                    style: pw.TextStyle(fontSize: 9.5, font: bold)),
              ),
          ],
        ),
        for (final row in entries)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(row[0],
                  style: pw.TextStyle(fontSize: 9.5, font: bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(row[1],
                  style: pw.TextStyle(fontSize: 9.5, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(row[2],
                  style: pw.TextStyle(fontSize: 9, font: regular)),
            ),
          ]),
      ],
    );
  }

  static pw.Widget _inputs({
    required HouseProject project,
    required double width,
    required double length,
    required double span,
    required double step,
    required double angleDeg,
    required String roofTypeTitle,
    required int snowZone,
    required double sg,
    required String? windZone,
    required double w0,
    required double mu,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final material = project.roof.roofingMaterial ?? '(не задан)';
    final region = project.brief.region ?? '(не задан)';
    final rows = <List<String>>[
      ['Регион проекта', region, 'из выбора пользователя'],
      ['Габариты дома (W × L)', '${width.toStringAsFixed(2)} × ${length.toStringAsFixed(2)} м', 'из выбора пользователя'],
      ['Тип кровли', roofTypeTitle, 'из выбора пользователя'],
      ['Кровельный материал', material, 'из выбора пользователя'],
      ['Угол ската α', '${angleDeg.toStringAsFixed(0)}°', 'из проекта или типовой по типу'],
      ['Полупролёт стропильной ноги L', '${span.toStringAsFixed(2)} м', 'L = W/2 для дву-/вальмовой; L = W для односкатной'],
      ['Шаг стропил t', '${step.toStringAsFixed(2)} м', 'СП 17.13330.2017 — по материалу кровли'],
      ['Снеговой район', '$snowZone', 'из выбора пользователя'],
      ['Sg (нормативная)', '${sg.toStringAsFixed(2)} кН/м²', 'СП 20.13330.2016 табл. 10.1'],
      ['μ (коэф. перехода)', mu.toStringAsFixed(2), 'СП 20.13330.2016 п. 10.4'],
      ['Ветровой район', windZone ?? '(не задан)', 'из выбора пользователя'],
      ['w0 (нормативное)', '${w0.toStringAsFixed(2)} кН/м²', 'СП 20.13330.2016 табл. 11.1'],
      ['Сорт древесины', '2 сорт (сосна)', 'СП 64.13330.2017 табл. 3'],
      ['Rи (расч. сопротивление изгибу)', '14 Н/мм²', 'СП 64.13330.2017 табл. 3 (2 сорт)'],
      ['E (модуль упругости)', '10000 Н/мм²', 'СП 64.13330.2017 п. 7.1'],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.6),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final h in const ['Параметр', 'Значение', 'Источник'])
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(h,
                    style: pw.TextStyle(fontSize: 9.5, font: bold)),
              ),
          ],
        ),
        for (final r in rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(r[0],
                  style: pw.TextStyle(fontSize: 10, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(r[1],
                  style: pw.TextStyle(fontSize: 10, font: bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(r[2],
                  style: pw.TextStyle(fontSize: 9, font: regular)),
            ),
          ]),
      ],
    );
  }

  /// Таблица постоянной нагрузки g — все слагаемые с весом и пунктом
  /// норматива.
  static pw.Widget _permanentLoadTable(
      _PermanentLoad p, pw.Font regular, pw.Font bold) {
    final rows = <List<String>>[
      [p.roofingTitle, p.roofingKn.toStringAsFixed(3), 'СП 17.13330.2017 прил. А'],
      ['Обрешётка + контробрешётка (доска 25 мм)', p.sheathingKn.toStringAsFixed(3), 'СП 64.13330.2017'],
      ['Утеплитель в скате (минвата 200, ρ=35)', p.insulationKn.toStringAsFixed(3), 'СП 50.13330.2012'],
      ['Собственный вес стропилы 50×200 при шаге 0.6 м', p.rafterSelfWeightKn.toStringAsFixed(3), 'СП 20.13330.2016 п. 7'],
      ['Итого g', p.totalKn.toStringAsFixed(3), 'сумма'],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.4),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(2.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final h in const [
              'Слой / составляющая',
              'g, кН/м²',
              'Источник',
            ])
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(h,
                    style: pw.TextStyle(fontSize: 9.5, font: bold)),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: i == rows.length - 1
                ? const pw.BoxDecoration(color: PdfColors.grey100)
                : null,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(rows[i][0],
                    style: pw.TextStyle(
                        fontSize: 10,
                        font: i == rows.length - 1 ? bold : regular)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(rows[i][1],
                    style: pw.TextStyle(
                        fontSize: 10,
                        font: i == rows.length - 1 ? bold : regular)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(rows[i][2],
                    style: pw.TextStyle(fontSize: 9, font: regular)),
              ),
            ],
          ),
      ],
    );
  }

  /// Раздел снеговой нагрузки — формула, μ-зависимость от α, S0.
  static pw.Widget _snowSection(int snowZone, double sg, double mu,
      double angleDeg, double s0, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'По СП 20.13330.2016 п. 10.1 нормативное значение снеговой '
          'нагрузки на покрытие S0 определяется по формуле:',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 4),
        _formulaCell(
          formula: 'S0 = Sg · μ',
          substitution:
              'S0 = ${sg.toStringAsFixed(2)} · ${mu.toStringAsFixed(2)} = ${s0.toStringAsFixed(2)}',
          result: 'S0 = ${s0.toStringAsFixed(2)} кН/м²',
          reference: 'СП 20.13330.2016 формула (10.1)',
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Sg — нормативное значение веса снегового покрова земли '
          'для $snowZone-го снегового района, по СП 20.13330.2016 табл. 10.1.',
          style: pw.TextStyle(fontSize: 9.5, font: regular),
        ),
        pw.Text(
          'μ — коэффициент перехода от веса снегового покрова земли '
          'к снеговой нагрузке на покрытие, СП 20.13330.2016 п. 10.4: '
          'для α ≤ 30° μ=1.0; для α ≥ 60° μ=0; в промежуточном диапазоне '
          'μ = (60° − α)/30°. При угле α = ${angleDeg.toStringAsFixed(0)}° '
          'получаем μ = ${mu.toStringAsFixed(2)}.',
          style: pw.TextStyle(fontSize: 9.5, font: regular),
        ),
      ],
    );
  }

  /// Расчёт линейной q на стропилу.
  static pw.Widget _qBlock({
    required double gKn,
    required double s0,
    required double gfPermanent,
    required double gfSnow,
    required double step,
    required double qHorizDesignKn,
    required double qKnPerM,
    required double qNormKnPerM,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Стропила собирают нагрузку с грузовой полосы шириной t (шаг). '
          'Сначала находим расчётную нагрузку на 1 м² горизонтальной '
          'проекции (с коэффициентами надёжности γf), затем — линейную '
          'нагрузку на стропилу умножением на шаг t.',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 6),
        _formulaCell(
          formula: 'q_гор = γf,g · g + γf,S · S0',
          substitution:
              'q_гор = ${gfPermanent.toStringAsFixed(1)} · ${gKn.toStringAsFixed(2)} + ${gfSnow.toStringAsFixed(1)} · ${s0.toStringAsFixed(2)} = ${qHorizDesignKn.toStringAsFixed(2)}',
          result: 'q_гор = ${qHorizDesignKn.toStringAsFixed(2)} кН/м²',
          reference: 'СП 20.13330.2016 табл. 7.1, п.п. 10.12',
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 4),
        _formulaCell(
          formula: 'q = q_гор · t',
          substitution:
              'q = ${qHorizDesignKn.toStringAsFixed(2)} · ${step.toStringAsFixed(2)} = ${qKnPerM.toStringAsFixed(2)}',
          result: 'q = ${qKnPerM.toStringAsFixed(2)} кН/м',
          reference: 'грузовая полоса = шаг стропил',
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 4),
        _formulaCell(
          formula: 'qн = (g + S0) · t  — для проверки прогиба',
          substitution:
              'qн = (${gKn.toStringAsFixed(2)} + ${s0.toStringAsFixed(2)}) · ${step.toStringAsFixed(2)} = ${qNormKnPerM.toStringAsFixed(2)}',
          result: 'qн = ${qNormKnPerM.toStringAsFixed(2)} кН/м',
          reference: 'СП 20.13330.2016 п. 5.2 — нормативные сочетания для '
              'проверки прогибов',
          regular: regular,
          bold: bold,
        ),
      ],
    );
  }

  /// Геометрия сечения: Wx = b·h²/6, Ix = b·h³/12.
  static pw.Widget _crossSectionTable(
      double widthMm, double heightMm, pw.Font regular, pw.Font bold) {
    final wx = widthMm * heightMm * heightMm / 6;
    final ix = widthMm * math.pow(heightMm, 3) / 12;
    final rows = <List<String>>[
      ['Ширина b, мм', widthMm.toStringAsFixed(0)],
      ['Высота h, мм', heightMm.toStringAsFixed(0)],
      ['Площадь A = b·h, мм²', (widthMm * heightMm).toStringAsFixed(0)],
      ['Момент сопротивления Wx = b·h²/6, мм³', wx.toStringAsFixed(0)],
      ['Момент инерции Ix = b·h³/12, мм⁴', ix.toStringAsFixed(0)],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
      },
      children: [
        for (final r in rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(r[0],
                  style: pw.TextStyle(fontSize: 10, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(r[1],
                  style: pw.TextStyle(fontSize: 10, font: bold)),
            ),
          ]),
      ],
    );
  }

  /// Маленькая ячейка «формула / подстановка / результат / ссылка».
  static pw.Widget _formulaCell({
    required String formula,
    required String substitution,
    required String result,
    required String reference,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Формула: $formula',
              style: pw.TextStyle(fontSize: 10, font: regular)),
          pw.Text('Подстановка: $substitution',
              style: pw.TextStyle(fontSize: 10, font: regular)),
          pw.Text('Результат: $result',
              style: pw.TextStyle(fontSize: 10, font: bold)),
          pw.Text(reference,
              style: pw.TextStyle(
                  fontSize: 9,
                  font: regular,
                  color: PdfColors.blueGrey700)),
        ],
      ),
    );
  }

  static List<pw.Widget> _stepsBlock(
      List<CalcStep> steps, pw.Font regular, pw.Font bold) {
    return [
      for (final s in steps)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s.title,
                  style: pw.TextStyle(fontSize: 10.5, font: bold)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
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
            ],
          ),
        ),
    ];
  }

  static pw.Widget _conclusion(RafterCheckResult res, double w, double h,
      double span, double step, pw.Font regular, pw.Font bold) {
    final strOk = res.strengthPasses ? 'выполняется' : 'НЕ выполняется';
    final defOk = res.deflectionPasses ? 'выполняется' : 'НЕ выполняется';
    final overall = res.passes
        ? 'Стропильная система НЕСУЩУЮ способность обеспечивает.'
        : 'ВНИМАНИЕ: сечение не проходит проверку — увеличить высоту h '
            'или применить парный/спаренный профиль.';
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Принято сечение стропильной ноги: '
            '${w.toStringAsFixed(0)}×${h.toStringAsFixed(0)} мм, сосна 2 сорт, '
            'пролёт L = ${span.toStringAsFixed(2)} м, шаг t = ${step.toStringAsFixed(2)} м.',
            style: pw.TextStyle(fontSize: 10.5, font: bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'σ = ${res.sigmaNmm2.toStringAsFixed(2)} Н/мм² ≤ '
            'Rи = ${res.sigmaAllowed.toStringAsFixed(2)} Н/мм² — '
            'условие прочности (СП 64 ф.33) $strOk.',
            style: pw.TextStyle(fontSize: 10, font: regular),
          ),
          pw.Text(
            'f = ${res.deflectionMm.toStringAsFixed(1)} мм ≤ '
            'L/200 = ${res.deflectionLimitMm.toStringAsFixed(1)} мм — '
            'условие прогиба (СП 20 табл. Д.1) $defOk.',
            style: pw.TextStyle(fontSize: 10, font: regular),
          ),
          pw.SizedBox(height: 6),
          pw.Text(overall,
              style: pw.TextStyle(
                  fontSize: 10,
                  font: bold,
                  color:
                      res.passes ? PdfColors.green800 : PdfColors.red800)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Комментарий: расчёт упрощён до однопролётной балки с '
            'равномерно распределённой нагрузкой. При наличии стойки/подкоса '
            'или подкосной фермы фактический пролёт сокращается, и реальные '
            'σ и f будут меньше — расчёт идёт «в запас».',
            style: pw.TextStyle(fontSize: 9, font: regular),
          ),
        ]);
  }

  static pw.Widget _header(
      HouseProject project, pw.Font font, String label) {
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
          pw.Text('ПЗ. $label',
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
          pw.Text('Construction Calculator',
              style: pw.TextStyle(fontSize: 8, font: font)),
          pw.Text('Лист ${ctx.pageNumber} из ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, font: font)),
        ],
      ),
    );
  }
}

/// Раскладка постоянной нагрузки на 1 м² гор. проекции (кН/м²) с
/// разбивкой по слоям пирога — для прозрачного отчёта.
class _PermanentLoad {
  const _PermanentLoad({
    required this.roofingTitle,
    required this.roofingKn,
    required this.sheathingKn,
    required this.rafterSelfWeightKn,
    required this.insulationKn,
    required this.totalKn,
  });
  final String roofingTitle;
  final double roofingKn;
  final double sheathingKn;
  final double rafterSelfWeightKn;
  final double insulationKn;
  final double totalKn;
}
