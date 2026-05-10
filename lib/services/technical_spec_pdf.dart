import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/rooms_catalog.dart';
import '../data/wall_materials.dart';
import '../models/house_project.dart';

/// Сборка итогового PDF «Техническое задание» — единого документа,
/// который содержит ответы и решения со всех четырёх этапов проекта.
///
/// В отличие от пояснительной записки фундамента ([FoundationExplanationPdf]),
/// здесь нет инженерных расчётов: это **архитектурно-планировочное** ТЗ,
/// которое читает заказчик/проектировщик/подрядчик. Структура:
///   1) Шапка проекта (имя, тип конструкции, дата).
///   2) Раздел «Начальные данные» — этажность, площадь, комнаты, материал
///      стен, дополнения, особые пожелания.
///   3) Раздел «Планировка» — материалы стен, тип перекрытий,
///      лестница (если есть), описание планировки.
///   4) Раздел «Фундамент» — климат, грунт, тип и параметры фундамента.
///   5) Раздел «Кровля» — тип, угол, покрытие.
///
/// PDF полностью на русском, использует TTF-шрифт DejaVu Sans
/// (тот же, что и в остальных PDF приложения). С v38 формат страницы — A3
/// landscape (как у комплекта АР/КР чертежей), чтобы все ПЗ были в одном
/// формате и легко подшивались к комплекту.
class TechnicalSpecPdf {
  TechnicalSpecPdf._();

