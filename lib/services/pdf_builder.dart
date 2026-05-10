import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/materials_library.dart';
import '../data/wall_materials.dart';
import '../models/building_dimensions.dart';
import '../models/building_footprint.dart';
import '../models/drawing.dart';
import '../models/floor_plan.dart';
import '../models/foundation.dart';
import '../models/foundation_plan.dart';
import '../models/furniture_symbol.dart';
import '../models/house_project.dart';
import '../models/organization_settings.dart';
import 'building3d_generator.dart';
import 'building3d_renderer.dart';
import 'foundation_plan_generator.dart';
import 'furniture/placement_engine.dart';
import 'material_volumes.dart';
import 'pdf_additional_plans.dart';
import 'pdf_builder_materials.dart';
import 'pdf_catalog_card.dart';
import 'pdf_detail_nodes.dart';
import 'pdf_engineering_specs.dart';
import 'pdf_general_data.dart';
import 'pdf_site_plan.dart';
import 'pdf_title_block.dart';
import 'rafter_section_picker.dart';
import 'roof_plan_geometry.dart';
import 'room_palette.dart';

/// Сборка комплекта планов в PDF (формат A3, ландшафт). На каждый
/// лист — один [FloorPlan] (схематический план этажа). В заголовке —
/// название проекта, номер версии, дата. Внизу штамп с реквизитами.
class PdfBuilder {
  PdfBuilder._();

  static Future<Uint8List> buildBatch({
    required HouseProject project,
    required List<Drawing> drawings,
    required int versionNumber,
    OrganizationSettings? organization,
  }) async {
    // Берём только листы со схематическими планами; именно они содержат
    // FloorPlan в payload и имеют смысл на чертеже.
    final plans = <(Drawing, FloorPlan)>[];
    for (final d in drawings) {
      if (d.kind != DrawingKind.schematicPlan) continue;
      final plan = FloorPlan.tryDecode(d.payload);
      if (plan != null) plans.add((d, plan));
    }

    // Загружаем кириллический шрифт из ассетов. Встроенный Helvetica
    // умеет только Latin-1 и падает с ArgumentError на «Лестница» / «Спальня».
    final regularData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final pdf = pw.Document(
      title: '${project.name} — Версия №$versionNumber',
      author: 'Construction Calculator',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    // Регистрируем PdfTtfFont в документе и используем напрямую в
    // PdfGraphics painter — иначе canvas.defaultFont вернёт Helvetica
    // (он добавляется первым) и кириллица упадёт.
    final pdfTtfRegular = PdfTtfFont(pdf.document, regularData);
    final pdfTtfBold = PdfTtfFont(pdf.document, boldData);

    if (plans.isEmpty) {
      pdf.addPage(_emptyPage(regular));
      return pdf.save();
    }

    // Составляем ведомость чертежей: сначала Общие данные (АР-1/АР-2),
    // затем схематические планы этажей (АР-3, АР-4, …), затем план
    // фундамента (КЖ-1) и план кровли (если у проекта задан тип кровли),
    // далее — разрезы, фасады, аксонометрия и спецификация.
    final hasRoofPlan = project.roof.isFilled;
    // План фундамента собирается из реальных расчётов cc_engine (СП 22 /
    // СП 20 / СП 63). Если фундамент не выбран или ТЗ не заполнено —
    // FoundationPlanGenerator возвращает null и лист не добавляется.
    final foundationPlan = FoundationPlanGenerator.generate(project);
    final hasFoundationPlan = foundationPlan != null;

    // АР-1 — ведомость + ТЭП; АР-2 — общие указания + объёмно-планир. +
    // пожарные решения; АР-3 — условные обозначения; АР-4 — перечень
    // ссылочных нормативных документов. Планы этажей начинаются с АР-5.
    const generalDataSheets = 4;
    // Итерация 2: после планов этажей идут план перегородок и план полов;
    // в зависимости от ТЗ — план подвала / технического подполья / чердака;
    // отдельные листы — схема балок (КД-1) и стропил (КД-2).
    final hasBasementPlan = project.brief.hasBasement == true;
    final foundationType = project.foundation.type;
    final hasSubfloorPlan = !hasBasementPlan &&
        (foundationType == FoundationType.pile ||
            foundationType == FoundationType.pileWithGrillage ||
            foundationType == FoundationType.columnar);
    final hasMansardFlag = project.brief.hasMansard == true;
    final hasAtticPlan = hasRoofPlan && !hasMansardFlag;
    final hasRaftersPlan = hasRoofPlan;

    // Очередь листов согласно ГОСТ Р 21.101-2020 (основные комплекты
    // рабочих чертежей): сначала весь комплект АР подряд, затем КР/КЖ,
    // затем КД, затем узлы (У-1…У-8) и в конце — раздел освидетельствования
    // (ОР). Сквозная нумерация (Лист N из M) проставляется по физическому
    // порядку страниц в PDF.
    // С v61 разрез и схема стропил объединены в один лист КД-2;
    // отдельного КД-2.1 больше нет (см. raftersCombinedPage). Для
    // плоской кровли raftersCombinedPage сам выводит короткую справку.
    final hasSteelBill =
        hasFoundationPlan && foundationType != FoundationType.pile;
    final hasStaircaseSheet = project.staircase.isFilled ||
        project.brief.hasStaircase == true ||
        (project.brief.floors ?? 1) > 1;

    // === Комплект АР ===
    // АР-1..АР-4 — общие данные; далее АР-(N+5)+ — планы этажей; затем
    // перегородки, полы, кровля/чердак, разрезы 1-1/2-2, фасады,
    // общий вид (аксонометрия), ведомость отделки и спецификация.
    int seq = generalDataSheets; // последний АР общих данных
    seq += plans.length; // планы этажей
    final partitionsSheetNumber = ++seq;
    final floorTypesSheetNumber = ++seq;
    final roofSheetNumber = hasRoofPlan ? ++seq : seq + 1;
    final atticSheetNumber = hasAtticPlan ? ++seq : seq + 1;
    final section1SheetNumber = ++seq;
    final section2SheetNumber = ++seq;
    final facadesStartSheetNumber = seq + 1;
    seq += 4;
    final axonoSheetNumber = ++seq;
    final roomFinishSheetNumber = ++seq;
    final materialsSheetNumber = ++seq;

    // === Комплект КР/КЖ ===
    final foundationSheetNumber = hasFoundationPlan ? ++seq : seq + 1;
    final basementSheetNumber = hasBasementPlan ? ++seq : seq + 1;
    final subfloorSheetNumber = hasSubfloorPlan ? ++seq : seq + 1;
    final foundationSectionSheetNumber =
        hasFoundationPlan ? ++seq : seq + 1;
    final steelBillSheetNumber = hasSteelBill ? ++seq : seq + 1;

    // === Комплект КД ===
    final beamsSheetNumber = ++seq; // КД-1, всегда
    // С v61 КД-2 — объединённый лист (разрез фермы + план + узлы +
    // спецификация); прежний отдельный лист КД-2.1 удалён.
    final raftersSheetNumber = hasRaftersPlan ? ++seq : seq + 1;
    final staircaseSpecSheetNumber =
        hasStaircaseSheet ? ++seq : seq + 1;

    // === Узлы и детали (У-1…У-8) ===
    final eaveNodeSheetNumber = ++seq;
    final ridgeNodeSheetNumber = hasRoofPlan ? ++seq : seq + 1;
    final windowJambNodeSheetNumber = ++seq;
    final rafterMauerlatNodeSheetNumber = hasRoofPlan ? ++seq : seq + 1;
    final plinthNodeSheetNumber = ++seq;
    final floorBeamNodeSheetNumber = ++seq;
    final roofPieSheetNumber = hasRoofPlan ? ++seq : seq + 1;
    final floorPieNodeSheetNumber = ++seq;

    // === ОР (Освидетельствование скрытых работ) ===
    final hiddenWorksSheetNumber = ++seq;
    final sheets = <SheetIndexEntry>[
      // === Комплект АР: архитектурные решения ===
      const SheetIndexEntry(code: 'АР-1', title: 'Общие данные (ведомость).'),
      const SheetIndexEntry(
        code: 'АР-2',
        title: 'Общие указания. Объёмно-планировочные и пожарные решения.',
      ),
      const SheetIndexEntry(
        code: 'АР-3',
        title: 'Условные обозначения.',
      ),
      const SheetIndexEntry(
        code: 'АР-4',
        title: 'Перечень ссылочных нормативных документов.',
      ),
      for (int i = 0; i < plans.length; i++)
        SheetIndexEntry(
          code: 'АР-${i + generalDataSheets + 1}',
          title: '${plans[i].$2.floorLabel} — схематический план.',
        ),
      SheetIndexEntry(
        code: 'АР-$partitionsSheetNumber',
        title: 'План расположения перегородок (1 этаж).',
      ),
      SheetIndexEntry(
        code: 'АР-$floorTypesSheetNumber',
        title: 'План полов с экспликацией типов П1…П4.',
      ),
      if (hasRoofPlan)
        SheetIndexEntry(
          code: 'АР-$roofSheetNumber',
          title: 'План кровли.',
        ),
      if (hasAtticPlan)
        SheetIndexEntry(
          code: 'АР-$atticSheetNumber',
          title: 'План холодного чердака.',
        ),
      SheetIndexEntry(
        code: 'АР-$section1SheetNumber',
        title: 'Разрез 1-1 (поперечный).',
      ),
      SheetIndexEntry(
        code: 'АР-$section2SheetNumber',
        title: 'Разрез 2-2 (продольный).',
      ),
      SheetIndexEntry(
        code: 'АР-$facadesStartSheetNumber',
        title: 'Фасад в осях 1–N (южный).',
      ),
      SheetIndexEntry(
        code: 'АР-${facadesStartSheetNumber + 1}',
        title: 'Фасад в осях N–1 (северный).',
      ),
      SheetIndexEntry(
        code: 'АР-${facadesStartSheetNumber + 2}',
        title: 'Фасад в осях А–Д (восточный).',
      ),
      SheetIndexEntry(
        code: 'АР-${facadesStartSheetNumber + 3}',
        title: 'Фасад в осях Д–А (западный).',
      ),
      SheetIndexEntry(
        code: 'АР-$axonoSheetNumber',
        title: 'Общий вид (аксонометрия).',
      ),
      SheetIndexEntry(
        code: 'АР-$roomFinishSheetNumber',
        title: 'Ведомость отделки помещений.',
      ),
      SheetIndexEntry(
        code: 'АР-$materialsSheetNumber',
        title: 'Спецификация материалов и сортаментов.',
      ),
      // === Комплект КР/КЖ: фундамент и ж/б конструкции ===
      if (hasFoundationPlan)
        SheetIndexEntry(
          code: 'КР-1',
          title: 'План фундамента (${foundationPlan.typeLabel}).',
        ),
      if (hasBasementPlan)
        const SheetIndexEntry(
          code: 'КР-2',
          title: 'План подвала.',
        ),
      if (hasSubfloorPlan)
        SheetIndexEntry(
          code: hasBasementPlan ? 'КР-3' : 'КР-2',
          title: 'План технического подполья.',
        ),
      if (hasFoundationPlan)
        const SheetIndexEntry(
          code: 'КЖ-1',
          title: 'Сечение и армирование фундамента.',
        ),
      if (hasSteelBill)
        const SheetIndexEntry(
          code: 'КЖ-2',
          title: 'Ведомость расхода стали на монолитные конструкции.',
        ),
      // === Комплект КД: деревянные/металлические конструкции и лестницы ===
      const SheetIndexEntry(
        code: 'КД-1',
        title: 'Схема расположения балок перекрытия.',
      ),
      if (hasRaftersPlan)
        const SheetIndexEntry(
          code: 'КД-2',
          title: 'Стропильная система: разрез фермы (со всеми элементами '
              '1…11), узлы «А»/«Б», план стропил, спецификация и расчёт.',
        ),
      if (hasStaircaseSheet)
        const SheetIndexEntry(
          code: 'КД-3',
          title: 'Спецификация элементов лестницы (марш ЛМ-1).',
        ),
      // === Узлы и детали (У-1…У-8) ===
      const SheetIndexEntry(
        code: 'У-1',
        title: 'Узел У-1. Карнизный свес (примыкание кровли к стене).',
      ),
      if (hasRoofPlan)
        const SheetIndexEntry(
          code: 'У-2',
          title: 'Узел У-2. Конёк скатной кровли.',
        ),
      const SheetIndexEntry(
        code: 'У-3',
        title: 'Узел У-3. Оконный откос (монтажный шов и утепление).',
      ),
      if (hasRoofPlan)
        const SheetIndexEntry(
          code: 'У-4',
          title: 'Узел У-4. Опирание стропилины на мауэрлат.',
        ),
      const SheetIndexEntry(
        code: 'У-5',
        title: 'Узел У-5. Цоколь, отмостка, гидроизоляция.',
      ),
      const SheetIndexEntry(
        code: 'У-6',
        title: 'Узел У-6. Опирание балки перекрытия на стену.',
      ),
      if (hasRoofPlan)
        const SheetIndexEntry(
          code: 'У-7',
          title: 'Состав кровельного пирога (детально).',
        ),
      const SheetIndexEntry(
        code: 'У-8',
        title: 'Узел У-8. Пирог пола 1-го этажа '
            '(по теплотехническому расчёту).',
      ),
      // === Раздел освидетельствования ===
      const SheetIndexEntry(
        code: 'ОР-1',
        title: 'Перечень видов работ, подлежащих освидетельствованию '
            '(акты скрытых работ).',
      ),
    ];
    final totalSheets = sheets.length;

    // Титульный лист альбома (без штампа и без сквозного номера) —
    // печатается первой страницей PDF; его реквизиты редактируются
    // пользователем до генерации (project.titlePage).
    pdf.addPage(buildTitlePage(
      project: project,
      font: regular,
      fontBold: bold,
    ));

    // АР-0 — каталожная карточка (Phase-3a-2 §17.1.1). Идёт сразу за
    // титульным листом, не считается частью комплекта АР по нумерации
    // (totalSheets / sheetNumber не сдвигаются).
    final catalogPlans = [for (final p in plans) p.$2];
    pdf.addPage(PdfCatalogCard.buildPage(
      project: project,
      font: regular,
      fontBold: bold,
      pdfTtfRegular: pdfTtfRegular,
      plans: catalogPlans,
      versionNumber: versionNumber,
      organization: organization,
    ));

    // АР-1…АР-4 — Общие данные (ведомость, ПЗ, УГО, ссылочные документы).
    for (final page in PdfGeneralData.buildPages(
      project: project,
      sheets: sheets,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    )) {
      pdf.addPage(page);
    }

    // АР-0a — Схема планировочной организации земельного участка
    // (Phase-3a-2 §17.1.2). Вставляется между общими данными и планами
    // этажей. Сквозная нумерация листов АР-N не сдвигается (АР-0a, как
    // и АР-0, считается «вспомогательным» листом-обложкой).
    pdf.addPage(PdfSitePlan.buildPage(
      project: project,
      font: regular,
      fontBold: bold,
      pdfTtfRegular: pdfTtfRegular,
      versionNumber: versionNumber,
      plans: plans.map((p) => p.$2).toList(),
    ));

    // АР-5+ — планы этажей (после АР-1..АР-4 «Общие данные»).
    for (var i = 0; i < plans.length; i++) {
      final pair = plans[i];
      final sheetNumber = i + generalDataSheets + 1;
      pdf.addPage(_planPage(
        project: project,
        drawing: pair.$1,
        plan: pair.$2,
        versionNumber: versionNumber,
        sheetNumber: sheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        pdfFontBold: pdfTtfBold,
        organization: organization,
      ));
    }

    // План перегородок и план полов — на основании пятна 1-го этажа.
    final firstPlan = plans.first.$2;
    final refPlan = plans.last.$2;
    final allPlans = [for (final p in plans) p.$2];
    pdf.addPage(PdfAdditionalPlans.partitionsPage(
      project: project,
      plan: firstPlan,
      versionNumber: versionNumber,
      sheetNumber: partitionsSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    pdf.addPage(PdfAdditionalPlans.floorTypesPage(
      project: project,
      plan: firstPlan,
      versionNumber: versionNumber,
      sheetNumber: floorTypesSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));

    // План кровли (АР-N).
    if (hasRoofPlan) {
      final topPlan = plans.last.$2;
      pdf.addPage(_roofPage(
        project: project,
        plan: topPlan,
        versionNumber: versionNumber,
        sheetNumber: roofSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        pdfFontBold: pdfTtfBold,
        organization: organization,
      ));
    }

    // План холодного чердака (АР-?, если есть скатная кровля и нет мансарды).
    if (hasAtticPlan) {
      pdf.addPage(PdfAdditionalPlans.atticPage(
        project: project,
        topPlan: plans.last.$2,
        versionNumber: versionNumber,
        sheetNumber: atticSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }

    // Разрезы 1-1 (поперечный по X) и 2-2 (продольный по Y). Для
    // фасадов и аксонометрии отдаём весь список планов, чтобы
    // отрисовать реальные проёмы (`plan.openings`) на каждом этаже.
    pdf.addPage(_sectionPage(
      project: project,
      plan: refPlan,
      versionNumber: versionNumber,
      sheetNumber: section1SheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      sectionId: '1-1',
      isTransverse: true,
      organization: organization,
    ));
    pdf.addPage(_sectionPage(
      project: project,
      plan: refPlan,
      versionNumber: versionNumber,
      sheetNumber: section2SheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      sectionId: '2-2',
      isTransverse: false,
      organization: organization,
    ));

    // Фасады С/Ю/В/З.
    const facadeSpecs = [
      ('Ю', 'Южный фасад', 'FacadeSide.south'),
      ('С', 'Северный фасад', 'FacadeSide.north'),
      ('В', 'Восточный фасад', 'FacadeSide.east'),
      ('З', 'Западный фасад', 'FacadeSide.west'),
    ];
    for (var i = 0; i < facadeSpecs.length; i++) {
      final spec = facadeSpecs[i];
      pdf.addPage(_facadePage(
        project: project,
        plan: refPlan,
        plans: allPlans,
        versionNumber: versionNumber,
        sheetNumber: facadesStartSheetNumber + i,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        facadeCode: spec.$1,
        facadeTitle: spec.$2,
        side: _FacadeSide.values[i],
        organization: organization,
      ));
    }

    // Аксонометрия.
    pdf.addPage(_axonometricPage(
      project: project,
      plan: refPlan,
      plans: allPlans,
      versionNumber: versionNumber,
      sheetNumber: axonoSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));

    // АР-N: ведомость отделки помещений (последний лист АР).
    pdf.addPage(PdfEngineeringSpecs.roomFinishSchedulePage(
      project: project,
      plans: allPlans,
      versionNumber: versionNumber,
      sheetNumber: roomFinishSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      organization: organization,
    ));

    // АР-N: спецификация материалов и сортаментов (последний лист АР).
    pdf.addPage(_materialsSpecPage(
      project: project,
      foundationPlan: foundationPlan,
      floorPlans: allPlans,
      versionNumber: versionNumber,
      sheetNumber: materialsSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      organization: organization,
    ));

    // === Комплект КР/КЖ ===
    // КР-1: план фундамента (реальная геометрия из cc_engine).
    if (hasFoundationPlan) {
      pdf.addPage(_foundationPlanPage(
        project: project,
        model: foundationPlan,
        versionNumber: versionNumber,
        sheetNumber: foundationSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    // КР-2: план подвала.
    if (hasBasementPlan) {
      pdf.addPage(PdfAdditionalPlans.basementPage(
        project: project,
        plan: firstPlan,
        versionNumber: versionNumber,
        sheetNumber: basementSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        sheetCode: 'КР-2',
        organization: organization,
      ));
    }
    // КР-2/3: план технического подполья.
    if (hasSubfloorPlan) {
      pdf.addPage(PdfAdditionalPlans.subfloorPage(
        project: project,
        plan: firstPlan,
        versionNumber: versionNumber,
        sheetNumber: subfloorSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        sheetCode: hasBasementPlan ? 'КР-3' : 'КР-2',
        organization: organization,
      ));
    }
    // КЖ-1: сечение фундамента и схема армирования.
    if (hasFoundationPlan) {
      pdf.addPage(_foundationSectionPage(
        project: project,
        hasBasement: hasBasementPlan,
        model: foundationPlan,
        versionNumber: versionNumber,
        sheetNumber: foundationSectionSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    // КЖ-2: ведомость расхода стали.
    if (hasSteelBill) {
      pdf.addPage(PdfEngineeringSpecs.steelBillPage(
        project: project,
        foundationPlan: foundationPlan,
        versionNumber: versionNumber,
        sheetNumber: steelBillSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        organization: organization,
      ));
    }

    // === Комплект КД ===
    // КД-1: схема расположения балок перекрытия.
    pdf.addPage(PdfAdditionalPlans.beamsPage(
      project: project,
      plan: firstPlan,
      versionNumber: versionNumber,
      sheetNumber: beamsSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    // КД-2: объединённый лист «Стропильная система: разрез и схема»
    // (разрез фермы со всеми элементами 1…11, узлы «А»/«Б»,
    //  план стропил, спецификация и расчёт). До v60 это было два
    //  раздельных листа КД-2 + КД-2.1, в v61 — один объединённый.
    if (hasRaftersPlan) {
      pdf.addPage(PdfAdditionalPlans.raftersCombinedPage(
        project: project,
        topPlan: plans.last.$2,
        versionNumber: versionNumber,
        sheetNumber: raftersSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    // КД-3: спецификация элементов лестницы.
    if (hasStaircaseSheet) {
      pdf.addPage(PdfEngineeringSpecs.staircaseSpecPage(
        project: project,
        plans: allPlans,
        versionNumber: versionNumber,
        sheetNumber: staircaseSpecSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }

    // === Узлы и детали (У-1…У-8) ===
    pdf.addPage(PdfDetailNodes.eaveNodePage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: eaveNodeSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    if (hasRoofPlan) {
      pdf.addPage(PdfDetailNodes.ridgeNodePage(
        project: project,
        versionNumber: versionNumber,
        sheetNumber: ridgeNodeSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    pdf.addPage(PdfDetailNodes.windowJambNodePage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: windowJambNodeSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    if (hasRoofPlan) {
      pdf.addPage(PdfDetailNodes.rafterMauerlatNodePage(
        project: project,
        versionNumber: versionNumber,
        sheetNumber: rafterMauerlatNodeSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    pdf.addPage(PdfDetailNodes.plinthApronNodePage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: plinthNodeSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    pdf.addPage(PdfDetailNodes.floorBeamNodePage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: floorBeamNodeSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));
    if (hasRoofPlan) {
      pdf.addPage(PdfDetailNodes.roofPiePage(
        project: project,
        versionNumber: versionNumber,
        sheetNumber: roofPieSheetNumber,
        totalSheets: totalSheets,
        font: regular,
        fontBold: bold,
        pdfFont: pdfTtfRegular,
        organization: organization,
      ));
    }
    // У-8: пирог пола 1-го этажа — слои + толщина утеплителя по
    // расчёту (СП 50.13330) для климата проекта.
    pdf.addPage(PdfDetailNodes.floorPieNodePage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: floorPieNodeSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      pdfFont: pdfTtfRegular,
      organization: organization,
    ));

    // === ОР: перечень видов работ, подлежащих освидетельствованию ===
    pdf.addPage(PdfEngineeringSpecs.hiddenWorksActsPage(
      project: project,
      versionNumber: versionNumber,
      sheetNumber: hiddenWorksSheetNumber,
      totalSheets: totalSheets,
      font: regular,
      fontBold: bold,
      organization: organization,
    ));

    return pdf.save();
  }

  /// Рамка чертежа по ГОСТ 2.301-68 / ГОСТ Р 21.101-2020.
  ///
  /// Внешний контур — тонкая линия 0.3 мм по краю поля чертежа;
  /// внутренний контур — толстая линия 0.7 мм со смещением 20 мм по
  /// левой стороне (поле для подшивки) и 5 мм по остальным трём сторонам.
  /// Все измерения переводим в pt (1 мм ≈ 2.835 pt).
  static pw.Widget _drawingFrame() {
    const mm = PdfPageFormat.mm;
    return pw.Stack(
      children: [
        // Внешняя тонкая линия — по краю листа.
        pw.Positioned.fill(
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.3),
            ),
          ),
        ),
        // Внутренняя толстая рамка: 20 мм слева, 5 мм с других сторон.
        pw.Positioned(
          left: 20 * mm,
          top: 5 * mm,
          right: 5 * mm,
          bottom: 5 * mm,
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  /// Стандартная PageTheme для всех листов чертежа: формат A3 landscape,
  /// поля под штамп и осевую сетку, и фоновая рамка ГОСТ 2.301-68.
  ///
  /// Поля page margin = 0, потому что мы рисуем рамку и контент в
  /// абсолютных координатах страницы. Контент в каждом листе оборачивается
  /// в `pw.Padding(_drawingContentPadding)` — это гарантирует, что
  /// контент не вылезет за внутреннюю рамку:
  ///   - 60 пт слева  (20 мм поле подшивки + 1 пт запас)
  ///   - 18 пт сверху (5 мм + 4 пт запас)
  ///   - 18 пт справа
  ///   - 18 пт снизу (для штампа отдельный отступ через bottom-padding в каждом листе)
  static pw.PageTheme _drawingPageTheme() {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: pw.EdgeInsets.zero,
      buildBackground: (context) => _drawingFrame(),
    );
  }

  /// Рамка чертежа (ГОСТ 2.301-68) — без штампа. Используется внешними
  /// модулями (pdf_engineering_specs.dart) для собственных PageTheme.
  static pw.Widget drawingFrame() => _drawingFrame();

  /// Публичная обёртка для `pdf_general_data.dart`.
  static pw.PageTheme drawingPageTheme() => _drawingPageTheme();

  static pw.Page _emptyPage(pw.Font font) {
    return pw.Page(
      pageFormat: PdfPageFormat.a3.landscape,
      build: (context) => pw.Center(
        child: pw.Text(
          'Нет схематических планов в этой версии.',
          style: pw.TextStyle(fontSize: 14, font: font),
        ),
      ),
    );
  }

  static pw.Page _planPage({
    required HouseProject project,
    required Drawing drawing,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            // Основное поле чертежа — оставляем место внизу для штампа.
            pw.Positioned.fill(
              child: pw.Padding(
                // 134 pt снизу — основное поле не налегает на штамп.
                // Уменьшенный штамп ГОСТ Р 21.101-2020 рисуется с
                // коэффициентом PdfTitleBlock.defaultScale = 0.75
                // (≈ 41 мм / 117 pt) + 17 pt запас → 134 pt.
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _header(
                      project,
                      drawing,
                      plan,
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
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
                                  _paintPlan(canvas, size, plan, pdfFont,
                                      project.brief.wallMaterial,
                                      staircaseType: project.staircase.type,
                                      staircaseSteps:
                                          project.staircase.stepsCount,
                                      floorHeight:
                                          project.staircase.floorHeight ??
                                              project.walls.height,
                                      fontBold: pdfFontBold,
                                      project: project),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Штамп ГОСТ Р 21.101-2020 в правом нижнем углу.
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
                sheetTitle: '${plan.floorLabel} · ${drawing.title}',
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

  static pw.Widget _header(
    HouseProject project,
    Drawing drawing,
    FloorPlan plan,
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
                fontSize: 12,
                font: fontBold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              '${plan.floorLabel} · ${drawing.title}',
              style: pw.TextStyle(fontSize: 9, font: font),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Версия №$versionNumber',
                style: pw.TextStyle(fontSize: 9, font: font)),
            pw.Text(
              _formatDate(drawing.createdAt),
              style: pw.TextStyle(fontSize: 8, font: font),
            ),
            if (drawing.isManualEdit)
              pw.Text('ручная правка',
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: font,
                    color: PdfColors.deepOrange,
                    fontStyle: pw.FontStyle.italic,
                  )),
          ],
        ),
      ],
    );
  }

  /// Отдельная страница «План фундамента» (КР-1).
  ///
  /// Все геометрические сущности — оси, ленты/плита/сваи, размеры,
  /// глубина заложения, бетон, армирование — приходят из
  /// [FoundationPlanModel], построенной на основе расчётов cc_engine
  /// (СП 22.13330.2016, СП 20.13330.2016, СП 63.13330.2018). Ничего
  /// не хардкодится — каждая цифра берётся из подбора по ТЗ проекта.
  static pw.Page _foundationPlanPage({
    required HouseProject project,
    required FoundationPlanModel model,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
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
                              'План фундамента · ${model.typeLabel}',
                              style: pw.TextStyle(fontSize: 11, font: font),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Версия №$versionNumber',
                                style: pw.TextStyle(fontSize: 11, font: font)),
                            pw.Text(
                              _formatDate(DateTime.now()),
                              style: pw.TextStyle(fontSize: 9, font: font),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
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
                                  _paintFoundationPlan(
                                      canvas, size, model, pdfFont),
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
                sheetTitle: 'План фундамента · ${model.typeLabel}',
                sheetCode: 'КР-1',
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

  /// Чертёж сечения фундамента и схема армирования (КЖ-1).
  ///
  /// На листе показываются:
  ///  • поперечный разрез ленты / плиты / сваи;
  ///  • размеры сечения (b, h, защитный слой);
  ///  • схема армирования с реальными диаметрами стержней (продольная
  ///    рабочая А500С + поперечная А240);
  ///  • песчаная подушка, гидроизоляция, отметка ±0.000.
  /// Все размеры читаемые — это требование ГОСТ 21.501-2018 п. 6.
  static pw.Page _foundationSectionPage({
    required HouseProject project,
    required bool hasBasement,
    required FoundationPlanModel model,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 184),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
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
                              'Сечение фундамента и схема армирования · '
                              '${model.typeLabel}',
                              style: pw.TextStyle(fontSize: 11, font: font),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Версия №$versionNumber',
                                style:
                                    pw.TextStyle(fontSize: 11, font: font)),
                            pw.Text(
                              _formatDate(DateTime.now()),
                              style: pw.TextStyle(fontSize: 9, font: font),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
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
                                  _paintFoundationSection(
                                      canvas, size, model, pdfFont,
                                      hasBasement: hasBasement),
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
                sectionTitle: 'Конструкции железобетонные',
                sheetTitle: 'Сечение и армирование',
                sheetCode: 'КЖ-1',
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

  /// Рисует поперечное сечение фундамента (в большом масштабе) и
  /// прилегающую схему армирования. Все размеры подписаны числами.
  ///
  /// Полная переработка по референсам ГОСТ 21.501-2018 и СП 22.13330:
  ///   • грунт со штриховкой выше отметки 0.000;
  ///   • цоколь и подземная часть фундамента (с собственной диагональной
  ///     штриховкой ж/б, как в СПДС);
  ///   • песчаная подушка с точечной заливкой + щебеночная подготовка;
  ///   • рабочая арматура (верхний и нижний пояс) и хомуты;
  ///   • защитный слой бетона (ас≥40 мм);
  ///   • гидроизоляция в зигзаг под цокольным узлом;
  ///   • размерные цепи: B (ширина), Hф (полная высота), hп (плита/подушка),
  ///     Hз (заглубление от 0.000), цоколь;
  ///   • легенда вынесена НИЖЕ чертежа (не перекрывает) с реальными
  ///     значениями расчёта.
  static void _paintFoundationSection(
    PdfGraphics canvas,
    PdfPoint size,
    FoundationPlanModel model,
    PdfFont font, {
    bool hasBasement = false,
  }) {
    // ===========================
    // Параметры сечения по типу.
    // ===========================
    double sectionWidthMm; // ширина «тела» в мм
    double sectionHeightMm; // высота тела в мм (без подушки)
    double plinthHeightMm; // высота цоколя над 0.000
    double depthBelowZeroM; // глубина заложения от ±0.000, м
    String mainBarLabel;
    int topBars;
    int bottomBars;
    String stirrupLabel;
    String concreteGrade;
    String coverMm;
    String typeTitle;
    String wallAboveLabel; // надпись для условной стены сверху
    final type = model.type;
    // Все размеры/арматура берутся из реальной модели плана фундамента
    // (foundation_plan.bands[].thicknessM, slab.thicknessM,
    // piles[].diameterM, depthM). Армирование подбирается по тем же
    // правилам, что и КЖ-2 (СП 63.13330.2018, п. 10.3).
    if (type == FoundationType.slab) {
      final t = model.slab?.thicknessM ?? 0.30;
      // Фрагмент плиты для масштабного отображения сечения.
      sectionWidthMm = 1500;
      sectionHeightMm = (t * 1000).clamp(150.0, 500.0);
      plinthHeightMm = 0; // плита — нет цоколя
      depthBelowZeroM = model.depthM > 0 ? model.depthM : 0.3;
      // Диаметр и шаг — от толщины плиты (как в КЖ-2).
      final d = t < 0.20 ? 10 : (t < 0.30 ? 12 : 14);
      final stepMm = t < 0.25 ? 150 : 200;
      // Кол-во стержней на 1500 мм фрагменте.
      final barsPerLayer = (1500 / stepMm).round() + 1;
      mainBarLabel = '⌀$d А500С шаг $stepMm';
      topBars = barsPerLayer;
      bottomBars = barsPerLayer;
      stirrupLabel = 'фиксаторы защитного слоя';
      concreteGrade = 'B25 W6 F150';
      coverMm = '40';
      typeTitle =
          'Монолитная плита δ=${(t * 1000).toStringAsFixed(0)} мм — '
          'фрагмент 1500 мм';
      wallAboveLabel = 'Несущая стена 1-го этажа';
    } else if (type == FoundationType.pileWithGrillage ||
        type == FoundationType.pile) {
      // Ростверк по сечению как у ленты, ширина = ширина грильяжа,
      // высота = глубина, но не менее 300 мм.
      final pileDia = model.piles.isNotEmpty
          ? model.piles.first.diameterM
          : 0.30;
      final grillageW = model.bands.isNotEmpty
          ? model.bands.first.thicknessM
          : math.max(0.30, pileDia + 0.10);
      sectionWidthMm = (grillageW * 1000).clamp(250.0, 600.0);
      sectionHeightMm = 400; // типовое сечение ростверка
      plinthHeightMm = 200;
      depthBelowZeroM = model.depthM > 0 ? model.depthM : 1.5;
      // Армирование ростверка — по правилам ленты от его ширины.
      final n = grillageW < 0.40 ? 4 : (grillageW < 0.60 ? 6 : 8);
      final d = sectionHeightMm < 500 ? 10 : 12;
      mainBarLabel = '$n⌀$d А500С (${n ~/ 2}↑ + ${n ~/ 2}↓)';
      topBars = n ~/ 2;
      bottomBars = n - topBars;
      stirrupLabel = '⌀8 А240 шаг 200';
      concreteGrade = 'B22.5';
      coverMm = '40';
      typeTitle = type == FoundationType.pile
          ? 'Винтовая свая ⌀${(pileDia * 1000).toStringAsFixed(0)} мм '
              '(сечение ростверка по обвязке)'
          : 'Ростверк по буронабивной свае '
              '⌀${(pileDia * 1000).toStringAsFixed(0)} мм';
      wallAboveLabel = 'Стена';
    } else if (type == FoundationType.columnar) {
      // Столбчатый: размеры столба ≈ pile.diameterM (модель хранит
      // столбы как «piles» с тем же полем).
      final colSide = model.piles.isNotEmpty
          ? model.piles.first.diameterM
          : 0.40;
      sectionWidthMm = (colSide * 1000).clamp(300.0, 800.0);
      sectionHeightMm = sectionWidthMm; // квадратное сечение
      plinthHeightMm = 200;
      depthBelowZeroM = model.depthM > 0 ? model.depthM : 1.2;
      final d = colSide <= 0.40 ? 10 : 12;
      mainBarLabel = '4⌀$d А500С';
      topBars = 2;
      bottomBars = 2;
      stirrupLabel = '⌀6 А240 шаг 200';
      concreteGrade = 'B20';
      coverMm = '50';
      typeTitle = 'Столбчатая опора '
          '${sectionWidthMm.toStringAsFixed(0)}×'
          '${sectionHeightMm.toStringAsFixed(0)}';
      wallAboveLabel = 'Балка обвязки';
    } else {
      // Лента: ширина = bands.first.thicknessM, высота тела = depthM.
      sectionWidthMm = 400;
      if (model.bands.isNotEmpty) {
        sectionWidthMm =
            (model.bands.first.thicknessM * 1000).clamp(300.0, 800.0);
      }
      // При подвале глубина в model.depthM включает высоту стены подвала
      // (~3.4 м). Сама лента в сечении не должна быть 2900 мм высотой —
      // это вводило в заблуждение (см. правку пользователя по листу 21).
      // Поэтому при наличии подвала ограничиваем «тело» ленты типовыми
      // 600 мм, а оставшееся пространство до 0.000 рисуем как стену
      // подвала (см. блок ниже).
      if (hasBasement) {
        sectionHeightMm = 600;
      } else {
        sectionHeightMm = (model.depthM > 0
                ? math.max(400.0, model.depthM * 1000 - 200)
                : 600)
            .toDouble();
      }
      plinthHeightMm = 400;
      depthBelowZeroM = model.depthM > 0 ? model.depthM : 1.2;
      // Подбор арматуры по тем же правилам, что КЖ-2 — используем
      // ту же геометрию (model.bands.first.thicknessM, model.depthM),
      // чтобы значения сечения и ведомости стали совпадали.
      final bandT = model.bands.isNotEmpty
          ? model.bands.first.thicknessM
          : sectionWidthMm / 1000.0;
      final bandH = model.depthM > 0
          ? model.depthM
          : (sectionHeightMm + plinthHeightMm) / 1000.0;
      final n = bandT < 0.40 ? 4 : (bandT < 0.60 ? 6 : 8);
      final d = bandH < 0.50 ? 10 : (bandH < 1.00 ? 12 : 14);
      final stirrupStepMm = bandH <= 0.6
          ? 200
          : (bandH <= 1.0 ? 250 : 300);
      mainBarLabel = '$n⌀$d А500С (${n ~/ 2} верх + ${n ~/ 2} низ)';
      topBars = n ~/ 2;
      bottomBars = n - topBars;
      stirrupLabel = '⌀8 А240 шаг $stirrupStepMm';
      concreteGrade = 'B22.5 W4 F75';
      coverMm = '40';
      typeTitle =
          'Лента ${sectionWidthMm.toStringAsFixed(0)}×'
          '${sectionHeightMm.toStringAsFixed(0)} мм';
      wallAboveLabel = 'Несущая стена';
    }
    const cushionMm = 300.0; // песок 200 + щебень 100

    // ===========================
    // Раскладка по странице.
    // ===========================
    final w = size.x;
    final h = size.y;
    // PDF Y отсчитывается снизу. Канвас здесь — это окно над штампом
    // (см. _foundationSectionPage). Ось pdfY=0 — низ окна.
    //
    // Делим окно вертикально:
    //   • верхние ~78% — само сечение (увеличен после п.3 v40),
    //   • нижние ~22% — табличка-легенда (ниже чертежа, не перекрывая).
    final legendH = math.max(90.0, h * 0.22);
    final drawTop = h - 6.0; // верхний край области чертежа (pdfY)
    // 24 pt запас между чертежом и таблицей «Параметры конструкции» —
    // чтобы нижние размерные цепи и отметки высот не наезжали на таблицу.
    final drawBottom = legendH + 24.0; // нижний край области чертежа
    final drawCx = w / 2;
    final drawW = w - 24;
    final drawH = drawTop - drawBottom;

    // Масштаб: вписываем сечение (тело + цоколь + подушка + заглубление)
    // в drawW × drawH. По высоте есть запас под подписи и землю.
    // Раньше horizontal-запас «под отмостку и подписи» был 600 мм
    // и s выходил очень мелким (≈0.06). Уменьшаем до 350 мм + 80 pt
    // в drawW: получаем масштаб ≈0.10 → сечение ~50 % крупнее.
    final totalH =
        plinthHeightMm + sectionHeightMm + cushionMm + depthBelowZeroM * 1000;
    final totalW = sectionWidthMm + 350;
    final sx = (drawW - 40) / totalW;
    final sy = (drawH - 80) / (totalH > 0 ? totalH : 1);
    final s = sx < sy ? sx : sy;

    // Высота стены подвала, мм. Заполняет промежуток между верхом
    // подушки + ленты и отметкой ±0.000. Для лент без подвала = 0.
    final basementWallHeightMm = (hasBasement && type == FoundationType.strip)
        ? math.max(0.0, depthBelowZeroM * 1000 - sectionHeightMm - cushionMm)
        : 0.0;

    // Геометрия в pdfY (растёт вверх).
    // zeroY — это уровень земли / отметка ±0.000 на странице.
    final zeroY = drawBottom + 60 + (depthBelowZeroM * 1000) * s;
    // При подвале лента «прижата» к подушке, а сверху остаётся место
    // под стену подвала. Без подвала — лента упирается верхней гранью
    // в ±0.000 (как было).
    final double bodyTopY;
    final double bodyBottomY;
    if (basementWallHeightMm > 0) {
      bodyBottomY = zeroY - (depthBelowZeroM * 1000 - cushionMm) * s;
      bodyTopY = bodyBottomY + sectionHeightMm * s;
    } else {
      bodyTopY = zeroY;
      bodyBottomY = bodyTopY - sectionHeightMm * s;
    }
    final cushionBottomY = bodyBottomY - cushionMm * s;
    // Цоколь над землёй.
    final plinthBottomY = zeroY;
    final plinthTopY = zeroY + plinthHeightMm * s;

    final bodyLeftX = drawCx - sectionWidthMm * s / 2;
    final bodyRightX = drawCx + sectionWidthMm * s / 2;
    final bodyW = sectionWidthMm * s;

    // ===========================
    // ГРУНТ (выше 0.000 не рисуем; ниже 0.000 — диагональная штриховка
    // 45° земли + поверхностный слой).
    // ===========================
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    // Линия земли — поверх всей ширины. Слегка выходит за тело фундамента.
    final groundLeft = math.max(12.0, bodyLeftX - 120);
    final groundRight = math.min(w - 12, bodyRightX + 120);
    canvas.drawLine(groundLeft, zeroY, bodyLeftX, zeroY);
    canvas.drawLine(bodyRightX, zeroY, groundRight, zeroY);
    canvas.strokePath();
    // Засечки уровня земли (45° штрихи) на участках слева/справа от тела.
    void drawGroundHatch(double x1, double x2) {
      const tickLen = 5.0;
      const step = 8.0;
      for (var x = x1; x < x2; x += step) {
        canvas.drawLine(x, zeroY, x - tickLen, zeroY - tickLen);
      }
      canvas.strokePath();
    }
    drawGroundHatch(groundLeft + 4, bodyLeftX);
    drawGroundHatch(bodyRightX + 4, groundRight);

    // ===========================
    // ПОДУШКА (песок 200 + щебень 100): рисуем отдельно две полосы.
    // ===========================
    final cushionLeftX = bodyLeftX - 8;
    final cushionRightX = bodyRightX + 8;
    final cushionW = cushionRightX - cushionLeftX;
    final cushionTotalH = cushionMm * s;
    // 1) Песок — нижние 2/3.
    final sandH = cushionTotalH * 2 / 3;
    final crushedH = cushionTotalH - sandH;
    final sandTopY = cushionBottomY + sandH;
    canvas.setColor(const PdfColor(0.97, 0.92, 0.78));
    canvas.drawRect(cushionLeftX, cushionBottomY, cushionW, sandH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(cushionLeftX, cushionBottomY, cushionW, sandH);
    canvas.strokePath();
    // Точечная заливка — песок.
    canvas.setColor(const PdfColor(0.62, 0.5, 0.3));
    final sandRng = math.Random(7);
    final sandDots = ((cushionW * sandH) / 22).round().clamp(40, 600);
    for (var i = 0; i < sandDots; i++) {
      final px = cushionLeftX + sandRng.nextDouble() * cushionW;
      final py = cushionBottomY + sandRng.nextDouble() * sandH;
      canvas.drawEllipse(px, py, 0.5, 0.5);
    }
    canvas.fillPath();
    // 2) Щебень — верхняя полоса.
    canvas.setColor(const PdfColor(0.85, 0.85, 0.85));
    canvas.drawRect(cushionLeftX, sandTopY, cushionW, crushedH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(cushionLeftX, sandTopY, cushionW, crushedH);
    canvas.strokePath();
    // Зерна щебня — рандомные эллипсы.
    canvas.setColor(const PdfColor(0.55, 0.55, 0.55));
    final crushRng = math.Random(13);
    final crushCount = ((cushionW * crushedH) / 60).round().clamp(15, 200);
    for (var i = 0; i < crushCount; i++) {
      final px = cushionLeftX + 4 + crushRng.nextDouble() * (cushionW - 8);
      final py = sandTopY + 1 + crushRng.nextDouble() * (crushedH - 2);
      canvas.drawEllipse(px, py, 1.4, 0.7);
    }
    canvas.fillPath();

    // ===========================
    // ТЕЛО ФУНДАМЕНТА (подземная часть) — серая заливка + диагональ.
    // ===========================
    canvas.setColor(const PdfColor(0.86, 0.86, 0.86));
    canvas.drawRect(bodyLeftX, bodyBottomY, bodyW, sectionHeightMm * s);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    canvas.drawRect(bodyLeftX, bodyBottomY, bodyW, sectionHeightMm * s);
    canvas.strokePath();
    // Штриховка ж/б — наклонные параллельные линии 45°, реже на больших телах.
    canvas.setStrokeColor(PdfColors.grey500);
    canvas.setLineWidth(0.3);
    void hatchRect45(double x, double y, double rw, double rh) {
      const step = 6.0;
      for (var d = -rh; d < rw; d += step) {
        var x1 = x + d;
        var y1 = y;
        var x2 = x + d + rh;
        var y2 = y + rh;
        if (x1 < x) {
          y1 += x - x1;
          x1 = x;
        }
        if (x2 > x + rw) {
          y2 -= x2 - (x + rw);
          x2 = x + rw;
        }
        canvas.drawLine(x1, y1, x2, y2);
      }
      canvas.strokePath();
    }
    hatchRect45(bodyLeftX, bodyBottomY, bodyW, sectionHeightMm * s);

    // ===========================
    // СТЕНА ПОДВАЛА (если выбран подвал) — между верхом ленты и 0.000.
    // Та же ширина, что у ленты, та же штриховка ж/б, но более светлая
    // заливка, чтобы визуально отделить от тела ленты.
    // Правка пользователя по листу 21: подвал должен быть показан, но
    // не полностью — главным элементом остаётся фундамент.
    // ===========================
    if (basementWallHeightMm > 0) {
      final wallH = basementWallHeightMm * s;
      canvas.setColor(const PdfColor(0.93, 0.93, 0.93));
      canvas.drawRect(bodyLeftX, bodyTopY, bodyW, wallH);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.7);
      canvas.drawRect(bodyLeftX, bodyTopY, bodyW, wallH);
      canvas.strokePath();
      hatchRect45(bodyLeftX, bodyTopY, bodyW, wallH);
      // Подпись «Стена подвала» — слева от стены через выноску, чтобы
      // текст не наслаивался на штриховку и не сжимался шириной 300 мм.
      if (wallH > 24) {
        final labelY = bodyTopY + wallH / 2;
        canvas.setStrokeColor(PdfColors.grey700);
        canvas.setLineWidth(0.4);
        canvas.drawLine(bodyLeftX, labelY, bodyLeftX - 30, labelY);
        canvas.strokePath();
        canvas.setFillColor(PdfColors.grey800);
        canvas.drawString(font, 7.5, 'Стена подвала',
            bodyLeftX - 100, labelY - 3);
      }
    }

    // ===========================
    // ЦОКОЛЬ (если есть) — над 0.000.
    // ===========================
    if (plinthHeightMm > 0) {
      canvas.setColor(const PdfColor(0.92, 0.92, 0.92));
      canvas.drawRect(bodyLeftX, plinthBottomY, bodyW, plinthHeightMm * s);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.7);
      canvas.drawRect(bodyLeftX, plinthBottomY, bodyW, plinthHeightMm * s);
      canvas.strokePath();
      hatchRect45(bodyLeftX, plinthBottomY, bodyW, plinthHeightMm * s);
    }

    // ===========================
    // ГИДРОИЗОЛЯЦИЯ — зигзагом по верху цоколя/тела.
    // ===========================
    canvas.setStrokeColor(const PdfColor(0.0, 0.4, 0.7));
    canvas.setLineWidth(0.7);
    final waterY = plinthHeightMm > 0 ? plinthTopY + 2 : bodyTopY + 2;
    var zx = bodyLeftX - 2;
    while (zx < bodyRightX + 2) {
      canvas.drawLine(zx, waterY, zx + 4, waterY + 2);
      canvas.drawLine(zx + 4, waterY + 2, zx + 8, waterY);
      zx += 8;
    }
    canvas.strokePath();
    // Подпись.
    canvas.setFillColor(const PdfColor(0.0, 0.4, 0.7));
    canvas.drawString(font, 7, 'гидроизоляция (2 сл.)',
        bodyRightX + 6, waterY + 1);

    // ===========================
    // СТЕНА СВЕРХУ (условно, для контекста) — пунктиром, тонкая.
    // ===========================
    final wallTopY = math.min(drawTop - 6, plinthTopY + 30 * s + 30);
    final wallW = bodyW * 0.85;
    final wallLeftX = drawCx - wallW / 2;
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setLineWidth(0.4);
    _foundationDrawDashedLine(canvas, wallLeftX, plinthTopY + 6,
        wallLeftX, wallTopY, dash: 3, gap: 2);
    _foundationDrawDashedLine(canvas, wallLeftX + wallW, plinthTopY + 6,
        wallLeftX + wallW, wallTopY, dash: 3, gap: 2);
    canvas.setFillColor(PdfColors.grey700);
    canvas.drawString(font, 7, wallAboveLabel, wallLeftX + 4, wallTopY - 8);

    // ===========================
    // АРМАТУРА.
    // ===========================
    canvas.setColor(PdfColors.black);
    final coverPx = math.max(3.0, (double.tryParse(coverMm) ?? 40) * s);
    final barR = math.max(2.0, math.min(3.5, bodyW * 0.012));
    final innerLeft = bodyLeftX + coverPx;
    final innerRight = bodyRightX - coverPx;
    final innerWArm = innerRight - innerLeft;
    final topArmY = bodyTopY - coverPx; // верхний пояс
    final botArmY = bodyBottomY + coverPx; // нижний пояс
    void drawBars(int count, double y) {
      if (count <= 0) return;
      final step = count == 1 ? 0 : innerWArm / (count - 1);
      for (var i = 0; i < count; i++) {
        canvas.drawEllipse(innerLeft + step * i, y, barR, barR);
      }
    }
    drawBars(topBars, topArmY);
    drawBars(bottomBars, botArmY);
    canvas.fillPath();
    // Хомут (стенки).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(
      innerLeft - 1,
      botArmY - 1,
      innerWArm + 2,
      (topArmY - botArmY).abs() + 2,
    );
    canvas.strokePath();

    // ===========================
    // РАЗМЕРЫ.
    // Снизу: ширина B.
    // Слева: общая высота Hф (тело + подушка); внутри (защитный слой).
    // Справа: глубина заложения Hз; цоколь hц (если есть).
    // ===========================
    void drawHorzDim(double x1, double x2, double y, String text) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawLine(x1, y, x2, y);
      canvas.drawLine(x1, y - 4, x1, y + 4);
      canvas.drawLine(x2, y - 4, x2, y + 4);
      // Выноски.
      canvas.drawLine(x1, y - 2, x1, y + 12);
      canvas.drawLine(x2, y - 2, x2, y + 12);
      canvas.strokePath();
      // Подпись СНИЗУ от линии — чтобы не конфликтовать с самой
      // линией сечения и подушкой выше.
      _drawCenteredText(canvas, text, (x1 + x2) / 2, y - 12,
          fontSize: 8.5, font: font);
    }
    void drawVertDim(double x, double y1, double y2, String text,
        {bool textRight = true, double textOffset = 28}) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawLine(x, y1, x, y2);
      canvas.drawLine(x - 4, y1, x + 4, y1);
      canvas.drawLine(x - 4, y2, x + 4, y2);
      canvas.strokePath();
      _drawCenteredText(canvas, text,
          x + (textRight ? textOffset : -textOffset),
          (y1 + y2) / 2,
          fontSize: 8.5, font: font);
    }

    // Низ: ширина B — линия размера ниже подушки на 28 pt, текст ещё
    // ниже на 12 pt, чтобы НЕ перекрывал «hп».
    drawHorzDim(bodyLeftX, bodyRightX, cushionBottomY - 28,
        'B = ${sectionWidthMm.toStringAsFixed(0)} мм');
    // Слева: высота тела h. Дальше от стены (-46), чтобы не
    // соприкасаться с отметкой ±0.000 (отметки идут на bodyLeftX-60).
    drawVertDim(bodyLeftX - 46, bodyBottomY, bodyTopY,
        'h = ${sectionHeightMm.toStringAsFixed(0)} мм',
        textRight: false, textOffset: 32);
    // Слева: подушка hп — ЕЩЁ дальше (-86), отдельной цепью, чтобы
    // не пересекаться с цепью «h» и отметкой подошвы.
    drawVertDim(bodyLeftX - 86, cushionBottomY, bodyBottomY,
        'hп = ${cushionMm.toStringAsFixed(0)} мм',
        textRight: false, textOffset: 32);
    // Справа: глубина заложения от 0.000.
    drawVertDim(bodyRightX + 46, cushionBottomY, zeroY,
        'Hз = ${(depthBelowZeroM * 1000).toStringAsFixed(0)} мм',
        textOffset: 36);
    // Справа: цоколь, если есть.
    if (plinthHeightMm > 0) {
      drawVertDim(bodyRightX + 86, plinthBottomY, plinthTopY,
          'hц = ${plinthHeightMm.toStringAsFixed(0)} мм',
          textOffset: 32);
    }

    // ===========================
    // Отметки ±0.000 и подошвы.
    // ===========================
    void drawElevationMark(double x, double y, String text) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setFillColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      const sz = 5.0;
      canvas.moveTo(x, y);
      canvas.lineTo(x - sz, y + sz);
      canvas.lineTo(x + sz, y + sz);
      canvas.lineTo(x, y);
      canvas.fillPath();
      canvas.drawLine(x - 18, y + sz, x + 18, y + sz);
      canvas.strokePath();
      canvas.drawString(font, 8.5, text, x + 22, y + 3);
    }
    drawElevationMark(bodyLeftX - 60, zeroY, '±0.000');
    drawElevationMark(bodyLeftX - 60, cushionBottomY,
        '−${(depthBelowZeroM + cushionMm / 1000).toStringAsFixed(3)}');
    if (plinthHeightMm > 0) {
      drawElevationMark(bodyLeftX - 60, plinthTopY,
          '+${(plinthHeightMm / 1000).toStringAsFixed(3)}');
    }
    // Отметка «пол подвала» — верхняя грань ленты, если выбран подвал.
    // Текст отметки короткий («−2.200»), пояснение «пол подвала»
    // выносим выше отметки слева, чтобы не наезжало на тело сечения.
    if (basementWallHeightMm > 0) {
      final basementFloorElev =
          -(depthBelowZeroM - cushionMm / 1000 - sectionHeightMm / 1000);
      drawElevationMark(bodyLeftX - 60, bodyTopY,
          basementFloorElev.toStringAsFixed(3));
      canvas.setFillColor(PdfColors.grey700);
      canvas.drawString(
          font, 7.5, 'пол подвала', bodyLeftX - 110, bodyTopY + 14);
    }

    // ===========================
    // Выноски для арматуры. Подписи выносим над линией цоколя/гидроизоляции,
    // чтобы текст не пересекался с линией грунта (zeroY) и зигзагом
    // гидроизоляции (waterY).
    // ===========================
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Безопасный y для подписей — выше плинтуса/гидроизоляции.
    final safeLabelY =
        math.max(plinthTopY + 30, waterY + 18).clamp(drawBottom + 30, drawTop - 12).toDouble();
    // Верхний пояс арматуры — выноска на правую сторону, в безопасную зону.
    final mainLeadStartX = innerRight - 1;
    final mainLeadStartY = topArmY;
    final mainLeadMidX = bodyRightX + 18;
    canvas.drawLine(mainLeadStartX, mainLeadStartY, mainLeadMidX, safeLabelY);
    canvas.drawLine(mainLeadMidX, safeLabelY, mainLeadMidX + 60, safeLabelY);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    // Префикс «L1» соответствует позиции в ведомости расхода стали (КЖ-2).
    canvas.drawString(
        font, 7.5, 'L1 — $mainBarLabel', mainLeadMidX + 2, safeLabelY + 3);
    // Хомуты — выноска на левую сторону, в ту же безопасную полосу.
    final stirrupLeadStartX = innerLeft + 1;
    final stirrupLeadStartY = (topArmY + botArmY) / 2;
    final stirrupLeadMidX = bodyLeftX - 18;
    canvas.drawLine(stirrupLeadStartX, stirrupLeadStartY,
        stirrupLeadMidX, safeLabelY);
    canvas.drawLine(
        stirrupLeadMidX, safeLabelY, stirrupLeadMidX - 60, safeLabelY);
    canvas.strokePath();
    canvas.drawString(font, 7.5, 'L2 — $stirrupLabel',
        stirrupLeadMidX - 60, safeLabelY + 3);

    // ===========================
    // ЛЕГЕНДА (таблица 2 столбца, под чертежом — НЕ перекрывает).
    // ===========================
    final tableTop = legendH; // pdfY
    final tableLeft = 12.0;
    final tableRight = w - 12;
    final tableW = tableRight - tableLeft;
    final colKeyW = tableW * 0.42;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    // Заголовок.
    canvas.setColor(const PdfColor(0.93, 0.93, 0.93));
    canvas.drawRect(tableLeft, tableTop - 18, tableW, 18);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.drawRect(tableLeft, tableTop - 18, tableW, 18);
    canvas.strokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 9.5,
        'Параметры конструкции (по расчёту)', tableLeft + 6, tableTop - 12);
    // Строки.
    final rows = <List<String>>[
      ['Тип', typeTitle],
      ['Бетон', concreteGrade],
      ['Защитный слой', '$coverMm мм'],
      ['Продольная арматура', mainBarLabel],
      ['Поперечная арматура', stirrupLabel],
      ['Подушка', 'песок 200 мм + щебень 100 мм с трамбованием по слоям'],
      ['Гидроизоляция', '2 слоя оклеечной (Унифлекс ЭПП / аналог)'],
      ['Глубина заложения Hз', '${(depthBelowZeroM * 1000).toStringAsFixed(0)} мм'],
      if (plinthHeightMm > 0)
        ['Высота цоколя hц', '${plinthHeightMm.toStringAsFixed(0)} мм'],
      ['Нормативные документы', 'СП 22.13330.2016, СП 63.13330.2018, ГОСТ 21.501-2018'],
    ];
    final rowH = (tableTop - 18 - 8) / rows.length;
    var ry = tableTop - 18;
    for (final row in rows) {
      ry -= rowH;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawRect(tableLeft, ry, colKeyW, rowH);
      canvas.drawRect(tableLeft + colKeyW, ry, tableW - colKeyW, rowH);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      canvas.drawString(font, 8, row[0], tableLeft + 4, ry + rowH / 2 - 3);
      canvas.drawString(
          font, 8, row[1], tableLeft + colKeyW + 4, ry + rowH / 2 - 3);
    }
  }

  /// Отдельная страница «План кровли» (АР-N).
  ///
  /// Использует те же поля и штамп, что `_planPage` для этажей. Контур
  /// кровли строится из габаритов верхнего этажа (плюс свес 0.5 м), а
  /// форма — из `project.roof.type` (двускатная / вальмовая / плоская
  /// и т. п.). Уклон скатов и снегозадержатели берутся из `project.roof`
  /// и `project.brief`.
  static pw.Page _roofPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    required PdfFont pdfFontBold,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _roofHeader(
                      project,
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
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
                                  _paintRoofPlan(canvas, size, plan,
                                      project, pdfFont, pdfFontBold),
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
                sheetTitle: 'План кровли',
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

  static pw.Widget _roofHeader(
    HouseProject project,
    int versionNumber,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final roof = project.roof;
    final shape = RoofShape.fromTypeId(roof.type);
    final shapeLabel = _roofShapeLabel(shape);
    final slope = roof.slopeAngle ?? 30;
    final material = _roofMaterialLabel(roof.roofingMaterial);
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
              'План кровли · $shapeLabel · '
              'уклон ${slope.toStringAsFixed(0)}°'
              '${material.isEmpty ? '' : ' · $material'}',
              style: pw.TextStyle(fontSize: 11, font: font),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Версия №$versionNumber',
                style: pw.TextStyle(fontSize: 11, font: font)),
            pw.Text(
              _formatDate(DateTime.now()),
              style: pw.TextStyle(fontSize: 9, font: font),
            ),
          ],
        ),
      ],
    );
  }

  static String _roofShapeLabel(RoofShape s) {
    switch (s) {
      case RoofShape.gable:
        return 'двускатная';
      case RoofShape.hip:
        return 'вальмовая';
      case RoofShape.flat:
        return 'плоская';
      case RoofShape.shed:
        return 'односкатная';
      case RoofShape.mansard:
        return 'мансардная';
    }
  }

  static String _roofMaterialLabel(String? id) {
    if (id == null) return '';
    final m = id.toLowerCase();
    if (m.contains('metal_tile') || m.contains('металлочер')) {
      return 'металлочерепица';
    }
    if (m.contains('clay') || m.contains('керам')) return 'керамическая черепица';
    if (m.contains('soft') || m.contains('бит')) return 'мягкая (битумная)';
    if (m.contains('seam') || m.contains('фальц')) return 'фальцевая';
    if (m.contains('slate') || m.contains('шифер')) return 'шифер';
    if (m.contains('membr') || m.contains('пвх')) return 'мембрана ПВХ';
    return id;
  }

  // Толщина стен (м), синхронно с FloorPlanView.
  // В PDF показываем стены чуть толще модельных — это стандартная
  // практика рабочих чертежей стадии АС (наружная стена 400 мм,
  // внутренняя несущая 250 мм). Геометрия модели не меняется.
  static const double _outerWall = 0.40;
  static const double _innerWall = 0.25;
  static const double _eps = 0.05;

  // Палитра PDF.
  /// Цвет «массы стены». Очень светлый — на нём поверх рисуется
  /// штриховка под материал (ГОСТ 2.306-68).
  static const PdfColor _wallMassColor = PdfColor.fromInt(0xFFEFEFEF);
  static const PdfColor _surfaceColor = PdfColors.white;
  static const PdfColor _staircaseStroke = PdfColors.deepPurple400;
  static const PdfColor _freeFill = PdfColor.fromInt(0xFFFAFAFA);
  static const PdfColor _doorColor = PdfColors.black;
  static const PdfColor _entryDoorColor = PdfColors.black;
  static const PdfColor _windowFill = PdfColors.white;
  static const PdfColor _windowStroke = PdfColors.black;

  /// Рисует план так же, как `FloorPlanPainter` на экране:
  ///   1) пятно заливается «массой стены» (тёмный onSurface);
  ///   2) поверх — внутренние прямоугольники комнат, отступ от рёбер равен
  ///      половине толщины стены (наружная 0.38 м, внутренняя 0.20 м) —
  ///      это даёт визуальный эффект толстых стен;
  ///   3) проёмы «вырезают» стену: окно — двойная линия (CAD-символ),
  ///      дверь — створка + дуга направления открывания, открытый проход —
  ///      просто заливка цветом свободной зоны;
  ///   4) лестница — штриховка ступеней + стрелка подъёма.
  /// Рисует план фундамента: контур пятна, ленты/плита/сваи (с штриховкой),
  /// осевая сетка А/Б/В… и 1/2/3…, две размерные цепи по каждому борту,
  /// аннотации с расчётными цифрами (бетон, армирование, глубина).
  ///
  /// Все геометрические данные приходят в [FoundationPlanModel] из
  /// [FoundationPlanGenerator] — здесь только отрисовка.
  static void _paintFoundationPlan(
    PdfGraphics canvas,
    PdfPoint size,
    FoundationPlanModel model,
    PdfFont font,
  ) {
    if (model.buildingWidth <= 0 || model.buildingLength <= 0) return;

    final w = size.x;
    final h = size.y;

    // Поля под оси, размерные цепи, аннотации, блок «Технические указания».
    // По ГОСТ 21.501 чертеж теперь рисуется так:
    //   • размерная цепь — снизу/слева на расстоянии 80 pt от плана
    //   • кружок оси — за размерной цепью, на расстоянии 130 pt
    //   • технические указания — ниже всего этого (под кружками осей)
    // Поэтому marginLeft/marginBottom расширены, чтобы вместить и
    // размерные цепи, и кружки осей, и заголовок указаний.
    // Поля плана фундамента: оси ПОСЛЕ всех размеров (правка по листу 8).
    // yAxisBase = chainTotalLeft 140 + 50 = 190; marginLeft = 220.
    const marginLeft = 220.0;
    const marginRight = 220.0; // под аннотацию глубины
    const marginTop = 60.0; // сверху ничего (нет зеркальных цепей)
    const marginBottom = 300.0; // цепи + указания

    final scaleX = (w - marginLeft - marginRight) / model.buildingWidth;
    final scaleY = (h - marginTop - marginBottom) / model.buildingLength;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final planW = model.buildingWidth * scale;
    final planH = model.buildingLength * scale;
    final ox = marginLeft + ((w - marginLeft - marginRight) - planW) / 2;
    final oy = marginBottom + ((h - marginTop - marginBottom) - planH) / 2;

    // Y инвертирована: модель — top-down, PdfGraphics — bottom-up.
    PdfPoint pp(double mx, double my) =>
        PdfPoint(ox + mx * scale, oy + planH - my * scale);

    // 1. Контур пятна — толстая чёрная линия.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    canvas.drawRect(ox, oy, planW, planH);
    canvas.strokePath();

    // 2. Плита (для slab).
    if (model.slab != null) {
      final slab = model.slab!;
      _foundationFillPolygon(canvas, slab.polygon, pp,
          fill: const PdfColor(0.85, 0.85, 0.85));
      _foundationHatchPolygon(canvas, slab.polygon, pp, scale,
          spacing: 8, angleDeg: 45, color: PdfColors.grey600);
      _foundationStrokePolygon(canvas, slab.polygon, pp,
          color: PdfColors.black, width: 0.8);
    }

    // 3. Ленты — заливка + штриховка как у бетона.
    for (final band in model.bands) {
      _foundationDrawBand(canvas, band, pp, scale);
    }

    // 4. Сваи / столбы.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    for (final pile in model.piles) {
      final p = pp(pile.x, pile.y);
      final r = math.max(2.5, pile.diameterM * scale / 2);
      canvas.setFillColor(PdfColors.grey800);
      canvas.drawEllipse(p.x, p.y, r, r);
      canvas.fillAndStrokePath();
      if (pile.label.isNotEmpty) {
        canvas.setFillColor(PdfColors.black);
        canvas.drawString(font, 7, pile.label, p.x + r + 2, p.y - 3);
      }
    }

    // 5. Осевые линии и кружки.
    _foundationDrawAxes(canvas, font, model, ox, oy, planW, planH, scale);

    // 6. Размерные цепи.
    _foundationDrawDimChains(
        canvas, font, model, ox, oy, planW, planH, scale);

    // 7. Аннотации с реальными числами.
    canvas.setFillColor(PdfColors.black);
    for (final ann in model.annotations) {
      final p = pp(ann.x, ann.y);
      if (ann.targetX != null && ann.targetY != null) {
        final t = pp(ann.targetX!, ann.targetY!);
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.4);
        canvas.drawLine(t.x, t.y, p.x, p.y);
        canvas.strokePath();
      }
      canvas.drawString(font, 8, ann.text, p.x, p.y);
    }

    // 8. Блок «Технические указания» — реальные цифры из расчёта.
    // Размерные цепи: oy - 80 ÷ oy - (80 + 28·N) (≤ oy - 108).
    // Кружок оси под цепью: oy - 130 ± 10. Поэтому верх блока
    // указаний помещаем на oy - 155 (ниже кружков осей + 5 pt).
    final notesTop = oy - 155;
    _foundationDrawNotesBlock(canvas, font, model, w, notesTop);
  }

  /// Палитра штриховки фундамента.
  static const PdfColor _foundationBandFill = PdfColor(0.78, 0.78, 0.78);
  static const PdfColor _foundationGrillageFill = PdfColor(0.88, 0.88, 0.88);

  static void _foundationDrawBand(
    PdfGraphics canvas,
    FoundationBand band,
    PdfPoint Function(double, double) pp,
    double scale,
  ) {
    final dx = band.x2 - band.x1;
    final dy = band.y2 - band.y1;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;
    final tx = dx / length;
    final ty = dy / length;
    final nx = -ty;
    final ny = tx;
    final hw = band.thicknessM / 2;
    final p1m = (band.x1 + nx * hw, band.y1 + ny * hw);
    final p2m = (band.x2 + nx * hw, band.y2 + ny * hw);
    final p3m = (band.x2 - nx * hw, band.y2 - ny * hw);
    final p4m = (band.x1 - nx * hw, band.y1 - ny * hw);
    final poly = [
      FoundationPoint(p1m.$1, p1m.$2),
      FoundationPoint(p2m.$1, p2m.$2),
      FoundationPoint(p3m.$1, p3m.$2),
      FoundationPoint(p4m.$1, p4m.$2),
    ];
    final fill = band.kind == FoundationBandKind.grillage
        ? _foundationGrillageFill
        : _foundationBandFill;
    _foundationFillPolygon(canvas, poly, pp, fill: fill);
    _foundationHatchPolygon(canvas, poly, pp, scale,
        spacing: 4, angleDeg: 45, color: PdfColors.grey600);
    _foundationStrokePolygon(canvas, poly, pp,
        color: PdfColors.black, width: 0.6);
  }

  static void _foundationFillPolygon(
    PdfGraphics canvas,
    List<FoundationPoint> poly,
    PdfPoint Function(double, double) pp, {
    required PdfColor fill,
  }) {
    if (poly.isEmpty) return;
    canvas.setFillColor(fill);
    final start = pp(poly.first.x, poly.first.y);
    canvas.moveTo(start.x, start.y);
    for (var i = 1; i < poly.length; i++) {
      final p = pp(poly[i].x, poly[i].y);
      canvas.lineTo(p.x, p.y);
    }
    canvas.closePath();
    canvas.fillPath();
  }

  static void _foundationStrokePolygon(
    PdfGraphics canvas,
    List<FoundationPoint> poly,
    PdfPoint Function(double, double) pp, {
    required PdfColor color,
    required double width,
  }) {
    if (poly.isEmpty) return;
    canvas.setStrokeColor(color);
    canvas.setLineWidth(width);
    final start = pp(poly.first.x, poly.first.y);
    canvas.moveTo(start.x, start.y);
    for (var i = 1; i < poly.length; i++) {
      final p = pp(poly[i].x, poly[i].y);
      canvas.lineTo(p.x, p.y);
    }
    canvas.closePath();
    canvas.strokePath();
  }

  /// Косая штриховка полигона (ГОСТ 2.306-68 — материал «бетон»).
  static void _foundationHatchPolygon(
    PdfGraphics canvas,
    List<FoundationPoint> poly,
    PdfPoint Function(double, double) pp,
    double scale, {
    required double spacing,
    required double angleDeg,
    required PdfColor color,
  }) {
    if (poly.isEmpty) return;
    // Bounds в pdf-координатах.
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final m in poly) {
      final p = pp(m.x, m.y);
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final diag = math.sqrt(
            math.pow(maxX - minX, 2) + math.pow(maxY - minY, 2)) /
        2;
    final ang = angleDeg * math.pi / 180;
    final dx = math.cos(ang);
    final dy = math.sin(ang);
    final px = -dy;
    final py = dx;
    canvas.saveContext();
    // Клиппинг внутрь полигона.
    final start = pp(poly.first.x, poly.first.y);
    canvas.moveTo(start.x, start.y);
    for (var i = 1; i < poly.length; i++) {
      final p = pp(poly[i].x, poly[i].y);
      canvas.lineTo(p.x, p.y);
    }
    canvas.closePath();
    canvas.clipPath();
    canvas.setStrokeColor(color);
    canvas.setLineWidth(0.3);
    final lines = (2 * diag / spacing).ceil();
    for (var i = -lines; i <= lines; i++) {
      final shift = i * spacing;
      final ax = cx + px * shift - dx * diag * 1.5;
      final ay = cy + py * shift - dy * diag * 1.5;
      final bx = cx + px * shift + dx * diag * 1.5;
      final by = cy + py * shift + dy * diag * 1.5;
      canvas.drawLine(ax, ay, bx, by);
    }
    canvas.strokePath();
    canvas.restoreContext();
  }

  static void _foundationDrawAxes(
    PdfGraphics canvas,
    PdfFont font,
    FoundationPlanModel model,
    double ox,
    double oy,
    double planW,
    double planH,
    double scale,
  ) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Кружок осей ставим за размерной цепью — вынос 130 pt от края
    // плана, чтобы цепи и кружки не перекрывали друг друга.
    const ext = 130.0;
    const radius = 10.0;

    // Цифровые оси (vertical lines, метка ТОЛЬКО снизу — ГОСТ 21.501).
    // Оставляем тонкую штрих-пунктирную линию через весь план, но
    // кружок ставим лишь с одной стороны.
    for (final ax in model.verticalAxes) {
      final x = ox + ax.position * scale;
      _foundationDrawDashedLine(
          canvas, x, oy - ext + radius, x, oy + planH, dash: 4, gap: 3);
      _foundationDrawAxisCircle(canvas, font, x, oy - ext, ax.label,
          radius: radius);
    }

    // Буквенные оси (horizontal lines, метка ТОЛЬКО слева).
    for (final ax in model.horizontalAxes) {
      final y = oy + planH - ax.position * scale;
      _foundationDrawDashedLine(
          canvas, ox - ext + radius, y, ox + planW, y, dash: 4, gap: 3);
      _foundationDrawAxisCircle(canvas, font, ox - ext, y, ax.label,
          radius: radius);
    }
  }

  static void _foundationDrawDashedLine(
    PdfGraphics canvas,
    double x1,
    double y1,
    double x2,
    double y2, {
    required double dash,
    required double gap,
  }) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    var t = 0.0;
    var on = true;
    while (t < len) {
      final segLen = math.min(on ? dash : gap, len - t);
      if (on) {
        canvas.drawLine(x1 + ux * t, y1 + uy * t,
            x1 + ux * (t + segLen), y1 + uy * (t + segLen));
      }
      t += segLen;
      on = !on;
    }
    canvas.strokePath();
  }

  static void _foundationDrawAxisCircle(
    PdfGraphics canvas,
    PdfFont font,
    double cx,
    double cy,
    String label, {
    required double radius,
  }) {
    canvas.setFillColor(PdfColors.white);
    canvas.drawEllipse(cx, cy, radius, radius);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawEllipse(cx, cy, radius, radius);
    canvas.strokePath();
    _drawCenteredText(canvas, label, cx, cy,
        fontSize: 9, font: font);
  }

  static void _foundationDrawDimChains(
    PdfGraphics canvas,
    PdfFont font,
    FoundationPlanModel model,
    double ox,
    double oy,
    double planW,
    double planH,
    double scale,
  ) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // По ГОСТ 21.501 габаритные размеры выносятся только с двух сторон
    // (одной цепочкой по каждой). Поэтому из всех цепей берём только
    // снизу и слева, а зеркальные сверху/справа отбрасываем — иначе
    // размеры дублируются и накладываются друг на друга.
    // Сохраняем не более одной цепи на каждом из этих двух сторон,
    // чтобы исключить повторение габаритов.
    final filteredChains = <FoundationDimChain>[];
    var hasBottom = false, hasLeft = false;
    for (final chain in model.dimensionChains) {
      if (chain.side == FoundationDimSide.bottom && !hasBottom) {
        filteredChains.add(chain);
        hasBottom = true;
      } else if (chain.side == FoundationDimSide.left && !hasLeft) {
        filteredChains.add(chain);
        hasLeft = true;
      }
    }
    for (final chain in filteredChains) {
      final stops = [...chain.stops]..sort();
      if (stops.length < 2) continue;
      const offset0 = 80.0; // вынос дальше, чтобы оси не пересекались
      const step = 28.0; // ↑ просторнее, чтобы цифры не наслаивались.
      final levelOffset = offset0 + (chain.level - 1) * step;

      switch (chain.side) {
        case FoundationDimSide.bottom:
          final y = oy - levelOffset;
          canvas.drawLine(ox + stops.first * scale, y,
              ox + stops.last * scale, y);
          for (var i = 0; i < stops.length; i++) {
            final cx = ox + stops[i] * scale;
            canvas.drawLine(cx, y - 3, cx, y + 3);
            canvas.drawLine(cx, oy - 4, cx, y);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final mx = ox + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              canvas.strokePath();
              _drawCenteredText(canvas, '$dimMm', mx, y + 7,
                  fontSize: 8, font: font);
              canvas.setStrokeColor(PdfColors.black);
              canvas.setLineWidth(0.4);
            }
          }
          canvas.strokePath();
          break;
        case FoundationDimSide.top:
          final y = oy + planH + levelOffset;
          canvas.drawLine(ox + stops.first * scale, y,
              ox + stops.last * scale, y);
          for (var i = 0; i < stops.length; i++) {
            final cx = ox + stops[i] * scale;
            canvas.drawLine(cx, y - 3, cx, y + 3);
            canvas.drawLine(cx, oy + planH + 4, cx, y);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final mx = ox + mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              canvas.strokePath();
              _drawCenteredText(canvas, '$dimMm', mx, y + 7,
                  fontSize: 8, font: font);
              canvas.setStrokeColor(PdfColors.black);
              canvas.setLineWidth(0.4);
            }
          }
          canvas.strokePath();
          break;
        case FoundationDimSide.right:
          final x = ox + planW + levelOffset;
          // PDF Y: меньшее значение = ниже. В нашей модели stop по
          // FoundationDimSide.right — это Y в model coords (top-down).
          canvas.drawLine(x, oy + planH - stops.first * scale, x,
              oy + planH - stops.last * scale);
          for (var i = 0; i < stops.length; i++) {
            final cy = oy + planH - stops[i] * scale;
            canvas.drawLine(x - 3, cy, x + 3, cy);
            canvas.drawLine(ox + planW + 4, cy, x, cy);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final my = oy + planH - mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              canvas.strokePath();
              _drawCenteredText(canvas, '$dimMm', x + 14, my,
                  fontSize: 8, font: font);
              canvas.setStrokeColor(PdfColors.black);
              canvas.setLineWidth(0.4);
            }
          }
          canvas.strokePath();
          break;
        case FoundationDimSide.left:
          final x = ox - levelOffset;
          canvas.drawLine(x, oy + planH - stops.first * scale, x,
              oy + planH - stops.last * scale);
          for (var i = 0; i < stops.length; i++) {
            final cy = oy + planH - stops[i] * scale;
            canvas.drawLine(x - 3, cy, x + 3, cy);
            canvas.drawLine(ox - 4, cy, x, cy);
            if (i < stops.length - 1) {
              final mid = (stops[i] + stops[i + 1]) / 2;
              final my = oy + planH - mid * scale;
              final dimMm = ((stops[i + 1] - stops[i]) * 1000).round();
              canvas.strokePath();
              _drawCenteredText(canvas, '$dimMm', x - 14, my,
                  fontSize: 8, font: font);
              canvas.setStrokeColor(PdfColors.black);
              canvas.setLineWidth(0.4);
            }
          }
          canvas.strokePath();
          break;
      }
    }
  }

  static void _foundationDrawNotesBlock(
    PdfGraphics canvas,
    PdfFont font,
    FoundationPlanModel model,
    double pageWidth,
    double notesTop,
  ) {
    final left = 70.0;
    final width = pageWidth - left - 28.0;
    final top = notesTop;
    const headingSize = 9.0;
    const lineSize = 7.5;
    const lineGap = 9.0;

    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, headingSize, 'Технические указания (из расчёта):',
        left, top);
    var y = top - lineGap - 2;
    for (final n in model.notes) {
      final wrapped = _foundationWrapNote(n, font, lineSize, width - 12);
      for (final line in wrapped) {
        canvas.drawString(font, lineSize, line, left + 8, y);
        y -= lineGap;
        if (y < 14) return;
      }
    }
    if (model.codeReferences.isNotEmpty) {
      y -= 4;
      canvas.drawString(font, lineSize,
          'Нормативы: ${model.codeReferences.join(' · ')}', left, y);
    }
  }

  static List<String> _foundationWrapNote(
      String text, PdfFont font, double fontSize, double maxWidth) {
    final words = text.split(' ');
    final lines = <String>[];
    var current = '• ';
    for (final w in words) {
      final candidate = current.isEmpty ? w : '$current$w ';
      final width = font.stringMetrics(candidate).width * fontSize;
      if (width > maxWidth && current != '• ') {
        lines.add(current.trimRight());
        current = '  $w ';
      } else {
        current = candidate;
      }
    }
    if (current.trim().isNotEmpty) lines.add(current.trimRight());
    return lines;
  }

  ///   5) осевая сетка с кружками (А/Б/В… и 1/2/3…), внешние размерные
  ///      цепи (шаг между осями + общий габарит), отметка ±0.000,
  ///      указатель севера.
  static void _paintPlan(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    PdfFont font,
    WallMaterial? wallMaterial, {
    String? staircaseType,
    int? staircaseSteps,
    double? floorHeight,
    PdfFont? fontBold,
    HouseProject? project,
  }) {
    final w = size.x;
    final h = size.y;
    // Размер полей вокруг плана для размерных цепей, кружков осей и стрелки
    // севера. Всё за границей плана в пределах этого «канта» — сетка, а не
    // сам план.
    // Дополнительные сдвиги цепей, если у плана есть пристройки слева
    // (att.x < 0) или снизу (att.y + att.height > planHeight). Размер в
    // метрах (плана) → перевод в pt будет через scale, поэтому на этапе
    // подбора marginов мы используем максимально-предполагаемый scale.
    double leftAttMt = 0.0;
    double bottomAttMt = 0.0;
    for (final a in plan.attachments) {
      if (a.x < 0 && -a.x > leftAttMt) leftAttMt = -a.x;
      if (a.y + a.height > plan.height) {
        final extra = a.y + a.height - plan.height;
        if (extra > bottomAttMt) bottomAttMt = extra;
      }
    }
    // Грубая оценка scale (без учёта marginов) — нужна, чтобы посчитать,
    // насколько надо увеличить marginLeft/marginBottom под пристройки.
    // Поля под цепи увеличены до 152 pt (раньше 130) после правки
    // пользователя — теперь общая цепь стоит на 112 pt от плана + 20 pt
    // запаса под кружок оси Ø 22 + 20 pt под подпись «общий габарит».
    // Поля плана: правка по листу 8 — наименование оси ставится ПОСЛЕ
    // всех размеров. yAxisBase теперь = chainTotalLeft + 50 = 190 (без
    // цепи по карнизу). marginLeft вмещает axes 190 + R 11 + label 8 +
    // 11 запаса = 220. marginBottom фитит chainTotal 140 + подписи 40.
    const baseMarginLeft = 220.0;
    const baseMarginRight = 200.0;
    const baseMarginTop = 175.0;
    const baseMarginBottom = 180.0;
    final approxScale = math.min(
      (w - baseMarginLeft - baseMarginRight) / plan.width,
      (h - baseMarginTop - baseMarginBottom) / plan.height,
    );
    final marginLeft = baseMarginLeft + leftAttMt * approxScale;
    const marginRight = baseMarginRight;
    const marginTop = baseMarginTop;
    final marginBottom = baseMarginBottom + bottomAttMt * approxScale;
    final scaleX = (w - marginLeft - marginRight) / plan.width;
    final scaleY = (h - marginTop - marginBottom) / plan.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final planW = plan.width * scale;
    final planH = plan.height * scale;
    final ox = marginLeft + ((w - marginLeft - marginRight) - planW) / 2;
    final oy = marginTop + ((h - marginTop - marginBottom) - planH) / 2;

    // PdfGraphics ось Y направлена вверх. У нас в модели — вниз.
    PdfPoint pp(double mx, double my) =>
        PdfPoint(ox + mx * scale, oy + planH - my * scale);

    void fillRectM(double mx, double my, double mw, double mh) {
      final tl = pp(mx, my);
      canvas.drawRect(tl.x, tl.y - mh * scale, mw * scale, mh * scale);
      canvas.fillPath();
    }

    void strokeRectM(
      double mx,
      double my,
      double mw,
      double mh,
    ) {
      final tl = pp(mx, my);
      canvas.drawRect(tl.x, tl.y - mh * scale, mw * scale, mh * scale);
      canvas.strokePath();
    }

    /// Phase-3b §17.2.1. Строит замкнутый PDF-путь по контуру пятна
    /// застройки (`plan.effectiveFootprint`) с учётом дырок. Не выполняет
    /// заливку/обводку — это делает вызывающий код через `fillPath` /
    /// `strokePath`. Для прямоугольных планов даёт ровно тот же путь,
    /// что и `drawRect(0, 0, plan.width, plan.height)`.
    void buildFootprintPath() {
      final fp = plan.effectiveFootprint;
      if (fp.outline.isEmpty) return;
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

    // 1. Заливка всего пятна цветом массы стены.
    // Для прямоугольных планов — старый путь (drawRect). Для полигональных
    // (L/T/U-образных) — обход контура moveTo/lineTo + fillPath с
    // even-odd правилом для дырок.
    canvas.setFillColor(_wallMassColor);
    if (plan.hasPolygonalFootprint) {
      buildFootprintPath();
      canvas.fillPath(evenOdd: true);
    } else {
      fillRectM(0, 0, plan.width, plan.height);
    }

    // 1b. Штриховка под выбранный материал стен (ГОСТ 2.306-68).
    // Рисуем по всему пятну — рост рендера: затем комнаты перекроют
    // штриховку белой заливкой, штриховка останется только в массе стены.
    // Phase-3b §17.2.1: для полигонального footprint обрамляем штриховку
    // PDF-clip-path по контуру полигона, чтобы паттерн не вылезал в
    // зону выреза L/T/U-форм.
    if (plan.hasPolygonalFootprint) {
      canvas.saveContext();
      buildFootprintPath();
      canvas.clipPath(evenOdd: true);
    }
    _paintWallHatching(
      canvas,
      pp,
      plan,
      scale,
      ox: ox,
      oy: oy,
      planW: planW,
      planH: planH,
      material: wallMaterial,
    );
    if (plan.hasPolygonalFootprint) {
      canvas.restoreContext();
    }

    // 2. Внутренние прямоугольники комнат поверх стен (закрывают штриховку).
    // Цвет заливки выбирается канонической палитрой по `roomKindName`
    // (см. RoomPalette) — это даёт визуальную идентификацию помещений
    // как у каталожных шаблонов (T-237, T-241_1 и т.п.). Для комнат
    // без roomKindName используется fallback по PlanRoomKind, что
    // совпадает со старым поведением (белая заливка).
    for (final r in plan.rooms) {
      final inner = _innerRect(r, plan);
      if (inner == null) continue;
      final fillColor = RoomPalette.fillFor(r);
      canvas.setFillColor(fillColor);
      fillRectM(inner.mx, inner.my, inner.mw, inner.mh);
      if (r.kind == PlanRoomKind.staircase) {
        // На плане 1-го этажа лестница в подвал указывается стрелкой
        // «вниз» (направление противоположно основной — наверх).
        // По требованию заказчика (п. 25): «лестница, ведущая из
        // подвала или цокольного этажа, должна быть указана на
        // чертеже плана первого этажа».
        final isFirstFloor = plan.floorLabel.startsWith('Этаж 1') ||
            plan.floorLabel.contains('1-');
        final hasBasement =
            project?.brief.hasBasement == true && isFirstFloor;
        _drawStaircasePattern(
          canvas,
          font,
          pp,
          inner,
          staircaseType: staircaseType,
          steps: staircaseSteps,
          floorHeight: floorHeight,
          descentToBasement: hasBasement,
        );
      }
    }

    // 2b. Контуры внутренних стен — обводим каждую комнату тонкой
    // линией 0.4. Это даёт визуальный «рисунок» внутренних стен,
    // т. к. подложка стены теперь светлая. Лестницу намеренно не
    // обводим: иначе перед маршем появлялась лишняя стена,
    // которой в реальном проекте быть не должно (требование
    // заказчика п. 9 — никогда не добавлять стену перед лестницей).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    for (final r in plan.rooms) {
      if (r.kind == PlanRoomKind.staircase) continue;
      final inner = _innerRect(r, plan);
      if (inner == null) continue;
      strokeRectM(inner.mx, inner.my, inner.mw, inner.mh);
    }

    // 2c. Мебель и сантехника (Phase-1 MVP). Рисуем поверх заливки
    // комнат, но ДО проёмов — чтобы дуги дверей перекрывали мебель,
    // когда расстановка слишком близко подошла к проёму.
    for (final r in plan.rooms) {
      if (r.furniture.isEmpty) continue;
      for (final f in r.furniture) {
        _drawFurnitureSymbol(canvas, f, pp, scale);
      }
    }

    // 3. Проёмы — окна, двери, открытые проходы.
    for (final o in plan.openings) {
      _drawOpening(canvas, plan, o, pp, scale);
    }

    // 3b. Марки проёмов (ОК-1, Д-1...) — кружок с буквой рядом
    // с каждым проёмом. Нумерация по порядку типов в ведомости.
    _paintOpeningMarkers(canvas, font, plan, pp, scale);

    // 4. Подписи комнат — по ГОСТ Р 21.501: номер в кружке + название
    // + площадь с подчёркиванием.
    var roomNumber = 0;
    for (final r in plan.rooms) {
      final inner = _innerRect(r, plan);
      if (inner == null) continue;
      final innerWPx = inner.mw * scale;
      final innerHPx = inner.mh * scale;
      if (innerWPx < 30 || innerHPx < 24) continue;
      roomNumber++;
      // Для лестницы кружок номера не рисуем — она уже имеет
      // собственный визуальный блок (стрелка «↑/↓» + подпись
      // «Лестница X.X м²»), и кружок в любой части комнаты
      // налезает либо на стрелку, либо на надпись (правка
      // пользователя по листу 5).
      if (r.kind == PlanRoomKind.staircase) continue;
      final cx = ox + (inner.mx + inner.mw / 2) * scale;
      final cy = oy + planH - (inner.my + inner.mh / 2) * scale;

      // Для тесных комнат (< 6 м² или физически узкая клетка) внутри
      // оставляем ТОЛЬКО кружок номера. Полная подпись «N. Имя X.X м²»
      // и так дублируется в таблице «Экспликация помещений» на этом
      // же листе — внутрь её втискивать не нужно, иначе слои текста
      // налезают друг на друга (правка пользователя по листу 5).
      // Дополнительно: в тесной комнате кружок ставим в верхний-левый
      // угол внутреннего бокса, а НЕ в центр. Иначе он наезжает на
      // марки внутренних дверей (Д-1), которые выносятся в полосу
      // 22 pt по нормали к стене — для межкомнатной двери эта полоса
      // часто оказывается ровно по центру соседней комнаты.
      final tight = r.area < 6.0 || innerWPx < 60 || innerHPx < 50;
      final fontSize = (innerWPx > 80 ? 9 : 7).toDouble();
      final numText = '$roomNumber';
      final numFs = fontSize + 1;
      final ntw = font.stringMetrics(numText).width * numFs;
      final numR = math.max<double>(fontSize * 0.85, ntw / 2 + 1.4);
      // В PDF Y направлен ВВЕРХ. Верхняя кромка внутреннего бокса в
      // canvas-координатах — `oy + planH - inner.my * scale`.
      final innerLeft = ox + inner.mx * scale;
      final innerTopCanvas = oy + planH - inner.my * scale;
      final numCx = tight ? innerLeft + numR + 3 : cx;
      final numCy =
          tight ? innerTopCanvas - numR - 3 : cy + fontSize * 1.3;
      canvas.setFillColor(PdfColors.white);
      canvas.drawEllipse(numCx, numCy, numR, numR);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.drawEllipse(numCx, numCy, numR, numR);
      canvas.strokePath();
      _drawCenteredText(
        canvas,
        numText,
        numCx,
        numCy,
        fontSize: numFs,
        font: font,
      );

      if (tight) continue;

      // Длинные названия комнат могут не помещаться в узкие комнаты,
      // поэтому ограничиваем ширину текста размерами внутренней ячейки.
      final maxLabelWidth = innerWPx - 6;
      _drawCenteredText(
        canvas,
        r.label,
        cx,
        cy,
        fontSize: fontSize,
        font: font,
        maxWidth: maxLabelWidth,
      );
      _drawCenteredText(
        canvas,
        '${r.area.toStringAsFixed(1)} м²',
        cx,
        cy - fontSize * 1.3,
        fontSize: fontSize,
        font: font,
        maxWidth: maxLabelWidth,
      );
      // Линия-подчёркивание под текстом площади (ГОСТ-стиль).
      // Линия должна находиться НИЖЕ нижней кромки символов, а не
      // зачёркивать их. Видимая глубина текста ниже геометрического
      // центра ≈ 0.35·fontSize. Берём ещё 2 pt запаса.
      final areaText = '${r.area.toStringAsFixed(1)} м²';
      final estW = font.stringMetrics(areaText).width * fontSize;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.3);
      final lineY = cy - fontSize * 1.3 - fontSize * 0.35 - 2;
      canvas.drawLine(cx - estW / 2, lineY, cx + estW / 2, lineY);
      canvas.strokePath();
    }

    // 5. Внешний контур пятна — поверх всего, утолщённый по ГОСТ.
    // Для полигональных планов — обводка по контуру `footprint.outline`
    // вместо bbox, чтобы стены ходили по «уступам» L/T/U-форм.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    if (plan.hasPolygonalFootprint) {
      buildFootprintPath();
      canvas.strokePath();
    } else {
      strokeRectM(0, 0, plan.width, plan.height);
    }

    // 5a. Пристройки: крыльцо + (опционально) терраса за наружной стеной.
    _paintAttachments(canvas, font, pp, plan, scale);

    // 5b. Колонны (ж/б 400×400 мм) — рисуются если задана высота этажа
    // > 3.3 м и пролёты комнат > 6 м (СП 63.13330.2018, п.10 v40).
    if (plan.columns.isNotEmpty) {
      for (final c in plan.columns) {
        final ccx = ox + c.x * scale;
        final ccy = oy + planH - c.y * scale;
        final halfPx = (c.sizeM / 2) * scale;
        // Чёрный квадрат с белой меткой — стандартное обозначение
        // колонн на КЖ-плане.
        canvas.setFillColor(PdfColors.black);
        canvas.drawRect(ccx - halfPx, ccy - halfPx, halfPx * 2, halfPx * 2);
        canvas.fillPath();
        // Маркировка «К1, К2…» рядом с колонной (справа+сверху).
        canvas.setFillColor(PdfColors.black);
        _drawCenteredText(
          canvas,
          c.label,
          ccx + halfPx + 8,
          ccy + halfPx + 4,
          fontSize: 6.5,
          font: font,
        );
      }
    }

    // 6. Осевая сетка, размерные цепи, стрелка севера.
    // Отметку ±0.000 на плане АР-5 НЕ рисуем — по правке пользователя
    // от 2026-05-05 на этом листе она избыточна (отметки высот идут на
    // фасадах и разрезах). Триангольник-флажок налезал на внутреннюю
    // подпись «Холл лестницы».
    _paintAxesAndDimensions(
      canvas: canvas,
      plan: plan,
      font: font,
      fontBold: fontBold,
      ox: ox,
      oy: oy,
      planW: planW,
      planH: planH,
      scale: scale,
      drawZeroMark: false,
    );

    // 6b. Отметки линий разрезов 1-1 и 2-2 — только на плане 1-го этажа
    // (ГОСТ 21.101). Разрез 1-1 — вертикальная секущая через центр X,
    // разрез 2-2 — горизонтальная через центр Y.
    if (plan.floorLabel.startsWith('Этаж 1') ||
        plan.floorLabel.contains('1-')) {
      _paintSectionMarks(
        canvas: canvas,
        font: font,
        plan: plan,
        ox: ox,
        oy: oy,
        planW: planW,
        planH: planH,
        scale: scale,
      );
    }

    // 7. Экспликация помещений и ведомости проёмов — выравниваем по
    // правому краю канвы, чтобы крайняя правая линия таблиц
    // совпадала с внутренним контуром листа (см. правки заказчика
    // п. 11). Раньше ведомости и экспликация были привязаны к плану
    // через `+130 pt`, из-за чего их правая граница «плавала» в
    // зависимости от размера дома.
    const explicationWidth = 175.0;
    final explicationX = w - explicationWidth;
    final explicationY = oy + planH;
    final explicationBottomY = _paintExplicationTable(
      canvas,
      font,
      plan,
      x: explicationX,
      yTop: explicationY,
      width: explicationWidth,
    );

    // 8. Ведомости окон и дверей — справа, под экспликацией.
    // Это убирает конфликт с нижней осевой сеткой и размерной цепью.
    final schedY = explicationBottomY - 25;
    _paintOpeningSchedule(
      canvas,
      font,
      plan,
      x: explicationX,
      yTop: schedY,
      totalWidth: explicationWidth,
    );
  }

  /// Рисует метки секущих плоскостей 1-1 и 2-2 на плане 1-го этажа по
  /// ГОСТ 21.101-2020 в том же графическом виде, что и условное
  /// обозначение «Линия и направление сечения» на листе АР-3
  /// (см. `pdf_general_data.dart` → `_buildLegendSymbol('sectionMark')`):
  ///   • толстый штрих, перпендикулярный оси разреза (по концам секущей);
  ///   • два тонких засечка-перпендикуляра на концах толстого штриха;
  ///   • заполненная стрелка-треугольник в направлении взгляда;
  ///   • цифра-номер разреза рядом со стрелкой.
  static void _paintSectionMarks({
    required PdfGraphics canvas,
    required PdfFont font,
    required FloorPlan plan,
    required double ox,
    required double oy,
    required double planW,
    required double planH,
    required double scale,
  }) {
    const markLen = 18.0; // длина основного штриха (как в АР-3)
    const tickLen = 5.0; // длина засечек-перпендикуляров на концах
    const arrowLen = 9.0;
    const arrowHalf = 3.0;
    const gap = 6.0; // отступ метки от границы плана

    // Подбираем позицию секущих, не попадающую в зоны крылец/террас.
    final modelHalfH = plan.height / 2;
    final modelHalfW = plan.width / 2;
    final clearY = _findClearAxisPosition(
      attachments: plan.attachments,
      isHorizontal: false,
      buildingExtent: plan.height,
      defaultPos: modelHalfH,
    );
    final clearX = _findClearAxisPosition(
      attachments: plan.attachments,
      isHorizontal: true,
      buildingExtent: plan.width,
      defaultPos: modelHalfW,
    );

    // Хелперы для отрисовки одного «торца» секущей плоскости.
    // sign = +1 если стрелка должна смотреть «внутрь плана» (т.е.
    // на лист со стороны метки), −1 наоборот. Для меток на левой
    // стороне плана стрелка идёт вправо (sign=+1), на правой —
    // влево (sign=−1) и т.д.
    void drawHorizontalEnd({
      required double cx,
      required double cy,
      required int arrowDirX, // +1 или -1: куда смотрит стрелка
      required String label,
    }) {
      // Толстый вертикальный штрих.
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(1.6);
      canvas.drawLine(cx, cy - markLen / 2, cx, cy + markLen / 2);
      canvas.strokePath();
      // Засечки-перпендикуляры (горизонтальные тонкие штрихи).
      canvas.setLineWidth(1.0);
      canvas.drawLine(
          cx - tickLen, cy + markLen / 2, cx + tickLen, cy + markLen / 2);
      canvas.drawLine(
          cx - tickLen, cy - markLen / 2, cx + tickLen, cy - markLen / 2);
      canvas.strokePath();
      // Стрелка-треугольник, заполненная, в направлении arrowDirX.
      // Базис — у нижней засечки (cy - markLen/2), как в АР-3 (там стрелка
      // у верхнего края, но логика та же: в торце штриха).
      canvas.setLineWidth(0.6);
      final ay = cy - markLen / 2;
      final ax0 = cx + arrowDirX * tickLen;
      final ax1 = cx + arrowDirX * (tickLen + arrowLen);
      canvas.moveTo(ax1, ay);
      canvas.lineTo(ax0, ay + arrowHalf);
      canvas.lineTo(ax0, ay - arrowHalf);
      canvas.lineTo(ax1, ay);
      canvas.fillPath();
      // Подпись (цифра) — за стрелкой по её ходу.
      _drawCenteredText(
          canvas,
          label,
          ax1 + arrowDirX * 6,
          ay - 3,
          fontSize: 9,
          font: font);
    }

    void drawVerticalEnd({
      required double cx,
      required double cy,
      required int arrowDirY, // +1 (вверх) или -1 (вниз)
      required String label,
    }) {
      // Толстый горизонтальный штрих.
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(1.6);
      canvas.drawLine(cx - markLen / 2, cy, cx + markLen / 2, cy);
      canvas.strokePath();
      // Засечки-перпендикуляры (вертикальные тонкие штрихи).
      canvas.setLineWidth(1.0);
      canvas.drawLine(
          cx - markLen / 2, cy - tickLen, cx - markLen / 2, cy + tickLen);
      canvas.drawLine(
          cx + markLen / 2, cy - tickLen, cx + markLen / 2, cy + tickLen);
      canvas.strokePath();
      // Стрелка-треугольник вертикальная.
      canvas.setLineWidth(0.6);
      final ax = cx - markLen / 2;
      final ay0 = cy + arrowDirY * tickLen;
      final ay1 = cy + arrowDirY * (tickLen + arrowLen);
      canvas.moveTo(ax, ay1);
      canvas.lineTo(ax + arrowHalf, ay0);
      canvas.lineTo(ax - arrowHalf, ay0);
      canvas.lineTo(ax, ay1);
      canvas.fillPath();
      // Подпись (цифра) — за стрелкой по её ходу.
      _drawCenteredText(
          canvas,
          label,
          ax,
          ay1 + arrowDirY * 8 - 3,
          fontSize: 9,
          font: font);
    }

    // Разрез 1-1 — горизонтальная секущая на плане (по строке clearY).
    // Метки рисуются на левой и правой стороне плана.
    final y1 = oy + planH - clearY * scale;
    drawHorizontalEnd(
      cx: ox - gap - markLen / 2,
      cy: y1,
      arrowDirX: 1, // взгляд внутрь плана (вправо)
      label: '1',
    );
    drawHorizontalEnd(
      cx: ox + planW + gap + markLen / 2,
      cy: y1,
      arrowDirX: -1, // взгляд внутрь плана (влево)
      label: '1',
    );

    // Разрез 2-2 — вертикальная секущая на плане (по столбцу clearX).
    // Метки сверху и снизу плана.
    final x2 = ox + clearX * scale;
    drawVerticalEnd(
      cx: x2,
      cy: oy - gap - markLen / 2,
      arrowDirY: 1, // взгляд внутрь плана (вверх)
      label: '2',
    );
    drawVerticalEnd(
      cx: x2,
      cy: oy + planH + gap + markLen / 2,
      arrowDirY: -1, // взгляд внутрь плана (вниз)
      label: '2',
    );
  }

  /// Подбирает координату секущей плоскости (X или Y в модели), не
  /// попадающую в зоны крылец/террас. Зоны блокировки определяются
  /// по выступам пристроек за внешний контур пятна:
  /// - `isHorizontal=true` — секущая по X-оси (вертикальная линия на
  ///   плане), блокировка по пристройкам сверху/снизу (y<0 или
  ///   y+height>planHeight); ищем чистый X.
  /// - `isHorizontal=false` — секущая по Y-оси, блокировка по пристройкам
  ///   слева/справа (x<0 или x+width>planWidth); ищем чистый Y.
  /// Возвращает координату в метрах в системе плана, в пределах [0, ext].
  static double _findClearAxisPosition({
    required List<PlanAttachment> attachments,
    required bool isHorizontal,
    required double buildingExtent,
    required double defaultPos,
    double margin = 0.4,
  }) {
    // Собираем «forbidden ranges» по нужной оси.
    final forbidden = <(double, double)>[];
    for (final a in attachments) {
      final blocks = isHorizontal
          ? (a.y < -0.01 || a.y + a.height > buildingExtent + 0.01) // СС/Юг
          : (a.x < -0.01 || a.x + a.width > buildingExtent + 0.01); // З/В
      if (!blocks) continue;
      final start = isHorizontal ? a.x : a.y;
      final end = isHorizontal ? a.x + a.width : a.y + a.height;
      forbidden.add((start - margin, end + margin));
    }
    bool isFree(double v) {
      if (v < margin || v > buildingExtent - margin) return false;
      for (final (s, e) in forbidden) {
        if (v >= s && v <= e) return false;
      }
      return true;
    }
    if (isFree(defaultPos)) return defaultPos;
    // Поиск ближайшей чистой точки шагом 0.5 м.
    const step = 0.5;
    for (var d = step; d <= buildingExtent; d += step) {
      final left = defaultPos - d;
      final right = defaultPos + d;
      if (isFree(right)) return right;
      if (isFree(left)) return left;
    }
    return defaultPos; // fallback — ничего не нашли, рисуем по центру
  }

  /// Марки проёмов на плане: ОК-1, ОК-2... для окон, Д-1, Д-2...
  /// для дверей. Нумерация по уникальным размерам (совпадает
  /// с нумерацией в ведомости окон/дверей).
  static void _paintOpeningMarkers(
    PdfGraphics canvas,
    PdfFont font,
    FloorPlan plan,
    PdfPoint Function(double, double) pp,
    double scale,
  ) {
    // Группировка проёмов по размерам — должна совпадать с ведомостью.
    final windowSizes = <String>[]; // порядок появления в sorted entries
    final doorSizes = <String>[];
    // Сначала строим то же отображение размер→количество, что в ведомости,
    // и делаем sort по убыванию количества.
    final windowsCount = <String, int>{};
    final doorsCount = <String, int>{};
    for (final o in plan.openings) {
      final lenMm = (o.length * 1000).round();
      final hMm = switch (o.kind) {
        OpeningKind.window => 1500,
        OpeningKind.externalDoor => 2100,
        _ => 2000,
      };
      final key = '$lenMm×$hMm';
      if (o.kind == OpeningKind.window) {
        windowsCount[key] = (windowsCount[key] ?? 0) + 1;
      } else if (o.kind == OpeningKind.door ||
          o.kind == OpeningKind.externalDoor) {
        doorsCount[key] = (doorsCount[key] ?? 0) + 1;
      }
    }
    final wSorted = windowsCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dSorted = doorsCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in wSorted) {
      windowSizes.add(e.key);
    }
    for (final e in dSorted) {
      doorSizes.add(e.key);
    }
    // Теперь для каждого проёма рисуем кружок-марку.
    const circleR = 7.0;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.white);
    canvas.setLineWidth(0.4);
    for (final o in plan.openings) {
      final lenMm = (o.length * 1000).round();
      final hMm = switch (o.kind) {
        OpeningKind.window => 1500,
        OpeningKind.externalDoor => 2100,
        _ => 2000,
      };
      final key = '$lenMm×$hMm';
      String? mark;
      if (o.kind == OpeningKind.window) {
        final idx = windowSizes.indexOf(key);
        if (idx >= 0) mark = 'ОК-${idx + 1}';
      } else if (o.kind == OpeningKind.door ||
          o.kind == OpeningKind.externalDoor) {
        final idx = doorSizes.indexOf(key);
        if (idx >= 0) mark = 'Д-${idx + 1}';
      }
      if (mark == null) continue;
      // Смещение марки — наружу от стены, по нормали.
      final cxM = switch (o.side) {
        WallSide.left => o.x,
        WallSide.right => o.x,
        WallSide.top => o.x + o.length / 2,
        WallSide.bottom => o.x + o.length / 2,
      };
      final cyM = switch (o.side) {
        WallSide.left => o.y + o.length / 2,
        WallSide.right => o.y + o.length / 2,
        WallSide.top => o.y,
        WallSide.bottom => o.y,
      };
      final p = pp(cxM, cyM);
      // Марку выносим НАРУЖУ плана, чтобы не пересекалась с подписями
      // комнат и площадями (правка пользователя по листу 5: при
      // смещении внутрь "ОК-1" / "Д-1" наезжали на названия помещений
      // и площади, а в узких комнатах вообще все подписи слипались).
      // Снаружи марки занимают полосу между стеной и кружками осей,
      // которые сейчас отодвинуты на 100+ pt — места достаточно.
      double dx = 0, dy = 0;
      const off = 22.0;
      switch (o.side) {
        case WallSide.left:
          dx = -off;
        case WallSide.right:
          dx = off;
        case WallSide.top:
          dy = off;
        case WallSide.bottom:
          dy = -off;
      }
      final cx = p.x + dx;
      final cy = p.y + dy;
      // Линия от проёма к марке.
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.3);
      canvas.drawLine(p.x, p.y, cx, cy);
      canvas.strokePath();
      // Белый кружок с чёрной обводкой. Авто-увеличение радиуса,
      // если ширина текста марки больше диаметра.
      const markFs = 6.0;
      final tw = font.stringMetrics(mark).width * markFs;
      final radius = math.max<double>(circleR, tw / 2 + 1.6);
      canvas.setFillColor(PdfColors.white);
      canvas.drawEllipse(cx, cy, radius, radius);
      canvas.fillPath();
      canvas.drawEllipse(cx, cy, radius, radius);
      canvas.strokePath();
      canvas.setFillColor(PdfColors.black);
      // Текст по центру кружка: y = cy (геометрический центр), функция
      // _drawCenteredText сама опустит baseline на 0.35·fontSize.
      _drawCenteredText(canvas, mark, cx, cy,
          fontSize: markFs, font: font);
    }
  }

  /// Экспликация помещений: таблица №/Наименование/Площадь (м²).
  /// Возвращает Y-координату нижнего края таблицы.
  static double _paintExplicationTable(
    PdfGraphics canvas,
    PdfFont font,
    FloorPlan plan, {
    required double x,
    required double yTop,
    required double width,
  }) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    const colNo = 20.0;
    const colArea = 50.0;
    final colName = width - colNo - colArea;
    const rowH = 14.0;
    const headerH = 16.0;

    // Заголовок над таблицей.
    canvas.setLineWidth(0.4);
    canvas.drawString(
      font,
      9,
      'Экспликация помещений',
      x,
      yTop + 6,
    );

    // Шапка
    var y = yTop - headerH;
    canvas.drawRect(x, y, width, headerH);
    canvas.strokePath();
    canvas.drawLine(x + colNo, y, x + colNo, y + headerH);
    canvas.strokePath();
    canvas.drawLine(x + colNo + colName, y, x + colNo + colName, y + headerH);
    canvas.strokePath();
    _drawCenteredText(canvas, '№', x + colNo / 2, y + headerH / 2,
        fontSize: 8, font: font);
    _drawCenteredText(canvas, 'Наименование',
        x + colNo + colName / 2, y + headerH / 2,
        fontSize: 8, font: font);
    _drawCenteredText(canvas, 'Пл., м²',
        x + colNo + colName + colArea / 2, y + headerH / 2,
        fontSize: 8, font: font);

    // Строки помещений (только real rooms, не свободная зона).
    var n = 0;
    double total = 0;
    for (final r in plan.rooms) {
      final inner = _innerRect(r, plan);
      if (inner == null) continue;
      // Slip free zones in numbering (но не пропускаем, считаем,
      // т. к. в плане они нумеруются вместе).
      n++;
      total += r.area;
      y -= rowH;
      canvas.drawRect(x, y, width, rowH);
      canvas.strokePath();
      canvas.drawLine(x + colNo, y, x + colNo, y + rowH);
      canvas.strokePath();
      canvas.drawLine(x + colNo + colName, y, x + colNo + colName, y + rowH);
      canvas.strokePath();
      _drawCenteredText(canvas, '$n', x + colNo / 2, y + rowH / 2,
          fontSize: 8, font: font);
      _drawClippedLeftText(
        canvas,
        font,
        text: r.label,
        x: x + colNo + 4,
        y: y + rowH / 2 - 8 * 0.35,
        fontSize: 8,
        maxWidth: colName - 8,
      );
      _drawCenteredText(canvas, r.area.toStringAsFixed(2),
          x + colNo + colName + colArea / 2, y + rowH / 2,
          fontSize: 8, font: font, maxWidth: colArea - 4);
    }
    // Итоговая строка.
    y -= rowH;
    canvas.drawRect(x, y, width, rowH);
    canvas.strokePath();
    canvas.drawLine(x + colNo + colName, y, x + colNo + colName, y + rowH);
    canvas.strokePath();
    canvas.drawString(
        font, 8, 'Итого:', x + 4, y + rowH / 2 - 8 * 0.35);
    _drawCenteredText(canvas, total.toStringAsFixed(2),
        x + colNo + colName + colArea / 2, y + rowH / 2,
        fontSize: 8, font: font);
    return y;
  }

  /// Ведомость окон и дверей по проёмам плана. Группировка по размеру.
  /// Таблицы выводятся друг под другом (сверху окна, снизу двери).
  static void _paintOpeningSchedule(
    PdfGraphics canvas,
    PdfFont font,
    FloorPlan plan, {
    required double x,
    required double yTop,
    required double totalWidth,
  }) {
    // Группируем окна и двери по размерам.
    final windows = <String, int>{};
    final doors = <String, int>{};
    for (final o in plan.openings) {
      final lenMm = (o.length * 1000).round();
      // Высота берётся стандартная: окно 1500, дверь внутр. 2000, наруж. 2100.
      final hMm = switch (o.kind) {
        OpeningKind.window => 1500,
        OpeningKind.externalDoor => 2100,
        _ => 2000,
      };
      final key = '$lenMm×$hMm';
      if (o.kind == OpeningKind.window) {
        windows[key] = (windows[key] ?? 0) + 1;
      } else if (o.kind == OpeningKind.door ||
          o.kind == OpeningKind.externalDoor) {
        doors[key] = (doors[key] ?? 0) + 1;
      }
    }

    final bottomAfterWindows = _drawScheduleTable(
      canvas, font, 'Спецификация окон',
      windows, prefix: 'ОК',
      x: x, yTop: yTop, width: totalWidth);
    _drawScheduleTable(
      canvas, font, 'Спецификация дверей',
      doors, prefix: 'Д',
      x: x, yTop: bottomAfterWindows - 25, width: totalWidth);
  }

  static double _drawScheduleTable(
    PdfGraphics canvas,
    PdfFont font,
    String title,
    Map<String, int> sizesToCount, {
    required String prefix,
    required double x,
    required double yTop,
    required double width,
  }) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawString(font, 9, title, x, yTop + 6);
    const colMark = 38.0;
    final colSize = (width - colMark - 36);
    const colCount = 36.0;
    const headerH = 16.0;
    const rowH = 12.0;
    var y = yTop - headerH;
    canvas.drawRect(x, y, width, headerH);
    canvas.strokePath();
    canvas.drawLine(x + colMark, y, x + colMark, y + headerH);
    canvas.strokePath();
    canvas.drawLine(x + colMark + colSize, y,
        x + colMark + colSize, y + headerH);
    canvas.strokePath();
    _drawCenteredText(canvas, 'Марка', x + colMark / 2, y + headerH / 2,
        fontSize: 8, font: font);
    _drawCenteredText(canvas, 'Размеры (Ш×В), мм',
        x + colMark + colSize / 2, y + headerH / 2,
        fontSize: 8, font: font);
    _drawCenteredText(canvas, 'Кол.',
        x + colMark + colSize + colCount / 2, y + headerH / 2,
        fontSize: 8, font: font);
    var n = 0;
    final entries = sizesToCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries) {
      n++;
      y -= rowH;
      canvas.drawRect(x, y, width, rowH);
      canvas.strokePath();
      canvas.drawLine(x + colMark, y, x + colMark, y + rowH);
      canvas.strokePath();
      canvas.drawLine(x + colMark + colSize, y,
          x + colMark + colSize, y + rowH);
      canvas.strokePath();
      _drawCenteredText(canvas, '$prefix-$n',
          x + colMark / 2, y + rowH / 2,
          fontSize: 8, font: font, maxWidth: colMark - 4);
      _drawCenteredText(canvas, e.key,
          x + colMark + colSize / 2, y + rowH / 2,
          fontSize: 8, font: font, maxWidth: colSize - 4);
      _drawCenteredText(canvas, '${e.value}',
          x + colMark + colSize + colCount / 2, y + rowH / 2,
          fontSize: 8, font: font, maxWidth: colCount - 4);
    }
    return y;
  }

  /// Буквы русского алфавита для обозначения продольных осей, с
  /// пропуском Ё, З, Й, О, Х, Ъ, Ы, Ь, Ч (ГОСТ Р 21.101-2020, п. 5.7.6).
  static const List<String> _axisLetters = [
    'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж',
    'И', 'К', 'Л', 'М', 'Н', 'П', 'Р',
    'С', 'Т', 'У', 'Ф', 'Ц', 'Ш', 'Щ',
    'Э', 'Ю', 'Я',
  ];

  /// Собирает уникальные координаты стен плана по выбранной оси.
  /// На сборку идут:
  ///   — внешние границы (0 и размер пятна);
  ///   — любые x/y, в которых лежит стена между двумя смежными комнатами.
  /// Координаты округляются с шагом 0.05 м, чтобы объединять «почти
  /// одинаковые» значения.
  /// Для указанной наружной стороны возвращает отсортированный список
  /// точек «простенков и проёмов»: края всех наружных проёмов на этой
  /// стороне + 0 и длина стороны. Сегменты между этими точками
  /// чередуются: «простенок, проём, простенок, проём, …».
  static List<double> _breakPointsOnSide(FloorPlan plan, WallSide side) {
    final outerEnd = side.isHorizontal ? plan.width : plan.height;
    final pts = <double>{0.0, outerEnd};
    for (final o in plan.openings) {
      if (o.side != side) continue;
      if (!_isOpeningOnOuterWall(plan, o)) continue;
      final start = side.isHorizontal ? o.x : o.y;
      pts.add(start);
      pts.add(start + o.length);
    }
    final sorted = pts.toList()..sort();
    // Отсекаем совсем близкие точки (< 3 см).
    final out = <double>[];
    for (final v in sorted) {
      if (out.isEmpty || (v - out.last).abs() > 0.03) out.add(v);
    }
    return out;
  }

  static List<double> _collectAxes(FloorPlan plan, bool isX) {
    final outerEnd = isX ? plan.width : plan.height;
    final set = <double>{0.0, outerEnd};
    for (final r in plan.rooms) {
      if (isX) {
        set.add(r.x);
        set.add(r.x + r.width);
      } else {
        set.add(r.y);
        set.add(r.y + r.height);
      }
    }
    final snapped = <double>[];
    for (final v in set) {
      final rounded = (v * 20).round() / 20; // шаг 0.05 м
      if (!snapped.any((s) => (s - rounded).abs() < 0.04)) {
        snapped.add(rounded);
      }
    }
    snapped.sort();
    // Прореживаем «слипающиеся» оси: если две внутренние оси ближе
    // 0.5 м (типичный артефакт от стен 400-500 мм), оставляем одну.
    // Внешние оси (0 и outerEnd) сохраняем всегда — это контур здания.
    const minGap = 0.5;
    final filtered = <double>[];
    for (final v in snapped) {
      final isPerimeter = v <= 0.04 || (v - outerEnd).abs() < 0.04;
      if (filtered.isEmpty || isPerimeter) {
        filtered.add(v);
        continue;
      }
      final prev = filtered.last;
      final prevIsPerimeter = prev <= 0.04 || (prev - outerEnd).abs() < 0.04;
      if (v - prev < minGap && !prevIsPerimeter) {
        // Заменяем предыдущую внутреннюю ось серединой пары — так не
        // потеряем геометрическую отметку, но избежим двух кружков
        // вплотную.
        filtered[filtered.length - 1] = (prev + v) / 2;
      } else {
        filtered.add(v);
      }
    }
    return filtered;
  }

  static void _paintAxesAndDimensions({
    required PdfGraphics canvas,
    required FloorPlan plan,
    required PdfFont font,
    required double ox,
    required double oy,
    required double planW,
    required double planH,
    required double scale,
    bool drawZeroMark = true,
    bool drawNorthArrow = true,
    bool drawOpeningsChain = true,
    // Включает/выключает нижнюю общую цепь «крайняя ось ↔ крайняя ось»
    // по численным осям (правка пользователя по листу 8: на плане кровли
    // третья горизонтальная линия — это габарит крыши по карнизу, а не
    // межосевой габарит, поэтому межосевую общую цепь снизу отключаем,
    // чтобы цифры/линии не дублировались).
    bool drawTotalChainBottom = true,
    // Аналогично — выключатель левой общей цепи (по буквенным осям).
    // На плане кровли её замещает цепь «по карнизу» вертикальная.
    bool drawTotalChainLeft = true,
    // Базовые смещения цепей «между осями» и «общий габарит» от плана
    // в пунктах PDF. По умолчанию 96 / 140 (см. ГОСТ 21.501-2018 +
    // правки пользователя по листу 5). На плане кровли (Лист 8) пользователь
    // попросил приблизить цепи к чертежу, чтобы габарит не наезжал на
    // штамп — там вызывается со значениями 36 / 76.
    double chainStepOffsetBase = 96.0,
    double chainTotalOffsetBase = 140.0,
    // Дополнительное расстояние самой внешней размерной цепи относительно
    // chainTotalLeft/Bottom (например, цепь «по карнизу» слева на плане
    // кровли). Кружки осей выносятся ЕЩЁ дальше, чтобы стояли после
    // ВСЕХ размеров и подписей.
    double outerChainExt = 0,
    // Учитывать ли пристройки (терраса/гараж/крыльцо) при определении
    // отступа размерных цепей. Для планов этажей и фундамента — да
    // (пристройки физически торчат ниже/левее плана и цепи нужно
    // отнести дальше). Для плана кровли пристройки не рисуются → сдвиг
    // не нужен и только наезжает выносными линиями на штамп
    // (правка пользователя по листу 8).
    bool applyAttachmentShift = true,
    PdfFont? fontBold,
  }) {
    final boldFont = fontBold ?? font;
    // --- Данные осей ---
    final xs = _collectAxes(plan, true); // вертикальные оси → числа
    final ys = _collectAxes(plan, false); // горизонтальные оси → буквы

    // Цифровые метки «1, 2, 3 …» слева-направо для каждой вертикальной оси.
    final xLabels = [for (var i = 0; i < xs.length; i++) '${i + 1}'];
    // Буквенные метки «А, Б, В …» сверху-вниз для каждой горизонтальной оси.
    final yLabels = [
      for (var i = 0; i < ys.length; i++)
        i < _axisLetters.length ? _axisLetters[i] : 'Я${i - _axisLetters.length + 1}',
    ];

    // --- Параметры отрисовки (в пунктах PDF) ---
    // Размерные цепи разнесены, чтобы цифры между линиями не
    // накладывались. При шрифте 8 pt строка ~10 pt + 6 pt запаса = 16 pt
    // шаг по вертикали между линией и текстом, поэтому минимальный шаг
    // между двумя соседними цепями — 22 pt; берём 24 pt с запасом.
    // По правке пользователя по листу 8 (план кровли, изображение): кружки
    // осей и размерные цепи слипались друг с другом — между ними оставалось
    // ~10 pt вместо 20+, поэтому подписи 6300/2250/1575/6075 пересекались с
    // кружками осей (А, Б, В…). axisExtension увеличена с 110 → 150 pt,
    // расстояния цепей разнесены на 20 pt каждое (32→44, 72→96, 112→140).
    // Зазор между внешней цепью (140 pt от плана) и кружком оси (150 + R 11
    // = 161 pt) = 21 pt — достаточно для подписи цепи без наложения.
    // Расширения за пределами пятна (м), которые надо учесть при выносе
    // размерных цепей: пристройки могут торчать ниже/левее плана и тогда
    // цепи просто наложатся на них.
    double bottomAttExtMt = 0.0; // максимум вдоль юга (y > planHeight)
    double leftAttExtMt = 0.0; // максимум вдоль запада (x < 0)
    if (applyAttachmentShift) {
      for (final a in plan.attachments) {
        final extBottom = (a.y + a.height) - plan.height;
        if (extBottom > bottomAttExtMt) bottomAttExtMt = extBottom;
        final extLeft = -a.x;
        if (extLeft > leftAttExtMt) leftAttExtMt = extLeft;
      }
    }
    final double bottomShift =
        bottomAttExtMt > 0 ? bottomAttExtMt * scale + 6 : 0;
    final double leftShift = leftAttExtMt > 0 ? leftAttExtMt * scale + 6 : 0;
    // Кружок оси сверху по-прежнему остаётся над планом (axisExt вверху
    // вне зоны пристроек снизу), но вынос вниз учитывает пристройки.
    const double axisExtension = 150.0;
    // Базовые отступы цепей. Снизу/слева цепи и так уходят за здание;
    // если у плана есть пристройки — увеличиваем отступ соответствующих
    // цепей, чтобы они не накладывались на крыльцо/гараж/террасу.
    //
    // По правке пользователя по листу 5 базовые расстояния цепей увеличены
    // ~ на 25 % (ближняя цепь — с 22 → 32 pt, шаг — 56 → 72 pt, габарит —
    // 90 → 112 pt), чтобы цифры размеров гарантированно НЕ накладывались
    // ни на стены, ни на крыльцо/террасу/гараж/эркер. Это влияет на ВСЕ
    // листы (планы этажей, фундамент, кровля, разрезы) — везде, где
    // применяется `_paintAxesAndDimensions`.
    final double chainOpeningBottom = 44.0 + bottomShift;
    final double chainStepBottom = chainStepOffsetBase + bottomShift;
    final double chainTotalBottom = chainTotalOffsetBase + bottomShift;
    final double chainOpeningLeft = 44.0 + leftShift;
    final double chainStepLeft = chainStepOffsetBase + leftShift;
    final double chainTotalLeft = chainTotalOffsetBase + leftShift;
    const double circleR = 11.0; // радиус кружка ~8 мм в масштабе
    const double labelFontSize = 8.5;
    const double dimFontSize = 7.5;
    // Минимальная ширина сегмента (pt), при которой текст удобно
    // помещается по центру. При меньшей ширине применяется alternating
    // offset — нечётные сегменты ставят текст ближе к плану, чётные —
    // дальше. Это типовой приём при перегруженных размерных цепях.
    const double minSegPt = 22.0;

    canvas.setLineWidth(0.4);

    // --- Штрих-пунктирная линия оси (ГОСТ 2.303-68, тип 4) ---
    // Шаблон: длинный штрих 6 pt + 2 pt пробел + точка + 2 pt пробел.
    // В библиотеке pdf шаблон задаём через setLineDashPattern.
    //
    // Прозрачность: при наложении оси на условное обозначение/размер ось
    // должна «бледнеть» — но всё равно перекрывать элемент. Достигается
    // полупрозрачным stroke-opacity через PdfGraphicState. Все элементы,
    // нарисованные ДО осей (стены, маркеры проёмов, размерные цепи),
    // остаются полностью непрозрачными — а ось через них «просвечивает».
    void drawAxisLine(double x1, double y1, double x2, double y2) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      canvas.setLineDashPattern([6, 2, 1, 2]);
      canvas.setGraphicState(const PdfGraphicState(strokeOpacity: 0.55));
      canvas.drawLine(x1, y1, x2, y2);
      canvas.strokePath();
      canvas.setLineDashPattern();
      canvas.setGraphicState(const PdfGraphicState(strokeOpacity: 1));
    }

    // --- Кружок оси с меткой (жирный шрифт, авто-увеличение диаметра) ---
    // Кружок белый, контур чёрный 0.6 pt. Если ширина текста (жирного)
    // превышает диаметр кружка, увеличиваем радиус.
    void drawAxisCircle(double cx, double cy, String label) {
      final tw = boldFont.stringMetrics(label).width * labelFontSize;
      final radius = math.max<double>(circleR, tw / 2 + 2.4);
      canvas.setFillColor(PdfColors.white);
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.6);
      canvas.drawEllipse(cx, cy, radius, radius);
      canvas.fillAndStrokePath();
      _drawCenteredText(
        canvas,
        label,
        cx,
        cy,
        fontSize: labelFontSize,
        font: boldFont,
      );
    }

    // --- Один сегмент размерной цепи (внешняя линия + засечки + число) ---
    // isHorizontal = true: сегмент вытягивается по X между a и b на высоте y.
    // isHorizontal = false: по Y между a и b на X = y.
    // textOffset — смещение текста перпендикулярно линии; положительное
    // значение означает «в сторону плана», отрицательное — «наружу».
    void drawDimSegment({
      required bool isHorizontal,
      required double a,
      required double b,
      required double cross,
      required String text,
      required double textOffset,
      int segIndex = 0,
      // Точки (вдоль линии цепи), которых подпись должна избегать —
      // обычно центры кружков осей. При коллизии текст сдвигается в
      // ближайший «чистый» зазор. Используется для общих габаритных
      // подписей, чтобы они не садились ровно на средний кружок оси
      // (правка пользователя по листу 8: «17200/16200» накладывались
      // на кружок «В»).
      List<double> avoidPoints = const [],
    }) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      const tick = 4.0;
      // Длина сегмента в pt — нужна, чтобы при узких сегментах смещать
      // текст по линии (вместо центра) и предотвратить наложение.
      final segLen = (b - a).abs();
      // Если сегмент уже текста, чередуем смещение: нечётные сегменты —
      // ближе к плану, чётные — дальше. Это «двухрядная» подпись по
      // ГОСТ 21.501-2018 / DIN 406.
      double extraText = 0.0;
      if (segLen < minSegPt) {
        extraText = segIndex.isOdd ? 9.0 : -9.0;
        // Знак extraText учитывает направление к плану (textOffset).
        // Если textOffset отрицателен (текст ближе к плану), то на
        // нечётных сегментах сдвигаемся ВПРОЧЬ от плана (то есть прибавляем
        // |extraText| с обратным знаком). Просто добавляем |extra| вдоль
        // нормали к линии:
        extraText = textOffset.isNegative ? -extraText : extraText;
      }
      // Размер текста; нужен для проверки пересечений с avoidPoints
      // (центрами кружков осей).
      final tw = font.stringMetrics(text).width * dimFontSize + 4;
      // Считаем «безопасную» позицию текста вдоль линии: если центр
      // сегмента попадает в зону кружка оси, сдвигаем в ближайший зазор
      // между парой соседних осей. Полу-ширина зоны коллизии — половина
      // ширины подписи + радиус кружка + 3 pt запаса.
      double safeAlong(double rawCenter) {
        if (avoidPoints.isEmpty) return rawCenter;
        const halfCircle = circleR;
        final halfText = tw / 2;
        final pad = halfText + halfCircle + 3;
        bool collides(double c) =>
            avoidPoints.any((p) => (p - c).abs() < pad);
        if (!collides(rawCenter)) return rawCenter;
        // Перебираем кандидатов: середины зазоров между соседними
        // кружками осей. Берём ближайшую к rawCenter, не задевающую
        // ни одной точки и в пределах [a + pad, b - pad].
        final sorted = List<double>.from(avoidPoints)..sort();
        final lo = math.min(a, b) + pad;
        final hi = math.max(a, b) - pad;
        final candidates = <double>[];
        for (var i = 0; i + 1 < sorted.length; i++) {
          candidates.add((sorted[i] + sorted[i + 1]) / 2);
        }
        candidates.add(lo);
        candidates.add(hi);
        candidates.sort((x, y) =>
            (x - rawCenter).abs().compareTo((y - rawCenter).abs()));
        for (final c in candidates) {
          if (c >= lo && c <= hi && !collides(c)) return c;
        }
        return rawCenter;
      }

      if (isHorizontal) {
        canvas.drawLine(a, cross, b, cross);
        canvas.strokePath();
        // Засечки под 45° (CAD-style).
        const tickDx = tick / math.sqrt2;
        canvas.drawLine(a - tickDx, cross - tickDx, a + tickDx, cross + tickDx);
        canvas.drawLine(b - tickDx, cross - tickDx, b + tickDx, cross + tickDx);
        canvas.strokePath();
        // Перед подписью — маленький белый «вырез» под текстом, чтобы
        // штрих-пунктирная ось локально становилась прозрачной и не
        // перечёркивала размер (ГОСТ 21.501-2018, п. 5.10.7).
        final tcx = safeAlong((a + b) / 2);
        final tcy = cross + textOffset + extraText;
        canvas.setFillColor(PdfColors.white);
        canvas.drawRect(tcx - tw / 2, tcy - dimFontSize * 0.55,
            tw, dimFontSize + 2);
        canvas.fillPath();
        canvas.setFillColor(PdfColors.black);
        _drawCenteredText(
          canvas,
          text,
          tcx,
          tcy,
          fontSize: dimFontSize,
          font: font,
        );
      } else {
        canvas.drawLine(cross, a, cross, b);
        canvas.strokePath();
        const tickDx = tick / math.sqrt2;
        canvas.drawLine(cross - tickDx, a - tickDx, cross + tickDx, a + tickDx);
        canvas.drawLine(cross - tickDx, b - tickDx, cross + tickDx, b + tickDx);
        canvas.strokePath();
        final tcx = cross + textOffset + extraText;
        final tcy = safeAlong((a + b) / 2);
        canvas.setFillColor(PdfColors.white);
        canvas.drawRect(tcx - tw / 2, tcy - dimFontSize * 0.55,
            tw, dimFontSize + 2);
        canvas.fillPath();
        canvas.setFillColor(PdfColors.black);
        _drawCenteredText(
          canvas,
          text,
          tcx,
          tcy,
          fontSize: dimFontSize,
          font: font,
        );
      }
    }

    // --- Оси и их вертикальные/горизонтальные «хвостики» ---
    // По ГОСТ 21.501 маркировку осей принято показывать только с двух
    // смежных сторон чертежа (снизу для цифровых и слева для буквенных).
    // Штрих-пунктирная линия оси всё равно проходит через весь план.
    //
    // П.2 v40: если кружки соседних осей визуально пересекаются
    // (расстояние между центрами < 2·R + 2 pt), сдвигаем одну из них
    // на 14 pt дальше — это «двухрядная» маркировка осей.
    final double tightThreshold = 2 * circleR + 2;
    const double tightOffset = 14.0;
    // Кружки X-осей сверху, поэтому не зависят от нижнего сдвига цепей.
    final xAxisExt = List<double>.filled(xs.length, axisExtension);
    for (var i = 1; i < xs.length; i++) {
      final d = (xs[i] - xs[i - 1]) * scale;
      if (d < tightThreshold) {
        // Сдвигаем оси через одну (i и i-2 на одном уровне; i-1 и i+1 — на другом).
        if (xAxisExt[i - 1] > axisExtension) {
          xAxisExt[i] = axisExtension; // оставляем
        } else {
          xAxisExt[i] = axisExtension + tightOffset;
        }
      }
    }
    // Кружки Y-осей слева — за самой внешней размерной цепью (включая
    // цепь «по карнизу» на плане кровли). +50 pt: ~30 pt полу-ширина
    // подписи общего габарита + 11 pt радиус кружка + 9 pt запаса.
    // Так наименование оси оказывается ПОСЛЕ всех размеров (ГОСТ
    // 21.501-2018, правка пользователя по листу 8).
    final yAxisBase = math.max(
      axisExtension,
      chainTotalLeft + outerChainExt + 50,
    );
    final yAxisExt = List<double>.filled(ys.length, yAxisBase);
    for (var i = 1; i < ys.length; i++) {
      final d = (ys[i] - ys[i - 1]) * scale;
      if (d < tightThreshold) {
        if (yAxisExt[i - 1] > yAxisBase) {
          yAxisExt[i] = yAxisBase;
        } else {
          yAxisExt[i] = yAxisBase + tightOffset;
        }
      }
    }
    // Аналогично, X-кружки находятся над планом, не пересекаются с
    // цепями снизу. Но при наличии пристройки на севере (y < 0) кружок
    // надо отодвинуть дальше — не реализовано, т. к. в текущем
    // генераторе плана таких пристроек нет.
    for (var i = 0; i < xs.length; i++) {
      final xMeters = xs[i];
      final xCanvas = ox + xMeters * scale;
      // Ось внутри плана — штрих-пунктирная сплошная линия.
      drawAxisLine(xCanvas, oy, xCanvas, oy + planH);
      // Связка от пятна до кружка оси (выше плана). Она НЕ
      // пересекает зону размерных цепей внизу и потому не
      // перечёркивает размеры.
      drawAxisLine(
        xCanvas,
        oy + planH + 4,
        xCanvas,
        oy + planH + xAxisExt[i] - circleR,
      );
      // Кружок только сверху (по ГОСТ маркируем оси с двух смежных
      // сторон: цифровые сверху, буквенные слева).
      drawAxisCircle(xCanvas, oy + planH + xAxisExt[i], xLabels[i]);
    }
    for (var i = 0; i < ys.length; i++) {
      final yMeters = ys[i];
      final yCanvas = oy + planH - yMeters * scale;
      // Ось внутри плана — штрих-пунктирная сплошная линия.
      drawAxisLine(ox, yCanvas, ox + planW, yCanvas);
      // Связка от пятна до кружка оси (слева). Не пересекает зону
      // цепей слева и потому не перечёркивает размеры.
      drawAxisLine(
        ox - yAxisExt[i] + circleR,
        yCanvas,
        ox - 4,
        yCanvas,
      );
      // Кружок только слева.
      drawAxisCircle(ox - yAxisExt[i], yCanvas, yLabels[i]);
    }

    // Текст размеров всегда размещаем ПО НАПРАВЛЕНИЮ К ПЛАНУ — между цепью
    // и пятном застройки; это стандартный способ расстановки, при котором
    // цифры не конфликтуют с кружками осей.

    // --- Точки привязки проёмов (уровень 1) ---
    // Для каждой наружной стены: точки = края наружных проёмов + границы
    // пятна; сегменты чередуются «простенок, проём, простенок, ...».
    // Цепи проёмов рисуем только снизу (для X) и слева (для Y),
    // чтобы не дублировать с противоположных сторон.
    //
    // На листах, где «проёмы» не имеют физического смысла (план кровли
    // и тому подобное), эту цепь отключаем (`drawOpeningsChain = false`),
    // иначе она дублирует значения и наезжает на оси.
    final bottomOpenings =
        drawOpeningsChain ? _breakPointsOnSide(plan, WallSide.bottom) : <double>[];
    final leftOpenings =
        drawOpeningsChain ? _breakPointsOnSide(plan, WallSide.left) : <double>[];

    // Выносные линии от точек цепей к зданию — для наглядности
    // (ГОСТ Р 21.501-2018, п. 5.10.5). Тонкая 0.3 pt, идёт от стены до
    // цепи через все 3 уровня размерных цепей. Рисуем ДО цепей, чтобы
    // белые «вырезы» под текстом размеров закрывали выносные линии.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.3);
    final extPointsBottom = <double>{
      ...bottomOpenings,
      ...xs, // оси тоже привязаны выносными линиями к цепям
    };
    final extPointsLeft = <double>{
      ...leftOpenings,
      ...ys,
    };
    for (final bp in extPointsBottom) {
      final xa = ox + bp * scale;
      // От пятна (oy) на 2 pt в сторону цепей, до самой внешней цепи + 4 pt.
      canvas.drawLine(xa, oy - 2, xa, oy - chainTotalBottom - 4);
      canvas.strokePath();
    }
    for (final bp in extPointsLeft) {
      final yc = oy + planH - bp * scale;
      canvas.drawLine(ox - 2, yc, ox - chainTotalLeft - 4, yc);
      canvas.strokePath();
    }

    // --- Внутренняя цепь «проёмы и простенки» (уровень 1) ---
    if (drawOpeningsChain) {
      for (var i = 0; i + 1 < bottomOpenings.length; i++) {
        final xa = ox + bottomOpenings[i] * scale;
        final xb = ox + bottomOpenings[i + 1] * scale;
        final dMm =
            ((bottomOpenings[i + 1] - bottomOpenings[i]) * 1000).round();
        drawDimSegment(
          isHorizontal: true,
          a: xa,
          b: xb,
          cross: oy - chainOpeningBottom,
          text: '$dMm',
          textOffset: 6,
          segIndex: i,
        );
      }
      for (var i = 0; i + 1 < leftOpenings.length; i++) {
        final yaCanvas = oy + planH - leftOpenings[i] * scale;
        final ybCanvas = oy + planH - leftOpenings[i + 1] * scale;
        final dMm =
            ((leftOpenings[i + 1] - leftOpenings[i]) * 1000).round();
        drawDimSegment(
          isHorizontal: false,
          a: ybCanvas,
          b: yaCanvas,
          cross: ox - chainOpeningLeft,
          text: '$dMm',
          textOffset: 8,
          segIndex: i,
        );
      }
    }

    // --- Размерная цепь: шаг между соседними осями ---
    // По правилу пользователя: размерные цепи рисуются только с двух
    // сторон, соответствующих маркам осей (снизу и слева).
    for (var i = 0; i + 1 < xs.length; i++) {
      final xa = ox + xs[i] * scale;
      final xb = ox + xs[i + 1] * scale;
      final deltaMm = ((xs[i + 1] - xs[i]) * 1000).round();
      drawDimSegment(
        isHorizontal: true,
        a: xa,
        b: xb,
        cross: oy - chainStepBottom,
        text: '$deltaMm',
        textOffset: 7, // к плану (выше в canvas)
      );
    }
    for (var i = 0; i + 1 < ys.length; i++) {
      final yaCanvas = oy + planH - ys[i] * scale;
      final ybCanvas = oy + planH - ys[i + 1] * scale;
      final deltaMm = ((ys[i + 1] - ys[i]) * 1000).round();
      drawDimSegment(
        isHorizontal: false,
        a: ybCanvas,
        b: yaCanvas,
        cross: ox - chainStepLeft,
        text: '$deltaMm',
        textOffset: 10, // к плану (правее, между цепью и стеной)
      );
    }

    // --- Общий габарит (крайняя ось ↔ крайняя ось) ---
    // Только снизу и слева.
    // На плане кровли (Лист 8) межосевой габарит снизу отключён —
    // его место занимает цепь «по карнизу» (правка пользователя:
    // третья горизонтальная линия снизу = габарит крыши, не межосевой).
    if (xs.length >= 2 && drawTotalChainBottom) {
      final xa = ox + xs.first * scale;
      final xb = ox + xs.last * scale;
      final totalMm = ((xs.last - xs.first) * 1000).round();
      // avoidPoints — все промежуточные оси, чтобы подпись общего
      // габарита не садилась ровно на средний кружок.
      final avoid = [
        for (var i = 1; i + 1 < xs.length; i++) ox + xs[i] * scale,
      ];
      drawDimSegment(
        isHorizontal: true,
        a: xa,
        b: xb,
        cross: oy - chainTotalBottom,
        text: '$totalMm',
        textOffset: 7,
        avoidPoints: avoid,
      );
    }
    // Аналогично — слева общий межосевой габарит можно выключить
    // (на плане кровли его замещает цепь «по карнизу»).
    if (ys.length >= 2 && drawTotalChainLeft) {
      final yaCanvas = oy + planH - ys.first * scale;
      final ybCanvas = oy + planH - ys.last * scale;
      final totalMm = ((ys.last - ys.first) * 1000).round();
      final avoid = [
        for (var i = 1; i + 1 < ys.length; i++) oy + planH - ys[i] * scale,
      ];
      drawDimSegment(
        isHorizontal: false,
        a: ybCanvas,
        b: yaCanvas,
        cross: ox - chainTotalLeft,
        text: '$totalMm',
        textOffset: 10,
        avoidPoints: avoid,
      );
    }

    // Зеркальные размерные цепи сверху и справа удалены по требованию
    // ГОСТ Р 21.501-2018: габаритные размеры плана выносятся только с
    // двух смежных сторон (снизу и слева). Это убирает дублирование
    // и снимает конфликт с экспликацией/ведомостями справа.

    // --- Phase-3b §17.2.1 next-slice: размерные цепи на уступы L/T/U-форм ---
    // Для прямоугольных планов внешние стены покрыты обычными цепями
    // снизу и слева. Для полигональных footprint-ов отрезки контура,
    // НЕ лежащие на bbox, остаются неподписанными — добавляем по короткой
    // цепи на каждый такой axis-aligned уступ-сегмент. Это две
    // цепи на стандартную L-форму (одна по «полке», одна по «врезке»).
    if (plan.hasPolygonalFootprint) {
      _paintFootprintNotchDims(
        canvas: canvas,
        plan: plan,
        font: font,
        ox: ox,
        oy: oy,
        planW: planW,
        planH: planH,
        scale: scale,
      );
    }

    // --- Отметка ±0,000 (в верхнем правом углу внутри плана) ---
    if (drawZeroMark) {
      _drawElevationMark(
        canvas,
        font,
        x: ox + planW - 40,
        y: oy + planH - 28,
        label: _formatLevelMeters(0),
      );
    }

    // --- Стрелка севера — за пределами плана, слева-сверху ---
    if (drawNorthArrow) {
      _drawNorthArrow(canvas, font, cx: ox - 55, cy: oy + planH + 55);
    }
  }

  /// Phase-3b §17.2.1 next-slice: рисует размерные цепи на «уступах»
  /// полигонального footprint-а (L/T/U/Г-формы).
  ///
  /// Для каждого axis-aligned сегмента outline-а, который НЕ лежит на
  /// границе bbox, рисуется короткая цепь:
  ///   • выносная линия параллельно сегменту, отступленная наружу
  ///     (в сторону, противоположную внутренней грани CCW-полигона);
  ///   • засечки на концах под 45°;
  ///   • подпись длины в миллиметрах посередине.
  ///
  /// Полигон уже отрисован в `_paintPlan` через `effectiveFootprint`,
  /// здесь мы только добавляем подписи длин уступов. Никакой связи с
  /// существующими цепями по периметру bbox — те по-прежнему дают
  /// габариты `width × length`, эта функция дополняет их геометрией
  /// уступов.
  static void _paintFootprintNotchDims({
    required PdfGraphics canvas,
    required FloorPlan plan,
    required PdfFont font,
    required double ox,
    required double oy,
    required double planW,
    required double planH,
    required double scale,
  }) {
    final fp = plan.effectiveFootprint;
    final outline = fp.outline;
    if (outline.length < 3) return;
    final bbox = fp.bbox;
    const double eps = 0.04; // 40 мм — допуск на «лежит-на-границе-bbox»
    const double offsetPt = 30.0; // отступ цепи наружу полигона, pt
    const double tick = 4.0;
    const double dimFontSize = 7.0;
    final tickDx = tick / math.sqrt2;

    bool onBboxEdge(double x1, double y1, double x2, double y2) {
      // Сегмент считается граничным, если ОБА конца имеют одну и ту же
      // экстремальную координату по одной оси (вся сторона на bbox).
      if ((x1 - bbox.minX).abs() < eps && (x2 - bbox.minX).abs() < eps) {
        return true;
      }
      if ((x1 - bbox.maxX).abs() < eps && (x2 - bbox.maxX).abs() < eps) {
        return true;
      }
      if ((y1 - bbox.minY).abs() < eps && (y2 - bbox.minY).abs() < eps) {
        return true;
      }
      if ((y1 - bbox.maxY).abs() < eps && (y2 - bbox.maxY).abs() < eps) {
        return true;
      }
      return false;
    }

    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);

    for (var i = 0; i < outline.length; i++) {
      final p1 = outline[i];
      final p2 = outline[(i + 1) % outline.length];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      // Не axis-aligned — пропускаем.
      final isHoriz = dy.abs() < eps && dx.abs() > eps;
      final isVert = dx.abs() < eps && dy.abs() > eps;
      if (!isHoriz && !isVert) continue;
      if (onBboxEdge(p1.x, p1.y, p2.x, p2.y)) continue;

      // Внешняя нормаль для CCW-полигона: повернуть направление на
      // 90° по часовой стрелке: (dx, dy) → (dy, -dx). Нормализуем.
      final nLen = math.sqrt(dx * dx + dy * dy);
      if (nLen < eps) continue;
      final nxReal = dy / nLen;
      final nyReal = -dx / nLen;

      // Перевод в PDF-координаты: y инвертируется относительно реальной.
      // Точки сегмента:
      final x1Pdf = ox + p1.x * scale;
      final x2Pdf = ox + p2.x * scale;
      final y1Pdf = oy + planH - p1.y * scale;
      final y2Pdf = oy + planH - p2.y * scale;
      // Внешняя нормаль в PDF: (nxReal, -nyReal).
      final nxPdf = nxReal;
      final nyPdf = -nyReal;

      // Точки выносной (размерной) линии — параллельно сегменту, со
      // смещением offsetPt вдоль внешней нормали.
      final ax = x1Pdf + nxPdf * offsetPt;
      final ay = y1Pdf + nyPdf * offsetPt;
      final bx = x2Pdf + nxPdf * offsetPt;
      final by = y2Pdf + nyPdf * offsetPt;

      // Сама размерная линия.
      canvas.drawLine(ax, ay, bx, by);
      canvas.strokePath();
      // Засечки под 45° на концах.
      canvas.drawLine(ax - tickDx, ay - tickDx, ax + tickDx, ay + tickDx);
      canvas.drawLine(bx - tickDx, by - tickDx, bx + tickDx, by + tickDx);
      canvas.strokePath();
      // Тонкие выносные линии от концов сегмента к концам цепи —
      // показывают, что цепь относится именно к этому отрезку.
      canvas.drawLine(x1Pdf, y1Pdf, ax, ay);
      canvas.drawLine(x2Pdf, y2Pdf, bx, by);
      canvas.strokePath();

      // Подпись посередине — длина в миллиметрах.
      final lengthMm = (nLen * 1000).round();
      final cx = (ax + bx) / 2;
      final cy = (ay + by) / 2;
      // Сдвиг подписи перпендикулярно оси цепи (наружу), чтобы
      // не садилась на саму линию.
      final tcx = cx + nxPdf * 6;
      final tcy = cy + nyPdf * 6;
      // Маленький белый прямоугольник под текстом — чтобы подпись
      // читалась над любыми штриховками штампа/штриховкой стен.
      final tw = font.stringMetrics('$lengthMm').width * dimFontSize + 4;
      canvas.setFillColor(PdfColors.white);
      canvas.drawRect(
        tcx - tw / 2,
        tcy - dimFontSize * 0.55,
        tw,
        dimFontSize + 2,
      );
      canvas.fillPath();
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(
        canvas,
        '$lengthMm',
        tcx,
        tcy,
        fontSize: dimFontSize,
        font: font,
      );
    }
  }

  /// Отметка высотной точки (треугольник + высота).
  static void _drawElevationMark(
    PdfGraphics canvas,
    PdfFont font, {
    required double x,
    required double y,
    required String label,
  }) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    const size = 6.0;
    // Треугольник-флажок: стороны 45°, вершина внизу.
    canvas.moveTo(x, y);
    canvas.lineTo(x - size, y + size);
    canvas.lineTo(x + size, y + size);
    canvas.lineTo(x, y);
    canvas.fillPath();
    // Горизонтальная черта над треугольником (уровень земли/пола).
    canvas.setLineWidth(0.6);
    canvas.drawLine(x - 22, y + size, x + 22, y + size);
    canvas.strokePath();
    _drawCenteredText(
      canvas,
      label,
      x,
      y + size + 6,
      fontSize: 8.5,
      font: font,
    );
  }

  /// Стандартный указатель севера: кружок Ø 15 мм, стрелка, буква «С».
  static void _drawNorthArrow(
    PdfGraphics canvas,
    PdfFont font, {
    required double cx,
    required double cy,
  }) {
    const r = 20.0;
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawEllipse(cx, cy, r, r);
    canvas.fillAndStrokePath();
    // Стрелка вверх: тонкое длинное копьё.
    canvas.setFillColor(PdfColors.black);
    canvas.moveTo(cx, cy + r - 4);
    canvas.lineTo(cx - 4, cy);
    canvas.lineTo(cx, cy + 2);
    canvas.lineTo(cx + 4, cy);
    canvas.lineTo(cx, cy + r - 4);
    canvas.fillPath();
    // Буква «С» в верхней части кружка.
    _drawCenteredText(
      canvas,
      'С',
      cx,
      cy + r + 8,
      fontSize: 10,
      font: font,
    );
  }

  /// Внутренний прямоугольник комнаты с учётом толщины стен.
  /// Возвращает `null`, если стены «съели» всю комнату.
  static _RectM? _innerRect(PlanRoom r, FloorPlan plan) {
    final left = _isOuter(r.x, 0) ? _outerWall / 2 : _innerWall / 2;
    final right = _isOuter(r.x + r.width, plan.width)
        ? _outerWall / 2
        : _innerWall / 2;
    final top = _isOuter(r.y, 0) ? _outerWall / 2 : _innerWall / 2;
    final bottom = _isOuter(r.y + r.height, plan.height)
        ? _outerWall / 2
        : _innerWall / 2;
    final innerW = r.width - left - right;
    final innerH = r.height - top - bottom;
    if (innerW <= 0 || innerH <= 0) return null;
    return _RectM(r.x + left, r.y + top, innerW, innerH);
  }

  static bool _isOuter(double v, double boundary) =>
      (v - boundary).abs() < _eps;

  static bool _isOpeningOnOuterWall(FloorPlan plan, PlanOpening o) {
    switch (o.side) {
      case WallSide.top:
        return o.y < _eps;
      case WallSide.bottom:
        return (plan.height - o.y).abs() < _eps;
      case WallSide.left:
        return o.x < _eps;
      case WallSide.right:
        return (plan.width - o.x).abs() < _eps;
    }
  }

  // ─── Графика мебели (Phase-1 MVP) ──────────────────────────────────
  //
  // Соответствует Части II §9 техзадания konstruktor_stroenii_full_spec.md.
  // Каждый символ рисуется как ограничивающий прямоугольник + базовый
  // внутренний рисунок. Цвет линии — чёрный, заливка очень светлая
  // (#FAFAFA) — чтобы не «забивать» цветную палитру комнаты. Толщина
  // линии 0.3 pt — тоньше внутренней стены (0.4 pt), но тоще, чем
  // штриховка (0.2 pt).

  static const PdfColor _furnitureFill = PdfColor.fromInt(0xFFFAFAFA);
  static const PdfColor _furnitureStroke = PdfColors.black;
  static const double _furnitureLineWidth = 0.3;

  static void _drawFurnitureSymbol(
    PdfGraphics canvas,
    FurnitureSymbol f,
    PdfPoint Function(double, double) pp,
    double scale,
  ) {
    final tl = pp(f.x, f.y);
    final px = tl.x;
    final py = tl.y - f.height * scale; // нижний-левый в PDF-координатах
    final pw = f.width * scale;
    final ph = f.height * scale;
    canvas.setStrokeColor(_furnitureStroke);
    canvas.setLineWidth(_furnitureLineWidth);
    canvas.setFillColor(_furnitureFill);

    // Базовый прямоугольник.
    canvas.drawRect(px, py, pw, ph);
    canvas.fillAndStrokePath();

    switch (f.kind) {
      case FurnitureKind.bedDouble:
      case FurnitureKind.bedSingle:
        _drawBedDetail(canvas, px, py, pw, ph, double_: f.kind == FurnitureKind.bedDouble);
        break;
      case FurnitureKind.sofa3:
      case FurnitureKind.sofaCorner:
        _drawSofaDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.kitchenStove:
        _drawStoveDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.kitchenSink:
        _drawSinkDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.kitchenFridge:
        _drawFridgeDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.bathtub:
        _drawBathtubDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.toilet:
        _drawToiletDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.washbasin:
        _drawWashbasinDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.shower:
        _drawShowerDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.washingMachine:
      case FurnitureKind.dryer:
        _drawWashingMachineDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.carSilhouette:
        _drawCarDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.boiler:
        _drawBoilerDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.outdoorTable:
        _drawOutdoorTableDetail(canvas, px, py, pw, ph);
        break;
      case FurnitureKind.diningTable:
      case FurnitureKind.coffeeTable:
      case FurnitureKind.tvStand:
      case FurnitureKind.nightstand:
      case FurnitureKind.armchair:
      case FurnitureKind.diningChair:
      case FurnitureKind.chair:
      case FurnitureKind.outdoorChair:
      case FurnitureKind.kitchenSection:
      case FurnitureKind.kitchenIsland:
      case FurnitureKind.wardrobe:
      case FurnitureKind.shoeCabinet:
      case FurnitureKind.hangerRack:
      case FurnitureKind.desk:
      case FurnitureKind.staircaseArrow:
        // Только базовый прямоугольник.
        break;
    }
  }

  static void _drawCarDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    final isHoriz = w >= h;
    if (isHoriz) {
      // 4 колеса + лобовое стекло.
      final wr = h * 0.10;
      final wy1 = y + h * 0.08;
      final wy2 = y + h * 0.92;
      final wx1 = x + w * 0.18;
      final wx2 = x + w * 0.82;
      for (final cx in [wx1, wx2]) {
        for (final cy in [wy1, wy2]) {
          c.drawEllipse(cx, cy, wr, wr);
          c.fillAndStrokePath();
        }
      }
      // Лобовое стекло (короткая дуга).
      c.drawLine(x + w * 0.65, y + h * 0.2, x + w * 0.65, y + h * 0.8);
      c.strokePath();
    } else {
      final wr = w * 0.10;
      final wx1 = x + w * 0.08;
      final wx2 = x + w * 0.92;
      final wy1 = y + h * 0.18;
      final wy2 = y + h * 0.82;
      for (final cy in [wy1, wy2]) {
        for (final cx in [wx1, wx2]) {
          c.drawEllipse(cx, cy, wr, wr);
          c.fillAndStrokePath();
        }
      }
      c.drawLine(x + w * 0.2, y + h * 0.65, x + w * 0.8, y + h * 0.65);
      c.strokePath();
    }
  }

  static void _drawBoilerDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Внутренний круг + 4 точки-подключения.
    final r = math.min(w, h) * 0.32;
    c.drawEllipse(x + w / 2, y + h / 2, r, r);
    c.strokePath();
    // Маленький символ «К» — обозначение котла.
    c.drawLine(x + w / 2 - r * 0.3, y + h / 2 - r * 0.35,
        x + w / 2 - r * 0.3, y + h / 2 + r * 0.35);
    c.drawLine(x + w / 2 - r * 0.3, y + h / 2,
        x + w / 2 + r * 0.3, y + h / 2 + r * 0.35);
    c.drawLine(x + w / 2 - r * 0.3, y + h / 2,
        x + w / 2 + r * 0.3, y + h / 2 - r * 0.35);
    c.strokePath();
  }

  static void _drawOutdoorTableDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Зонтик: круг по центру.
    final r = math.min(w, h) * 0.18;
    c.drawEllipse(x + w / 2, y + h / 2, r, r);
    c.strokePath();
    // Крестик в центре круга — стержень зонта.
    c.drawLine(x + w / 2 - r * 0.5, y + h / 2,
        x + w / 2 + r * 0.5, y + h / 2);
    c.drawLine(x + w / 2, y + h / 2 - r * 0.5,
        x + w / 2, y + h / 2 + r * 0.5);
    c.strokePath();
  }

  static void _drawBedDetail(
    PdfGraphics c, double x, double y, double w, double h,
      {required bool double_}) {
    // «Подушка»: тонкая линия в верхней (изголовной) трети.
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    final pillowY = y + h * 0.78;
    c.drawLine(x + w * 0.08, pillowY, x + w * 0.92, pillowY);
    c.strokePath();
    if (double_) {
      // Разделитель посередине (двуспальная).
      c.drawLine(x + w / 2, y, x + w / 2, y + h * 0.78);
      c.strokePath();
    }
  }

  static void _drawSofaDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Линия спинки (внутри прямоугольника, отступ ~25%).
    final isHoriz = w >= h;
    if (isHoriz) {
      final by = y + h * 0.75;
      c.drawLine(x, by, x + w, by);
    } else {
      final bx = x + w * 0.25;
      c.drawLine(bx, y, bx, y + h);
    }
    c.strokePath();
  }

  static void _drawStoveDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    final r = math.min(w, h) * 0.18;
    final cxs = [x + w * 0.3, x + w * 0.7];
    final cys = [y + h * 0.3, y + h * 0.7];
    for (final cy in cys) {
      for (final cx in cxs) {
        c.drawEllipse(cx, cy, r, r);
        c.strokePath();
      }
    }
  }

  static void _drawSinkDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Овальная мойка внутри прямоугольника.
    final mx = x + w * 0.15;
    final my = y + h * 0.15;
    final mw = w * 0.7;
    final mh = h * 0.7;
    c.drawEllipse(mx + mw / 2, my + mh / 2, mw / 2, mh / 2);
    c.strokePath();
  }

  static void _drawFridgeDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Полка-разделитель в верхней трети.
    final dy = y + h * 0.7;
    c.drawLine(x, dy, x + w, dy);
    c.strokePath();
  }

  static void _drawBathtubDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Внутренний скруглённый «ковш» (упрощённо — эллипс).
    final mx = x + w * 0.06;
    final my = y + h * 0.18;
    final mw = w * 0.88;
    final mh = h * 0.64;
    c.drawEllipse(mx + mw / 2, my + mh / 2, mw / 2, mh / 2);
    c.strokePath();
  }

  static void _drawToiletDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Бачок (узкий прямоугольник вверху) + чаша (овал внизу).
    final isVert = h >= w;
    if (isVert) {
      final tankH = h * 0.30;
      c.drawRect(x, y + h - tankH, w, tankH);
      c.strokePath();
      final bx = x + w * 0.1;
      final by = y + h * 0.05;
      final bw = w * 0.8;
      final bh = h * 0.55;
      c.drawEllipse(bx + bw / 2, by + bh / 2, bw / 2, bh / 2);
      c.strokePath();
    } else {
      final tankW = w * 0.30;
      c.drawRect(x, y, tankW, h);
      c.strokePath();
      final bx = x + w * 0.4;
      final by = y + h * 0.1;
      final bw = w * 0.55;
      final bh = h * 0.8;
      c.drawEllipse(bx + bw / 2, by + bh / 2, bw / 2, bh / 2);
      c.strokePath();
    }
  }

  static void _drawWashbasinDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    final mx = x + w * 0.10;
    final my = y + h * 0.10;
    final mw = w * 0.80;
    final mh = h * 0.80;
    c.drawEllipse(mx + mw / 2, my + mh / 2, mw / 2, mh / 2);
    c.strokePath();
  }

  static void _drawShowerDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    // Крест в центре — символ «трапа».
    c.drawLine(x + w * 0.2, y + h / 2, x + w * 0.8, y + h / 2);
    c.drawLine(x + w / 2, y + h * 0.2, x + w / 2, y + h * 0.8);
    c.strokePath();
  }

  static void _drawWashingMachineDetail(
      PdfGraphics c, double x, double y, double w, double h) {
    c.setStrokeColor(_furnitureStroke);
    c.setLineWidth(_furnitureLineWidth);
    final r = math.min(w, h) * 0.35;
    c.drawEllipse(x + w / 2, y + h / 2, r, r);
    c.strokePath();
  }

  static void _drawOpening(
    PdfGraphics canvas,
    FloorPlan plan,
    PlanOpening o,
    PdfPoint Function(double, double) pp,
    double scale,
  ) {
    final isExternal = _isOpeningOnOuterWall(plan, o);
    final thickness = isExternal ? _outerWall : _innerWall;
    final isVerticalWall = !o.side.isHorizontal;
    // Глубина проёма в стене. Для окна — уменьшаем глубину до 60 % от
    // толщины стены (по ГОСТ 21.501 окно занимает не всю толщину, а
    // только центральную часть; снаружи остаётся четверть, изнутри —
    // подоконник). Для двери — полная толщина: дверь распахивается.
    final double openingDepth = (o.kind == OpeningKind.window)
        ? thickness * 0.6
        : thickness;

    // Прямоугольник проёма в модельных координатах (Y вниз).
    final double mx, my, mw, mh;
    if (isVerticalWall) {
      mx = o.x - openingDepth / 2;
      my = o.y;
      mw = openingDepth;
      mh = o.length;
    } else {
      mx = o.x;
      my = o.y - openingDepth / 2;
      mw = o.length;
      mh = openingDepth;
    }

    void fillRect(PdfColor c) {
      canvas.setFillColor(c);
      final tl = pp(mx, my);
      canvas.drawRect(tl.x, tl.y - mh * scale, mw * scale, mh * scale);
      canvas.fillPath();
    }

    if (o.kind == OpeningKind.archway) {
      // Открытый проход — две свободные зоны соединены, рисуем заливку.
      fillRect(_freeFill);
      return;
    }

    if (o.kind == OpeningKind.window) {
      // Окно по ГОСТ 21.501-2018: контур проёма + двойная линия рамы +
      // подоконник, выступающий с внутренней стороны на 80 мм. Снаружи
      // оставляем тонкую линию плоскости остекления.
      fillRect(_windowFill);
      canvas.setStrokeColor(_windowStroke);
      canvas.setLineWidth(0.7);
      final tl = pp(mx, my);
      canvas.drawRect(tl.x, tl.y - mh * scale, mw * scale, mh * scale);
      canvas.strokePath();

      // Внутренняя сторона стены — для подоконника определяем направление.
      // Для side=top подоконник внутри = вниз (Y растёт); для bottom = вверх и т. д.
      const double inset = 0.04;
      const double sillProj = 0.08; // 80 мм выступ внутрь
      if (isVerticalWall) {
        // Двойная линия остекления вдоль вертикальной стены.
        final m1 = mx + mw * 0.33;
        final m2 = mx + mw * 0.67;
        final p1a = pp(m1, my + inset);
        final p1b = pp(m1, my + mh - inset);
        final p2a = pp(m2, my + inset);
        final p2b = pp(m2, my + mh - inset);
        canvas.drawLine(p1a.x, p1a.y, p1b.x, p1b.y);
        canvas.strokePath();
        canvas.drawLine(p2a.x, p2a.y, p2b.x, p2b.y);
        canvas.strokePath();
        // Подоконник: на стороне left — выступ вправо (внутрь); right — влево.
        final sillSign = (o.side == WallSide.left) ? 1.0 : -1.0;
        final sillX = (o.side == WallSide.left)
            ? mx + mw
            : mx; // внутренняя кромка стены
        canvas.setLineWidth(0.5);
        final s1 = pp(sillX, my - 0.02);
        final s2 = pp(sillX + sillSign * sillProj, my - 0.02);
        final s3 = pp(sillX + sillSign * sillProj, my + mh + 0.02);
        final s4 = pp(sillX, my + mh + 0.02);
        canvas.drawLine(s1.x, s1.y, s2.x, s2.y);
        canvas.drawLine(s2.x, s2.y, s3.x, s3.y);
        canvas.drawLine(s3.x, s3.y, s4.x, s4.y);
        canvas.strokePath();
      } else {
        final m1 = my + mh * 0.33;
        final m2 = my + mh * 0.67;
        final p1a = pp(mx + inset, m1);
        final p1b = pp(mx + mw - inset, m1);
        final p2a = pp(mx + inset, m2);
        final p2b = pp(mx + mw - inset, m2);
        canvas.drawLine(p1a.x, p1a.y, p1b.x, p1b.y);
        canvas.strokePath();
        canvas.drawLine(p2a.x, p2a.y, p2b.x, p2b.y);
        canvas.strokePath();
        // Подоконник: для top — выступ вниз (внутрь), для bottom — вверх.
        final sillSign = (o.side == WallSide.top) ? 1.0 : -1.0;
        final sillY = (o.side == WallSide.top)
            ? my + mh
            : my; // внутренняя кромка стены
        canvas.setLineWidth(0.5);
        final s1 = pp(mx - 0.02, sillY);
        final s2 = pp(mx - 0.02, sillY + sillSign * sillProj);
        final s3 = pp(mx + mw + 0.02, sillY + sillSign * sillProj);
        final s4 = pp(mx + mw + 0.02, sillY);
        canvas.drawLine(s1.x, s1.y, s2.x, s2.y);
        canvas.drawLine(s2.x, s2.y, s3.x, s3.y);
        canvas.drawLine(s3.x, s3.y, s4.x, s4.y);
        canvas.strokePath();
      }
      return;
    }

    // Дверь: «вырезаем» стену цветом пола, рисуем створку и дугу.
    fillRect(_surfaceColor);
    final isEntry = o.kind == OpeningKind.externalDoor;
    final color = isEntry ? _entryDoorColor : _doorColor;
    canvas.setStrokeColor(color);
    canvas.setLineWidth(isEntry ? 1.4 : 1.0);

    // Координаты hinge / leaf-end в модельной системе (Y вниз).
    final double hingeX, hingeY, leafX, leafY;
    final double startAngle;
    const double sweep = math.pi / 2;
    if (isVerticalWall) {
      final centerM = mx + mw / 2;
      if (o.swing >= 0) {
        hingeX = centerM;
        hingeY = my;
        leafX = centerM + o.length;
        leafY = my;
        startAngle = 0;
      } else {
        hingeX = centerM;
        hingeY = my + mh;
        leafX = centerM + o.length;
        leafY = my + mh;
        startAngle = -math.pi / 2;
      }
    } else {
      final centerM = my + mh / 2;
      if (o.swing >= 0) {
        hingeX = mx;
        hingeY = centerM;
        leafX = mx;
        leafY = centerM + o.length;
      } else {
        hingeX = mx + mw;
        hingeY = centerM;
        leafX = mx + mw;
        leafY = centerM + o.length;
      }
      startAngle = math.pi / 2;
    }

    // Створка (полотно).
    final hp = pp(hingeX, hingeY);
    final lp = pp(leafX, leafY);
    canvas.drawLine(hp.x, hp.y, lp.x, lp.y);
    canvas.strokePath();

    // Дуга направления открывания — четверть круга от leafEnd к перпендикуляру.
    canvas.setStrokeColor(_lighten(color, 0.45));
    canvas.setLineWidth(0.6);
    _drawArcM(
      canvas,
      pp,
      cxM: hingeX,
      cyM: hingeY,
      radiusM: o.length,
      startAngle: startAngle,
      sweep: sweep,
    );

    if (isEntry) {
      // Жирная отметка стороны улицы — короткий штрих наружу.
      canvas.setStrokeColor(color);
      canvas.setLineWidth(1.6);
      final outX = isVerticalWall
          ? (o.side == WallSide.left ? mx - 0.25 : mx + mw + 0.25)
          : mx + mw / 2;
      final outY = isVerticalWall
          ? my + mh / 2
          : (o.side == WallSide.top ? my - 0.25 : my + mh + 0.25);
      final innX = isVerticalWall
          ? (o.side == WallSide.left ? mx + mw : mx)
          : mx + mw / 2;
      final innY = isVerticalWall ? my + mh / 2 : my + mh / 2;
      final a = pp(outX, outY);
      final b = pp(innX, innY);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }
  }

  /// Полилиния-аппроксимация дуги в модельных координатах. [steps]
  /// сегментов хватает на гладкую кривую при печати A3.
  static void _drawArcM(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp, {
    required double cxM,
    required double cyM,
    required double radiusM,
    required double startAngle,
    required double sweep,
    int steps = 24,
  }) {
    final p0 = pp(
      cxM + radiusM * math.cos(startAngle),
      cyM + radiusM * math.sin(startAngle),
    );
    canvas.moveTo(p0.x, p0.y);
    for (var i = 1; i <= steps; i++) {
      final a = startAngle + sweep * i / steps;
      final p = pp(
        cxM + radiusM * math.cos(a),
        cyM + radiusM * math.sin(a),
      );
      canvas.lineTo(p.x, p.y);
    }
    canvas.strokePath();
  }

  /// Заливочная штриховка под выбранный материал стены, по ГОСТ 2.306-68.
  /// Рисуется по всему пятну застройки. Внутренние помещения, которые
  /// рисуются поверх (белой заливкой), затирают штриховку — она остаётся
  /// видна только в массе стен.
  static void _paintWallHatching(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp,
    FloorPlan plan, // ignore: avoid_unused_constructor_parameters
    double scale, {
    required double ox,
    required double oy,
    required double planW,
    required double planH,
    required WallMaterial? material,
  }) {
    // Стиль штриховки: цвет, шаг между линиями, вторая (перпендикулярная)
    // подсетка — да/нет.
    final PdfColor color;
    final double stepPt;
    final bool crossHatch;
    final bool dotted;
    switch (material) {
      case WallMaterial.brick:
        color = const PdfColor.fromInt(0xFF8A3515);
        stepPt = 4.5;
        crossHatch = true; // кирпичная кладка — двойная сетка
        dotted = false;
      case WallMaterial.aerated:
      case WallMaterial.expandedClay:
        color = const PdfColor.fromInt(0xFF3A7A3A);
        stepPt = 3.5;
        crossHatch = false;
        dotted = false;
      case WallMaterial.timber:
        color = const PdfColor.fromInt(0xFF6A4A25);
        stepPt = 3.0;
        crossHatch = false; // только продольные
        dotted = false;
      case WallMaterial.frame:
        color = const PdfColor.fromInt(0xFF6A7A8A);
        stepPt = 4.5;
        crossHatch = true; // каркасная сетка
        dotted = true;
      case null:
        color = const PdfColor.fromInt(0xFF5A5A5A);
        stepPt = 4.5;
        crossHatch = false;
        dotted = false;
    }
    canvas.setStrokeColor(color);
    canvas.setLineWidth(0.5);

    final left = ox;
    final right = ox + planW;
    final top = oy + planH;
    final bottom = oy;

    if (material == WallMaterial.timber) {
      // Брус: только горизонтальные линии (волокна вдоль стен).
      for (double y = bottom + stepPt; y < top; y += stepPt) {
        canvas.drawLine(left, y, right, y);
        canvas.strokePath();
      }
      return;
    }

    // 45° диагонали: y = x + c. Параметризуем через c в диапазоне
    // [-planW, planH], шаг stepPt * sqrt(2) даёт постоянное расстояние
    // между линиями stepPt.
    final paramStep = stepPt * math.sqrt2;
    for (double c = -planW; c < planH; c += paramStep) {
      // Начало линии — слева (x=left, y=bottom + max(0, c))
      // Конец — снизу или справа.
      final x1 = left;
      final y1 = bottom + (c < 0 ? 0 : c);
      final dx1 = c < 0 ? -c : 0.0;
      final actualX1 = x1 + dx1;
      // Конечная точка
      final x2End = right;
      final y2End = bottom + c + (right - left);
      final actualX2 = y2End > top ? right - (y2End - top) : x2End;
      final actualY2 = y2End > top ? top : y2End;
      if (actualX1 >= right || actualY2 <= bottom) continue;
      if (dotted) {
        // Точечная штриховка — короткие отрезки
        const dashLen = 1.5;
        const gapLen = 2.5;
        final dx = actualX2 - actualX1;
        final dy = actualY2 - y1;
        final len = math.sqrt(dx * dx + dy * dy);
        final ux = dx / len;
        final uy = dy / len;
        for (double t = 0; t < len; t += dashLen + gapLen) {
          final t2 = math.min(t + dashLen, len);
          canvas.drawLine(
            actualX1 + ux * t,
            y1 + uy * t,
            actualX1 + ux * t2,
            y1 + uy * t2,
          );
          canvas.strokePath();
        }
      } else {
        canvas.drawLine(actualX1, y1, actualX2, actualY2);
        canvas.strokePath();
      }
    }
    if (crossHatch) {
      // Вторая семья диагоналей: y = -x + c.
      for (double c = bottom; c < top + planW; c += paramStep) {
        final y1Calc = c;
        final actualY1 = y1Calc > top ? top : y1Calc;
        final actualX1 = y1Calc > top ? left + (y1Calc - top) : left;
        final y2Calc = c - (right - left);
        final actualX2 = y2Calc < bottom ? right - (bottom - y2Calc) : right;
        final actualY2 = y2Calc < bottom ? bottom : y2Calc;
        if (actualX1 >= right || actualY1 <= bottom) continue;
        if (actualX2 <= left || actualY2 >= top) continue;
        canvas.drawLine(actualX1, actualY1, actualX2, actualY2);
        canvas.strokePath();
      }
    }
  }

  /// Рисует пристройки (крыльцо, терраса) за контуром дома.
  /// Тонкий контур, деревянная штриховка горизонтальными линиями (дощатый
  /// настил по ГОСТ 2.306-68), подпись названия и габаритные размеры.
  static void _paintAttachments(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    FloorPlan plan,
    double scale,
  ) {
    if (plan.attachments.isEmpty) return;
    for (final a in plan.attachments) {
      final topLeft = pp(a.x, a.y);
      final bottomRight = pp(a.x + a.width, a.y + a.height);
      final rx = math.min(topLeft.x, bottomRight.x);
      final ry = math.min(topLeft.y, bottomRight.y);
      final rw = (bottomRight.x - topLeft.x).abs();
      final rh = (bottomRight.y - topLeft.y).abs();
      // Заливка зависит от типа: терраса — песочная, гараж — серый
      // (по СПДС — пристройки иной функциональной зоны затемнены),
      // крыльцо — светло-серая.
      final PdfColor fill = switch (a.kind) {
        PlanAttachmentKind.terrace => const PdfColor(0.96, 0.92, 0.82),
        PlanAttachmentKind.garage => const PdfColor(0.84, 0.84, 0.86),
        PlanAttachmentKind.porch => const PdfColor(0.94, 0.94, 0.90),
      };
      canvas.setFillColor(fill);
      canvas.drawRect(rx, ry, rw, rh);
      canvas.fillPath();
      // Контур: гараж — толще (это стена), остальные — тоньше.
      canvas.setStrokeColor(PdfColors.grey800);
      canvas.setLineWidth(a.kind == PlanAttachmentKind.garage ? 1.2 : 0.6);
      canvas.drawRect(rx, ry, rw, rh);
      canvas.strokePath();
      if (a.kind == PlanAttachmentKind.garage) {
        // Ворота гаража — широкая дверь по стороне, прилегающей к зданию.
        // Ищем сторону, обращённую внутрь дома: ту, что ближе к плану.
        final planCenterX = pp(plan.width / 2, plan.height / 2).x;
        final planCenterY = pp(plan.width / 2, plan.height / 2).y;
        final centerX = rx + rw / 2;
        final centerY = ry + rh / 2;
        final dx = (centerX - planCenterX).abs();
        final dy = (centerY - planCenterY).abs();
        // Если гараж ближе по X — ворота на Y-стороне; иначе на X-стороне.
        canvas.setStrokeColor(PdfColors.grey800);
        canvas.setLineWidth(0.8);
        if (dx > dy) {
          // ворота на наружной (от дома) X-стороне
          final xWall = (centerX > planCenterX) ? rx + rw : rx;
          final gateLen = math.min(rh - 8, 50.0);
          final y1 = centerY - gateLen / 2;
          final y2 = centerY + gateLen / 2;
          canvas.setLineWidth(2.0);
          canvas.drawLine(xWall, y1, xWall, y2);
          canvas.strokePath();
          canvas.setLineWidth(0.4);
        } else {
          final yWall = (centerY > planCenterY) ? ry + rh : ry;
          final gateLen = math.min(rw - 8, 50.0);
          final x1 = centerX - gateLen / 2;
          final x2 = centerX + gateLen / 2;
          canvas.setLineWidth(2.0);
          canvas.drawLine(x1, yWall, x2, yWall);
          canvas.strokePath();
          canvas.setLineWidth(0.4);
        }
      } else {
        // Доски настила (терраса/крыльцо) — горизонтальные линии.
        canvas.setStrokeColor(const PdfColor(0.55, 0.42, 0.25));
        canvas.setLineWidth(0.3);
        const plankPt = 6.0;
        for (var yy = ry + plankPt; yy < ry + rh; yy += plankPt) {
          canvas.drawLine(rx, yy, rx + rw, yy);
        }
        canvas.strokePath();
      }
      // Phase-2b: мебель внутри пристройки (авто в гараже, стол+стулья
      // на террасе/балконе/крыльце). Рисуется ДО подписи, чтобы
      // подпись потом ушла в свободный угол.
      final attFurniture = placeFurnitureForAttachment(a);
      for (final f in attFurniture) {
        _drawFurnitureSymbol(canvas, f, pp, scale);
      }
      // Подпись пристройки. Если внутри есть мебель — текст уезжает в
      // верхний-левый угол, чтобы не накладываться на силуэт авто
      // или стол. Если мебели нет (крыльцо) — оставляем текст по
      // центру, как было.
      final hasFurn = attFurniture.isNotEmpty;
      final labelCx = hasFurn ? rx + 4 : rx + rw / 2;
      final labelCy = hasFurn ? ry + rh - 8 : ry + rh / 2 + 3;
      final labelAlign = hasFurn ? _TextAlign.left : _TextAlign.center;
      _drawAlignedText(
        canvas,
        a.label,
        labelCx,
        labelCy,
        fontSize: 7,
        font: font,
        color: PdfColors.grey800,
        align: labelAlign,
      );
      // Габариты в мм под подписью.
      final wMm = (a.width * 1000).round();
      final hMm = (a.height * 1000).round();
      _drawAlignedText(
        canvas,
        '$wMm×$hMm',
        labelCx,
        hasFurn ? labelCy - 8 : ry + rh / 2 - 6,
        fontSize: 6,
        font: font,
        color: PdfColors.grey700,
        align: labelAlign,
      );
    }
  }

  static void _drawAlignedText(
    PdfGraphics canvas,
    String text,
    double x,
    double y, {
    required double fontSize,
    required PdfFont font,
    PdfColor color = PdfColors.black,
    _TextAlign align = _TextAlign.center,
  }) {
    if (align == _TextAlign.center) {
      _drawCenteredText(canvas, text, x, y,
          fontSize: fontSize, font: font, color: color);
      return;
    }
    canvas.setFillColor(color);
    canvas.drawString(font, fontSize, text, x, y - fontSize * 0.35);
    canvas.setFillColor(PdfColors.black);
  }

  static void _drawStaircasePattern(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    _RectM r, {
    String? staircaseType,
    int? steps,
    double? floorHeight,
    bool descentToBasement = false,
  }) {
    // Тип лестницы из этапа 2 «Лестница»:
    //   marsh   — маршевая (прямой одномаршевый/двухмаршевый);
    //   rotary  — Г-образная двухмаршевая с площадкой 90° (СП 54.13330.2022);
    //   screw   — винтовая, ступени радиально из центра.
    // Если тип не задан, рисуем маршевую как раньше.
    canvas.setStrokeColor(_staircaseStroke);
    canvas.setLineWidth(0.4);
    final horizontal = r.mw >= r.mh;
    final h = floorHeight ?? 2.8;
    final riser = staircaseType == 'screw' ? 0.180 : 0.165;
    final n = steps ?? (h / riser).ceil();
    final riserMm = (h * 1000 / n).round();
    const margin = 0.08;

    if (staircaseType == 'screw') {
      _drawScrewStaircase(canvas, font, pp, r, n, riserMm);
      if (descentToBasement) {
        _drawDescentLabel(canvas, font, pp, r, horizontal);
      }
      return;
    }
    if (staircaseType == 'rotary') {
      _drawRotaryStaircase(canvas, font, pp, r, n, riserMm);
      if (descentToBasement) {
        _drawDescentLabel(canvas, font, pp, r, horizontal);
      }
      return;
    }

    // ---- Маршевая (по умолчанию) ----
    if (horizontal) {
      final flightLen = r.mw - margin * 2;
      final stepW = flightLen / n;
      for (var i = 0; i <= n; i++) {
        final lx = r.mx + margin + stepW * i;
        final a = pp(lx, r.my + margin);
        final b = pp(lx, r.my + r.mh - margin);
        canvas.drawLine(a.x, a.y, b.x, b.y);
        canvas.strokePath();
      }
      // Линия обрыва марша на 60 % длины (для двухмаршевой компоновки).
      final cutX1 = r.mx + flightLen * 0.55 + margin;
      final cutX2 = cutX1 + 0.1;
      canvas.setLineWidth(0.6);
      final a1 = pp(cutX1, r.my + margin);
      final b1 = pp(cutX2, r.my + r.mh - margin);
      canvas.drawLine(a1.x, a1.y, b1.x, b1.y);
      canvas.strokePath();
    } else {
      final flightLen = r.mh - margin * 2;
      final stepH = flightLen / n;
      for (var i = 0; i <= n; i++) {
        final ly = r.my + margin + stepH * i;
        final a = pp(r.mx + margin, ly);
        final b = pp(r.mx + r.mw - margin, ly);
        canvas.drawLine(a.x, a.y, b.x, b.y);
        canvas.strokePath();
      }
      final cutY1 = r.my + flightLen * 0.55 + margin;
      final cutY2 = cutY1 + 0.1;
      canvas.setLineWidth(0.6);
      final a1 = pp(r.mx + margin, cutY1);
      final b1 = pp(r.mx + r.mw - margin, cutY2);
      canvas.drawLine(a1.x, a1.y, b1.x, b1.y);
      canvas.strokePath();
    }
    _drawStaircaseArrow(canvas, font, pp, r, '$n×$riserMm', horizontal);
    if (descentToBasement) {
      _drawDescentLabel(canvas, font, pp, r, horizontal);
    }
  }

  /// Малая подпись «↓ в подвал» рядом с лестницей на плане 1-го этажа.
  /// Не пересекает основную стрелку «↑», нанесённую _drawStaircaseArrow.
  static void _drawDescentLabel(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    _RectM r,
    bool horizontal,
  ) {
    canvas.setFillColor(PdfColors.black);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    // Небольшая дополнительная стрелка в обратном направлении
    // (показывает спуск в подвал) и подпись «↓ в подвал».
    final PdfPoint a;
    final PdfPoint b;
    final double tx, ty;
    if (horizontal) {
      a = pp(r.mx + 0.2, r.my + r.mh - 0.18);
      b = pp(r.mx + r.mw * 0.3, r.my + r.mh - 0.18);
      tx = b.x + 4;
      ty = b.y - 3;
    } else {
      a = pp(r.mx + r.mw - 0.18, r.my + r.mh - 0.2);
      b = pp(r.mx + r.mw - 0.18, r.my + r.mh * 0.7);
      tx = b.x + 4;
      ty = b.y - 1;
    }
    canvas.drawLine(a.x, a.y, b.x, b.y);
    canvas.strokePath();
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      final ux = dx / len, uy = dy / len;
      const arrL = 5.0, arrW = 2.4;
      final lx = b.x - ux * arrL - uy * arrW;
      final ly = b.y - uy * arrL + ux * arrW;
      final rx = b.x - ux * arrL + uy * arrW;
      final ry = b.y - uy * arrL - ux * arrW;
      canvas.drawLine(b.x, b.y, lx, ly);
      canvas.drawLine(b.x, b.y, rx, ry);
      canvas.strokePath();
    }
    canvas.drawString(font, 6, 'в подвал', tx, ty);
  }

  /// Рисует поднимающуюся стрелку «n×riser» внутри лестницы.
  static void _drawStaircaseArrow(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    _RectM r,
    String label,
    bool horizontal,
  ) {
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    final PdfPoint arrStart;
    final PdfPoint arrEnd;
    if (horizontal) {
      arrStart = pp(r.mx + 0.2, r.my + r.mh / 2);
      arrEnd = pp(r.mx + r.mw - 0.2, r.my + r.mh / 2);
    } else {
      arrStart = pp(r.mx + r.mw / 2, r.my + r.mh - 0.2);
      arrEnd = pp(r.mx + r.mw / 2, r.my + 0.2);
    }
    canvas.drawLine(arrStart.x, arrStart.y, arrEnd.x, arrEnd.y);
    canvas.strokePath();
    final dx = arrEnd.x - arrStart.x;
    final dy = arrEnd.y - arrStart.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      final ux = dx / len, uy = dy / len;
      const arrL = 7.0, arrW = 3.0;
      final tipX = arrEnd.x, tipY = arrEnd.y;
      final leftX = tipX - ux * arrL - uy * arrW;
      final leftY = tipY - uy * arrL + ux * arrW;
      final rightX = tipX - ux * arrL + uy * arrW;
      final rightY = tipY - uy * arrL - ux * arrW;
      canvas.drawLine(tipX, tipY, leftX, leftY);
      canvas.drawLine(tipX, tipY, rightX, rightY);
      canvas.strokePath();
    }
    final lblX = (arrStart.x + arrEnd.x) / 2;
    final lblY = (arrStart.y + arrEnd.y) / 2 + 8;
    _drawCenteredText(canvas, label, lblX, lblY,
        fontSize: 6.5, font: font, color: PdfColors.black);
  }

  /// Г-образная двухмаршевая лестница с поворотной площадкой 90°.
  /// Помещение делится по диагонали: нижний марш — половина, площадка
  /// в углу, верхний марш — другая половина (под прямым углом).
  static void _drawRotaryStaircase(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    _RectM r,
    int n,
    int riserMm,
  ) {
    final n1 = n ~/ 2;
    final n2 = n - n1;
    const margin = 0.08;
    // Делим зону на квадрант 60/40, нижний марш — горизонтальная полоска
    // снизу, верхний марш — вертикальная полоска слева (Г-образно).
    final halfW = r.mw * 0.55;
    final halfH = r.mh * 0.55;

    // 1) Нижний марш — слева снизу (горизонтальный).
    final lowMx = r.mx + margin;
    final lowMy = r.my + r.mh - halfH; // нижняя половина — по Y модельной (вниз)
    final lowMw = halfW - margin;
    final lowMh = halfH - margin;
    final stepW = lowMw / n1;
    for (var i = 0; i <= n1; i++) {
      final lx = lowMx + stepW * i;
      final a = pp(lx, lowMy);
      final b = pp(lx, lowMy + lowMh);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }
    // 2) Верхний марш — справа сверху (вертикальный, противоположное направление).
    final upMx = r.mx + halfW;
    final upMy = r.my + margin;
    final upMw = r.mw - halfW - margin;
    final upMh = halfH - margin;
    final stepH = upMh / n2;
    for (var i = 0; i <= n2; i++) {
      final ly = upMy + stepH * i;
      final a = pp(upMx, ly);
      final b = pp(upMx + upMw, ly);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }
    // 3) Площадка 90° — заштрихована тонкими линиями.
    canvas.setLineWidth(0.3);
    canvas.setStrokeColor(PdfColors.grey500);
    final landingMx = r.mx + halfW;
    final landingMy = r.my + r.mh - halfH;
    final landingMw = r.mw - halfW - margin;
    final landingMh = halfH - margin;
    const hatchStep = 0.06;
    for (var x = 0.0; x < landingMw + landingMh; x += hatchStep) {
      final p1 = pp(landingMx + x, landingMy);
      final p2 = pp(landingMx + x - landingMh, landingMy + landingMh);
      canvas.drawLine(p1.x, p1.y, p2.x, p2.y);
      canvas.strokePath();
    }

    // Стрелка по нижнему маршу (горизонтально вправо к площадке).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    final aStart = pp(lowMx + 0.05, lowMy + lowMh / 2);
    final aEnd = pp(lowMx + lowMw - 0.05, lowMy + lowMh / 2);
    canvas.drawLine(aStart.x, aStart.y, aEnd.x, aEnd.y);
    canvas.strokePath();
    _drawArrowhead(canvas, aStart, aEnd);
    final lblX = (aStart.x + aEnd.x) / 2;
    final lblY = (aStart.y + aEnd.y) / 2 + 8;
    _drawCenteredText(canvas, '$n×$riserMm (Г-образная)', lblX, lblY,
        fontSize: 6.5, font: font, color: PdfColors.black);
  }

  /// Винтовая лестница: 12–14 радиальных ступеней из центра помещения.
  static void _drawScrewStaircase(
    PdfGraphics canvas,
    PdfFont font,
    PdfPoint Function(double, double) pp,
    _RectM r,
    int n,
    int riserMm,
  ) {
    final cx = r.mx + r.mw / 2;
    final cy = r.my + r.mh / 2;
    final radius = math.min(r.mw, r.mh) / 2 - 0.08;
    final innerRadius = radius * 0.18; // центральная стойка

    canvas.setStrokeColor(_staircaseStroke);
    canvas.setLineWidth(0.4);

    // Внешняя окружность (обводка лестницы).
    _drawCircle(canvas, pp, cx, cy, radius, segments: 64);
    // Центральная стойка.
    _drawCircle(canvas, pp, cx, cy, innerRadius, segments: 24);
    // Радиальные подступёнки.
    for (var i = 0; i < n; i++) {
      final ang = 2 * math.pi * i / n;
      final x1 = cx + math.cos(ang) * innerRadius;
      final y1 = cy + math.sin(ang) * innerRadius;
      final x2 = cx + math.cos(ang) * radius;
      final y2 = cy + math.sin(ang) * radius;
      final a = pp(x1, y1);
      final b = pp(x2, y2);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }
    // Стрелка вращения (дуга со стрелкой) — символично указываем направление.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    final arrR = radius * 0.55;
    PdfPoint? prev;
    for (var i = 0; i <= 36; i++) {
      final t = i / 36;
      final ang = math.pi * 0.2 + t * math.pi * 1.2;
      final x = cx + math.cos(ang) * arrR;
      final y = cy + math.sin(ang) * arrR;
      final p = pp(x, y);
      if (prev != null) {
        canvas.drawLine(prev.x, prev.y, p.x, p.y);
        canvas.strokePath();
      }
      prev = p;
    }
    // Подпись по центру.
    final centerPt = pp(cx, cy + radius * 0.6);
    _drawCenteredText(
      canvas,
      '$n×$riserMm (винтовая)',
      centerPt.x,
      centerPt.y - 4,
      fontSize: 6.5,
      font: font,
      color: PdfColors.black,
    );
  }

  /// Утилита: окружность отрезками.
  static void _drawCircle(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp,
    double cx,
    double cy,
    double radius, {
    int segments = 32,
  }) {
    PdfPoint? prev;
    for (var i = 0; i <= segments; i++) {
      final ang = 2 * math.pi * i / segments;
      final x = cx + math.cos(ang) * radius;
      final y = cy + math.sin(ang) * radius;
      final p = pp(x, y);
      if (prev != null) {
        canvas.drawLine(prev.x, prev.y, p.x, p.y);
        canvas.strokePath();
      }
      prev = p;
    }
  }

  /// Утилита: наконечник стрелки на отрезке start→end.
  static void _drawArrowhead(
    PdfGraphics canvas,
    PdfPoint start,
    PdfPoint end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0) return;
    final ux = dx / len, uy = dy / len;
    const arrL = 7.0, arrW = 3.0;
    final leftX = end.x - ux * arrL - uy * arrW;
    final leftY = end.y - uy * arrL + ux * arrW;
    final rightX = end.x - ux * arrL + uy * arrW;
    final rightY = end.y - uy * arrL - ux * arrW;
    canvas.drawLine(end.x, end.y, leftX, leftY);
    canvas.drawLine(end.x, end.y, rightX, rightY);
    canvas.strokePath();
  }

  /// Осветлить цвет на [t] (0..1) — линейная интерполяция к белому.
  static PdfColor _lighten(PdfColor c, double t) => PdfColor(
        c.red + (1 - c.red) * t,
        c.green + (1 - c.green) * t,
        c.blue + (1 - c.blue) * t,
      );

  /// Форматирует высотную отметку в метрах по ГОСТ Р 21.101-2020:
  /// «±0,000», «+5,398», «-0,150» — три знака после запятой,
  /// разделитель — запятая, нулевая отметка с «±».
  static String _formatLevelMeters(double meters) {
    final value = meters.abs() < 0.0005 ? 0.0 : meters;
    final formatted = value.abs().toStringAsFixed(3).replaceAll('.', ',');
    if (value > 0) return '+$formatted';
    if (value < 0) return '-$formatted';
    return '±$formatted';
  }

  /// Подгоняет строку под `maxWidth` (в точках) — если не влезает,
  /// обрезает по символам и добавляет «…». Использовать везде, где
  /// текст попадает в фиксированную ячейку таблицы/штампа.
  static String _fitText(
    String text,
    PdfFont font,
    double fontSize,
    double maxWidth, {
    String ellipsis = '…',
  }) {
    if (text.isEmpty) return text;
    final full = font.stringMetrics(text).width * fontSize;
    if (full <= maxWidth) return text;
    final ellipsisW = font.stringMetrics(ellipsis).width * fontSize;
    var lo = 0;
    var hi = text.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final w = font.stringMetrics(text.substring(0, mid)).width * fontSize;
      if (w + ellipsisW <= maxWidth) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo <= 0) return ellipsis;
    return '${text.substring(0, lo).trimRight()}$ellipsis';
  }

  /// Отрисовывает текст слева в ячейке, гарантируя что он не выйдет за
  /// правый край. При необходимости обрезает строку с добавлением «…».
  static void _drawClippedLeftText(
    PdfGraphics canvas,
    PdfFont font, {
    required String text,
    required double x,
    required double y,
    required double fontSize,
    required double maxWidth,
  }) {
    final fitted = _fitText(text, font, fontSize, maxWidth);
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, fontSize, fitted, x, y);
  }

  static void _drawCenteredText(
    PdfGraphics canvas,
    String text,
    double cx,
    double cy, {
    required double fontSize,
    required PdfFont font,
    PdfColor color = PdfColors.black,
    double? maxWidth,
  }) {
    final effective = maxWidth != null
        ? _fitText(text, font, fontSize, maxWidth)
        : text;
    final lines = effective.split('\n');
    final lineHeight = fontSize * 1.15;
    // Для визуального центрирования строки baseline должен быть смещён
    // относительно центра на ~0.35·fontSize вниз (т. к. видимая высота
    // буквы — это ascent ≈ 0.7·fontSize, и геометрический центр буквы
    // находится на baseline + 0.35·fontSize).
    // Для нескольких строк top-line baseline = центр + (n−1)·lh/2
    // − 0.35·fontSize.
    final firstBaseline =
        cy + (lines.length - 1) * lineHeight / 2 - fontSize * 0.35;
    var y = firstBaseline;
    canvas.setFillColor(color);
    for (final line in lines) {
      final width = font.stringMetrics(line).width * fontSize;
      canvas.drawString(font, fontSize, line, cx - width / 2, y);
      y -= lineHeight;
    }
    canvas.setFillColor(PdfColors.black);
  }

  /// Палитра плана кровли.
  static const PdfColor _roofRidgeColor = PdfColors.red700;
  static const PdfColor _roofHipColor = PdfColors.deepOrange700;
  // Phase-3b §17.2.1 next-slice: ендова — внутренний стык скатов
  // на L/T/U-форме. Рисуем сине-фиолетовым, чтобы отличался
  // от конька (красный) и накоса (оранжевый).
  static const PdfColor _roofValleyColor = PdfColors.indigo700;
  static const PdfColor _roofEaveColor = PdfColors.black;
  static const PdfColor _roofWallOutline = PdfColors.grey700;
  static const PdfColor _roofDrainColor = PdfColors.blue700;
  static const PdfColor _roofSnowGuardColor = PdfColors.indigo700;
  static const PdfColor _roofChimneyColor = PdfColors.brown700;
  static const PdfColor _roofAeratorColor = PdfColors.teal700;
  static const PdfColor _roofSlopeFill = PdfColor(0.97, 0.97, 0.94);

  /// Рисует план кровли:
  ///   1) контур кровли с карнизным свесом;
  ///   2) скаты со стрелками уклона + процент уклона;
  ///   3) конёк (красный жирный);
  ///   4) накосы для вальмовой кровли (оранжевый);
  ///   5) водосливы (синие кружки);
  ///   6) снегозадержатели (треугольники по карнизу);
  ///   7) дымоходы (коричневые квадраты);
  ///   8) аэраторы (бирюзовые кружки);
  ///   9) осевая сетка по контуру здания (как в АР-3);
  ///  10) отметка ±0.000 + отметка конька + указатель севера.
  static void _paintRoofPlan(
    PdfGraphics canvas,
    PdfPoint size,
    FloorPlan plan,
    HouseProject project,
    PdfFont font,
    PdfFont fontBold,
  ) {
    final roof = project.roof;
    final shape = RoofShape.fromTypeId(roof.type);
    final slopeDeg = roof.slopeAngle ?? 30;
    final snowZone = project.brief.snowZone ?? 1;

    // Габариты подсказки + свес 0.5 м, плюс симметричные поля для осей,
    // как в _paintPlan. Размеры свеса добавляем к расчёту масштаба.
    // Phase-3b §17.2.1 next-slice: для полигональных footprint-ов
    // (L/T/U/Г-формы) используем `computePolygonal`, который
    // раскладывает полигон на подпрямоугольники, ставит конёк в
    // каждом и добавляет ендовы по общим рёбрам — иначе кровля
    // «висит» прямоугольником над зоной выреза.
    final RoofPlanGeometry geom = plan.hasPolygonalFootprint
        ? RoofPlanGeometry.computePolygonal(
            shape: shape,
            footprint: plan.footprint!,
            slopeDegrees: slopeDeg,
            snowZone: snowZone,
            chimneyCount: 1,
            aeratorCount: shape == RoofShape.flat ? 0 : 2,
          )
        : RoofPlanGeometry.compute(
            shape: shape,
            buildingWidth: plan.width,
            buildingHeight: plan.height,
            slopeDegrees: slopeDeg,
            snowZone: snowZone,
            chimneyCount: project.brief.hasBasement == true ||
                    project.brief.hasMansard == true
                ? 1
                : 1, // как минимум одна дымовая шахта (отопление)
            aeratorCount: shape == RoofShape.flat ? 0 : 2,
          );

    final w = size.x;
    final h = size.y;
    // Слева оставляем место для (после правки пользователя по листу 9
    // расстояния увеличены ~ на 25 %):
    //   – цепи между осями (72 pt),
    //   – общего габарита здания (112 pt),
    //   – дополнительной габаритной цепи по карнизу (132 pt) + 25 pt
    //     запаса на подпись.
    // На листе кровли цепь «проёмы» отключена, поэтому её 32 pt
    // не нужны, но запас под подпись на самой внешней цепи увеличен.
    // Поля кровли расширены: оси выносятся ПОСЛЕ цепи по карнизу
    // (правка по листу 8). yAxisBase = chainTotalLeft 140 + outerChainExt 28
    // + 50 = 218. marginLeft = 218 + R 11 + label 8 + запас = 250.
    const marginLeft = 250.0;
    // Справа резервируем 250 pt: легенда условных обозначений
    // (~175 pt) + 75 pt на отступ от чертежа.
    const marginRight = 250.0;
    const marginTop = 110.0;
    const marginBottom = 200.0;
    // Масштаб считаем по полному габариту кровли (с учётом свеса) — иначе
    // карнизы упрутся в размерные цепи.
    final scaleX = (w - marginLeft - marginRight) / geom.totalWidth;
    final scaleY = (h - marginTop - marginBottom) / geom.totalHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final planW = plan.width * scale;
    final planH = plan.height * scale;
    final ox =
        marginLeft + ((w - marginLeft - marginRight) - planW) / 2;
    final oy =
        marginTop + ((h - marginTop - marginBottom) - planH) / 2;

    // Преобразование «модельные метры → пункты PDF».
    PdfPoint pp(double mx, double my) =>
        PdfPoint(ox + mx * scale, oy + planH - my * scale);

    // 1. Заливка скатов.
    canvas.setFillColor(_roofSlopeFill);
    canvas.setStrokeColor(_roofEaveColor);
    canvas.setLineWidth(0.6);
    for (final s in geom.slopes) {
      _drawRoofPolygon(canvas, pp, s.polygon, fill: true, stroke: false);
    }

    // 2. Контур внешнего свеса (штрих-пунктир).
    _drawDashedPolygon(canvas, pp, geom.outerOutline,
        color: _roofEaveColor, lineWidth: 0.8, dash: [5, 3]);

    // 3. Контур здания под кровлей (серая тонкая линия).
    // Для полигональных footprint-ов рисуем линию по реальному outline.
    canvas.setStrokeColor(_roofWallOutline);
    canvas.setLineWidth(0.5);
    if (plan.hasPolygonalFootprint) {
      final outline = plan.footprint!.outline;
      for (var i = 0; i < outline.length; i++) {
        final p1 = outline[i];
        final p2 = outline[(i + 1) % outline.length];
        final a = pp(p1.x, p1.y);
        final b = pp(p2.x, p2.y);
        canvas.drawLine(a.x, a.y, b.x, b.y);
      }
    } else {
      final w0 = pp(0, 0);
      final w1 = pp(plan.width, 0);
      final w2 = pp(plan.width, plan.height);
      final w3 = pp(0, plan.height);
      canvas.drawLine(w0.x, w0.y, w1.x, w1.y);
      canvas.drawLine(w1.x, w1.y, w2.x, w2.y);
      canvas.drawLine(w2.x, w2.y, w3.x, w3.y);
      canvas.drawLine(w3.x, w3.y, w0.x, w0.y);
    }
    canvas.strokePath();

    // 4. Конёк (красный, жирный).
    canvas.setStrokeColor(_roofRidgeColor);
    canvas.setLineWidth(2.0);
    for (final r in geom.ridges) {
      final a = pp(r.a.x, r.a.y);
      final b = pp(r.b.x, r.b.y);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }

    // 5. Накосы (оранжевый, средняя толщина).
    canvas.setStrokeColor(_roofHipColor);
    canvas.setLineWidth(1.2);
    for (final hp in geom.hips) {
      final a = pp(hp.a.x, hp.a.y);
      final b = pp(hp.b.x, hp.b.y);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }

    // 5b. Ендовы (для L/T/U-форм; сине-фиолетовый, средняя толщина).
    canvas.setStrokeColor(_roofValleyColor);
    canvas.setLineWidth(1.2);
    for (final vy in geom.valleys) {
      final a = pp(vy.a.x, vy.a.y);
      final b = pp(vy.b.x, vy.b.y);
      canvas.drawLine(a.x, a.y, b.x, b.y);
      canvas.strokePath();
    }

    // 6. Стрелки уклонов + проценты.
    for (final s in geom.slopes) {
      final anchor = pp(s.arrowAnchor.x, s.arrowAnchor.y);
      // flowDirection в plane-кадре (Y вниз), на canvas Y инвертирована.
      final dxc = s.flowDirection.x;
      final dyc = -s.flowDirection.y; // canvas Y вверх
      _drawSlopeArrow(canvas, anchor.x, anchor.y, dxc, dyc, font,
          slopeDegrees: s.slopeDegrees,
          slopePercent: s.slopePercent);
    }

    // 7. Снегозадержатели (короткие треугольники вдоль линии).
    canvas.setStrokeColor(_roofSnowGuardColor);
    canvas.setLineWidth(0.6);
    for (final sg in geom.snowGuards) {
      _drawSnowGuards(canvas, pp, sg);
    }

    // 8. Водосливы (синие кружки Ø 4 пт).
    canvas.setFillColor(_roofDrainColor);
    canvas.setStrokeColor(_roofDrainColor);
    canvas.setLineWidth(0.6);
    for (final d in geom.drains) {
      final p = pp(d.x, d.y);
      canvas.drawEllipse(p.x, p.y, 3.5, 3.5);
      canvas.fillAndStrokePath();
    }
    // Подпись «В1, В2 …» рядом с водосливами.
    for (var i = 0; i < geom.drains.length; i++) {
      final p = pp(geom.drains[i].x, geom.drains[i].y);
      _drawCenteredText(
        canvas,
        'В${i + 1}',
        p.x + 9,
        p.y - 2,
        fontSize: 7,
        font: font,
      );
    }

    // 9. Дымоходы (коричневые квадраты 6×6 пт).
    canvas.setFillColor(_roofChimneyColor);
    canvas.setStrokeColor(_roofChimneyColor);
    canvas.setLineWidth(0.6);
    for (final c in geom.chimneys) {
      final p = pp(c.x, c.y);
      canvas.drawRect(p.x - 3, p.y - 3, 6, 6);
      canvas.fillAndStrokePath();
    }

    // 10. Аэраторы (бирюзовые кружки Ø 5 пт с крестом).
    canvas.setStrokeColor(_roofAeratorColor);
    canvas.setFillColor(PdfColors.white);
    canvas.setLineWidth(0.6);
    for (final a in geom.aerators) {
      final p = pp(a.x, a.y);
      canvas.drawEllipse(p.x, p.y, 4, 4);
      canvas.fillAndStrokePath();
      canvas.setStrokeColor(_roofAeratorColor);
      canvas.setLineWidth(0.5);
      canvas.drawLine(p.x - 3, p.y, p.x + 3, p.y);
      canvas.drawLine(p.x, p.y - 3, p.x, p.y + 3);
      canvas.strokePath();
    }

    // 11. Осевая сетка по контуру здания (как АР-3). Стрелку севера и
    // отметку ±0.000 рисуем сами ниже — внутри плана для них нет места
    // (там и так конёк, скаты, дымоход). Передаём fontBold, чтобы
    // подписи в кружках осей были жирными по ГОСТ 21.501-2018.
    //
    // По правкам пользователя по листу 8:
    //  • снизу (по численным осям) — две цепи: между осями + габарит
    //    крыши «по карнизу»; межосевой общий габарит и проёмы выключены;
    //  • слева (по буквенным осям) — две цепи: между осями + габарит
    //    крыши; межосевой общий габарит выключен (`drawTotalChainLeft:
    //    false`), цепь по карнизу занимает его место;
    //  • цепи прижаты ближе к плану (chainStep 96→36, chainTotal 140→76),
    //    чтобы габарит не лез на штамп и условные обозначения.
    _paintAxesAndDimensions(
      canvas: canvas,
      plan: plan,
      font: font,
      fontBold: fontBold,
      ox: ox,
      oy: oy,
      planW: planW,
      planH: planH,
      scale: scale,
      drawZeroMark: false,
      drawNorthArrow: false,
      drawOpeningsChain: false,
      drawTotalChainBottom: false,
      drawTotalChainLeft: false,
      chainStepOffsetBase: 36.0,
      chainTotalOffsetBase: 76.0,
      // Цепь «по карнизу» теперь ровно на месте chainTotal (76 pt) —
      // дополнительного выноса осей не нужно.
      outerChainExt: 0,
      // Пристройки (терраса/гараж/крыльцо) не рисуются на плане кровли,
      // поэтому attachment-shift не применяем — иначе цепь между осями
      // уехала бы НИЖЕ цепи карниза и хвост выносных линий вылез бы
      // на штамп (правка пользователя по листу 8).
      applyAttachmentShift: false,
    );

    // 11.1 Габаритная цепь по крайним точкам кровли (свес).
    // По ГОСТ 21.501-2018 п. 5.10.3 общий габарит здания/кровли
    // показывают по крайним выступающим элементам — карнизам.
    // Ставим отдельную цепь снизу и слева на уровне «дальше штатной»
    // (пунктом ниже стандартных габаритов плана).
    final overhangPx = geom.overhang * scale;
    final eaveLeft = ox - overhangPx;
    final eaveRight = ox + planW + overhangPx;
    final eaveBottom = oy + planH + overhangPx;
    final eaveTop = oy - overhangPx;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Снизу — цепь длиной (W + 2·свес). Это «вторая горизонтальная
    // линия» по правкам пользователя по листу 8: остались только две
    // цепи (между осями 36 pt + габарит по карнизу 76 pt), и они
    // прижаты ближе к плану, чтобы габарит не лез на штамп.
    final roofEnvBottomY = oy - 76.0;
    canvas.drawLine(eaveLeft, roofEnvBottomY, eaveRight, roofEnvBottomY);
    const tickD = 4.0 / math.sqrt2;
    canvas.drawLine(eaveLeft - tickD, roofEnvBottomY - tickD,
        eaveLeft + tickD, roofEnvBottomY + tickD);
    canvas.drawLine(eaveRight - tickD, roofEnvBottomY - tickD,
        eaveRight + tickD, roofEnvBottomY + tickD);
    // Выносные линии от углов карниза (B3, B4) к нижней цепи —
    // от точки на стене (eaveTop) до 4 pt за цепью (правка пользователя
    // по листу 8: габарит должен быть привязан к чертежу с обеих сторон).
    canvas.drawLine(eaveLeft, eaveTop - 2, eaveLeft, roofEnvBottomY - 4);
    canvas.drawLine(eaveRight, eaveTop - 2, eaveRight, roofEnvBottomY - 4);
    canvas.strokePath();
    final totalEnvWMm = (geom.totalWidth * 1000).round();
    // Подпись по карнизу должна избегать центров кружков осей —
    // иначе на чётном числе осей подпись садится прямо на ось «В»
    // (правка пользователя по листу 8). Сдвигаем X в зазор между осями.
    double safeAlong1D(double rawCenter, double lo, double hi,
        List<double> avoid, double textHalf) {
      const halfCircle = 11.0;
      final pad = textHalf + halfCircle + 3;
      bool collides(double c) => avoid.any((p) => (p - c).abs() < pad);
      if (!collides(rawCenter)) return rawCenter;
      final sorted = List<double>.from(avoid)..sort();
      final cands = <double>[
        for (var i = 0; i + 1 < sorted.length; i++)
          (sorted[i] + sorted[i + 1]) / 2,
        lo + pad,
        hi - pad,
      ];
      cands.sort((x, y) =>
          (x - rawCenter).abs().compareTo((y - rawCenter).abs()));
      for (final c in cands) {
        if (c >= lo + pad && c <= hi - pad && !collides(c)) return c;
      }
      return rawCenter;
    }

    // Подпись «13000 (по карнизу)» по правке пользователя должна стоять
    // ровно по центру всей выноски, без обхода осей — текст-то всё равно
    // читается поверх тонкой выносной линии.
    final eaveLabelX = (eaveLeft + eaveRight) / 2;
    // Подпись ставим ВЫШЕ цепи (ближе к плану) — такая же конвенция,
    // как и у chainStep/openings; иначе текст пересекается с концами
    // выносных линий, которые уходят на 4 pt ниже цепи.
    _drawCenteredText(
      canvas,
      '$totalEnvWMm  (по карнизу)',
      eaveLabelX,
      roofEnvBottomY + 7,
      fontSize: 7.5,
      font: font,
    );
    // Слева — цепь длиной (H + 2·свес). На месте chainTotalLeft (76 pt),
    // межосевой общий габарит слева выключен (`drawTotalChainLeft:
    // false`).
    final roofEnvLeftX = ox - 76.0;
    canvas.drawLine(roofEnvLeftX, eaveTop, roofEnvLeftX, eaveBottom);
    canvas.drawLine(roofEnvLeftX - tickD, eaveTop - tickD,
        roofEnvLeftX + tickD, eaveTop + tickD);
    canvas.drawLine(roofEnvLeftX - tickD, eaveBottom - tickD,
        roofEnvLeftX + tickD, eaveBottom + tickD);
    // Выносные линии от углов карниза (B1, B3) к левой цепи —
    // от стены (eaveLeft) до 4 pt за цепью (правка пользователя по листу 8).
    canvas.drawLine(eaveLeft - 2, eaveTop, roofEnvLeftX - 4, eaveTop);
    canvas.drawLine(eaveLeft - 2, eaveBottom, roofEnvLeftX - 4, eaveBottom);
    canvas.strokePath();
    final totalEnvHMm = (geom.totalHeight * 1000).round();
    final hLabelH = 7.5 + 2;
    final axesYPos = [
      for (final y in _collectAxes(plan, false)) oy + planH - y * scale,
    ];
    final eaveLabelY = safeAlong1D(
      (eaveTop + eaveBottom) / 2,
      eaveTop,
      eaveBottom,
      axesYPos
          .where((y) =>
              y > eaveTop + hLabelH / 2 + 14 &&
              y < eaveBottom - hLabelH / 2 - 14)
          .toList(),
      hLabelH / 2,
    );
    _drawCenteredText(
      canvas,
      '$totalEnvHMm',
      roofEnvLeftX - 18,
      eaveLabelY,
      fontSize: 7.5,
      font: font,
    );

    // Указатель севера — слева сверху (за пределами плана).
    _drawNorthArrow(canvas, font, cx: ox - 55, cy: oy + planH + 55);

    // 12. Отметки высот (конёк/карниз/±0.000) на плане кровли —
    // по правке пользователя убираем ВСЕ. Они дублируются на разрезах
    // (АР-9..АР-12), на плане кровли только мешают чтению чертежа.

    // 13. Легенда (справа от плана, вне зоны размерных цепей и кружков
    // осей по правому верху). Сдвигаем дальше — на 130 pt от пятна,
    // чтобы условные обозначения не наслаивались на свес кровли.
    _drawRoofLegend(
      canvas,
      font,
      x: ox + planW + 130,
      y: oy + planH * 0.35,
      shape: shape,
      slopeDeg: slopeDeg,
      slopePercent: geom.slopes.isEmpty ? 0 : geom.slopes.first.slopePercent,
      snowZone: snowZone,
      hasSnowGuards: geom.snowGuards.isNotEmpty,
      drainCount: geom.drains.length,
      hasValleys: geom.valleys.isNotEmpty,
    );
  }

  static void _drawRoofPolygon(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp,
    List<RoofPoint> poly, {
    required bool fill,
    required bool stroke,
  }) {
    if (poly.isEmpty) return;
    final start = pp(poly.first.x, poly.first.y);
    canvas.moveTo(start.x, start.y);
    for (var i = 1; i < poly.length; i++) {
      final p = pp(poly[i].x, poly[i].y);
      canvas.lineTo(p.x, p.y);
    }
    canvas.lineTo(start.x, start.y);
    if (fill && stroke) {
      canvas.fillAndStrokePath();
    } else if (fill) {
      canvas.fillPath();
    } else if (stroke) {
      canvas.strokePath();
    }
  }

  static void _drawDashedPolygon(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp,
    List<RoofPoint> poly, {
    required PdfColor color,
    required double lineWidth,
    required List<double> dash,
  }) {
    canvas.setStrokeColor(color);
    canvas.setLineWidth(lineWidth);
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      _drawDashedLine(canvas, pp(a.x, a.y), pp(b.x, b.y), dash);
    }
  }

  static void _drawDashedLine(
    PdfGraphics canvas,
    PdfPoint a,
    PdfPoint b,
    List<double> dash,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 0.5) return;
    final ux = dx / length;
    final uy = dy / length;
    var t = 0.0;
    var draw = true;
    var i = 0;
    while (t < length) {
      final segLen = dash[i % dash.length];
      final t2 = (t + segLen).clamp(0.0, length);
      if (draw) {
        canvas.drawLine(
          a.x + ux * t,
          a.y + uy * t,
          a.x + ux * t2,
          a.y + uy * t2,
        );
        canvas.strokePath();
      }
      t = t2;
      draw = !draw;
      i++;
    }
  }

  /// Стрелка стока в плановой проекции с подписью «<процент>%».
  static void _drawSlopeArrow(
    PdfGraphics canvas,
    double cx,
    double cy,
    double dxc,
    double dyc,
    PdfFont font, {
    required double slopeDegrees,
    required double slopePercent,
  }) {
    const arrowLen = 28.0;
    const arrowHead = 6.0;
    final mag = math.sqrt(dxc * dxc + dyc * dyc);
    if (mag < 0.001) return;
    final ux = dxc / mag;
    final uy = dyc / mag;
    final ax = cx - ux * arrowLen / 2;
    final ay = cy - uy * arrowLen / 2;
    final bx = cx + ux * arrowLen / 2;
    final by = cy + uy * arrowLen / 2;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    canvas.drawLine(ax, ay, bx, by);
    canvas.strokePath();
    // Наконечник стрелки.
    final px = -uy;
    final py = ux;
    canvas.moveTo(bx, by);
    canvas.lineTo(bx - ux * arrowHead + px * arrowHead * 0.5,
        by - uy * arrowHead + py * arrowHead * 0.5);
    canvas.lineTo(bx - ux * arrowHead - px * arrowHead * 0.5,
        by - uy * arrowHead - py * arrowHead * 0.5);
    canvas.lineTo(bx, by);
    canvas.fillPath();
    // Подпись «уклон 30° / 58%» — над серединой стрелки, перпендикулярно
    // направлению.
    final labelX = cx + px * 9;
    final labelY = cy + py * 9;
    _drawCenteredText(
      canvas,
      '${slopeDegrees.toStringAsFixed(0)}° / '
      '${slopePercent.toStringAsFixed(0)}%',
      labelX,
      labelY,
      fontSize: 7.5,
      font: font,
    );
  }

  /// Снегозадержатели — пунктир из маленьких треугольников.
  static void _drawSnowGuards(
    PdfGraphics canvas,
    PdfPoint Function(double, double) pp,
    RoofSegment seg,
  ) {
    final a = pp(seg.a.x, seg.a.y);
    final b = pp(seg.b.x, seg.b.y);
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 4) return;
    final ux = dx / length;
    final uy = dy / length;
    // Линия снегозадержателей.
    canvas.setStrokeColor(_roofSnowGuardColor);
    canvas.setLineWidth(0.7);
    canvas.drawLine(a.x, a.y, b.x, b.y);
    canvas.strokePath();
    // Маленькие треугольники-«зубцы» каждые 12 пт.
    const step = 12.0;
    const tooth = 3.0;
    final px = -uy;
    final py = ux;
    canvas.setFillColor(_roofSnowGuardColor);
    var t = step / 2;
    while (t < length) {
      final cx = a.x + ux * t;
      final cy = a.y + uy * t;
      canvas.moveTo(cx, cy);
      canvas.lineTo(cx + ux * tooth + px * tooth, cy + uy * tooth + py * tooth);
      canvas.lineTo(cx - ux * tooth + px * tooth, cy - uy * tooth + py * tooth);
      canvas.lineTo(cx, cy);
      canvas.fillPath();
      t += step;
    }
  }

  /// Условные обозначения справа от плана.
  static void _drawRoofLegend(
    PdfGraphics canvas,
    PdfFont font, {
    required double x,
    required double y,
    required RoofShape shape,
    required double slopeDeg,
    required double slopePercent,
    required int snowZone,
    required bool hasSnowGuards,
    required int drainCount,
    bool hasValleys = false,
  }) {
    final lines = <String>[
      'Условные обозначения:',
      '— конёк',
      if (shape == RoofShape.hip) '— накос (хребет)',
      if (hasValleys) '— ендова (стык скатов)',
      '— водосливная воронка (В1, В2 …)',
      if (hasSnowGuards) '— снегозадержатель',
      '— дымоход',
      if (shape != RoofShape.flat) '— аэратор',
      '',
      'Параметры:',
      'Тип: ${_roofShapeLabel(shape)}',
      'Уклон: ${slopeDeg.toStringAsFixed(0)}° / '
          '${slopePercent.toStringAsFixed(0)}%',
      'Снеговой район: $snowZone',
      'Воронок: $drainCount',
    ];
    canvas.setFillColor(PdfColors.black);
    var cy = y + lines.length * 11;
    for (final ln in lines) {
      canvas.drawString(font, 7.5, ln, x, cy);
      cy -= 11;
    }
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  // ===================================================================
  //  v16.1 / v16.2 / v16.3 — Разрезы, фасады, аксонометрия
  // ===================================================================

  /// Габариты по высоте для разреза/фасада.
  static _BuildingElevation _elevation(HouseProject project, FloorPlan plan) {
    // v68.11: единый источник истины — `BuildingDimensions`. Все
    // цифры (высота этажа, цоколь, глубина фундамента, высота кровли,
    // подвал) идут из одного объекта; раньше та же логика лежала
    // отдельно здесь и отдельно в `Building3DGenerator`, что давало
    // расхождения slab=0.20 ⟂ slab=0.0 на разрезе vs аксонометрии.
    final dims = BuildingDimensions.of(
      project,
      widthM: plan.width,
      lengthM: plan.height,
    );
    return _BuildingElevation(
      floors: dims.floors,
      hasBasement: dims.hasBasement,
      hasMansard: dims.hasMansard,
      floorHeight: dims.floorHeight,
      foundationDepth: dims.foundationDepth,
      plinthHeight: dims.plinthHeight,
      roofHeight: dims.roofHeight,
      roofShape: dims.roofShape,
      slopeDeg: dims.slopeDeg,
      basementHeight: dims.basementHeight,
    );
  }

  static pw.Page _sectionPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    required String sectionId,
    required bool isTransverse,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      'Разрез $sectionId — '
                      '${isTransverse ? 'поперечный' : 'продольный'}',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
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
                              painter: (canvas, size) => _paintSection(
                                canvas,
                                size,
                                project,
                                plan,
                                pdfFont,
                                sectionId: sectionId,
                                isTransverse: isTransverse,
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
                sectionTitle: 'Архитектурные решения',
                sheetTitle: 'Разрез $sectionId',
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

  static pw.Page _facadePage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    required String facadeCode,
    required String facadeTitle,
    required _FacadeSide side,
    List<FloorPlan>? plans,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      facadeTitle,
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
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
                              painter: (canvas, size) => _paintFacade(
                                canvas,
                                size,
                                project,
                                plan,
                                pdfFont,
                                side: side,
                                plans: plans ?? [plan],
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
                sectionTitle: 'Архитектурные решения',
                sheetTitle: facadeTitle,
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

  static pw.Page _axonometricPage({
    required HouseProject project,
    required FloorPlan plan,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfFont pdfFont,
    List<FloorPlan>? plans,
    OrganizationSettings? organization,
  }) {
    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      'Общий вид (аксонометрия)',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
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
                              painter: (canvas, size) => _paintAxonometric(
                                canvas,
                                size,
                                project,
                                plan,
                                pdfFont,
                                plans: plans ?? [plan],
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
                sectionTitle: 'Архитектурные решения',
                sheetTitle: 'Общий вид',
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

  /// Лист «Спецификация материалов и сортаментов» — собирает в единую
  /// сводку все справочные материалы из `materials_library.dart`.
  /// На листе несколько таблиц:
  ///  1. Бетон (классы по прочности и применение).
  ///  2. Арматурная сталь (классы и сортамент диаметров).
  ///  3. Стеновые материалы (плотность, λ, прочность).
  ///  4. Кровельные материалы (вес, мин. уклон, срок службы).
  ///  5. Утеплители.
  ///  6. Сортамент стальных профилей (двутавр).
  static pw.Page _materialsSpecPage({
    required HouseProject project,
    FoundationPlanModel? foundationPlan,
    List<FloorPlan>? floorPlans,
    required int versionNumber,
    required int sheetNumber,
    required int totalSheets,
    required pw.Font font,
    required pw.Font fontBold,
    OrganizationSettings? organization,
  }) {
    // Все таблицы на странице нормализуются по ширине столбцов и высоте
    // строк (одна высота строки на всю спецификацию, одна ширина колонки
    // на конкретную таблицу). Текст усекается до 1 строки + многоточие,
    // чтобы строки гарантированно были одной высоты.
    const double rowH = 16; // фиксированная высота строки
    const double headerH = 18; // заголовок чуть выше
    const double cellPadH = 3;
    const double cellPadV = 0;

    pw.Widget headerCell(String text, double width) => pw.Container(
          width: width,
          height: headerH,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(
              horizontal: cellPadH, vertical: cellPadV),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            border: pw.Border.all(width: 0.4, color: PdfColors.black),
          ),
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 7, font: fontBold),
          ),
        );

    pw.Widget bodyCell(String text, double width) => pw.Container(
          width: width,
          height: rowH,
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(
              horizontal: cellPadH, vertical: cellPadV),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.3, color: PdfColors.black),
          ),
          child: pw.Text(
            text,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 7, font: font),
          ),
        );

    pw.Widget headerRow(List<String> labels, double totalWidth) {
      final cellWidth = totalWidth / labels.length;
      return pw.Row(
        children: [
          for (final label in labels) headerCell(label, cellWidth),
        ],
      );
    }

    pw.Widget bodyRow(List<String> values, double totalWidth) {
      final cellWidth = totalWidth / values.length;
      return pw.Row(
        children: [
          for (final v in values) bodyCell(v, cellWidth),
        ],
      );
    }

    pw.Widget tableTitle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child: pw.Text(
            text,
            style: pw.TextStyle(fontSize: 10, font: fontBold),
          ),
        );

    // === ФИЛЬТРАЦИЯ ПО ВЫБРАННЫМ В ПРОЕКТЕ МАТЕРИАЛАМ.
    //
    // В спецификации показываем ТОЛЬКО те материалы, которые
    // действительно использованы при строительстве; справочные строки
    // других классов в АР-12 не выводятся.
    final foundationType = project.foundation.type;
    final wallCode = project.walls.material ??
        project.brief.wallMaterial?.name ??
        'brick';
    final roofMatRaw = project.roof.roofingMaterial;

    // Класс бетона: для ленты/столбов/пиле-ростверка — B20, для плиты —
    // B25, для винтовых свай (FoundationType.pile) бетон не нужен.
    final useConcrete = foundationType == FoundationType.strip ||
        foundationType == FoundationType.slab ||
        foundationType == FoundationType.columnar ||
        foundationType == FoundationType.pileWithGrillage;
    final concreteGradesUsed = <ConcreteGrade>[];
    if (useConcrete) {
      // Подбетонка — только для монолитных конструкций.
      concreteGradesUsed.add(
        concreteGrades.firstWhere((g) => g.grade == 'B7,5'),
      );
      if (foundationType == FoundationType.slab) {
        concreteGradesUsed.add(
          concreteGrades.firstWhere((g) => g.grade == 'B25'),
        );
      } else {
        concreteGradesUsed.add(
          concreteGrades.firstWhere((g) => g.grade == 'B20'),
        );
      }
    }

    // Арматура: A500С (рабочая) + A240 (хомуты) — если используется бетон.
    final rebarGradesUsed = <RebarGrade>[];
    if (useConcrete) {
      rebarGradesUsed.add(
        rebarGrades.firstWhere((g) => g.grade.startsWith('A500')),
      );
      rebarGradesUsed.add(
        rebarGrades.firstWhere((g) => g.grade.startsWith('A240')),
      );
    }

    // Двутавр: только для свайного фундамента (винтовых свай) — обвязка.
    final ibeamProfilesUsed = <IBeamProfile>[];
    if (foundationType == FoundationType.pile) {
      // Типовой подбор обвязки винтовых свай ИЖС: №16 или №18.
      ibeamProfilesUsed.add(
        iBeamProfiles.firstWhere((p) => p.name == '16Б1'),
      );
      ibeamProfilesUsed.add(
        iBeamProfiles.firstWhere((p) => p.name == '18Б1'),
      );
    }

    // Стены: подбираем материалы из библиотеки по выбранному коду.
    bool wallMatches(String key) {
      switch (wallCode) {
        case 'brick':
          return key == 'brick_solid' || key == 'brick_hollow';
        case 'aerated':
          return key == 'aerated_d500' ||
              key == 'aerated_d600' ||
              key == 'foam_d600';
        case 'expandedClay':
          return key == 'expanded_clay';
        case 'timber':
          return key == 'timber_solid' || key == 'timber_glulam';
        case 'log':
          return key == 'log';
        case 'frame':
          return key == 'frame_sip';
        default:
          return false;
      }
    }

    final wallMatsUsed =
        wallMaterialsLibrary.where((m) => wallMatches(m.key)).toList();

    // Кровля: подбираем материалы из библиотеки по выбранному коду.
    // Коды соответствуют выбору в roof_page.dart:
    //   metal_tile (металлочерепица), soft (битумная), ceramic, slate,
    //   seam (фальцевая); + flat→membrane для плоских крыш.
    bool roofMatches(String key) {
      switch (roofMatRaw) {
        case 'metal_tile':
        case 'metal':
        case 'profile':
          return key == 'metal_tile' || key == 'profile_sheet';
        case 'ceramic':
        case 'tile':
          return key == 'ceramic_tile' || key == 'cement_tile';
        case 'soft':
          return key == 'soft_tile';
        case 'slate':
          // В библиотеке шифера сейчас нет — используем фальцевую как
          // ближайший аналог по типу применения.
          return key == 'seam_metal';
        case 'seam':
          return key == 'seam_metal';
        case 'membrane':
        case 'rolled':
          return key == 'rolled_bitumen' || key == 'pvc_membrane';
        default:
          // Если материал кровли не указан — берём как fallback самый
          // распространённый для скатных крыш ИЖС.
          return key == 'metal_tile';
      }
    }

    final roofMatsUsed =
        roofMaterialsLibrary.where((m) => roofMatches(m.key)).toList();

    // Утеплители — пока в проекте нет явного выбора, поэтому раздел
    // выводим только если стены каркасные (там утеплитель обязателен).
    final insulationsUsed = <InsulationMaterialSpec>[];
    if (wallCode == 'frame') {
      insulationsUsed.add(
        insulationLibrary.firstWhere((m) => m.key == 'mineral_wool_basalt'),
      );
    }

    // === ОБЪЁМЫ МАТЕРИАЛОВ.
    final volumes = MaterialVolumes.compute(
      project,
      foundationPlan: foundationPlan,
      floorPlans: floorPlans,
    );

    // === ВЁРСТКА ТАБЛИЦ.
    // Все колонки в каждой таблице — равной ширины (заданная totalWidth /
    // число колонок). Высота строки и заголовка задаётся фиксированно.
    const double columnTotalWidth = 320.0;

    // Тип фундамента — для подписи конструкции в таблицах.
    String foundationLabel() {
      switch (foundationType) {
        case FoundationType.strip:
          return 'Ленточный фундамент';
        case FoundationType.slab:
          return 'Плитный фундамент';
        case FoundationType.columnar:
          return 'Столбчатый фундамент';
        case FoundationType.pile:
          return 'Винтовые сваи';
        case FoundationType.pileWithGrillage:
          return 'Свайно-ростверковый фундамент';
        // ignore: unreachable_switch_default
        default:
          return 'Фундамент';
      }
    }

    final foundationConstrLabel = foundationLabel();

    // 1. Бетон. Колонка «Применение» переименована в «Конструкция» —
    // показывает, в какой конструкции работает данный класс бетона
    // (подбетонка / лента / плита / ростверк).
    final concreteRows = <pw.Widget>[
      headerRow(
        ['Класс', 'Марка', 'Rb, МПа', 'V, м³', 'Конструкция'],
        columnTotalWidth,
      ),
      for (final c in concreteGradesUsed)
        bodyRow(
          [
            c.grade,
            c.mGrade,
            c.rb.toStringAsFixed(1),
            // Подбетонка ≈ 0.1 от основного объёма; основной — `volumes`.
            c.grade == 'B7,5'
                ? (volumes.concreteVolumeM3 * 0.10).toStringAsFixed(2)
                : volumes.concreteVolumeM3.toStringAsFixed(2),
            c.grade == 'B7,5'
                ? 'Подбетонка под фундамент'
                : foundationConstrLabel,
          ],
          columnTotalWidth,
        ),
    ];

    // 2. Арматура — только реально применяемые диаметры.
    final usedDia = volumes.rebarDiametersMm;
    final filteredRebar = <RebarGrade>[];
    for (final r in rebarGradesUsed) {
      // Оставляем только пересечение каталожных диаметров с реально
      // используемыми (Ø6/8 — хомуты, Ø10/12/14 — рабочая).
      final keep = r.diameters.where(usedDia.contains).toList();
      if (keep.isEmpty) {
        // На случай, если объёмы не подсчитаны — не выводим строку.
        continue;
      }
      filteredRebar.add(RebarGrade(
        grade: r.grade,
        rs: r.rs,
        legacy: r.legacy,
        useCase: r.useCase,
        diameters: keep,
      ));
    }
    final rebarRows = <pw.Widget>[
      headerRow(
        ['Класс', 'Rs, МПа', 'Ø, мм', 'Масса, кг', 'Конструкция'],
        columnTotalWidth,
      ),
      for (final r in filteredRebar)
        bodyRow(
          [
            r.grade,
            r.rs.toStringAsFixed(0),
            r.diameters.map((d) => 'Ø$d').join(', '),
            // Делим суммарную массу пропорционально классам:
            // A500С — 70% (рабочая), A240 — 30% (хомуты).
            (volumes.rebarMassKg *
                    (r.grade.startsWith('A500') ? 0.70 : 0.30))
                .toStringAsFixed(0),
            r.grade.startsWith('A500')
                ? 'Рабочая арматура $foundationConstrLabel'
                : 'Хомуты, конструктивная арматура',
          ],
          columnTotalWidth,
        ),
    ];

    // 3. Двутавр (для винтовых свай).
    final ibeamRows = <pw.Widget>[
      headerRow(
        ['Профиль', 'h, мм', 'b, мм', 'm, кг/м', 'Конструкция'],
        columnTotalWidth,
      ),
      for (final p in ibeamProfilesUsed)
        bodyRow(
          [
            p.name,
            p.heightMm.toStringAsFixed(0),
            p.widthMm.toStringAsFixed(0),
            p.linearMassKgM.toStringAsFixed(2),
            'Обвязка винтовых свай',
          ],
          columnTotalWidth,
        ),
    ];

    // 4. Стеновые материалы. Колонка «Конструкция» (бывш. «Элемент
    // дома») показывает, где именно работает данный материал:
    // наружные стены / перегородки / фронтон и т. п.
    final wallRows = <pw.Widget>[
      headerRow(
        [
          'Материал',
          'Конструкция',
          'V, м³',
          'Площадь, м²',
          'Расход с отходами',
        ],
        columnTotalWidth,
      ),
      for (final m in wallMatsUsed)
        () {
          final element =
              PdfBuilderMaterials.wallMaterialElement(m.key, project);
          // Для перегородок берём ОТДЕЛЬНЫЙ объём из MaterialVolumes —
          // у наружных стен и перегородок не должно быть одинаковых
          // значений в спецификации.
          final isPartition = element.toLowerCase().contains('перегород');
          final v = isPartition
              ? volumes.partitionVolumeM3
              : volumes.wallVolumeM3;
          final a = isPartition
              ? volumes.partitionAreaM2
              : volumes.wallAreaM2;
          return bodyRow(
            [
              m.title,
              element,
              v.toStringAsFixed(1),
              a.toStringAsFixed(1),
              PdfBuilderMaterials.wallMaterialConsumption(m.key, v, a),
            ],
            columnTotalWidth,
          );
        }(),
    ];

    // Подпись типа кровли — из выбора пользователя (`project.roof.type`).
    String roofConstrLabel() {
      final t = (project.roof.type ?? '').toLowerCase();
      if (t.contains('flat') || t.contains('плоск')) return 'Плоская кровля';
      if (t.contains('hip') || t.contains('вальм')) return 'Вальмовая кровля';
      if (t.contains('shed') || t.contains('односкат')) {
        return 'Односкатная кровля';
      }
      if (t.contains('mansard') || t.contains('ломан')) {
        return 'Ломаная (мансардная) кровля';
      }
      return 'Двускатная кровля';
    }

    final roofConstrText = roofConstrLabel();

    final roofRows = <pw.Widget>[
      headerRow(
        [
          'Покрытие',
          'Конструкция',
          'Угол ≥',
          'Площадь, м²',
          'Расход с отходами',
        ],
        columnTotalWidth,
      ),
      for (final m in roofMatsUsed)
        bodyRow(
          [
            m.title,
            roofConstrText,
            '${m.minSlopeDeg.toStringAsFixed(0)}°',
            volumes.roofAreaM2.toStringAsFixed(1),
            PdfBuilderMaterials.roofMaterialConsumption(m.key, volumes.roofAreaM2),
          ],
          columnTotalWidth,
        ),
    ];

    String insulConstrLabel() {
      final parts = <String>[];
      if (wallCode == 'frame') parts.add('Каркасные стены');
      if (project.roof.isFilled) parts.add('Кровельный пирог');
      // Полы первого этажа всегда утепляются по СП 50.13330.
      parts.add('Пол 1-го этажа');
      return parts.join(' / ');
    }

    final insulConstrText = insulConstrLabel();

    final insulRows = <pw.Widget>[
      headerRow(
        [
          'Утеплитель',
          'Конструкция',
          'λ, Вт/(м·К)',
          'V, м³',
          'Расход с отходами',
        ],
        columnTotalWidth,
      ),
      for (final m in insulationsUsed)
        bodyRow(
          [
            m.title,
            insulConstrText,
            m.thermalConductivity.toStringAsFixed(3),
            volumes.insulationVolumeM3.toStringAsFixed(1),
            PdfBuilderMaterials.insulationConsumption(
              m.key,
              volumes.insulationVolumeM3,
              volumes.insulationAreaM2,
            ),
          ],
          columnTotalWidth,
        ),
    ];

    // Таблица должна показываться только если есть хоть одна data-row,
    // чтобы не выводить «пустые» заголовки.
    final showConcrete = concreteGradesUsed.isNotEmpty;
    final showRebar = filteredRebar.isNotEmpty;
    final showIBeam = ibeamProfilesUsed.isNotEmpty;
    final showWalls = wallMatsUsed.isNotEmpty;
    final showRoof = roofMatsUsed.isNotEmpty;
    final showInsul = insulationsUsed.isNotEmpty;

    return pw.Page(
      pageTheme: _drawingPageTheme(),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(70, 16, 14, 134),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sheetHeader(
                      project.name.isEmpty
                          ? 'Индивидуальный жилой дом'
                          : project.name,
                      'Спецификация материалов и сортаментов',
                      versionNumber,
                      font,
                      fontBold,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Левая колонка — бетон / арматура / двутавр.
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                if (showConcrete) ...[
                                  tableTitle(
                                    '1. Бетон тяжёлый (СП 63.13330.2018, '
                                        'ГОСТ 26633-2015)',
                                  ),
                                  ...concreteRows,
                                ],
                                if (showRebar) ...[
                                  tableTitle(
                                    '2. Арматура (ГОСТ 34028-2016)',
                                  ),
                                  ...rebarRows,
                                ],
                                if (showIBeam) ...[
                                  tableTitle(
                                    '3. Сортамент двутавра (ГОСТ 8239-89)',
                                  ),
                                  ...ibeamRows,
                                ],
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 14),
                          // Правая колонка — стены / кровля / утеплители.
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                if (showWalls) ...[
                                  tableTitle(
                                    '4. Стеновые материалы '
                                        '(СП 50.13330.2012)',
                                  ),
                                  ...wallRows,
                                ],
                                if (showRoof) ...[
                                  tableTitle(
                                    '5. Кровельные материалы',
                                  ),
                                  ...roofRows,
                                ],
                                if (showInsul) ...[
                                  tableTitle(
                                    '6. Теплоизоляционные материалы',
                                  ),
                                  ...insulRows,
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Примечание: справочные значения по ГОСТ/СП. '
                          'При проектировании уточнить по сертификатам '
                          'конкретных производителей.',
                      style: pw.TextStyle(
                        fontSize: 7,
                        font: font,
                        fontStyle: pw.FontStyle.italic,
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
                sheetTitle: 'Спецификация материалов',
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

  static pw.Widget _sheetHeader(
    String projectName,
    String sheetTitle,
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
            pw.Text(projectName,
                style: pw.TextStyle(
                    fontSize: 14, font: fontBold, color: PdfColors.black)),
            pw.Text(sheetTitle,
                style: pw.TextStyle(
                    fontSize: 10,
                    font: font,
                    color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Версия №$versionNumber',
                style: pw.TextStyle(fontSize: 10, font: font)),
            pw.Text(_formatDate(DateTime.now()),
                style: pw.TextStyle(fontSize: 9, font: font)),
          ],
        ),
      ],
    );
  }

  /// Рисует поперечный / продольный разрез здания.
  static void _paintSection(
    PdfGraphics canvas,
    PdfPoint size,
    HouseProject project,
    FloorPlan plan,
    PdfFont font, {
    required String sectionId,
    required bool isTransverse,
  }) {
    final el = _elevation(project, plan);
    // Длина разреза вдоль горизонтали (в модели).
    final buildingLen = isTransverse ? plan.width : plan.height;

    // Положение секущей плоскости в модели (та же логика, что в
    // _paintSectionMarks): для 1-1 (поперечный) — Y-координата на плане,
    // для 2-2 (продольный) — X-координата.
    final cutModel = isTransverse
        ? _findClearAxisPosition(
            attachments: plan.attachments,
            isHorizontal: false,
            buildingExtent: plan.height,
            defaultPos: plan.height / 2,
          )
        : _findClearAxisPosition(
            attachments: plan.attachments,
            isHorizontal: true,
            buildingExtent: plan.width,
            defaultPos: plan.width / 2,
          );
    // Общая высота кадра: фундамент + подвал (если есть) + (этажи) + кровля.
    // Подвал помещается ВНУТРИ глубины фундамента (от -basementHeight до 0),
    // поэтому в totalH он не плюсуется отдельно — но для понятности
    // оставляем переменную.
    final totalH = el.foundationDepth +
        el.floors * el.floorHeight +
        (el.hasMansard ? el.floorHeight * 0.8 : 0) +
        el.roofHeight;
    // Поля.
    const marginLeft = 110.0;
    const marginRight = 70.0;
    const marginTop = 70.0;
    const marginBottom = 90.0;
    final w = size.x;
    final h = size.y;
    final scaleX = (w - marginLeft - marginRight) / buildingLen;
    final scaleY = (h - marginTop - marginBottom) / (totalH + 2); // +2 для земли снизу
    final scale = math.min(scaleX, scaleY);
    final drawW = buildingLen * scale;
    final drawH = totalH * scale;
    final ox =
        marginLeft + ((w - marginLeft - marginRight) - drawW) / 2;
    // oy = низ разреза (самая нижняя точка = дно фундамента).
    final oy = marginBottom +
        ((h - marginTop - marginBottom) - drawH) / 2;

    // Преобразование model-высот в PDF y (Y PDF вверх).
    // Уровень 0.000 (пол первого этажа) = oy + el.foundationDepth*scale.
    final y0 = oy + el.foundationDepth * scale;
    double yAt(double elevMeters) => y0 + elevMeters * scale;

    // --- 1. Земля ниже уровня планировки — высота цоколя из расчёта
    // (см. _BuildingElevation.plinthHeight); штриховка грунта 45°.
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.4);
    final groundY = yAt(-el.plinthHeight);
    // Горизонтальная линия земли — за пределами дома на 40 pt.
    canvas.drawLine(ox - 40, groundY, ox + drawW + 40, groundY);
    canvas.strokePath();
    // Штриховка грунта: косые линии под 45° ниже линии земли.
    canvas.setStrokeColor(PdfColors.grey500);
    canvas.setLineWidth(0.3);
    const groundHatchDepth = 14.0;
    for (var gx = ox - 40; gx < ox + drawW + 40; gx += 6) {
      canvas.drawLine(gx, groundY, gx - groundHatchDepth, groundY - groundHatchDepth);
    }
    canvas.strokePath();

    // --- 2. Фундамент — рисунок зависит от выбранного типа.
    final foundPreview = _foundationPreview(project, plan);
    // ВАЖНО: глубину передаём из `el.foundationDepth` (с учётом
    // подвала), а не из `preview.depthM` — у ленты в preview всегда
    // 0.8 м, и при подвале фундамент рисовался только в полосе
    // -1.4..-0.8, не доходя до -3.4 (Низ фундамента). Правка
    // пользователя по листам 10-11.
    _paintFoundationOnSection(
      canvas,
      preview: foundPreview,
      ox: ox,
      drawW: drawW,
      yAt: yAt,
      scale: scale,
      font: font,
      plinthHeight: el.plinthHeight,
      effectiveDepthM: el.foundationDepth,
    );

    // --- 3a. Подвал (если выбран): рисуем дополнительный этаж ниже
    // отметки 0.000. Стены подвала — монолитный бетон (штриховка),
    // помещение — белая заливка, перекрытие над подвалом = пол 1-го
    // этажа (рисуется ниже общим способом).
    if (el.hasBasement && el.basementHeight > 0) {
      final yBase = yAt(-el.basementHeight); // пол подвала
      final yTopBase = yAt(0); // потолок подвала = пол 1 эт.
      // Помещение подвала — внутри фундаментных стен/лент. Если стрип-
      // фундамент шириной b, то внутренний контур = ox+b … ox+drawW-b.
      // Раньше белая заливка помещения шла по всей ширине плана и
      // полностью закрывала штриховку фундаментных лент → на разрезе
      // фундамент пропадал (правка пользователя по листам 10-11).
      double innerLeftIns = 0;
      double innerRightIns = 0;
      switch (foundPreview.type) {
        case FoundationType.strip:
        case FoundationType.columnar:
          innerLeftIns = innerRightIns =
              math.max(30.0, foundPreview.widthM * scale);
          break;
        case FoundationType.pile:
        case FoundationType.pileWithGrillage:
          innerLeftIns = innerRightIns =
              math.max(8.0, foundPreview.pileDiameterM * scale) / 2 + 4;
          break;
        case FoundationType.slab:
          innerLeftIns = innerRightIns = 0;
          break;
      }
      final innerX = ox + innerLeftIns;
      final innerW = drawW - innerLeftIns - innerRightIns;
      // Заливка помещения подвала — белая.
      canvas.setFillColor(PdfColors.white);
      canvas.drawRect(innerX, yBase, innerW, yTopBase - yBase);
      canvas.fillPath();
      // Контур.
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(1.0);
      canvas.drawRect(innerX, yBase, innerW, yTopBase - yBase);
      canvas.strokePath();
      // Пол подвала — слой бетонной плиты 0.20 м (под основной плитой
      // подбетонка/гидроизоляция уже рисуется в _paintFoundationOnSection).
      canvas.setFillColor(PdfColors.black);
      final basementSlabH = 0.2 * scale;
      canvas.drawRect(innerX, yBase - basementSlabH, innerW, basementSlabH);
      canvas.fillPath();
      // Метка «Подвал» по центру.
      canvas.setFillColor(PdfColors.black);
      _drawCenteredText(
        canvas,
        'Подвал',
        innerX + innerW / 2,
        (yBase + yTopBase) / 2,
        fontSize: 10,
        font: font,
      );
      _drawCenteredText(
        canvas,
        '−${el.basementHeight.toStringAsFixed(2)} м',
        innerX + innerW / 2,
        (yBase + yTopBase) / 2 - 12,
        fontSize: 8,
        font: font,
      );
    }

    // --- 3b. Этажи (надземные).
    canvas.setFillColor(PdfColors.white);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    final totalFloors = el.floors + (el.hasMansard ? 1 : 0);
    for (var i = 0; i < totalFloors; i++) {
      final isMansardFloor = el.hasMansard && i == totalFloors - 1;
      final fhMeters = isMansardFloor ? el.floorHeight * 0.8 : el.floorHeight;
      final bottomElev = i * el.floorHeight;
      final topElev = bottomElev + fhMeters;
      final yBot = yAt(bottomElev);
      final yTop = yAt(topElev);
      // Заливка — белая (внутреннее помещение).
      canvas.drawRect(ox, yBot, drawW, yTop - yBot);
      canvas.fillPath();
      // Перекрытие над этажом — чёрная полоса 0.2 м толщины.
      canvas.setFillColor(PdfColors.black);
      final slabH = 0.2 * scale;
      canvas.drawRect(ox, yTop - slabH, drawW, slabH);
      canvas.fillPath();
      // Контур этажа.
      canvas.setFillColor(PdfColors.white);
      canvas.setStrokeColor(PdfColors.black);
      canvas.drawRect(ox, yBot, drawW, yTop - yBot);
      canvas.strokePath();
    }
    // Перекрытие над фундаментом (пол первого этажа) — 0.2 м толщина.
    canvas.setFillColor(PdfColors.black);
    final slab0h = 0.2 * scale;
    canvas.drawRect(ox, y0 - slab0h, drawW, slab0h);
    canvas.fillPath();

    // --- 4. Стены — толстый контур на левом и правом краях со штриховкой
    // по материалу из проекта. Толщина наружной стены — из walls.thickness
    // (мм → м), цоколь — высота из _BuildingElevation.plinthHeight.
    final wallCode = PdfBuilderMaterials.wallMaterialCode(project);
    canvas.setFillColor(PdfBuilderMaterials.facadeWallFill(wallCode));
    final wallThkM = (project.walls.thickness ?? 350) / 1000.0;
    final wallThk = wallThkM * scale;
    final topElev = totalFloors == 0
        ? el.floorHeight
        : (el.floors * el.floorHeight +
            (el.hasMansard ? el.floorHeight * 0.8 : 0));
    final wallTopY = yAt(topElev);
    // Левая стена.
    canvas.drawRect(ox, y0, wallThk, wallTopY - y0);
    canvas.fillPath();
    // Правая стена.
    canvas.drawRect(ox + drawW - wallThk, y0, wallThk, wallTopY - y0);
    canvas.fillPath();
    // Штриховка стен в сечении — характер штриховки зависит от материала
    // (ГОСТ 2.306-68): кирпич — диагональная решётка, газобетон — мелкая
    // квадратная сетка, брус/каркас — горизонтальные «брёвна» с насечкой.
    for (final wallX in [ox, ox + drawW - wallThk]) {
      PdfBuilderMaterials.drawSectionWallHatch(
        canvas,
        x: wallX,
        y: y0,
        w: wallThk,
        h: wallTopY - y0,
        material: wallCode,
      );
    }
    // Контур стен (поверх штриховки).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    canvas.drawRect(ox, y0, wallThk, wallTopY - y0);
    canvas.drawRect(ox + drawW - wallThk, y0, wallThk, wallTopY - y0);
    canvas.strokePath();
    // Цоколь — высота plinthHeight, тёмно-серая полоса со штриховкой бетона.
    canvas.setFillColor(const PdfColor(0.62, 0.62, 0.62));
    canvas.drawRect(ox, groundY, drawW, y0 - groundY);
    canvas.fillPath();
    canvas.setStrokeColor(const PdfColor(0.30, 0.30, 0.30));
    canvas.setLineWidth(0.25);
    for (var hy = groundY + 2; hy < y0 - 0.5; hy += 2.5) {
      canvas.drawLine(ox + 1, hy, ox + drawW - 1, hy);
    }
    canvas.strokePath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawRect(ox, groundY, drawW, y0 - groundY);
    canvas.strokePath();

    // --- 5. Внутренние стены и проёмы (двери/окна) на секущей плоскости.
    // На разрез выводим всё, что пересекается секущей плоскостью.
    //
    // Геометрия проёма по высоте:
    //   - окно: подоконник 0.9 м, высота 1.5 м;
    //   - дверь межкомнатная: от пола 0.0 до 2.0 м;
    //   - входная дверь: от пола 0.0 до 2.1 м.
    const winH = 1.5;
    const winSillH = 0.9;
    const innerDoorH = 2.0;
    const externalDoorH = 2.1;
    const innerWallThk = 0.15; // 150 мм межкомнатная перегородка

    // Перевод координаты модели (по плану, перпендикулярно секущей)
    // в горизонтальную PDF-координату на разрезе. Для 1-1 buildingLen =
    // plan.width, ось разреза = X плана. Для 2-2 buildingLen = plan.height,
    // ось разреза = Y плана.
    double sx(double modelCoord) => ox + modelCoord * scale;

    // Сборка набора внутренних стен: уникальные x-координаты пересечения
    // секущей с внутренними перегородками. Берём только те room boundaries,
    // которые НЕ совпадают с внешним контуром (0 и buildingLen).
    final innerWallSet = <double>{};
    for (final r in plan.rooms) {
      // Определяем, проходит ли секущая через комнату.
      final crosses = isTransverse
          ? (cutModel > r.y + 1e-3 && cutModel < r.y + r.height - 1e-3)
          : (cutModel > r.x + 1e-3 && cutModel < r.x + r.width - 1e-3);
      if (!crosses) continue;
      // Перпендикулярные секущей стены — это left/right (для 1-1) или
      // top/bottom (для 2-2) границы комнаты.
      final w1 = isTransverse ? r.x : r.y;
      final w2 = isTransverse ? r.x + r.width : r.y + r.height;
      for (final wc in [w1, w2]) {
        // Пропускаем стены, совпадающие с внешним контуром.
        if (wc < 0.05 || wc > buildingLen - 0.05) continue;
        innerWallSet.add(double.parse(wc.toStringAsFixed(3)));
      }
    }

    // Рисуем внутренние стены: тонкая «перегородка» 150 мм. Перегородки
    // на каждом этаже рисуются отдельным прямоугольником и обрываются у
    // плиты перекрытия — перекрытие опирается на стены, а не вмонтировано
    // в них (СП 70.13330.2012 п. 9.4.6).
    final innerWThkPx = innerWallThk * scale;
    final slabH = 0.2 * scale;
    canvas.setFillColor(const PdfColor(0.94, 0.94, 0.94));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.7);
    for (final wc in innerWallSet) {
      final wx = sx(wc) - innerWThkPx / 2;
      for (var i = 0; i < totalFloors; i++) {
        final isMansardFloor = el.hasMansard && i == totalFloors - 1;
        final fhMeters =
            isMansardFloor ? el.floorHeight * 0.8 : el.floorHeight;
        final yBot = yAt(i * el.floorHeight);
        final yTop = yAt(i * el.floorHeight + fhMeters);
        // Стена занимает высоту этажа минус толщина плиты сверху —
        // плита опирается на стену.
        final wallTopOnFloor = yTop - slabH;
        canvas.drawRect(wx, yBot, innerWThkPx, wallTopOnFloor - yBot);
        canvas.fillAndStrokePath();
        // Лёгкая штриховка перегородки.
        canvas.setStrokeColor(PdfColors.grey600);
        canvas.setLineWidth(0.2);
        const innerHatchStep = 5.0;
        for (var hy = yBot; hy < wallTopOnFloor; hy += innerHatchStep) {
          final dx = math.min(innerWThkPx, wallTopOnFloor - hy);
          canvas.drawLine(wx, hy, wx + dx, hy + dx);
        }
        canvas.strokePath();
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.7);
      }
    }

    // Собираем проёмы, пересечённые секущей. Группируем по этажу
    // на основе того, что openings из FloorPlan этажа уже привязаны к
    // конкретному уровню. Здесь у нас один план, поэтому проёмы
    // повторяются по всем этажам — стандартное допущение для жилья.
    final cutOpenings = <_SectionOpening>[];
    for (final o in plan.openings) {
      final crossesHere = isTransverse
          ? (o.side == WallSide.left || o.side == WallSide.right) &&
              cutModel > o.y + 1e-3 &&
              cutModel < o.y + o.length - 1e-3
          : (o.side == WallSide.top || o.side == WallSide.bottom) &&
              cutModel > o.x + 1e-3 &&
              cutModel < o.x + o.length - 1e-3;
      if (!crossesHere) continue;
      // Координата проёма на оси разреза.
      // Для 1-1 (вертикальные стены): wall_x = o.x. Для 2-2 (горизонтальные):
      // wall_y = o.y.
      final secX = isTransverse ? o.x : o.y;
      // Ширина проёма в проекции на разрез — берём типовую (1.5 м для
      // окна, 0.9 м для двери), т. к. реальная длина o.length — это длина
      // по фронту, не по разрезу. Окно/дверь видны как «дыра в стене»
      // фиксированной ширины ≈ толщине проёма.
      final widthPx = (o.kind == OpeningKind.window ? 1.2 : 0.9) * scale;
      cutOpenings.add(_SectionOpening(
        kind: o.kind,
        secX: secX,
        widthPx: widthPx,
      ));
    }

    // Рисуем проёмы — окна на каждом этаже, двери только на первом этаже
    // (входная) или каждом (межкомнатные). Проём всегда «вырезается»
    // внутри толщины пересечённой стены (наружной 0.35 м или внутренней
    // 0.15 м), а не висит наружу.
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    for (final co in cutOpenings) {
      final isExternalDoor = co.kind == OpeningKind.externalDoor;
      final isWindow = co.kind == OpeningKind.window;
      final isLeftEdge = co.secX < 0.05;
      final isRightEdge = co.secX > buildingLen - 0.05;
      final isOuterWall = isLeftEdge || isRightEdge;

      // X-диапазон, в котором «вырезается» проём, в координатах PDF.
      // Для левой/правой наружной стены — внутри её толщины (от ox до
      // ox+wallThk или ox+drawW-wallThk до ox+drawW). Для внутренних —
      // в пределах перегородки 0.15 м, по центру.
      final double wx, ww;
      if (isLeftEdge) {
        wx = ox;
        ww = wallThk;
      } else if (isRightEdge) {
        wx = ox + drawW - wallThk;
        ww = wallThk;
      } else {
        ww = innerWThkPx;
        wx = sx(co.secX) - ww / 2;
      }

      // Этажи, на которых рисуем проём.
      for (var i = 0; i < totalFloors; i++) {
        if (isExternalDoor && i != 0) continue;
        final floorBase = i * el.floorHeight;
        final isMansardFloor = el.hasMansard && i == totalFloors - 1;
        final fhMeters =
            isMansardFloor ? el.floorHeight * 0.8 : el.floorHeight;
        // Y-диапазон проёма.
        final double sillElev, topElev2;
        if (isWindow) {
          sillElev = floorBase + winSillH;
          topElev2 = sillElev + winH;
          if (topElev2 > floorBase + fhMeters - 0.1) continue;
        } else {
          sillElev = floorBase;
          topElev2 = floorBase +
              (isExternalDoor ? externalDoorH : innerDoorH);
        }
        final yw1 = yAt(sillElev);
        final yw2 = yAt(topElev2);

        // «Вырезаем» стену — белый прямоугольник в пределах толщины стены.
        canvas.setFillColor(PdfColors.white);
        canvas.drawRect(wx, yw1, ww, yw2 - yw1);
        canvas.fillPath();

        if (isWindow) {
          // Контур окна (рамка по периметру выреза) + средник по центру.
          canvas.setStrokeColor(PdfColors.black);
          canvas.drawRect(wx, yw1, ww, yw2 - yw1);
          canvas.strokePath();
          canvas.drawLine(wx + ww / 2, yw1, wx + ww / 2, yw2);
          canvas.strokePath();
          // Подоконник — горизонтальная полка с выступом наружу 4 пт
          // (только для наружной стены, поэтому выступ — со стороны улицы).
          if (isOuterWall) {
            final sillOut = isLeftEdge ? -4.0 : 4.0;
            canvas.setStrokeColor(PdfColors.grey700);
            canvas.setLineWidth(0.5);
            if (isLeftEdge) {
              canvas.drawLine(wx + sillOut, yw1, wx + ww, yw1);
            } else if (isRightEdge) {
              canvas.drawLine(wx, yw1, wx + ww + sillOut, yw1);
            } else {
              canvas.drawLine(wx, yw1, wx + ww, yw1);
            }
            canvas.strokePath();
            canvas.setLineWidth(0.6);
          }
        } else {
          // Дверь: косяки + перемычка. Полотно условно не показано в
          // разрезе, чтобы не загромождать (как принято в архитектурных
          // разрезах ГОСТ 21.501-2018).
          canvas.setStrokeColor(PdfColors.black);
          canvas.drawLine(wx, yw1, wx, yw2);
          canvas.drawLine(wx + ww, yw1, wx + ww, yw2);
          canvas.drawLine(wx, yw2, wx + ww, yw2);
          canvas.strokePath();
        }
      }
    }

    // --- 6. Кровля. Цвет — из выбранного `roofingMaterial`. После заливки
    // силуэта — поверх рисуем стропильные ноги (по типовой схеме шага
    // 600 мм) и обозначаем мауэрлат над стенами.
    final ridgeY = yAt(topElev + el.roofHeight);
    final eaveY = wallTopY;
    final roofFill = PdfBuilderMaterials.facadeRoofFill(project.roof.roofingMaterial);
    canvas.setFillColor(roofFill);
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    final mat = project.roof.roofingMaterial;
    // Для скатных кровель в разрезе показываем СТРУКТУРУ кровельного пирога
    // (стропилы видны в проёме треугольника), а не сплошную заливку
    // силуэта — чтобы видно было стропильную систему. Кровельный «пирог»
    // (мембрана + контробрешётка + кровля) рисуется тонкой полосой по
    // ребру ската, а не заполнением.
    final rafterSectionHeightM =
        RafterSectionPicker.pickFor(project).heightMm / 1000.0;
    final rafterSecH = rafterSectionHeightM * scale;
    final roofingThkPx = math.max(2.0, 0.06 * scale); // ~60 мм пирог
    void drawRoofingStrip(PdfPoint a, PdfPoint b) {
      // Полоса вдоль ската (a → b), толщина перпендикулярно скату.
      final dxv = b.x - a.x;
      final dyv = b.y - a.y;
      final len = math.sqrt(dxv * dxv + dyv * dyv);
      if (len < 1e-3) return;
      // Перпендикуляр (наружу скату — вверх по нормали).
      final nx = -dyv / len;
      final ny = dxv / len;
      // На двускатной норма наружу = вверх (положительная y нормали).
      final sign = ny > 0 ? 1.0 : -1.0;
      final ox1 = a.x + sign * nx * roofingThkPx;
      final oy1 = a.y + sign * ny * roofingThkPx;
      final ox2 = b.x + sign * nx * roofingThkPx;
      final oy2 = b.y + sign * ny * roofingThkPx;
      canvas.setFillColor(PdfBuilderMaterials.facadeRoofFill(mat));
      canvas.moveTo(a.x, a.y);
      canvas.lineTo(b.x, b.y);
      canvas.lineTo(ox2, oy2);
      canvas.lineTo(ox1, oy1);
      canvas.lineTo(a.x, a.y);
      canvas.fillAndStrokePath();
    }

    void drawRafterTimber(PdfPoint a, PdfPoint b) {
      // Реальный стропильный брус сечением (rafterSecW × rafterSecH мм).
      // Нога идёт от мауэрлата (a) к коньку (b). Толщина по нормали к скату.
      final dxv = b.x - a.x;
      final dyv = b.y - a.y;
      final len = math.sqrt(dxv * dxv + dyv * dyv);
      if (len < 1e-3) return;
      final nx = -dyv / len;
      final ny = dxv / len;
      final sign = ny > 0 ? -1.0 : 1.0; // нога ниже линии ската
      final hHalf = rafterSecH / 2;
      final p1 = PdfPoint(a.x - sign * nx * hHalf, a.y - sign * ny * hHalf);
      final p2 = PdfPoint(b.x - sign * nx * hHalf, b.y - sign * ny * hHalf);
      final p3 = PdfPoint(b.x + sign * nx * hHalf, b.y + sign * ny * hHalf);
      final p4 = PdfPoint(a.x + sign * nx * hHalf, a.y + sign * ny * hHalf);
      canvas.setFillColor(const PdfColor(0.55, 0.40, 0.25));
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      canvas.moveTo(p1.x, p1.y);
      canvas.lineTo(p2.x, p2.y);
      canvas.lineTo(p3.x, p3.y);
      canvas.lineTo(p4.x, p4.y);
      canvas.lineTo(p1.x, p1.y);
      canvas.fillAndStrokePath();
    }
    switch (el.roofShape) {
      case RoofShape.flat:
        // Плоская: тонкая полоса сверху.
        final flatH = el.roofHeight * scale;
        canvas.drawRect(ox, eaveY, drawW, flatH);
        canvas.fillPath();
        // Текстура (п.4): мембрана/рулонка для плоских.
        PdfBuilderMaterials.drawFacadeRoofTexture(
          canvas,
          [
            PdfPoint(ox, eaveY),
            PdfPoint(ox + drawW, eaveY),
            PdfPoint(ox + drawW, eaveY + flatH),
            PdfPoint(ox, eaveY + flatH),
          ],
          mat,
        );
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(1.0);
        canvas.drawRect(ox, eaveY, drawW, flatH);
        canvas.strokePath();
        break;
      case RoofShape.shed:
        // Односкатная: видим стропилы и тонкий пирог сверху.
        // Стропильные ноги (балки) — каждая ~ через 0.6 м вдоль ската,
        // в одной плоскости разреза, изображаем все «лежащие на боку».
        final aLeft = PdfPoint(ox, eaveY);
        final aRight = PdfPoint(ox + drawW, ridgeY);
        // 1. Балка (главная стропильная нога — толстая, видимая в разрезе).
        drawRafterTimber(aLeft, aRight);
        // 2. Кровельный пирог поверх.
        drawRoofingStrip(aLeft, aRight);
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.7);
        canvas.drawLine(aLeft.x, aLeft.y, aRight.x, aRight.y);
        canvas.strokePath();
        break;
      case RoofShape.gable:
      case RoofShape.hip:
        // Двускатная/вальмовая: ферма треугольником, стропилы видны.
        final aLeft = PdfPoint(ox, eaveY);
        final aTop = PdfPoint(ox + drawW / 2, ridgeY);
        final aRight = PdfPoint(ox + drawW, eaveY);
        // 1. Стропильные ноги — два бруска.
        drawRafterTimber(aLeft, aTop);
        drawRafterTimber(aTop, aRight);
        // 2. Затяжка (нижний пояс фермы) — тонкий брус по горизонту.
        canvas.setFillColor(const PdfColor(0.55, 0.40, 0.25));
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.5);
        final tieY = eaveY - rafterSecH * 0.6;
        canvas.drawRect(ox, tieY, drawW, rafterSecH * 0.6);
        canvas.fillAndStrokePath();
        // 3. Кровельный пирог по обоим скатам.
        drawRoofingStrip(aLeft, aTop);
        drawRoofingStrip(aTop, aRight);
        // 4. Контурные линии скатов сверху, чтобы силуэт был чёткий.
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.9);
        canvas.drawLine(aLeft.x, aLeft.y, aTop.x, aTop.y);
        canvas.drawLine(aTop.x, aTop.y, aRight.x, aRight.y);
        canvas.strokePath();
        break;
      case RoofShape.mansard:
        // Мансардная: ломаная — нижние крутые скаты + верхние пологие.
        // Стропилы видны как два сегмента с обеих сторон, верхняя
        // часть — ферма с затяжкой.
        final midY = yAt(topElev + el.roofHeight * 0.55);
        // Точки ломаной слева → справа
        final mLeftBot = PdfPoint(ox, eaveY);
        final mLeftMid = PdfPoint(ox + drawW * 0.15, midY);
        final mLeftTop = PdfPoint(ox + drawW * 0.35, ridgeY);
        final mRightTop = PdfPoint(ox + drawW * 0.65, ridgeY);
        final mRightMid = PdfPoint(ox + drawW * 0.85, midY);
        final mRightBot = PdfPoint(ox + drawW, eaveY);
        // 1. Стропилы — каждый сегмент как настоящий брус.
        drawRafterTimber(mLeftBot, mLeftMid);
        drawRafterTimber(mLeftMid, mLeftTop);
        drawRafterTimber(mLeftTop, mRightTop);
        drawRafterTimber(mRightTop, mRightMid);
        drawRafterTimber(mRightMid, mRightBot);
        // 2. Затяжка нижнего пояса фермы.
        canvas.setFillColor(const PdfColor(0.55, 0.40, 0.25));
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.5);
        final tieYM = midY - rafterSecH * 0.6;
        canvas.drawRect(ox + drawW * 0.15, tieYM,
            drawW * 0.70, rafterSecH * 0.6);
        canvas.fillAndStrokePath();
        // 3. Кровельный пирог по всем сегментам.
        drawRoofingStrip(mLeftBot, mLeftMid);
        drawRoofingStrip(mLeftMid, mLeftTop);
        drawRoofingStrip(mLeftTop, mRightTop);
        drawRoofingStrip(mRightTop, mRightMid);
        drawRoofingStrip(mRightMid, mRightBot);
        // 4. Контур силуэта сверху для чёткости.
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.9);
        canvas.moveTo(mLeftBot.x, mLeftBot.y);
        canvas.lineTo(mLeftMid.x, mLeftMid.y);
        canvas.lineTo(mLeftTop.x, mLeftTop.y);
        canvas.lineTo(mRightTop.x, mRightTop.y);
        canvas.lineTo(mRightMid.x, mRightMid.y);
        canvas.lineTo(mRightBot.x, mRightBot.y);
        canvas.strokePath();
        break;
    }
    // Мауэрлат: маленький квадратик 0.10 × 0.10 м на верхнем обрезе стен.
    final maurelatSize = math.max(4.0, 0.10 * scale);
    canvas.setFillColor(const PdfColor(0.50, 0.30, 0.18));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawRect(
      ox + wallThk / 2 - maurelatSize / 2,
      eaveY - maurelatSize,
      maurelatSize,
      maurelatSize,
    );
    canvas.drawRect(
      ox + drawW - wallThk / 2 - maurelatSize / 2,
      eaveY - maurelatSize,
      maurelatSize,
      maurelatSize,
    );
    canvas.fillAndStrokePath();

    // --- 7. Отметки высот слева. Уровень земли и низ фундамента —
    // из расчёта (plinthHeight, foundationDepth, basementHeight).
    final marks = <_HeightMark>[
      _HeightMark(-el.foundationDepth, 'Низ фундамента'),
      if (el.hasBasement && el.basementHeight > 0)
        _HeightMark(-el.basementHeight, 'Пол подвала'),
      _HeightMark(-el.plinthHeight, 'Уровень земли'),
      const _HeightMark(0.0, 'Пол 1 эт. (верх цоколя)'),
      for (var i = 1; i <= el.floors; i++)
        _HeightMark(
          i * el.floorHeight,
          i == el.floors && !el.hasMansard
              ? 'Низ кровли'
              : 'Перекрытие над $i-м эт.',
        ),
      if (el.hasMansard)
        _HeightMark(
          el.floors * el.floorHeight + el.floorHeight * 0.8,
          'Перекрытие над мансардой',
        ),
      _HeightMark(topElev + el.roofHeight, 'Конёк'),
    ];
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Sort marks by Y to avoid label overlaps.
    final sortedMarks = List<_HeightMark>.from(marks)
      ..sort((a, b) => a.elev.compareTo(b.elev));
    double? lastLabelY;
    for (final m in sortedMarks) {
      final my = yAt(m.elev);
      final markX = ox - 40;
      canvas.drawLine(ox, my, markX, my);
      canvas.strokePath();
      canvas.moveTo(markX + 6, my + 3);
      canvas.lineTo(markX + 12, my);
      canvas.lineTo(markX + 6, my - 3);
      canvas.lineTo(markX + 6, my + 3);
      canvas.fillPath();
      final valueStr = _formatLevelMeters(m.elev);
      // If previous label too close — shift this label up to avoid overlap.
      double labelY = my;
      if (lastLabelY != null && (labelY - lastLabelY).abs() < 17) {
        labelY = lastLabelY + 17;
      }
      canvas.setFillColor(PdfColors.black);
      canvas.drawString(font, 7.5, valueStr, markX - 42, labelY + 1);
      canvas.drawString(font, 6.5, m.label, markX - 42, labelY - 7);
      lastLabelY = labelY;
    }

    // --- 8. Размерная цепь снизу (общий габарит).
    final dimY = yAt(-el.foundationDepth) - 20;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawLine(ox, dimY, ox + drawW, dimY);
    canvas.strokePath();
    const tickD = 3.0;
    canvas.drawLine(ox - tickD, dimY - tickD, ox + tickD, dimY + tickD);
    canvas.drawLine(ox + drawW - tickD, dimY - tickD,
        ox + drawW + tickD, dimY + tickD);
    canvas.strokePath();
    _drawCenteredText(
      canvas,
      '${(buildingLen * 1000).round()}',
      ox + drawW / 2,
      dimY + 5,
      fontSize: 8,
      font: font,
    );

    // --- 9. Маркер разреза сверху («Разрез 1-1»).
    _drawCenteredText(
      canvas,
      'Разрез $sectionId',
      ox + drawW / 2,
      yAt(topElev + el.roofHeight) + 22,
      fontSize: 11,
      font: font,
    );

    // --- 10. Подпись/выноска фундамента — тип + габариты подобранного
    // сечения. По требованию пользователя (Лист 10/11) — размещаем
    // в ЛЕВОМ нижнем углу листа, ниже размерной цепи и легенды.
    _drawFoundationCallout(
      canvas,
      preview: foundPreview,
      x: 6,
      y: 70,
      font: font,
    );

    // --- 11. Вертикальная цепь высот справа: реальные мм между уровнями
    // (низ фундамента → ур. земли → пол → перекрытия → конёк).
    final dimXChain = ox + drawW + 26;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    final yChainBottom = yAt(-el.foundationDepth);
    final yChainTop = yAt(topElev + el.roofHeight);
    canvas.drawLine(dimXChain, yChainBottom, dimXChain, yChainTop);
    canvas.strokePath();
    final chainLevels = <double>[
      -el.foundationDepth,
      -el.plinthHeight,
      0.0,
      for (var i = 1; i <= el.floors; i++) i * el.floorHeight,
      if (el.hasMansard) topElev,
      topElev + el.roofHeight,
    ];
    for (final lvl in chainLevels) {
      final ye = yAt(lvl);
      canvas.drawLine(dimXChain - 3, ye, dimXChain + 3, ye);
    }
    canvas.strokePath();
    for (var i = 0; i < chainLevels.length - 1; i++) {
      final mm = ((chainLevels[i + 1] - chainLevels[i]) * 1000).round();
      final ya = yAt(chainLevels[i]);
      final yb = yAt(chainLevels[i + 1]);
      _drawCenteredText(canvas, '$mm', dimXChain + 14, (ya + yb) / 2 - 2,
          fontSize: 7, font: font);
    }
    // По требованию пользователя — надпись «Высоты, мм» сдвинута
    // правее размерных значений цепи, чтобы не накладываться на них.
    canvas.drawString(font, 6.5, 'Высоты, мм',
        dimXChain + 22, yChainTop + 4);

    // --- 12. Легенда материалов (стены / кровля / фундамент) — справа
    // вдоль вертикальной цепи высот (ниже её низа), чтобы не
    // перекрывать сам разрез и оставлять левый-нижний угол под
    // блок данных фундамента.
    final legendX = dimXChain - 6;
    final legendY = yAt(-el.foundationDepth) - 30;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    // Ряд «Стены»: цветной swatch + чёрная подпись.
    canvas.setFillColor(PdfBuilderMaterials.facadeWallFill(wallCode));
    canvas.drawRect(legendX, legendY, 9, 7);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7,
        'Стены: ${PdfBuilderMaterials.facadeWallLabel(wallCode)}, ${(wallThkM * 1000).round()} мм',
        legendX + 12, legendY);
    canvas.setFillColor(roofFill);
    canvas.drawRect(legendX, legendY - 11, 9, 7);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7,
        'Кровля: ${PdfBuilderMaterials.facadeRoofLabel(project.roof.roofingMaterial)}',
        legendX + 12, legendY - 11);
    canvas.setFillColor(const PdfColor(0.86, 0.86, 0.86));
    canvas.drawRect(legendX, legendY - 22, 9, 7);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7,
        'Фундамент: ${foundPreview.typeLabel}, d = ${(el.foundationDepth * 1000).round()} мм',
        legendX + 12, legendY - 22);

    // --- 13. Указатель уклона кровли с выносной полкой (только для скатных).
    // Цепь высот стоит СПРАВА от чертежа, поэтому выноску уклона
    // переносим на ЛЕВУЮ (противоположную) сторону, чтобы она не
    // боролась с цепью за свободное место. Сама выноска — короткая.
    if (el.roofShape != RoofShape.flat) {
      final slopePct = (math.tan(el.slopeDeg * math.pi / 180) * 100).round();
      final slopeStr = '∠${el.slopeDeg.toStringAsFixed(0)}° / $slopePct%';
      // Анкер на ЛЕВОМ скате двускатной кровли (60 % от карниза до конька).
      final fSlope = 0.60;
      final slopeAnchorX = ox + drawW * 0.5 * (1 - fSlope);
      final slopeAnchorY = yAt(topElev + el.roofHeight * fSlope);
      final shelfX = ox - 6;
      final shelfY = slopeAnchorY + 12;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      canvas.drawLine(slopeAnchorX, slopeAnchorY, shelfX, shelfY);
      canvas.drawLine(shelfX, shelfY, shelfX - 56, shelfY);
      canvas.strokePath();
      // Текст подписи уклона должен быть чёрным как и остальной текст
      // (правка пользователя по листам 10-11): в разрезе ранее цвет
      // заливки оставался от предыдущей штриховки (стены/кровли) и
      // подпись становилась полупрозрачной.
      canvas.setFillColor(PdfColors.black);
      final lblW = font.stringMetrics('Уклон: $slopeStr').width * 8;
      canvas.drawString(font, 8, 'Уклон: $slopeStr',
          shelfX - lblW - 1, shelfY + 2);
    }
  }

  /// Параметры подобранного фундамента, нужные именно для рисования
  /// разреза/фасада: глубина, ширина элемента, шаги/диаметры свай и т. п.
  /// Это упрощённая heuristic-оценка, которая повторяет логику страницы
  /// «Подбор сечения», но не требует полного пересчёта нагрузок —
  /// достаточно для согласованного отображения на чертеже.
  static _FoundationPreview _foundationPreview(
      HouseProject project, FloorPlan plan) {
    final type = project.foundation.type ?? FoundationType.strip;
    final area = plan.width * plan.height;
    final maxSpan = math.max(plan.width, plan.height);
    switch (type) {
      case FoundationType.strip:
        // Лента: типичные размеры для ИЖС 1–2 эт.: b=400, h=600, d=800.
        // Согласовано со StripFootingDesigner и здравым смыслом.
        return _FoundationPreview(
          type: type,
          typeLabel: 'Ленточный (монолитный)',
          dimsLabel: 'b = 400 мм · h = 600 мм · d = 800 мм',
          details: const [
            'Бетон B20 (СП 63.13330.2018)',
            'Армирование: 4⌀12 А500С + хомуты ⌀6, шаг 250 мм',
            'Подушка: песок средней крупности 100 + щебень 100 мм',
          ],
          depthM: 0.8,
          widthM: 0.4,
        );
      case FoundationType.slab:
        // Плита: толщина = max(0.20, span/30).
        final t = math.max(0.20, _round05(maxSpan / 30));
        return _FoundationPreview(
          type: type,
          typeLabel: 'Плитный (монолитный)',
          dimsLabel:
              'h = ${(t * 1000).toStringAsFixed(0)} мм · A = ${area.toStringAsFixed(1)} м²',
          details: [
            'Бетон B25 W6 F150',
            'Армирование: 2 сетки ⌀12 А500С, шаг 200 мм',
            'Подушка: песок 100 + щебень 100 мм с трамбовкой',
          ],
          depthM: t,
          widthM: plan.width,
          slabThicknessM: t,
        );
      case FoundationType.pile:
        // Свайный (винтовые сваи 108×3, лопасть ⌀300, длина 2.5 м).
        return _FoundationPreview(
          type: type,
          typeLabel: 'Свайный (винтовые сваи)',
          dimsLabel: 'Свая СВ-108·3 · L = 2,5 м · Fd ≈ 30 кН',
          details: const [
            'Свая 108×3 мм, лопасть ⌀300 мм',
            'Шаг свай по периметру ~ 1,5–2,0 м',
            'Обвязка: двутавр №16 / швеллер №20, сварка',
          ],
          depthM: 2.5,
          widthM: 0.108,
          pileSpacingM: 1.8,
          pileDiameterM: 0.108,
        );
      case FoundationType.pileWithGrillage:
        return _FoundationPreview(
          type: type,
          typeLabel: 'Сваи с ростверком',
          dimsLabel:
              'Сваи буронабивные ⌀300, L = 3,0 м · Ростверк 400×400 мм',
          details: const [
            'Сваи: буронабивные ⌀300 мм, бетон B20',
            'Ростверк: 400×400 мм, B20, армирование 4⌀12 А500С',
            'Шаг свай по периметру ~ 2,0 м',
          ],
          depthM: 3.0,
          widthM: 0.4,
          pileSpacingM: 2.0,
          pileDiameterM: 0.30,
        );
      case FoundationType.columnar:
        return _FoundationPreview(
          type: type,
          typeLabel: 'Столбчатый (монолитный)',
          dimsLabel: 'Столб 400×400 мм · L = 1,5 м · шаг ~ 2,5 м',
          details: const [
            'Бетон B20',
            'Армирование: 4⌀12 А500С, хомуты ⌀6 шаг 250 мм',
            'Обвязка: ж/б ростверк 300×400 мм',
          ],
          depthM: 1.5,
          widthM: 0.4,
          pileSpacingM: 2.5,
        );
    }
  }

  static double _round05(double v) => (v * 20).roundToDouble() / 20;

  /// Рисует фундамент в разрезе. Для ленты/плиты/столбов/свай — разная
  /// геометрия. Все элементы заштрихованы как бетон (косые тонкие линии),
  /// контур чёрный.
  static void _paintFoundationOnSection(
    PdfGraphics canvas, {
    required _FoundationPreview preview,
    required double ox,
    required double drawW,
    required double Function(double) yAt,
    required double scale,
    required PdfFont font,
    required double plinthHeight,
    double? effectiveDepthM,
  }) {
    final groundY = yAt(-plinthHeight);
    // При наличии подвала фактическая глубина может быть больше типовой
    // глубины из preview (см. `_buildBuildingElevation`), поэтому
    // используем переданную effectiveDepthM как fallback.
    final depthM = effectiveDepthM ?? preview.depthM;
    final foundBottom = yAt(-depthM);
    // По правке пользователя по листам 10-11 — фундамент должен быть
    // отчётливо виден на разрезе. Ранее заливка 0.86 + штриховка 0.25 pt
    // grey700 терялись на печати. Делаем заливку чуть темнее и
    // штриховку ярче (чёрная 0.4 pt с шагом 4 pt).
    final fillColor = const PdfColor(0.78, 0.78, 0.78);

    void hatchedRect(double x, double y, double w, double h) {
      canvas.setFillColor(fillColor);
      canvas.drawRect(x, y, w, h);
      canvas.fillPath();
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(1.1);
      canvas.drawRect(x, y, w, h);
      canvas.strokePath();
      // косая штриховка бетона
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.4);
      const step = 4.0;
      for (var cx = x - h; cx < x + w + h; cx += step) {
        final ax = cx.clamp(x, x + w);
        final ay = (y + h) - (ax - cx);
        final bx = (cx + h).clamp(x, x + w);
        final by = (y + h) - (bx - cx);
        if (ay < y || by < y) continue;
        canvas.drawLine(ax, ay, bx, by);
      }
      canvas.strokePath();
    }

    switch (preview.type) {
      case FoundationType.strip:
        // Лента под наружными стенами + проступающая средняя стена.
        // Минимальная видимая ширина 30 pt (правка пользователя по
        // листам 10-11: ленты 300-400 мм при масштабе разреза терялись
        // в общей толщине стены и фундамент визуально пропадал).
        final stripW = math.max(30.0, preview.widthM * scale);
        // Левая лента
        hatchedRect(ox, foundBottom, stripW, groundY - foundBottom);
        // Правая лента
        hatchedRect(ox + drawW - stripW, foundBottom, stripW,
            groundY - foundBottom);
        // Средняя несущая стена (под центром)
        hatchedRect(ox + drawW / 2 - stripW / 2, foundBottom, stripW,
            groundY - foundBottom);
        break;
      case FoundationType.slab:
        // Плита под всем зданием — сплошной прямоугольник.
        hatchedRect(ox, foundBottom, drawW, groundY - foundBottom);
        break;
      case FoundationType.columnar:
        // Столбы по краям + центр + ростверк сверху.
        final colW = math.max(18.0, preview.widthM * scale);
        // 3 столба в сечении
        hatchedRect(ox, foundBottom, colW, groundY - foundBottom);
        hatchedRect(ox + drawW / 2 - colW / 2, foundBottom, colW,
            groundY - foundBottom);
        hatchedRect(ox + drawW - colW, foundBottom, colW,
            groundY - foundBottom);
        // Ростверк сверху столбов (полоса 0.3 м над землёй).
        final ribbonH = 0.30 * scale;
        hatchedRect(ox - 4, groundY - ribbonH, drawW + 8, ribbonH);
        break;
      case FoundationType.pile:
      case FoundationType.pileWithGrillage:
        // Сваи: вертикальные «жирные» линии под всеми углами и по перим.
        final dPile = math.max(8.0, preview.pileDiameterM * scale);
        // Пять свай в видимом разрезе (углы + промежуточные).
        final positions = <double>[
          ox,
          ox + drawW * 0.25,
          ox + drawW * 0.5,
          ox + drawW * 0.75,
          ox + drawW,
        ];
        for (final px in positions) {
          hatchedRect(
              px - dPile / 2, foundBottom, dPile, groundY - foundBottom);
        }
        // Ростверк (для pileWithGrillage) — горизонтальная балка над землёй.
        if (preview.type == FoundationType.pileWithGrillage) {
          final ribbonH = 0.40 * scale;
          hatchedRect(ox - 4, groundY - ribbonH, drawW + 8, ribbonH);
        }
        break;
    }
  }

  /// Подпись (выноска) фундамента слева на разрезе: тип + габариты
  /// + детали армирования. Показывает, ЧТО именно подобрано — чтобы
  /// при смене типа на странице расчёта чертёж тоже менялся.
  static void _drawFoundationCallout(
    PdfGraphics canvas, {
    required _FoundationPreview preview,
    required double x,
    required double y,
    required PdfFont font,
  }) {
    final lines = <String>[
      'Фундамент: ${preview.typeLabel}',
      preview.dimsLabel,
      ...preview.details,
    ];
    const fontSize = 7.5;
    const padding = 4.0;
    const lineHeight = 9.5;
    final maxWidth = lines
        .map((s) => _measureText(s, font, fontSize))
        .reduce((a, b) => a > b ? a : b);
    final boxW = maxWidth + padding * 2;
    final boxH = lines.length * lineHeight + padding * 2;
    final boxX = x;
    final boxY = y - boxH;
    canvas.setFillColor(PdfColors.white);
    canvas.drawRect(boxX, boxY, boxW, boxH);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(boxX, boxY, boxW, boxH);
    canvas.strokePath();
    for (var i = 0; i < lines.length; i++) {
      canvas.setFillColor(PdfColors.black);
      canvas.drawString(
        font,
        fontSize,
        lines[i],
        boxX + padding,
        boxY + boxH - padding - (i + 1) * lineHeight + 2,
      );
    }
  }

  static double _measureText(String s, PdfFont font, double size) {
    try {
      final m = font.stringMetrics(s);
      return m.width * size;
    } catch (_) {
      return s.length * size * 0.55;
    }
  }

  /// Рисует фасад (внешний вид) с одной стороны.
  static void _paintFacade(
    PdfGraphics canvas,
    PdfPoint size,
    HouseProject project,
    FloorPlan plan,
    PdfFont font, {
    required _FacadeSide side,
    required List<FloorPlan> plans,
  }) {
    final el = _elevation(project, plan);
    // Ширина фасада = сторона пятна, ПЕРПЕНДИКУЛЯРНАЯ оси взгляда.
    // Южный/северный фасады смотрят вдоль Y, видят длину X.
    final double buildingLen =
        (side == _FacadeSide.south || side == _FacadeSide.north)
            ? plan.width
            : plan.height;
    final plinthH = el.plinthHeight; // м, цоколь над землёй (по типу фундамента)
    final totalH = el.floors * el.floorHeight +
        (el.hasMansard ? el.floorHeight * 0.8 : 0) +
        el.roofHeight +
        plinthH;
    const marginLeft = 110.0;
    const marginRight = 110.0;
    const marginTop = 70.0;
    // Низ удлинён до 168 pt, чтобы оси (-78 от земли) и легенда
    // (-110 от земли) поместились ниже чертежа без наложений.
    const marginBottom = 168.0;
    final w = size.x;
    final h = size.y;
    final scaleX = (w - marginLeft - marginRight) / buildingLen;
    final scaleY = (h - marginTop - marginBottom) / (totalH + 1.5);
    final scale = math.min(scaleX, scaleY);
    final drawW = buildingLen * scale;
    final drawH = totalH * scale;
    final ox = marginLeft + ((w - marginLeft - marginRight) - drawW) / 2;
    final oy = marginBottom +
        ((h - marginTop - marginBottom) - drawH) / 2;
    // Ур. земли = низ цоколя.
    final groundY = oy + plinthH * scale;
    double yAt(double e) => groundY + (e + plinthH) * scale;

    // --- 1. Земля.
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.5);
    canvas.drawLine(ox - 30, groundY, ox + drawW + 30, groundY);
    canvas.strokePath();
    canvas.setStrokeColor(PdfColors.grey500);
    canvas.setLineWidth(0.3);
    for (var gx = ox - 30; gx < ox + drawW + 30; gx += 6) {
      canvas.drawLine(gx, groundY, gx - 10, groundY - 10);
    }
    canvas.strokePath();

    // --- 2. Цоколь 0.15 м.
    final plinthTop = yAt(0.0);
    canvas.setFillColor(const PdfColor(0.70, 0.70, 0.70));
    canvas.drawRect(ox, groundY, drawW, plinthTop - groundY);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.8);
    canvas.drawRect(ox, groundY, drawW, plinthTop - groundY);
    canvas.strokePath();

    // --- 3. Стены — материал в зависимости от brief.
    final wallCode = PdfBuilderMaterials.wallMaterialCode(project);
    final wallFill = PdfBuilderMaterials.facadeWallFill(wallCode);
    final totalFloors = el.floors + (el.hasMansard ? 1 : 0);
    final topElev = el.floors * el.floorHeight +
        (el.hasMansard ? el.floorHeight * 0.8 : 0);
    final wallTopY = yAt(topElev);
    canvas.setFillColor(wallFill);
    canvas.drawRect(ox, plinthTop, drawW, wallTopY - plinthTop);
    canvas.fillPath();
    // 3a. Текстура — кладочные швы, блоки, бруски — из централизованной
    // библиотеки материалов, чтобы фасад наглядно отображал выбор пользователя.
    PdfBuilderMaterials.paintWallTextureOverlay(
      canvas,
      ox,
      plinthTop,
      drawW,
      wallTopY - plinthTop,
      WallMaterial.fromName(project.brief.wallMaterial?.name),
      scale,
    );
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.4);
    canvas.drawRect(ox, plinthTop, drawW, wallTopY - plinthTop);
    canvas.strokePath();

    // --- 3b. Линии межэтажных перекрытий — тонкие пунктирные линии
    // на отметках перекрытий +floorHeight, +2·floorHeight и т.д.
    canvas.setStrokeColor(const PdfColor(0.30, 0.30, 0.30));
    canvas.setLineWidth(0.4);
    for (var k = 1; k < totalFloors; k++) {
      final ye = yAt(k * el.floorHeight);
      // Пунктир: чередующиеся короткие штрихи.
      const dash = 4.0;
      const gap = 3.0;
      double xCur = ox + 1;
      while (xCur < ox + drawW - 1) {
        final xNext = math.min(xCur + dash, ox + drawW - 1);
        canvas.drawLine(xCur, ye, xNext, ye);
        xCur = xNext + gap;
      }
    }
    canvas.strokePath();

    // --- 4. Проёмы на каждом этаже — из plan.openings реальных планов.
    // На фасад проецируются только внешние проёмы: окна и входные двери
    // со стороны, соответствующей [side].
    // Высоты окон и дверей задаём по СП 55.13330.2017 (типовые значения для
    // жилого дома): окно 1.2×1.5 м с подоконником 0.9 м; входная дверь
    // 0.95×2.1 м от уровня пола.
    const defaultWinH = 1.5;
    const defaultWinSillH = 0.9;
    const defaultDoorH = 2.1;
    int windowMarkCounter = 0;
    int doorMarkCounter = 0;
    for (var floor = 0; floor < totalFloors; floor++) {
      // Для каждого этажа берём соответствующий план; если этаж вне
      // индекса (например, только 1 план, а этажей > 1), повторяем
      // план верхнего уровня.
      final floorPlan = floor < plans.length
          ? plans[floor]
          : plans.isNotEmpty
              ? plans.last
              : plan;
      final isMansardFloor = el.hasMansard && floor == totalFloors - 1;
      final fhMeters =
          isMansardFloor ? el.floorHeight * 0.8 : el.floorHeight;
      final floorBase = floor * el.floorHeight;
      // Фильтруем проёмы стороны и преобразуем в позицию вдоль фасада.
      final facadeOpenings = <_FacadeOpening>[];
      for (final o in floorPlan.openings) {
        final proj = _projectOpeningOnFacade(
          o,
          side: side,
          planW: floorPlan.width,
          planH: floorPlan.height,
        );
        if (proj != null) facadeOpenings.add(proj);
      }
      // Сортируем по x вдоль фасада — для последовательных марок ОК/Д.
      facadeOpenings.sort((a, b) => a.startX.compareTo(b.startX));
      for (final fo in facadeOpenings) {
        final xStart = ox + fo.startX * scale;
        final xEnd = ox + (fo.startX + fo.length) * scale;
        if (fo.isDoor) {
          // Входная дверь: от цоколя до 2.1 м.
          final yTop = yAt(defaultDoorH);
          _drawFacadeDoor(
            canvas,
            xStart: xStart,
            xEnd: xEnd,
            yBot: plinthTop,
            yTop: yTop,
          );
          // Марка Д-N (только на первом этаже — входная дверь обычно одна).
          if (floor == 0) {
            doorMarkCounter++;
            _drawOpeningMarkWithSize(
              canvas, font,
              label: 'Д-$doorMarkCounter',
              sizeLabel: _formatOpeningSize(
                widthM: fo.length,
                heightM: defaultDoorH,
              ),
              cx: (xStart + xEnd) / 2,
              cy: yTop + 16,
            );
          }
        } else {
          // Окно: подоконник 0.9 м от уровня пола этажа.
          final sillE = floorBase + defaultWinSillH;
          final topE = sillE +
              math.min(defaultWinH, fhMeters - defaultWinSillH - 0.3);
          final y1 = yAt(sillE);
          final y2 = yAt(topE);
          _drawFacadeWindow(
            canvas,
            xStart: xStart,
            xEnd: xEnd,
            yBot: y1,
            yTop: y2,
            widthM: fo.length,
          );
          // Марка ОК-N (снаружи слева от окна на 1 этаже, справа на 2+).
          if (floor == 0) {
            windowMarkCounter++;
            _drawOpeningMarkWithSize(
              canvas, font,
              label: 'ОК-$windowMarkCounter',
              sizeLabel: _formatOpeningSize(
                widthM: fo.length,
                heightM: topE - sillE,
              ),
              cx: (xStart + xEnd) / 2,
              cy: y2 + 16,
            );
          }
        }
      }
    }

    // --- 6. Кровля — силуэт со свесом карниза 30 см по ГОСТ 21.501-2018.
    // Цвет — из реального материала кровли (project.roof.roofingMaterial).
    final ridgeY = yAt(topElev + el.roofHeight);
    final overhang = 0.3 * scale;
    final mat2 = project.roof.roofingMaterial;
    canvas.setFillColor(PdfBuilderMaterials.facadeRoofFill(mat2));
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    List<PdfPoint> roofPoly;
    switch (el.roofShape) {
      case RoofShape.flat:
        final flatH = el.roofHeight * scale;
        canvas.drawRect(
            ox - overhang, wallTopY, drawW + overhang * 2, flatH);
        canvas.fillAndStrokePath();
        roofPoly = [
          PdfPoint(ox - overhang, wallTopY),
          PdfPoint(ox + drawW + overhang, wallTopY),
          PdfPoint(ox + drawW + overhang, wallTopY + flatH),
          PdfPoint(ox - overhang, wallTopY + flatH),
        ];
        break;
      case RoofShape.shed:
        canvas.moveTo(ox - overhang, wallTopY);
        canvas.lineTo(ox + drawW + overhang, wallTopY);
        canvas.lineTo(ox + drawW + overhang, ridgeY);
        canvas.lineTo(ox - overhang, wallTopY);
        canvas.fillAndStrokePath();
        roofPoly = [
          PdfPoint(ox - overhang, wallTopY),
          PdfPoint(ox + drawW + overhang, wallTopY),
          PdfPoint(ox + drawW + overhang, ridgeY),
        ];
        break;
      case RoofShape.hip:
        final ridgeHalf = drawW * 0.25;
        canvas.moveTo(ox - overhang, wallTopY);
        canvas.lineTo(ox + drawW / 2 - ridgeHalf / 2, ridgeY);
        canvas.lineTo(ox + drawW / 2 + ridgeHalf / 2, ridgeY);
        canvas.lineTo(ox + drawW + overhang, wallTopY);
        canvas.lineTo(ox - overhang, wallTopY);
        canvas.fillAndStrokePath();
        roofPoly = [
          PdfPoint(ox - overhang, wallTopY),
          PdfPoint(ox + drawW / 2 - ridgeHalf / 2, ridgeY),
          PdfPoint(ox + drawW / 2 + ridgeHalf / 2, ridgeY),
          PdfPoint(ox + drawW + overhang, wallTopY),
        ];
        break;
      case RoofShape.gable:
        canvas.moveTo(ox - overhang, wallTopY);
        canvas.lineTo(ox + drawW / 2, ridgeY);
        canvas.lineTo(ox + drawW + overhang, wallTopY);
        canvas.lineTo(ox - overhang, wallTopY);
        canvas.fillAndStrokePath();
        roofPoly = [
          PdfPoint(ox - overhang, wallTopY),
          PdfPoint(ox + drawW / 2, ridgeY),
          PdfPoint(ox + drawW + overhang, wallTopY),
        ];
        break;
      case RoofShape.mansard:
        final midY = yAt(topElev + el.roofHeight * 0.55);
        canvas.moveTo(ox - overhang, wallTopY);
        canvas.lineTo(ox + drawW * 0.15, midY);
        canvas.lineTo(ox + drawW * 0.35, ridgeY);
        canvas.lineTo(ox + drawW * 0.65, ridgeY);
        canvas.lineTo(ox + drawW * 0.85, midY);
        canvas.lineTo(ox + drawW + overhang, wallTopY);
        canvas.lineTo(ox - overhang, wallTopY);
        canvas.fillAndStrokePath();
        roofPoly = [
          PdfPoint(ox - overhang, wallTopY),
          PdfPoint(ox + drawW * 0.15, midY),
          PdfPoint(ox + drawW * 0.35, ridgeY),
          PdfPoint(ox + drawW * 0.65, ridgeY),
          PdfPoint(ox + drawW * 0.85, midY),
          PdfPoint(ox + drawW + overhang, wallTopY),
        ];
        break;
    }
    // Текстура кровли (п.4 v40) поверх заливки.
    PdfBuilderMaterials.drawFacadeRoofTexture(canvas, roofPoly, mat2);
    // Тень свеса — подчёркивает вылет карниза.
    if (el.roofShape != RoofShape.flat) {
      canvas.setFillColor(const PdfColor(0.10, 0.10, 0.10, 0.35));
      canvas.drawRect(
          ox - overhang, wallTopY - 2.0, drawW + overhang * 2, 2.0);
      canvas.fillPath();
    }

    // --- 6b. Дымоходная труба на фасаде. СНиП 41-01-2003 п. 6.6.13:
    // труба должна возвышаться над коньком кровли не менее 0.5 м (для
    // расстояния до 1.5 м от конька). Размер сечения трубы (внутренний
    // канал) — типовой 0.40×0.40 м для кирпичной (260×260 мм канала
    // при толщине стенок 120 мм).
    //
    // Принципиально важно, чтобы труба выходила ЧЕРЕЗ кровлю — её
    // основание совпадает с линией кровли в той точке, где она проходит,
    // а не «висит» сбоку. Поэтому считаем Y кровли в точке трубы.
    {
      final chimneyW = 0.4 * scale;
      // Высота над кровлей: 0.6 м над линией кровли в точке выхода.
      final chimneyAboveRoof = 0.6 * scale;
      // Размещаем трубу на 0.55 от ширины фасада (чуть смещена от центра,
      // как делается в реальной планировке — над печным стояком).
      final chimneyCx = ox + drawW * 0.55;
      // Расчёт Y кровли в точке chimneyCx (для разных форм крыши).
      double roofYAt(double x) {
        final dx = x - ox;
        switch (el.roofShape) {
          case RoofShape.flat:
            return wallTopY;
          case RoofShape.gable:
            // Двускатная: пик по центру.
            final t = (dx / drawW * 2).clamp(0.0, 2.0);
            final s = t < 1.0 ? t : (2.0 - t);
            return wallTopY - (wallTopY - ridgeY) * s;
          case RoofShape.shed:
            // Односкатная: ridgeY на правом краю.
            return wallTopY - (wallTopY - ridgeY) * (dx / drawW).clamp(0.0, 1.0);
          case RoofShape.hip:
            // Вальмовая: до 0.375 — линейно от карниза до конька; от 0.375
            // до 0.625 — конек; от 0.625 до 1.0 — линейно вниз.
            final r = (dx / drawW).clamp(0.0, 1.0);
            if (r < 0.375) {
              return wallTopY - (wallTopY - ridgeY) * (r / 0.375);
            } else if (r > 0.625) {
              return wallTopY - (wallTopY - ridgeY) * ((1 - r) / 0.375);
            }
            return ridgeY;
          case RoofShape.mansard:
            // Мансардная: ломаный профиль.
            final midY = yAt(topElev + el.roofHeight * 0.55);
            final r = (dx / drawW).clamp(0.0, 1.0);
            if (r < 0.15) {
              return wallTopY - (wallTopY - midY) * (r / 0.15);
            } else if (r < 0.35) {
              return midY - (midY - ridgeY) * ((r - 0.15) / 0.20);
            } else if (r < 0.65) {
              return ridgeY;
            } else if (r < 0.85) {
              return ridgeY - (ridgeY - midY) * ((0.85 - r) / 0.20);
            }
            return midY - (midY - wallTopY) * ((r - 0.85) / 0.15);
        }
      }
      final roofTopAtChim = roofYAt(chimneyCx);
      // Часть трубы внутри (под) кровли — заходит в крышу на 0.2 м,
      // чтобы визуально труба «прорастала» через кровлю.
      final embedDepth = 0.2 * scale;
      final chimneyBaseY = roofTopAtChim + embedDepth;
      final chimneyTopY = roofTopAtChim - chimneyAboveRoof;
      canvas.setFillColor(const PdfColor(0.60, 0.35, 0.25));
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.6);
      // Тело трубы — прямоугольник от chimneyTopY до chimneyBaseY.
      canvas.drawRect(
        chimneyCx - chimneyW / 2,
        chimneyTopY,
        chimneyW,
        chimneyBaseY - chimneyTopY,
      );
      canvas.fillAndStrokePath();
      // Оголовок (капитель) — расширение сверху на 4 pt в стороны и
      // высотой 3 pt. По СНиП 41-01-2003 — защитный зонт.
      canvas.drawRect(
        chimneyCx - chimneyW / 2 - 2,
        chimneyTopY - 3,
        chimneyW + 4,
        3,
      );
      canvas.fillAndStrokePath();
      // Кирпичная штриховка на трубе — горизонтальные линии каждые 4 pt.
      canvas.setStrokeColor(const PdfColor(0.30, 0.20, 0.15));
      canvas.setLineWidth(0.25);
      for (var yh = chimneyTopY; yh < chimneyBaseY; yh += 4) {
        canvas.drawLine(
          chimneyCx - chimneyW / 2 + 1,
          yh,
          chimneyCx + chimneyW / 2 - 1,
          yh,
        );
      }
      canvas.strokePath();
    }

    // --- 6c. Силуэты пристроек (крыльцо / терраса / гараж) из плана —
    // только на фасаде, где они «смотрят» наружу. Рисуем низкий
    // прямоугольник высотой 0.9 м (для террасы / крыльца) или
    // 2.5 м (для гаража) вдоль земли.
    // Сначала собираем горизонтальные диапазоны фасада, занятые
    // гаражами. Гараж стоит на собственном фундаменте и не имеет
    // цоколя дома, поэтому штриховка цоколя должна обрываться в
    // месте пересечения с гаражом и продолжаться только на доме
    // (требование пользователя по Лист 14).
    final garageRanges = _facadeGarageXRanges(
      plan: plan,
      side: side,
      ox: ox,
      drawW: drawW,
      scale: scale,
    );
    // Штриховка цоколя — горизонтальные линии «бетон» по ГОСТ 2.306-68;
    // прерываем линии на участках, занятых гаражом.
    canvas.setStrokeColor(const PdfColor(0.35, 0.35, 0.35));
    canvas.setLineWidth(0.25);
    for (var yh = groundY + 2; yh < plinthTop - 0.5; yh += 2.5) {
      _drawHorizontalLineBreakingAt(
        canvas: canvas,
        x1: ox + 1,
        x2: ox + drawW - 1,
        y: yh,
        breakRanges: garageRanges,
      );
    }
    canvas.strokePath();
    // Гаражи рисуем ПОСЛЕ цокольной штриховки, чтобы их заливка
    // полностью перекрыла любые остаточные линии цоколя в зоне
    // гаража.
    _paintFacadeAttachments(
      canvas: canvas,
      font: font,
      plan: plan,
      side: side,
      ox: ox,
      drawW: drawW,
      groundY: groundY,
      scale: scale,
      buildingLen: buildingLen,
    );

    // --- 7. Отметки высот слева. По правке пользователя по листам
    // 12-15: отметку «Пол подвала» убираем (она дублируется на разрезах
    // АР-9..АР-12). Главные отметки на фасаде — уровень земли, пол 1 эт.,
    // низ окна (подоконник 0.9 м от пола) и низ входной двери = пол 1 эт.
    const winSillFromFloorM = 0.9;
    final marks = <_HeightMark>[
      _HeightMark(-el.plinthHeight, 'Ур. земли'),
      const _HeightMark(0.0, 'Пол 1 эт.'),
      const _HeightMark(winSillFromFloorM, 'Низ окна'),
      for (var i = 1; i <= el.floors; i++)
        _HeightMark(i * el.floorHeight, 'Пер. $i'),
      _HeightMark(topElev + el.roofHeight, 'Конёк'),
    ];
    canvas.setStrokeColor(PdfColors.black);
    canvas.setFillColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    final sortedMarks = List<_HeightMark>.from(marks)
      ..sort((a, b) => a.elev.compareTo(b.elev));
    double? lastLabelY;
    for (final m in sortedMarks) {
      final my = yAt(m.elev);
      final markX = ox - 35;
      canvas.drawLine(ox, my, markX, my);
      canvas.strokePath();
      canvas.moveTo(markX + 6, my + 3);
      canvas.lineTo(markX + 12, my);
      canvas.lineTo(markX + 6, my - 3);
      canvas.fillPath();
      double labelY = my;
      if (lastLabelY != null && (labelY - lastLabelY).abs() < 11) {
        labelY = lastLabelY + 11;
      }
      canvas.drawString(
          font, 7.5, _formatLevelMeters(m.elev),
          markX - 40, labelY + 1);
      lastLabelY = labelY;
    }

    // --- 8. Цепь осей + общая размерная линия внизу.
    // Выше — тонкая цепочка с кружками осей (А, Б, В… или 1, 2, 3…
    // в зависимости от стороны) на расстояниях, кратных комнатам
    // (если известны). Ниже — общая длина фасада в мм.
    final axisLabels = _facadeAxisLabelsFor(side);
    // На фасаде показываем ТОЛЬКО крайние оси (СП 21.501-2018 п. 6.4 —
    // на фасаде требуется привязка к крайним осям и габариты, остальные
    // оси и размеры внутренних стен выносятся на план/разрез). Это
    // убирает «лес» осей и оставляет только габарит фасада.
    final allAxisPositions = _facadeAxisPositionsFor(
      side: side,
      plan: plan,
      buildingLen: buildingLen,
    );
    final axisPositions = allAxisPositions.length >= 2
        ? <double>[allAxisPositions.first, allAxisPositions.last]
        : allAxisPositions;
    // По требованию пользователя (Лист 8) — оси и кружки осей должны
    // быть отнесены ДАЛЬШЕ от чертежа, чтобы не накладываться на
    // размеры. Раньше: -22 / -42 (слишком близко). Теперь -34 / -78.
    final dimYAxis = groundY - 78;
    final dimYTotal = groundY - 34;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    if (axisPositions.isNotEmpty) {
      // Горизонтальная линия цепочки осей — обычная сплошная.
      canvas.drawLine(ox, dimYAxis, ox + drawW, dimYAxis);
      canvas.strokePath();
      // Вертикальные оси через всё здание — штрих-пунктирная линия
      // (ГОСТ 2.303-68, тип 4) с пониженной непрозрачностью, чтобы
      // пересечения с фасадом просвечивали и не «перечёркивали»
      // элементы. Это показывает пользователю, к какой оси относится
      // соответствующий габаритный размер.
      for (var i = 0; i < axisPositions.length; i++) {
        final xp = ox + axisPositions[i] * scale;
        canvas.setLineDashPattern([6, 2, 1, 2]);
        canvas.setGraphicState(
            const PdfGraphicState(strokeOpacity: 0.40));
        canvas.drawLine(xp, yAt(topElev + el.roofHeight) + 4,
            xp, dimYAxis - 9 - 6);
        canvas.strokePath();
        canvas.setLineDashPattern();
        canvas.setGraphicState(
            const PdfGraphicState(strokeOpacity: 1));
      }
      for (var i = 0; i < axisPositions.length; i++) {
        final xp = ox + axisPositions[i] * scale;
        canvas.drawLine(xp, dimYAxis, xp, dimYAxis + 10);
        canvas.strokePath();
        // Кружок оси: радиус 6, шрифт авто-уменьшается, чтобы текст
        // не вылез за рамки кружка (фикс по л.21–24).
        const axisR = 6.0;
        canvas.setFillColor(PdfColors.white);
        canvas.drawEllipse(xp, dimYAxis - 9, axisR, axisR);
        canvas.fillPath();
        canvas.setStrokeColor(PdfColors.black);
        canvas.drawEllipse(xp, dimYAxis - 9, axisR, axisR);
        canvas.strokePath();
        final lblIdx = i == 0 ? 0 : allAxisPositions.length - 1;
        final label =
            lblIdx < axisLabels.length ? axisLabels[lblIdx] : '${lblIdx + 1}';
        // Подбираем размер шрифта так, чтобы текст помещался в кружок.
        final lblW7 = font.stringMetrics(label).width * 7.0;
        final maxW = axisR * 2 - 2.0;
        final lblFs = lblW7 > maxW
            ? (7.0 * maxW / lblW7).clamp(4.5, 7.0)
            : 7.0;
        _drawCenteredText(canvas, label, xp, dimYAxis - 9,
            fontSize: lblFs.toDouble(), font: font);
      }
    }
    // Общая длина.
    canvas.drawLine(ox, dimYTotal, ox + drawW, dimYTotal);
    canvas.strokePath();
    const tickD = 3.0;
    canvas.drawLine(ox - tickD, dimYTotal - tickD, ox + tickD, dimYTotal + tickD);
    canvas.drawLine(ox + drawW - tickD, dimYTotal - tickD,
        ox + drawW + tickD, dimYTotal + tickD);
    canvas.strokePath();
    _drawCenteredText(canvas, '${(buildingLen * 1000).round()}',
        ox + drawW / 2, dimYTotal + 5, fontSize: 8, font: font);

    // --- 9. Вертикальная цепочка размеров справа — реальные высоты:
    // цоколь / этаж / этаж / … / кровля. Все мм из расчётов.
    final dimXChain = ox + drawW + 24;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    final lowestElev = (el.hasBasement && el.basementHeight > 0)
        ? -el.basementHeight
        : -plinthH;
    final yChainBottom = yAt(lowestElev);
    final yChainTop = yAt(topElev + el.roofHeight);
    canvas.drawLine(dimXChain, yChainBottom, dimXChain, yChainTop);
    canvas.strokePath();
    // Тики/выноски: −basement (если есть), −plinth, 0.000,
    // +floorHeight, …, +topElev, +ridge.
    final chainLevels = <double>[
      if (el.hasBasement && el.basementHeight > 0) -el.basementHeight,
      -plinthH,
      0.0,
      for (var i = 1; i <= el.floors; i++) i * el.floorHeight,
      if (el.hasMansard) topElev,
      topElev + el.roofHeight,
    ];
    for (var i = 0; i < chainLevels.length; i++) {
      final ye = yAt(chainLevels[i]);
      canvas.drawLine(dimXChain - 3, ye, dimXChain + 3, ye);
    }
    canvas.strokePath();
    for (var i = 0; i < chainLevels.length - 1; i++) {
      final mm = ((chainLevels[i + 1] - chainLevels[i]) * 1000).round();
      final ya = yAt(chainLevels[i]);
      final yb = yAt(chainLevels[i + 1]);
      _drawCenteredText(canvas, '$mm', dimXChain + 14, (ya + yb) / 2 - 2,
          fontSize: 7, font: font);
    }
    // Подпись «Высоты, мм» — справа от значений, чтобы не пересекаться
    // с числами цепи (требование пользователя по Лист 14).
    canvas.drawString(font, 6.5, 'Высоты, мм',
        dimXChain + 22, yChainTop + 4);

    // --- 10. Подписи материалов: уклон кровли (на выносной полке за
    // пределами чертежа) + материал стен/кровли.
    final slopePct = (math.tan(el.slopeDeg * math.pi / 180) * 100).round();
    final slopeStr = '${el.slopeDeg.toStringAsFixed(0)}° / $slopePct%';
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    if (el.roofShape != RoofShape.flat) {
      // Выноска уклона — переносим на ЛЕВУЮ сторону (вертикальная цепь
      // высот стоит справа, поэтому слева чище). Анкер ставим прямо на
      // ЛЕВОМ скате двускатной кровли — для двускатки конёк по центру:
      // на уровне 60 % высоты ската левый скат проходит через
      // x = 0.5·drawW · (1−0.60) = 0.20·drawW от левого края.
      // Для других форм используется приблизительная позиция,
      // которая визуально остаётся внутри контура крыши.
      final fSlope = 0.60;
      final slopeAnchorX = ox + drawW * 0.5 * (1 - fSlope);
      final slopeAnchorY = yAt(topElev + el.roofHeight * fSlope);
      // Короткая выноска: диагональ ~12 pt, полка ~52 pt.
      final shelfX = ox - 4;
      final shelfY = slopeAnchorY + 12;
      canvas.drawLine(slopeAnchorX, slopeAnchorY, shelfX, shelfY);
      canvas.drawLine(shelfX, shelfY, shelfX - 52, shelfY);
      canvas.strokePath();
      // Текст — над полкой, выровнен по правому краю (ближе к выноске).
      final lblW = font.stringMetrics('Уклон $slopeStr').width * 8;
      canvas.drawString(font, 8, 'Уклон $slopeStr',
          shelfX - lblW - 1, shelfY + 2);
    }
    // 10.2 Легенда материалов (стены / кровля / цоколь) — РЯДОМ внизу
    // листа в горизонтальной строке, чтобы НЕ перекрывать чертёж и
    // вертикальную цепь высот справа.
    final fpLabel = _foundationPreview(project, plan).typeLabel;
    // Легенда ниже цепи осей (и так далеко от чертежа) — чтобы не
    // пересекалась с кружками осей и размерами по Лист 8.
    final legendY = math.min(groundY - 110, oy - 6 + 14);
    final wallLabel = 'Стены: ${PdfBuilderMaterials.facadeWallLabel(wallCode)}';
    final roofLabel = 'Кровля: ${PdfBuilderMaterials.facadeRoofLabel(project.roof.roofingMaterial)}';
    final foundLabel = 'Фундамент / цоколь: $fpLabel';
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.setFillColor(wallFill);
    canvas.drawRect(ox, legendY, 10, 8);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7, wallLabel, ox + 14, legendY + 1);
    final wlblW = font.stringMetrics(wallLabel).width * 7 + 22;
    final col2X = ox + wlblW;
    canvas.setFillColor(
        PdfBuilderMaterials.facadeRoofFill(project.roof.roofingMaterial));
    canvas.drawRect(col2X, legendY, 10, 8);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7, roofLabel, col2X + 14, legendY + 1);
    final rlblW = font.stringMetrics(roofLabel).width * 7 + 22;
    final col3X = col2X + rlblW;
    canvas.setFillColor(const PdfColor(0.70, 0.70, 0.70));
    canvas.drawRect(col3X, legendY, 10, 8);
    canvas.fillAndStrokePath();
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 7, foundLabel, col3X + 14, legendY + 1);
  }

  /// Возвращает PDF-x диапазоны (минимальный, максимальный) на фасаде,
  /// которые занимают пристройки типа гараж. По требованию пользователя
  /// (Лист 14) штриховка цоколя дома должна обрываться в этих диапазонах.
  static List<({double xMin, double xMax})> _facadeGarageXRanges({
    required FloorPlan plan,
    required _FacadeSide side,
    required double ox,
    required double drawW,
    required double scale,
  }) {
    final ranges = <({double xMin, double xMax})>[];
    for (final a in plan.attachments) {
      if (a.kind != PlanAttachmentKind.garage) continue;
      double startAlong;
      double lenAlong;
      bool onThisSide = false;
      switch (side) {
        case _FacadeSide.south:
          if (a.y >= plan.height - 0.01) {
            onThisSide = true;
            startAlong = a.x;
            lenAlong = a.width;
          } else {
            startAlong = 0;
            lenAlong = 0;
          }
          break;
        case _FacadeSide.north:
          if (a.y + a.height <= 0.01) {
            onThisSide = true;
            startAlong = plan.width - a.x - a.width;
            lenAlong = a.width;
          } else {
            startAlong = 0;
            lenAlong = 0;
          }
          break;
        case _FacadeSide.east:
          if (a.x >= plan.width - 0.01) {
            onThisSide = true;
            startAlong = a.y;
            lenAlong = a.height;
          } else {
            startAlong = 0;
            lenAlong = 0;
          }
          break;
        case _FacadeSide.west:
          if (a.x + a.width <= 0.01) {
            onThisSide = true;
            startAlong = plan.height - a.y - a.height;
            lenAlong = a.height;
          } else {
            startAlong = 0;
            lenAlong = 0;
          }
          break;
      }
      if (!onThisSide || lenAlong <= 0) continue;
      final xMin = ox + startAlong * scale - 1;
      final xMax = ox + (startAlong + lenAlong) * scale + 1;
      ranges.add((xMin: xMin, xMax: xMax));
    }
    return ranges;
  }

  /// Рисует горизонтальную линию [x1..x2] на высоте [y], обрывая её на
  /// заданных диапазонах [breakRanges] (например, на участках, занятых
  /// гаражом). Используется для штриховки цоколя на фасаде.
  static void _drawHorizontalLineBreakingAt({
    required PdfGraphics canvas,
    required double x1,
    required double x2,
    required double y,
    required List<({double xMin, double xMax})> breakRanges,
  }) {
    if (breakRanges.isEmpty) {
      canvas.drawLine(x1, y, x2, y);
      return;
    }
    // Сортируем диапазоны по xMin.
    final sorted = [...breakRanges]
      ..sort((a, b) => a.xMin.compareTo(b.xMin));
    double cur = x1;
    for (final r in sorted) {
      if (r.xMax <= cur) continue;
      if (r.xMin >= x2) break;
      final segEnd = r.xMin.clamp(cur, x2).toDouble();
      if (segEnd > cur + 0.5) {
        canvas.drawLine(cur, y, segEnd, y);
      }
      cur = r.xMax.clamp(cur, x2).toDouble();
      if (cur >= x2) return;
    }
    if (cur < x2 - 0.5) {
      canvas.drawLine(cur, y, x2, y);
    }
  }

  /// Рисует силуэты пристроек (крыльцо / терраса) у земли на фасаде —
  /// те, что «смотрят» в сторону стороны [side]. Координаты [PlanAttachment]
  /// заданы в системе пятна застройки; сторона определяется положением
  /// attachment-а за соответствующей гранью пятна.
  static void _paintFacadeAttachments({
    required PdfGraphics canvas,
    required PdfFont font,
    required FloorPlan plan,
    required _FacadeSide side,
    required double ox,
    required double drawW,
    required double groundY,
    required double scale,
    required double buildingLen,
  }) {
    for (final a in plan.attachments) {
      // Определяем, «смотрит» ли пристройка в нужную сторону — она
      // должна находиться за соответствующей гранью плана.
      double startAlongFacade;
      double lenAlongFacade;
      bool onThisSide = false;
      switch (side) {
        case _FacadeSide.south:
          // Южный фасад — нижняя сторона (y = plan.height).
          if (a.y >= plan.height - 0.01) {
            onThisSide = true;
            startAlongFacade = a.x;
            lenAlongFacade = a.width;
          } else {
            startAlongFacade = 0;
            lenAlongFacade = 0;
          }
          break;
        case _FacadeSide.north:
          if (a.y + a.height <= 0.01) {
            onThisSide = true;
            // По X зеркалим (северный фасад смотрит «с обратной стороны»).
            startAlongFacade = plan.width - a.x - a.width;
            lenAlongFacade = a.width;
          } else {
            startAlongFacade = 0;
            lenAlongFacade = 0;
          }
          break;
        case _FacadeSide.east:
          if (a.x >= plan.width - 0.01) {
            onThisSide = true;
            startAlongFacade = a.y;
            lenAlongFacade = a.height;
          } else {
            startAlongFacade = 0;
            lenAlongFacade = 0;
          }
          break;
        case _FacadeSide.west:
          if (a.x + a.width <= 0.01) {
            onThisSide = true;
            // Западный фасад — зеркалим по Y.
            startAlongFacade = plan.height - a.y - a.height;
            lenAlongFacade = a.height;
          } else {
            startAlongFacade = 0;
            lenAlongFacade = 0;
          }
          break;
      }
      if (!onThisSide) continue;
      if (lenAlongFacade <= 0) continue;
      // Высота силуэта: гараж — реальная высота из спецификации
      // (по умолчанию 2.7 м); терраса 0.9 м (перила/навес); крыльцо 0.9 м.
      final silhouetteH = a.kind == PlanAttachmentKind.garage
          ? 2.7
          : 0.9;
      final x1 = ox + startAlongFacade * scale;
      final w = lenAlongFacade * scale;
      final h = silhouetteH * scale;
      final PdfColor fill = switch (a.kind) {
        PlanAttachmentKind.terrace => const PdfColor(0.92, 0.85, 0.74),
        PlanAttachmentKind.garage => const PdfColor(0.78, 0.78, 0.80),
        PlanAttachmentKind.porch => const PdfColor(0.88, 0.80, 0.68),
      };
      canvas.setFillColor(fill);
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.5);
      canvas.drawRect(x1, groundY, w, h);
      canvas.fillAndStrokePath();
      // Гараж — нарисуем ворота (трапеция) и плоскую кровлю над прямоугольником.
      if (a.kind == PlanAttachmentKind.garage) {
        // Кровля — тонкая плоская полоска поверх стен.
        canvas.setFillColor(const PdfColor(0.45, 0.45, 0.48));
        canvas.drawRect(x1 - 2, groundY + h, w + 4, 4);
        canvas.fillPath();
        // Ворота: ширина в МЕТРАХ, не в pt — ранее жёсткий cap 90 pt
        // на любых масштабах превращал ворота в 2.0–2.5 м, и
        // внедорожник (≈2.0–2.1 м с зеркалами + запас) едва проходил.
        // Теперь:  3.0 м гарантированно (рекомендация для гаража 1
        // авто), 2.5 м минимум, и не больше 88 % фактической ширины
        // гаража, чтобы остались простенки по 0.3 м с каждой стороны.
        const gateMinM = 2.5; // абсолютный минимум — не меньше 2.5 м
        const gateTargetM = 3.0; // целевая ширина для внедорожника
        final gateMaxByGarageM = lenAlongFacade * 0.88;
        final gateM = math.max(
          math.min<double>(gateTargetM, gateMaxByGarageM),
          math.min<double>(gateMinM, gateMaxByGarageM),
        );
        final gateW = gateM * scale;
        final gateH = math.min(h * 0.78, 2.4 * scale); // 2.4 м высота
        final gx = x1 + (w - gateW) / 2;
        canvas.setStrokeColor(PdfColors.grey700);
        canvas.setFillColor(const PdfColor(0.96, 0.96, 0.96));
        canvas.setLineWidth(0.7);
        canvas.drawRect(gx, groundY, gateW, gateH);
        canvas.fillAndStrokePath();
        // Секции на воротах — горизонтальные полосы (3 шт.)
        canvas.setLineWidth(0.3);
        for (var s = 1; s < 4; s++) {
          final sy = groundY + gateH * s / 4;
          canvas.drawLine(gx, sy, gx + gateW, sy);
        }
        canvas.strokePath();
        // Размерная цепь шириной ворот — пользователь должен видеть,
        // что ворота 3.0 м (под внедорожник).
        canvas.setStrokeColor(PdfColors.black);
        canvas.setLineWidth(0.4);
        final dimY = groundY - 14;
        canvas.drawLine(gx, dimY, gx + gateW, dimY);
        canvas.drawLine(gx, dimY - 3, gx, dimY + 3);
        canvas.drawLine(gx + gateW, dimY - 3, gx + gateW, dimY + 3);
        // Выносные линии от ворот к размерной линии.
        canvas.drawLine(gx, groundY - 1, gx, dimY - 4);
        canvas.drawLine(gx + gateW, groundY - 1, gx + gateW, dimY - 4);
        canvas.strokePath();
        _drawCenteredText(
          canvas,
          '${(gateM * 1000).round()}',
          gx + gateW / 2,
          dimY + 2,
          fontSize: 7,
          font: font,
        );
      }
      final label = switch (a.kind) {
        PlanAttachmentKind.terrace => 'Терраса',
        PlanAttachmentKind.garage => 'Гараж',
        PlanAttachmentKind.porch => 'Крыльцо',
      };
      _drawCenteredText(canvas, label, x1 + w / 2, groundY + h - 8,
          fontSize: 7, font: font, maxWidth: w - 4);
    }
  }

  /// Форматирует размер проёма в «ШxВ, мм» по ГОСТ 21.501-2018.
  /// Пример: 1.5 × 1.5 → `1500×1500`.
  static String _formatOpeningSize({
    required double widthM,
    required double heightM,
  }) {
    return '${(widthM * 1000).round()}×${(heightM * 1000).round()}';
  }

  /// Маркирует проём по ГОСТ Р 21.501-2018 с двумя строками внутри марки:
  /// верх — шифр (ОК-1 / Д-1), низ — размер проёма (1500×1500).
  /// Форма марки — овал, размер подбирается под максимальную из строк, чтобы
  /// текст не выходил за рамки. Шрифт авто-уменьшается, если строка
  /// длиннее ширины овала.
  static void _drawOpeningMarkWithSize(
    PdfGraphics canvas,
    PdfFont font, {
    required String label,
    required String sizeLabel,
    required double cx,
    required double cy,
  }) {
    // ry ↑ 10 → 11 pt + полная пара строк по 7/6 pt + межстрочный 1.4 pt
    // влезает с запасом в 22 pt вертикали (ранее текст накладывался
    // на верх/низ овала по фасадам и сечениям).
    const ry = 11.0;
    const baseTopFs = 7.0;
    const baseBotFs = 6.0;
    // 6 pt — общий горизонтальный запас (3 pt с каждой стороны), плюс
    // ниже добавляется 15 % на неточности stringMetrics в DejaVuSans
    // (метрики не учитывают кернинг и иногда занижают ширину).
    final innerWPad = 6.0;
    // Подбираем rx, чтобы оба текста помещались с базовыми кеглями.
    final topW = font.stringMetrics(label).width * baseTopFs * 1.15;
    final botW = font.stringMetrics(sizeLabel).width * baseBotFs * 1.15;
    final rx = math.max(15.0,
        math.max(topW, botW) / 2 + innerWPad);
    // Если даже после расширения овал слишком узкий — уменьшаем шрифт
    // снизу (для размера, чтобы не было обрыва).
    final maxInnerW = (rx - innerWPad / 2) * 2;
    final topFs = topW > maxInnerW
        ? (baseTopFs * maxInnerW / topW).clamp(4.5, baseTopFs)
        : baseTopFs;
    final botFs = botW > maxInnerW
        ? (baseBotFs * maxInnerW / botW).clamp(4.0, baseBotFs)
        : baseBotFs;
    // Белый фон овальной марки.
    canvas.setFillColor(PdfColors.white);
    canvas.drawEllipse(cx, cy, rx, ry);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.5);
    canvas.drawEllipse(cx, cy, rx, ry);
    canvas.strokePath();
    // Разделитель между шифром и размером.
    canvas.drawLine(cx - rx + 1.5, cy, cx + rx - 1.5, cy);
    canvas.strokePath();
    // Верхняя строка — шифр; визуальный центр строки в середине верхней
    // половины овала, чтобы текст не наезжал на разделитель и не выходил
    // вверх за границу.
    _drawCenteredText(canvas, label, cx, cy + ry / 2,
        fontSize: topFs.toDouble(), font: font);
    _drawCenteredText(canvas, sizeLabel, cx, cy - ry / 2,
        fontSize: botFs.toDouble(), font: font);
  }

  /// Рисует окно на фасаде: подоконник, перемычка, четверти, стеклопакет,
  /// горизонтальный импост (~60% от низа) и 0..2 вертикальных мулиона
  /// в зависимости от ширины окна (ГОСТ 21.501-2018, СП 55.13330.2017).
  static void _drawFacadeWindow(
    PdfGraphics canvas, {
    required double xStart,
    required double xEnd,
    required double yBot,
    required double yTop,
    required double widthM,
  }) {
    final w = xEnd - xStart;
    final h = yTop - yBot;

    // Четверти: светло-серая окантовка снаружи проёма (заглубление 65 мм).
    const qInset = 1.6;
    canvas.setFillColor(const PdfColor(0.55, 0.48, 0.42, 0.35));
    canvas.drawRect(xStart - qInset, yTop, w + 2 * qInset, qInset);
    canvas.drawRect(xStart - qInset, yBot - qInset, w + 2 * qInset, qInset);
    canvas.drawRect(xStart - qInset, yBot, qInset, h);
    canvas.drawRect(xEnd, yBot, qInset, h);
    canvas.fillPath();

    // Стеклопакет — светло-голубой фон.
    canvas.setFillColor(const PdfColor(0.82, 0.90, 0.96));
    canvas.drawRect(xStart, yBot, w, h);
    canvas.fillPath();

    // Горизонтальный импост — на ~60% высоты от низа (для Ш ≥ 0.5 м).
    if (widthM >= 0.5) {
      final impostY = yBot + h * 0.60;
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.8);
      canvas.drawLine(xStart, impostY, xEnd, impostY);
      canvas.strokePath();
    }

    // Вертикальные мулионы: количество зависит от ширины.
    final int mullions;
    if (widthM < 0.80) {
      mullions = 0;
    } else if (widthM < 1.60) {
      mullions = 1;
    } else {
      mullions = 2;
    }
    if (mullions > 0) {
      canvas.setStrokeColor(PdfColors.black);
      canvas.setLineWidth(0.8);
      for (var i = 1; i <= mullions; i++) {
        final mx = xStart + w * i / (mullions + 1);
        canvas.drawLine(mx, yBot, mx, yTop);
      }
      canvas.strokePath();
    }

    // Оконная рама (внешний контур).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    canvas.drawRect(xStart, yBot, w, h);
    canvas.strokePath();

    // Подоконник — тёмно-серый выступ 4 пт на сторону, толщиной 2.5 пт.
    const sillOverhang = 4.0;
    const sillThickness = 2.5;
    final sillY = yBot - 0.5 - sillThickness;
    canvas.setFillColor(const PdfColor(0.55, 0.55, 0.55));
    canvas.drawRect(xStart - sillOverhang, sillY,
        w + 2 * sillOverhang, sillThickness);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(xStart - sillOverhang, sillY,
        w + 2 * sillOverhang, sillThickness);
    canvas.strokePath();

    // Перемычка над проёмом — тёмная линия с «ушами» 3 пт на сторону.
    const lintelOverhang = 3.0;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    canvas.drawLine(
      xStart - lintelOverhang, yTop + 1.2,
      xEnd + lintelOverhang, yTop + 1.2,
    );
    canvas.strokePath();
  }

  /// Рисует входную дверь на фасаде: коробка, полотно с филёнками,
  /// четверти, порог и перемычка (ГОСТ 21.501-2018, СП 55.13330.2017).
  static void _drawFacadeDoor(
    PdfGraphics canvas, {
    required double xStart,
    required double xEnd,
    required double yBot,
    required double yTop,
  }) {
    final w = xEnd - xStart;
    final h = yTop - yBot;

    // Четверти — серая окантовка заглубления.
    const qInset = 1.6;
    canvas.setFillColor(const PdfColor(0.55, 0.48, 0.42, 0.35));
    canvas.drawRect(xStart - qInset, yTop, w + 2 * qInset, qInset);
    canvas.drawRect(xStart - qInset, yBot, qInset, h);
    canvas.drawRect(xEnd, yBot, qInset, h);
    canvas.fillPath();

    // Дверная коробка (рама).
    canvas.setFillColor(const PdfColor(0.36, 0.24, 0.14));
    canvas.drawRect(xStart, yBot, w, h);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.0);
    canvas.drawRect(xStart, yBot, w, h);
    canvas.strokePath();

    // Полотно двери (заглублено 2 пт).
    const frameInset = 2.0;
    final dx0 = xStart + frameInset;
    final dx1 = xEnd - frameInset;
    final dy0 = yBot + frameInset;
    final dy1 = yTop - frameInset;
    final dw = dx1 - dx0;
    final dh = dy1 - dy0;
    canvas.setFillColor(const PdfColor(0.45, 0.32, 0.20));
    canvas.drawRect(dx0, dy0, dw, dh);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.6);
    canvas.drawRect(dx0, dy0, dw, dh);
    canvas.strokePath();

    // 3 филёнки (горизонтальные панели).
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.35);
    final panelX = dx0 + 2;
    final panelW = dw - 4;
    if (panelW > 2 && dh > 10) {
      final p1H = dh * 0.26;
      final p2H = dh * 0.26;
      final p3H = dh * 0.34;
      canvas.drawRect(panelX, dy1 - 2 - p1H, panelW, p1H);
      canvas.drawRect(panelX, dy1 - 2 - p1H - 4 - p2H, panelW, p2H);
      canvas.drawRect(panelX, dy0 + 2, panelW, p3H);
      canvas.strokePath();
    }

    // Ручка (чуть ниже середины, у правого края полотна).
    canvas.setFillColor(PdfColors.grey900);
    canvas.drawEllipse(dx1 - 4, (dy0 + dy1) / 2 - 2, 1.3, 1.3);
    canvas.fillPath();

    // Порог — тёмная полоса, выступает 3 пт на сторону.
    const thOverhang = 3.0;
    canvas.setFillColor(PdfColors.grey800);
    canvas.drawRect(
        xStart - thOverhang, yBot - 1.2, w + 2 * thOverhang, 1.5);
    canvas.fillPath();
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(0.4);
    canvas.drawRect(
        xStart - thOverhang, yBot - 1.2, w + 2 * thOverhang, 1.5);
    canvas.strokePath();

    // Перемычка над дверью.
    const lintelOverhang = 3.0;
    canvas.setStrokeColor(PdfColors.black);
    canvas.setLineWidth(1.2);
    canvas.drawLine(
      xStart - lintelOverhang, yTop + 1.2,
      xEnd + lintelOverhang, yTop + 1.2,
    );
    canvas.strokePath();
  }

  /// Проецирует проём плана [o] на фасад стороны [side].
  /// Возвращает позицию вдоль фасада (startX, length в метрах) и флаг
  /// «это входная дверь», или `null` если проём не видно с этой стороны.
  static _FacadeOpening? _projectOpeningOnFacade(
    PlanOpening o, {
    required _FacadeSide side,
    required double planW,
    required double planH,
  }) {
    // На фасад выводим только внешние проёмы: окна и входные двери.
    if (o.kind != OpeningKind.window &&
        o.kind != OpeningKind.externalDoor) {
      return null;
    }
    // Для каждой стороны смотрим, совпадает ли сторона проёма со
    // стороной фасада. Для «обратных» фасадов (северный, западный)
    // координата вдоль фасада зеркалится — мы смотрим на здание
    // с противоположной стороны.
    switch (side) {
      case _FacadeSide.south:
        if (o.side != WallSide.bottom) return null;
        return _FacadeOpening(
          startX: o.x,
          length: o.length,
          isDoor: o.kind == OpeningKind.externalDoor,
        );
      case _FacadeSide.north:
        if (o.side != WallSide.top) return null;
        return _FacadeOpening(
          startX: planW - o.x - o.length,
          length: o.length,
          isDoor: o.kind == OpeningKind.externalDoor,
        );
      case _FacadeSide.east:
        if (o.side != WallSide.right) return null;
        return _FacadeOpening(
          startX: o.y,
          length: o.length,
          isDoor: o.kind == OpeningKind.externalDoor,
        );
      case _FacadeSide.west:
        if (o.side != WallSide.left) return null;
        return _FacadeOpening(
          startX: planH - o.y - o.length,
          length: o.length,
          isDoor: o.kind == OpeningKind.externalDoor,
        );
    }
  }

  /// Метки осей для «юг/север» — цифры 1, 2, 3 … (ось X).
  /// Для «восток/запад» — буквы А, Б, В … (ось Y).
  static List<String> _facadeAxisLabelsFor(_FacadeSide side) {
    if (side == _FacadeSide.south || side == _FacadeSide.north) {
      return const ['1', '2', '3', '4', '5', '6', '7', '8'];
    }
    return const ['А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'И'];
  }

  /// Возвращает позиции осей вдоль фасада (в метрах от левого края
  /// фасада), дублируя границы комнат на стороне взгляда. Всегда
  /// включает 0 и `buildingLen` как крайние оси.
  static List<double> _facadeAxisPositionsFor({
    required _FacadeSide side,
    required FloorPlan plan,
    required double buildingLen,
  }) {
    final positions = <double>{0, buildingLen};
    // Крайние оси от краёв комнат на соответствующей стороне.
    for (final r in plan.rooms) {
      switch (side) {
        case _FacadeSide.south:
        case _FacadeSide.north:
          // Продольные оси по X.
          positions.add(r.x);
          positions.add(r.x + r.width);
          break;
        case _FacadeSide.east:
        case _FacadeSide.west:
          positions.add(r.y);
          positions.add(r.y + r.height);
          break;
      }
    }
    // Зеркалим X для «обратных» фасадов.
    final list = positions.toList()..sort();
    if (side == _FacadeSide.north || side == _FacadeSide.west) {
      for (var i = 0; i < list.length; i++) {
        list[i] = buildingLen - list[i];
      }
      list.sort();
    }
    // Оставляем только точки в диапазоне [0, buildingLen] с небольшим допуском.
    final unique = <double>[];
    for (final v in list) {
      if (v < -0.01 || v > buildingLen + 0.01) continue;
      if (unique.isNotEmpty && (unique.last - v).abs() < 0.05) continue;
      unique.add(v.clamp(0.0, buildingLen));
    }
    return unique;
  }

  /// Лист «Общий вид» — реальная 3D-модель здания, собранная из ТЗ
  /// и расчётов через [Building3DGenerator] и отрисованная через
  /// [Building3DRenderer] (изометрическая ортогональная проекция,
  /// painter's algorithm + back-face culling, без внешних 3D-движков).
  static void _paintAxonometric(
    PdfGraphics canvas,
    PdfPoint size,
    HouseProject project,
    FloorPlan plan,
    PdfFont font, {
    required List<FloorPlan> plans,
  }) {
    // 3D-модель строится по реальным планам пользователя — это
    // обеспечивает идентичность проёмов на фасаде/изометрии и в
    // схематических планах этажей.
    final building =
        Building3DGenerator.generate(project, floorPlans: plans);
    if (building == null) return;
    PdfBuilderMaterials.renderBuilding3DToPdf(
      canvas: canvas,
      size: size,
      building: building,
      font: font,
      caption: 'Общий вид (3D-модель). Изометрия 1:100',
    );
  }
}

/// Габариты здания по высоте — для разрезов и фасадов.
class _BuildingElevation {
  final int floors;
  final bool hasBasement;
  final bool hasMansard;
  final double floorHeight;
  final double foundationDepth;
  final double plinthHeight;
  final double roofHeight;
  final RoofShape roofShape;
  final double slopeDeg;
  /// Высота помещения подвала, м (только если `hasBasement == true`,
  /// иначе 0). Берётся равной `floorHeight` или 2.5 м минимум.
  final double basementHeight;
  const _BuildingElevation({
    required this.floors,
    required this.hasBasement,
    required this.hasMansard,
    required this.floorHeight,
    required this.foundationDepth,
    required this.plinthHeight,
    required this.roofHeight,
    required this.roofShape,
    required this.slopeDeg,
    this.basementHeight = 0,
  });
}

/// Параметры подобранного фундамента для рисования (тип, габариты, армирование).
class _FoundationPreview {
  final FoundationType type;
  final String typeLabel;
  final String dimsLabel;
  final List<String> details;
  final double depthM;
  final double widthM;
  final double pileSpacingM;
  final double pileDiameterM;
  final double slabThicknessM;
  const _FoundationPreview({
    required this.type,
    required this.typeLabel,
    required this.dimsLabel,
    required this.details,
    required this.depthM,
    required this.widthM,
    this.pileSpacingM = 0,
    this.pileDiameterM = 0,
    this.slabThicknessM = 0,
  });
}

/// Отметка высоты на разрезе/фасаде.
class _HeightMark {
  final double elev;
  final String label;
  const _HeightMark(this.elev, this.label);
}

/// Проёмы, пересечённые секущей плоскостью разреза.
/// `secX` — координата центра проёма в метрах вдоль оси разреза;
/// `widthPx` — ширина «прорезанного» проёма в пунктах PDF.
class _SectionOpening {
  final OpeningKind kind;
  final double secX;
  final double widthPx;
  const _SectionOpening({
    required this.kind,
    required this.secX,
    required this.widthPx,
  });
}

/// Сторона, с которой рисуется фасад.
enum _FacadeSide { south, north, east, west }

/// Выравнивание текста для `_drawAlignedText`.
enum _TextAlign { center, left }

/// Проекция проёма плана на фасад: положение (в метрах от левого края
/// фасада) и длина в метрах. Высоту определяет `isDoor`.
class _FacadeOpening {
  final double startX;
  final double length;
  final bool isDoor;
  const _FacadeOpening({
    required this.startX,
    required this.length,
    required this.isDoor,
  });
}

/// Прямоугольник в модельных координатах (метры, ось Y вниз).
class _RectM {
  final double mx;
  final double my;
  final double mw;
  final double mh;
  const _RectM(this.mx, this.my, this.mw, this.mh);
}

