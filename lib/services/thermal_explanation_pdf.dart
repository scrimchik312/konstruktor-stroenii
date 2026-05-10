import 'dart:typed_data';

import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/wall_materials.dart';
import '../models/house_project.dart';

/// Пояснительная записка по теплотехническому расчёту наружных
/// ограждающих конструкций (СП 50.13330.2012 / СП 131.13330.2020 /
/// ГОСТ 30494-2011).
///
/// Цель — показать пользователю не только итог, но и **откуда берётся
/// каждое значение**: расшифровка всех обозначений, формулы с пунктами
/// СП, подстановка фактических чисел и проверка по нормам.
///
/// Структура записки:
///   1. Перечень обозначений (расшифровка греческих букв и индексов).
///   2. Исходные данные (климат, материалы стен и кровли, λ из СП 50).
///   3. Расчёт ГСОП и требуемого сопротивления теплопередаче R₀ᵗᵖ.
///   4. Состав наружной стены и расчёт фактического R₀.
///   5. Состав покрытия (кровельного пирога) и расчёт фактического R₀.
///   6. Сравнение R₀ ≥ R₀ᵗᵖ — вывод о достаточности утепления.
class ThermalExplanationPdf {
  ThermalExplanationPdf._();

  /// Подбирает климатическую зону по региону проекта. По умолчанию — Москва.
  /// Список расширен в v43 — добавлены Казань, Нижний Новгород, Якутск,
  /// Сочи, Мурманск, Владивосток, Иркутск (СП 131.13330.2020 табл. 3.1).
  static ClimateZone _climateForProject(HouseProject project) {
    final region = project.brief.region?.toLowerCase() ?? '';
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

  /// Подбирает минимальную толщину утеплителя (мм) для прохождения
  /// требуемого R₀ᵗᵖ в заданном климате (п.1 v43, СП 50.13330.2012).
  ///
  /// На вход — список «не-утеплительных» слоёв (несущая стена,
  /// штукатурки, внутренняя обшивка) и λ предполагаемого утеплителя.
  /// Возвращает толщину утеплителя в мм (округлено вверх до 50 мм
  /// — типовая шаговая толщина плит).
  ///
  /// Формула:
  ///   R₀ ≥ R₀ᵗᵖ
  ///   1/αв + ΣRᵢ + δ_утеп/λ_утеп + 1/αн ≥ R₀ᵗᵖ
  ///   δ_утеп ≥ λ_утеп · (R₀ᵗᵖ − 1/αв − ΣRᵢ − 1/αн)
  static double _suggestInsulationThicknessMm({
    required ClimateZone climate,
    required BuildingEnvelope envelope,
    required List<EnvelopeLayer> nonInsulationLayers,
    required double insulationLambda,
    double alphaIn = 8.7,
    double alphaOut = 23.0,
  }) {
    final probe = ThermalCalculator.compute(
      climate: climate,
      envelope: envelope,
      layers: nonInsulationLayers,
      alphaIn: alphaIn,
      alphaOut: alphaOut,
    );
    final rReq = probe.rReq;
    final rBase = nonInsulationLayers.fold<double>(0, (p, l) => p + l.r);
    final remaining = rReq - 1 / alphaIn - rBase - 1 / alphaOut;
    if (remaining <= 0) return 0; // утеплитель не требуется
    final thicknessM = remaining * insulationLambda;
    final mm = thicknessM * 1000;
    // Округление вверх до 50 мм (типовая толщина плит).
    return ((mm / 50).ceil() * 50).toDouble();
  }

  /// Возвращает λ для выбранного материала стены (Вт/(м·°C),
  /// СП 50.13330.2012 приложение Т / приложение С).
  static double _wallLambda(String wallCode) {
    switch (wallCode) {
      case 'brick':
        return 0.81; // кирпич полнотелый ГОСТ 530, ρ=1800 кг/м³
      case 'aerated':
        return 0.16; // газобетон D500 ГОСТ 31360
      case 'expandedClay':
        return 0.46; // керамзитоблок ГОСТ 6133
      case 'timber':
        return 0.18; // брус сосна, поперёк волокон
      case 'log':
        return 0.18;
      case 'frame':
        return 0.045; // утеплитель базальт ГОСТ 32314
      default:
        return 0.30;
    }
  }

  static String _wallTitle(String wallCode) {
    switch (wallCode) {
      case 'brick':
        return 'Кирпич полнотелый ρ=1800 кг/м³';
      case 'aerated':
        return 'Газобетон D500';
      case 'expandedClay':
        return 'Керамзитобетон D1200';
      case 'timber':
        return 'Брус сосна, поперёк волокон';
      case 'log':
        return 'Бревно сосна';
      case 'frame':
        return 'Каркасная стена';
      default:
        return 'Стеновой материал';
    }
  }

  /// Реальный состав наружной стены: основной материал + штукатурка/отделка.
  ///
  /// П.1 v43: толщина утеплителя выбирается по климату (через
  /// `_suggestInsulationThicknessMm`), а не задаётся константой. Это
  /// гарантирует, что в Якутске стены будут утеплены ~250 мм минваты,
  /// а в Сочи — 50 мм (или вовсе без утеплителя для брус/каркас).
  ///
  /// Для каркаса — отдельно: ОСП-плита снаружи, минвата в каркасе,
  /// пароизоляция (R≈0), ГКЛ изнутри. λ — по СП 50 приложение Т.
  static List<EnvelopeLayer> _wallLayers(
    String wallCode,
    double thicknessMm, {
    required ClimateZone climate,
  }) {
    const insulLambdaMineralWool = 0.045;
    switch (wallCode) {
      case 'frame':
        // Каркасная стена — основной утеплитель. Толщина считается так,
        // чтобы конструкция в одиночку держала R₀ᵗᵖ.
        final shellLayers = <EnvelopeLayer>[
          const EnvelopeLayer(
              name: 'Гипсокартон ГКЛ', thicknessMm: 12.5, lambda: 0.21),
          const EnvelopeLayer(
              name: 'Плита OSB-3', thicknessMm: 12, lambda: 0.13),
        ];
        final insulMm = _suggestInsulationThicknessMm(
          climate: climate,
          envelope: BuildingEnvelope.wall,
          nonInsulationLayers: shellLayers,
          insulationLambda: insulLambdaMineralWool,
        );
        return <EnvelopeLayer>[
          shellLayers[0], // ГКЛ внутри
          EnvelopeLayer(
              name: 'Минераловатная плита (базальт)',
              thicknessMm: insulMm,
              lambda: insulLambdaMineralWool),
          shellLayers[1], // OSB снаружи
        ];
      case 'aerated':
        // Газобетон обычно не требует наружного утеплителя при толщине
        // 400+ мм. Проверяем и при необходимости добавляем минвату.
        final base = <EnvelopeLayer>[
          const EnvelopeLayer(
              name: 'Штукатурка ц/п внутр.',
              thicknessMm: 10,
              lambda: 0.93),
          EnvelopeLayer(
              name: 'Газобетон D500', thicknessMm: thicknessMm, lambda: 0.16),
          const EnvelopeLayer(
              name: 'Декоративная штукатурка',
              thicknessMm: 8,
              lambda: 0.85),
        ];
        final insulMm = _suggestInsulationThicknessMm(
          climate: climate,
          envelope: BuildingEnvelope.wall,
          nonInsulationLayers: base,
          insulationLambda: insulLambdaMineralWool,
        );
        if (insulMm <= 0) return base;
        return <EnvelopeLayer>[
          base[0],
          base[1],
          EnvelopeLayer(
              name: 'Минвата фасадная',
              thicknessMm: insulMm,
              lambda: insulLambdaMineralWool),
          base[2],
        ];
      case 'brick':
        final base = <EnvelopeLayer>[
          const EnvelopeLayer(
              name: 'Штукатурка ц/п внутр.',
              thicknessMm: 15,
              lambda: 0.93),
          EnvelopeLayer(
              name: 'Кирпич полнотелый ρ=1800',
              thicknessMm: thicknessMm,
              lambda: 0.81),
          const EnvelopeLayer(
              name: 'Штукатурка фасадная',
              thicknessMm: 8,
              lambda: 0.85),
        ];
        final insulMm = _suggestInsulationThicknessMm(
          climate: climate,
          envelope: BuildingEnvelope.wall,
          nonInsulationLayers: base,
          insulationLambda: insulLambdaMineralWool,
        );
        if (insulMm <= 0) return base;
        return <EnvelopeLayer>[
          base[0],
          base[1],
          EnvelopeLayer(
              name: 'Минвата фасадная',
              thicknessMm: insulMm,
              lambda: insulLambdaMineralWool),
          base[2],
        ];
      case 'expandedClay':
        final base = <EnvelopeLayer>[
          const EnvelopeLayer(
              name: 'Штукатурка ц/п внутр.',
              thicknessMm: 15,
              lambda: 0.93),
          EnvelopeLayer(
              name: 'Керамзитобетонный блок D1200',
              thicknessMm: thicknessMm,
              lambda: 0.46),
          const EnvelopeLayer(
              name: 'Штукатурка фасадная',
              thicknessMm: 8,
              lambda: 0.85),
        ];
        final insulMm = _suggestInsulationThicknessMm(
          climate: climate,
          envelope: BuildingEnvelope.wall,
          nonInsulationLayers: base,
          insulationLambda: insulLambdaMineralWool,
        );
        if (insulMm <= 0) return base;
        return <EnvelopeLayer>[
          base[0],
          base[1],
          EnvelopeLayer(
              name: 'Минвата фасадная',
              thicknessMm: insulMm,
              lambda: insulLambdaMineralWool),
          base[2],
        ];
      case 'timber':
      case 'log':
        final base = <EnvelopeLayer>[
          EnvelopeLayer(
              name: 'Брус/бревно сосна',
              thicknessMm: thicknessMm,
              lambda: 0.18),
        ];
        // В деревянном доме часто оставляют стену открытой (без утепления).
        // Если стена не проходит — в записке отметим это в выводах,
        // но утеплитель не подкладываем автоматически: для бруса это
        // меняет архитектуру.
        return base;
      default:
        return [
          EnvelopeLayer(
              name: 'Стеновой материал',
              thicknessMm: thicknessMm,
              lambda: 0.30),
        ];
    }
  }

  /// Состав покрытия (кровельный пирог): пароизоляция, утеплитель,
  /// диффузионная мембрана, обрешётка.
  ///
  /// П.1 v43: толщина минваты подбирается по климату.
  static List<EnvelopeLayer> _roofLayers({required ClimateZone climate}) {
    const insulLambda = 0.045;
    final shell = <EnvelopeLayer>[
      const EnvelopeLayer(
          name: 'Гипсокартон/ОСП внутр.', thicknessMm: 12, lambda: 0.21),
      const EnvelopeLayer(
          name: 'Доска обрешётки сосна', thicknessMm: 25, lambda: 0.18),
    ];
    final insulMm = _suggestInsulationThicknessMm(
      climate: climate,
      envelope: BuildingEnvelope.roof,
      nonInsulationLayers: shell,
      insulationLambda: insulLambda,
    );
    return <EnvelopeLayer>[
      shell[0],
      EnvelopeLayer(
          name: 'Минвата (базальт)',
          thicknessMm: insulMm,
          lambda: insulLambda),
      shell[1],
    ];
  }

  static Future<Uint8List> build({required HouseProject project}) async {
    final regularData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final climate = _climateForProject(project);
    final wallCode = project.walls.material ??
        project.brief.wallMaterial?.name ??
        'aerated';
    final wallThicknessMm = (project.walls.thickness ?? 400).toDouble();
    final wallLambda = _wallLambda(wallCode);
    final wallLayers =
        _wallLayers(wallCode, wallThicknessMm, climate: climate);
    final wallResult = ThermalCalculator.compute(
      climate: climate,
      envelope: BuildingEnvelope.wall,
      layers: wallLayers,
    );
    final roofLayers = _roofLayers(climate: climate);
    final roofResult = ThermalCalculator.compute(
      climate: climate,
      envelope: BuildingEnvelope.roof,
      layers: roofLayers,
    );

    // Расчёт пирога пола 1-го этажа над неотапливаемым подпольем
    // (фундаментным пространством или грунтом). Слои — без утеплителя
    // на пробу, чтобы получить требуемое R₀ᵗᵖ и подобрать δ_утеп.
    final floorBaseLayers = const <EnvelopeLayer>[
      EnvelopeLayer(
        name: 'Ламинат 33 класс',
        thicknessMm: 8,
        lambda: 0.18,
      ),
      EnvelopeLayer(
        name: 'Подложка вспен. полиэтилен',
        thicknessMm: 3,
        lambda: 0.038,
      ),
      EnvelopeLayer(
        name: 'Стяжка ЦПС М150',
        thicknessMm: 50,
        lambda: 0.93,
      ),
    ];
    const floorInsulLambda = 0.034; // ЭППС / Пеноплэкс
    final floorInsulMm = _suggestInsulationThicknessMm(
      climate: climate,
      envelope: BuildingEnvelope.floorOverUnheated,
      nonInsulationLayers: floorBaseLayers,
      insulationLambda: floorInsulLambda,
      alphaIn: 8.7,
      alphaOut: 6.0,
    );
    final floorLayers = <EnvelopeLayer>[
      ...floorBaseLayers,
      EnvelopeLayer(
        name: 'Утеплитель ЭППС (Пеноплэкс)',
        thicknessMm: floorInsulMm,
        lambda: floorInsulLambda,
      ),
    ];
    final floorResult = ThermalCalculator.compute(
      climate: climate,
      envelope: BuildingEnvelope.floorOverUnheated,
      layers: floorLayers,
      alphaIn: 8.7,
      alphaOut: 6.0,
    );

    final pdf = pw.Document(
      title: 'ПЗ. Теплотехнический расчёт — ${project.name}',
      author: 'Construction Calculator',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      header: (ctx) => _header(project, regular, 'Теплотехнический расчёт'),
      footer: (ctx) => _footer(ctx, regular),
      build: (ctx) => [
        _title(project, bold, regular, climate),
        pw.SizedBox(height: 12),
        _section('1. Обозначения и источники', bold),
        _glossary(regular, bold),
        pw.SizedBox(height: 12),
        _section('2. Исходные данные', bold),
        _inputs(climate, project, wallCode, wallThicknessMm, wallLambda,
            regular, bold),
        pw.SizedBox(height: 12),
        _section('3. ГСОП и требуемое R₀ᵗᵖ для наружной стены', bold),
        ..._stepsBlock(wallResult.steps.take(2).toList(), regular, bold),
        pw.SizedBox(height: 8),
        _section('4. Состав наружной стены — расчёт фактического R₀', bold),
        _layersTable(wallLayers, regular, bold),
        pw.SizedBox(height: 6),
        ..._stepsBlock(wallResult.steps.skip(2).toList(), regular, bold),
        pw.SizedBox(height: 12),
        _section('5. Состав покрытия (кровельного пирога) — R₀', bold),
        _layersTable(roofLayers, regular, bold),
        pw.SizedBox(height: 6),
        ..._stepsBlock(roofResult.steps, regular, bold),
        pw.SizedBox(height: 12),
        _section(
            '6. Состав пола 1-го этажа (пирог пола) — '
            'расчёт фактического R₀',
            bold),
        _floorPieIntro(climate, floorInsulMm, regular, bold),
        pw.SizedBox(height: 4),
        _layersTable(floorLayers, regular, bold),
        pw.SizedBox(height: 6),
        ..._stepsBlock(floorResult.steps, regular, bold),
        pw.SizedBox(height: 12),
        _section('7. Энергопаспорт. Годовые теплопотери', bold),
        _energyPassport(project, climate, wallResult, roofResult,
            regular, bold),
        pw.SizedBox(height: 12),
        _section('8. Выводы', bold),
        _conclusion(wallResult, roofResult, regular, bold),
      ],
    ));

    return pdf.save();
  }