  static Future<Uint8List> build(HouseProject project) async {
    final regularData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final pdf = pw.Document(
      title: 'Техническое задание — ${project.name}',
      author: 'Construction Calculator',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        header: (ctx) => _header(project, regular),
        footer: (ctx) => _footer(ctx, regular),
        build: (ctx) => [
          _title(project, bold, regular),
          pw.SizedBox(height: 12),
          _sectionTitle('1. Начальные данные', bold),
          _kvTable(_initialDataRows(project), regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('2. Планировка', bold),
          _kvTable(_planningRows(project), regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('3. Кровля', bold),
          _kvTable(_roofRows(project), regular, bold),
          pw.SizedBox(height: 8),
          _sectionTitle('4. Фундамент', bold),
          _kvTable(_foundationRows(project), regular, bold),
          pw.SizedBox(height: 12),
          _notesBlock(project, regular, bold),
        ],
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------
  // Сборка строк по разделам
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // Словари перевода технических идентификаторов на русские формулировки.
  // Идентификаторы используются как стабильные ключи в моделях; в PDF
  // показываем только локализованные надписи.
  // ---------------------------------------------------------------------

  static const Map<String, String> _roofTypeLabels = {
    'gable': 'Двускатная',
    'hip': 'Четырёхскатная (вальмовая)',
    'mansard': 'Мансардная',
    'flat': 'Плоская',
  };

  static const Map<String, String> _roofMaterialLabels = {
    'metal_tile': 'Металлочерепица',
    'soft': 'Мягкая (битумная)',
    'ceramic': 'Керамическая',
    'slate': 'Шифер',
    'seam': 'Фальцевая',
  };

  static const Map<String, String> _staircaseTypeLabels = {
    'marsh': 'Маршевая',
    'rotary': 'Поворотная (с забежными)',
    'screw': 'Винтовая',
  };

  static const Map<String, String> _slabTypeLabels = {
    'monolith': 'Монолитное ж/б',
    'precast': 'Сборное ж/б',
    'wood_beams': 'По деревянным балкам',
    'metal_beams': 'По металлическим балкам',
  };

  static String _roomLabel(String name) {
    for (final r in RoomKind.values.where((e) => e.userSelectable)) {
      if (r.name == name) return r.title;
    }
    return name;
  }

  static String _wallSummaryRu(HouseProject p) {
    final w = p.walls;
    if (!w.isFilled) return '—';
    String matLabel = w.material ?? '?';
    final fromEnum = WallMaterial.fromName(w.material)?.title;
    if (fromEnum != null) matLabel = fromEnum;
    final th = w.thickness == null
        ? '?'
        : '${w.thickness!.toStringAsFixed(0)} мм';
    final h = w.height == null ? '' : ' · h=${w.height!.toStringAsFixed(2)} м';
    return '$matLabel · $th$h';
  }

  static String _slabSummaryRu(HouseProject p) {
    final s = p.floorSlabs;
    if (!s.isFilled) return '—';
    final type = _slabTypeLabels[s.type] ?? s.type ?? '?';
    final mat = (s.material == null || s.material!.isEmpty)
        ? ''
        : ' · ${s.material}';
    final th = s.thickness == null
        ? ''
        : ' · ${s.thickness!.toStringAsFixed(0)} мм';
    return '$type$mat$th';
  }

  static String _staircaseSummaryRu(HouseProject p) {
    final s = p.staircase;
    if (!s.isFilled) return '—';
    final type = _staircaseTypeLabels[s.type] ?? s.type ?? '?';
    final steps =
        s.stepsCount == null ? '' : ' · ${s.stepsCount} ступеней';
    return '$type$steps';
  }

  static String _roofTypeRu(HouseProject p) {
    final t = p.roof.type;
    if (t == null) return '—';
    return _roofTypeLabels[t] ?? t;
  }

  static String _roofMaterialRu(HouseProject p) {
    final m = p.roof.roofingMaterial;
    if (m == null) return '—';
    return _roofMaterialLabels[m] ?? m;
  }

  static Map<String, String> _initialDataRows(HouseProject p) {
    final b = p.brief;
    final addons = <String>[];
    if (b.hasMansard == true) addons.add('мансарда');
    if (b.hasBasement == true) addons.add('подвал/цоколь');
    final addonStr = addons.isEmpty ? '' : ' + ${addons.join(' + ')}';
    final rooms = b.rooms.entries
        .where((e) => e.value > 0)
        .map((e) => '${_roomLabel(e.key)} ×${e.value}')
        .join(', ');

    return {
      'Этажность':
          b.floors == null ? '—' : '${b.floors}$addonStr',
      'Целевая площадь':
          b.targetArea == null ? '—' : '${b.targetArea!.toStringAsFixed(0)} м²',
      'Габариты здания': (b.footprintWidth != null && b.footprintLength != null)
          ? '${b.footprintWidth!.toStringAsFixed(0)} × '
              '${b.footprintLength!.toStringAsFixed(0)} м'
          : '—',
      'Состав комнат': rooms.isEmpty ? '—' : rooms,
      'Ориентир по стенам': b.wallMaterial?.title ?? '—',
      'Особые пожелания':
          (b.specialRequirements == null || b.specialRequirements!.isEmpty)
              ? '—'
              : b.specialRequirements!,
    };
  }

  static Map<String, String> _planningRows(HouseProject p) {
    return {
      'Планировка':
          p.drawings.isEmpty ? '—' : p.drawings.summary,
      'Стены': _wallSummaryRu(p),
      'Перекрытия': _slabSummaryRu(p),
      'Лестница': p.includesStaircase
          ? _staircaseSummaryRu(p)
          : 'Не требуется (одноэтажный дом)',
    };
  }

  static Map<String, String> _foundationRows(HouseProject p) {
    final b = p.brief;
    final layers = b.soilLayers
        .where((l) => l.type != null)
        .map((l) => l.type!.title)
        .join(', ');
    return {
      'Регион': b.region ?? '—',
      'Снеговой район': b.snowZone?.toString() ?? '—',
      'Ветровой район': b.windZone ?? '—',
      'Грунт': layers.isEmpty ? '—' : layers,
      'Тип фундамента':
          p.foundation.isFilled ? p.foundation.summary : '—',
    };
  }

  static Map<String, String> _roofRows(HouseProject p) {
    final r = p.roof;
    return {
      'Тип кровли': _roofTypeRu(p),
      'Угол ската': r.slopeAngle == null
          ? (r.type == 'flat' ? 'плоская (≤ 5°)' : '—')
          : '${r.slopeAngle!.toStringAsFixed(0)}°',
      'Покрытие': _roofMaterialRu(p),
    };
  }

  // ---------------------------------------------------------------------
  // PDF-примитивы
  // ---------------------------------------------------------------------

  static pw.Widget _header(HouseProject project, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(project.name,
              style: pw.TextStyle(fontSize: 9, font: font)),
          pw.Text('Техническое задание',
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
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Сгенерировано Construction Calculator',
              style: pw.TextStyle(fontSize: 8, font: font)),
          pw.Text('Лист ${ctx.pageNumber} из ${ctx.pagesCount}',
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
        pw.Text('ТЕХНИЧЕСКОЕ ЗАДАНИЕ',
            style: pw.TextStyle(fontSize: 16, font: bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'на проектирование жилого дома',
          style: pw.TextStyle(fontSize: 12, font: regular),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Объект: ${project.name}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Тип конструкции: ${project.constructionType.title}',
            style: pw.TextStyle(fontSize: 11, font: regular)),
        pw.Text('Дата: $date',
            style: pw.TextStyle(fontSize: 11, font: regular)),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 12, font: bold)),
    );
  }

  static pw.Widget _kvTable(
      Map<String, String> rows, pw.Font regular, pw.Font bold) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        for (final e in rows.entries)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(e.key,
                    style: pw.TextStyle(fontSize: 10, font: regular)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(e.value,
                    style: pw.TextStyle(fontSize: 10, font: bold)),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _notesBlock(
      HouseProject project, pw.Font regular, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Примечания',
            style: pw.TextStyle(fontSize: 11, font: bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Это техническое задание сформировано автоматически из ответов '
          'пользователя на четырёх этапах проектирования. Расчёт нагрузок '
          'и подбор сечений конструкций выполняется отдельной пояснительной '
          'запиской по фундаменту (см. раздел «Фундамент» приложения). '
          'Чертежи планов этажей выгружаются отдельным комплектом '
          '(PDF и DXF) из раздела «Чертежи».',
          style: pw.TextStyle(fontSize: 9.5, font: regular),
        ),
      ],
    );
  }
}