  /// Энергопаспорт (п.1 v43): оценка годовых теплопотерь через
  /// наружные стены и покрытие по упрощённой формуле:
  ///
  ///   Q_год = (tвн − tот.ср) · zот · 24 / R₀ · A / 1000  (кВт·ч/год),
  ///
  /// где A — площадь конструкции (м²). Делим на 1000 для перевода
  /// Вт·ч → кВт·ч. Это соответствует методике приложения Д
  /// СП 50.13330 (упрощённый учёт).
  ///
  /// Также показываем удельную характеристику расхода тепловой
  /// энергии q, кВт·ч/(м²·год), и сравниваем её с нормативом для
  /// малоэтажного жилого здания (СП 50.13330 табл. 14):
  ///   • базовый норматив q₀ = 130 кВт·ч/(м²·год) для одноэтажных,
  ///     90 для двух-трёх этажных.
  static pw.Widget _energyPassport(
    HouseProject project,
    ClimateZone climate,
    ThermalResult wall,
    ThermalResult roof,
    pw.Font regular,
    pw.Font bold,
  ) {
    final brief = project.brief;
    final w = brief.footprintWidth ?? 0;
    final l = brief.footprintLength ?? 0;
    final floors = (brief.floors ?? 1).clamp(1, 5);
    final wallH = project.walls.height ?? 2.8;
    // Площадь стен — периметр × высота × этажи, минус остекление 12%.
    final perimeter = 2 * (w + l);
    final wallArea = perimeter * wallH * floors * 0.88;
    final roofArea = w * l * 1.10; // с учётом свесов и уклона
    final dt = climate.tIn - climate.tHeatAvg;
    final hours = climate.heatingDays * 24;
    final qWallKwh = wall.rActual > 0
        ? dt * hours * wallArea / wall.rActual / 1000
        : 0.0;
    final qRoofKwh = roof.rActual > 0
        ? dt * hours * roofArea / roof.rActual / 1000
        : 0.0;
    final totalKwh = qWallKwh + qRoofKwh;
    // Площадь дома (м²) — по ТЗ.
    final houseArea = brief.targetArea ?? (w * l * floors);
    final qSpec = houseArea > 0 ? totalKwh / houseArea : 0.0;
    // Норматив для одноэтажных 130, для 2–3-этажных 90 кВт·ч/(м²·год).
    final qNorm = floors >= 2 ? 90.0 : 130.0;
    final passes = qSpec <= qNorm;
    String row(String name, String val) => '$name: $val';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Расчёт тепловых потерь через наружные ограждения за '
          'отопительный период (упрощённый по СП 50.13330 прил. Д):',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          row('Площадь наружных стен', '${wallArea.toStringAsFixed(0)} м²'),
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.Text(
          row('Площадь покрытия (с учётом уклона)',
              '${roofArea.toStringAsFixed(0)} м²'),
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.Text(
          row('Δt = (tвн − tот.ср) · zот · 24',
              '${dt.toStringAsFixed(1)} · ${climate.heatingDays.toStringAsFixed(0)} · 24 = '
              '${(dt * hours).toStringAsFixed(0)} °C·ч'),
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          row('Q_стены',
              '${qWallKwh.toStringAsFixed(0)} кВт·ч/год '
              '(R₀ = ${wall.rActual.toStringAsFixed(2)} м²·°C/Вт)'),
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.Text(
          row('Q_покрытие',
              '${qRoofKwh.toStringAsFixed(0)} кВт·ч/год '
              '(R₀ = ${roof.rActual.toStringAsFixed(2)} м²·°C/Вт)'),
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          row('Итого по ограждениям',
              '${totalKwh.toStringAsFixed(0)} кВт·ч/год'),
          style: pw.TextStyle(fontSize: 11, font: bold),
        ),
        pw.Text(
          row('Удельная характеристика q',
              '${qSpec.toStringAsFixed(0)} кВт·ч/(м²·год); '
              'норма ≤ ${qNorm.toStringAsFixed(0)} — ${passes ? "выполняется" : "НЕ выполняется"}'),
          style: pw.TextStyle(fontSize: 11, font: bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Примечание: учтены теплопотери только через наружные стены '
          'и покрытие; вентиляция, окна, двери и пол по грунту не '
          'включены — они даются в полном энергопаспорте отдельно.',
          style: pw.TextStyle(
              fontSize: 9, font: regular, color: PdfColors.blueGrey700),
        ),
      ],
    );
  }

  static pw.Widget _title(HouseProject project, pw.Font bold,
      pw.Font regular, ClimateZone climate) {
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, "0")}.'
        '${now.month.toString().padLeft(2, "0")}.${now.year}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ПОЯСНИТЕЛЬНАЯ ЗАПИСКА',
            style: pw.TextStyle(fontSize: 16, font: bold)),
        pw.SizedBox(height: 4),
        pw.Text('Теплотехнический расчёт ограждающих конструкций',
            style: pw.TextStyle(fontSize: 12, font: regular)),
        pw.SizedBox(height: 8),
        pw.Text('Объект: ${project.name}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Регион: ${climate.city}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Дата: $date',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.SizedBox(height: 6),
        pw.Text(
          'Расчёт выполнен по СП 50.13330.2012 «Тепловая защита зданий», '
          'СП 131.13330.2020 «Строительная климатология» и '
          'ГОСТ 30494-2011 «Здания жилые и общественные. Параметры микроклимата».',
          style: pw.TextStyle(fontSize: 10, font: regular),
        ),
      ],
    );
  }

  static pw.Widget _section(String text, pw.Font bold) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 12, font: bold)),
      );

  /// Расшифровка обозначений.  Каждая величина — название по-русски,
  /// единица измерения, и где её взять (СП-пункт).
  static pw.Widget _glossary(pw.Font regular, pw.Font bold) {
    final entries = <List<String>>[
      [
        'tвн',
        'Расчётная температура внутреннего воздуха, °C',
        'ГОСТ 30494-2011 табл. 1 (для жилых: 20 °C для жилых комнат, 22 °C для угловых)'
      ],
      [
        'tот.ср',
        'Средняя температура наружного воздуха за отопительный период, °C',
        'СП 131.13330.2020 табл. 3.1, столбец 11'
      ],
      [
        'zот',
        'Продолжительность отопительного периода, сут',
        'СП 131.13330.2020 табл. 3.1, столбец 13'
      ],
      [
        'Dd (ГСОП)',
        'Градусо-сутки отопительного периода, °C·сут — характеристика суровости климата',
        'СП 50.13330.2012 п. 5.2, формула (5.2): Dd = (tвн − tот.ср) · zот'
      ],
      [
        'R₀ᵗᵖ',
        'Требуемое (нормируемое) сопротивление теплопередаче, м²·°C/Вт',
        'СП 50.13330.2012 п. 5.2, формула (5.1) и табл. 3: R₀ᵗᵖ = a·Dd + b. '
            'Коэффициенты a, b — из табл. 3 для жилых зданий: '
            'стена a=0.00035, b=1.4; покрытие a=0.0005, b=2.2.'
      ],
      [
        'R₀',
        'Фактическое сопротивление теплопередаче многослойной конструкции, м²·°C/Вт',
        'СП 50.13330.2012 формула (Е.6): R₀ = 1/αв + ΣRᵢ + 1/αн'
      ],
      [
        'αв',
        'Коэффициент тепловосприятия внутренней поверхности ограждения, '
            'Вт/(м²·°C). Принят 8.7 (стены, перекрытия)',
        'СП 50.13330.2012 табл. 4'
      ],
      [
        'αн',
        'Коэффициент теплоотдачи наружной поверхности ограждения, '
            'Вт/(м²·°C). Принят 23 (для стен, скатов кровли)',
        'СП 50.13330.2012 табл. 6'
      ],
      [
        'δ',
        'Толщина слоя ограждения, м (в формулах используется в метрах; '
            'в таблицах — в мм)',
        '—'
      ],
      [
        'λ',
        'Расчётный коэффициент теплопроводности материала, Вт/(м·°C)',
        'СП 50.13330.2012 приложение Т (для условий эксплуатации Б)'
      ],
      [
        'Rᵢ',
        'Сопротивление теплопередаче одного слоя, м²·°C/Вт',
        'СП 50.13330.2012 п. Е.5: Rᵢ = δᵢ / λᵢ'
      ],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(2.6),
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

  static pw.Widget _inputs(
    ClimateZone climate,
    HouseProject project,
    String wallCode,
    double wallThickness,
    double lambda,
    pw.Font regular,
    pw.Font bold,
  ) {
    final rows = <List<String>>[
      [
        'Город',
        climate.city,
        'СП 131.13330.2020',
      ],
      [
        'tвн (расчётная температура внутреннего воздуха)',
        '${climate.tIn.toStringAsFixed(0)} °C',
        'ГОСТ 30494-2011 табл. 1',
      ],
      [
        'tот.ср (средняя температура отопит. периода)',
        '${climate.tHeatAvg.toStringAsFixed(1)} °C',
        'СП 131.13330.2020 табл. 3.1',
      ],
      [
        'zот (продолжительность отопит. периода)',
        '${climate.heatingDays.toStringAsFixed(0)} сут',
        'СП 131.13330.2020 табл. 3.1',
      ],
      [
        'Dd (ГСОП)',
        '${climate.gsop.toStringAsFixed(0)} °C·сут',
        'вычислено: (tвн − tот.ср) · zот',
      ],
      [
        'Тип стены',
        _wallTitle(wallCode),
        'выбор пользователя',
      ],
      [
        'Толщина основного слоя стены',
        '${wallThickness.toStringAsFixed(0)} мм',
        'из проекта',
      ],
      [
        'λ основного слоя',
        '${lambda.toStringAsFixed(3)} Вт/(м·°C)',
        'СП 50.13330.2012 прил. Т',
      ],
      [
        'αв (внутр. теплоотдача)',
        '8.7 Вт/(м²·°C)',
        'СП 50.13330.2012 табл. 4',
      ],
      [
        'αн (наружн. теплоотдача)',
        '23 Вт/(м²·°C)',
        'СП 50.13330.2012 табл. 6',
      ],
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

  /// Сводная таблица слоёв ограждения: материал, δ, λ, R = δ/λ.
  /// Развёрнутое обоснование расчёта пирога пола 1-го этажа: формулы
  /// R₀ᵗᵖ, δ_утеп, ссылки на СП. Полностью на русском, без сокращений.
  static pw.Widget _floorPieIntro(
    ClimateZone climate,
    double insulMm,
    pw.Font regular,
    pw.Font bold,
  ) {
    final lines = <String>[
      '6.1. Конструкция пола 1-го этажа рассматривается как ограждение '
          'над неотапливаемым подпольем (BuildingEnvelope.floorOverUnheated). '
          'Расчёт выполняется по СП 50.13330.2024 с использованием тех же '
          'формул, что и для стен и покрытия (см. п. 3).',
      '',
      '6.2. Требуемое сопротивление теплопередаче по таблице 3 СП 50.13330: '
          'для пола над неотапливаемым подпольем коэффициенты a = 0,00045, '
          'b = 1,9. Расчёт ГСОП выполнен по формуле 5.2 СП 50.13330: '
          'Dd = (tвн − tот.ср) · zот, где tвн = 20 °C (ГОСТ 30494, '
          'жилое помещение).',
      '',
      '6.3. Климатические параметры для города ${climate.city} '
          '(СП 131.13330.2020 табл. 3.1):',
      '   • продолжительность отопительного периода '
          'zот = ${climate.heatingDays.toStringAsFixed(0)} сут;',
      '   • средняя температура отопительного периода '
          'tот.ср = ${climate.tHeatAvg.toStringAsFixed(1)} °C;',
      '   • ГСОП Dd = (20 − ${climate.tHeatAvg.toStringAsFixed(1)}) · '
          '${climate.heatingDays.toStringAsFixed(0)} = '
          '${climate.gsop.toStringAsFixed(0)} °C·сут.',
      '',
      '6.4. Толщина утеплителя ЭППС подобрана по формуле:',
      '   δ_утеп ≥ λ_утеп · (R₀ᵗᵖ − 1/αв − ΣRбаз − 1/αн),',
      '   где αв = 8,7 Вт/(м²·°C) — коэффициент теплоотдачи внутренней '
          'поверхности (СП 50.13330, табл. 4);',
      '   αн = 6,0 Вт/(м²·°C) — пониженный коэффициент теплоотдачи '
          'нижней поверхности пола над неотапливаемым подпольем '
          '(СП 50.13330, табл. 6, прим. 1);',
      '   λ_утеп = 0,034 Вт/(м·°C) — теплопроводность ЭППС в условиях '
          'эксплуатации Б (СП 50.13330, прил. Т);',
      '   ΣRбаз — сопротивление слоёв, не считая утеплителя.',
      '',
      '6.5. По расчёту получаем толщину утеплителя '
          'δ_утеп = ${insulMm.toStringAsFixed(0)} мм '
          '(округлено вверх до кратного 50 мм — стандартный '
          'модуль плит ЭППС).',
      '',
      '6.6. Гидроизоляция оклеечная (2 слоя рубероида с нахлёстом '
          '100 мм по СП 17.13330, п. 5.1.6) принята непосредственно '
          'под утеплителем для отсечки капиллярной влаги от грунта '
          'или подпольного пространства; в общий R₀ её сопротивление '
          'не включается (тонкая плёнка).',
      '',
      '6.7. Стяжка ЦПС М150 толщиной 50 мм армируется сеткой Ø3 Вр-1 '
          '100×100 (СП 71.13330, п. 8.6); зазор от стен 8…10 мм '
          'заполняется демпферной лентой и закрывается плинтусом.',
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          pw.Text(line,
              style: pw.TextStyle(fontSize: 9.5, font: regular)),
      ],
    );
  }

  static pw.Widget _layersTable(
      List<EnvelopeLayer> layers, pw.Font regular, pw.Font bold) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.5),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final h in const [
              'Слой (изнутри → наружу)',
              'δ, мм',
              'λ, Вт/(м·°C)',
              'R = δ/λ, м²·°C/Вт',
            ])
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(h,
                    style: pw.TextStyle(fontSize: 9.5, font: bold)),
              ),
          ],
        ),
        for (final l in layers)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(l.name,
                  style: pw.TextStyle(fontSize: 10, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(l.thicknessMm.toStringAsFixed(0),
                  style: pw.TextStyle(fontSize: 10, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(l.lambda.toStringAsFixed(3),
                  style: pw.TextStyle(fontSize: 10, font: regular)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(l.r.toStringAsFixed(3),
                  style: pw.TextStyle(fontSize: 10, font: bold)),
            ),
          ]),
      ],
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

  static pw.Widget _conclusion(ThermalResult wall, ThermalResult roof,
      pw.Font regular, pw.Font bold) {
    final wallOk = wall.passes ? 'выполняется' : 'НЕ выполняется';
    final roofOk = roof.passes ? 'выполняется' : 'НЕ выполняется';
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Стена. R₀ = ${wall.rActual.toStringAsFixed(2)} м²·°C/Вт ≥ '
            'R₀ᵗᵖ = ${wall.rReq.toStringAsFixed(2)} м²·°C/Вт — условие $wallOk.',
            style: pw.TextStyle(fontSize: 10, font: regular),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Покрытие. R₀ = ${roof.rActual.toStringAsFixed(2)} м²·°C/Вт ≥ '
            'R₀ᵗᵖ = ${roof.rReq.toStringAsFixed(2)} м²·°C/Вт — условие $roofOk.',
            style: pw.TextStyle(fontSize: 10, font: regular),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Если условие не выполняется — увеличить толщину утеплителя '
            'или выбрать материал с меньшим λ. Все λ — для условий '
            'эксплуатации Б (СП 50.13330.2012 прил. Т).',
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

  // ignore: unused_element
  static pw.Widget _wallMaterialPlaceholder(WallMaterial _) => pw.SizedBox();
}
