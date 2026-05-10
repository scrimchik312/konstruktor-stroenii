import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/organization_settings.dart';

/// Основной штамп листа по ГОСТ Р 21.101-2020 (форма 3, основная надпись
/// для чертежей и схем).
///
/// Рендерим как «прямоугольник 185 × 55 мм», разбитый на ячейки линиями
/// 0.5 мм. Внутри — поля: история изменений, ФИО и подписи исполнителей,
/// наименование объекта / наименование листа, стадия / номер листа /
/// количество листов, реквизиты организации.
///
/// Подписи могут быть пустыми — тогда ячейки просто не заполняются.
/// На экране печати штамп всегда фиксируется в правом нижнем углу листа.
class PdfTitleBlock {
  PdfTitleBlock._();

  /// Ширина штампа в миллиметрах. Фиксирована стандартом.
  static const double widthMm = 185;

  /// Высота штампа в миллиметрах.
  static const double heightMm = 55;

  /// Конвертор мм → пункты PDF (1 мм ≈ 2.8346 pt).
  static double _mm(double mm) => mm * PdfPageFormat.mm;

  /// Дефолтный коэффициент сжатия штампа.
  ///
  /// Полноразмерный штамп ГОСТ Р 21.101 — 185 × 55 мм. На листах А3 такой
  /// штамп занимает существенную часть страницы и оставляет мало места
  /// под основной чертёж, поэтому в проекте он рисуется уменьшенным до
  /// этого коэффициента (≈ 138.75 × 41.25 мм). Все ячейки и шрифты
  /// масштабируются пропорционально.
  static const double defaultScale = 0.75;

  /// Эффективная ширина штампа в пунктах PDF при заданном масштабе.
  static double widthPt({double scale = defaultScale}) =>
      _mm(widthMm) * scale;

  /// Эффективная высота штампа в пунктах PDF при заданном масштабе.
  static double heightPt({double scale = defaultScale}) =>
      _mm(heightMm) * scale;

  /// Строит виджет-штамп.
  ///
  /// - [projectName] — «Индивидуальный жилой дом» и т. п. (строка 1 — крупно).
  /// - [sectionTitle] — «Архитектурные решения» / «Конструкции железобетонные».
  /// - [sheetTitle] — «Общие данные (начало)», «План этажа на отметке ±0.000».
  /// - [sheetCode] — обозначение листа (например, «АР-3»).
  /// - [sheetNumber], [totalSheets] — номер листа и общее кол-во листов.
  /// - [stage] — стадия проектирования («РП», «П», «Р»).
  /// - [company] — ООО «…».
  /// - [companyPhone] — контактный телефон/адрес.
  /// - [signatories] — до 5 строк вида («ГАП», «Иванов И. И.», «12.24»).
  static pw.Widget build({
    required pw.Font font,
    required pw.Font fontBold,
    required String projectName,
    required String sectionTitle,
    required String sheetTitle,
    required String sheetCode,
    required int sheetNumber,
    required int totalSheets,
    OrganizationSettings? organization,
    String? stage,
    String? company,
    String? companyPhone,
    List<TitleBlockSignatory>? signatories,
    double scale = defaultScale,
  }) {
    // Эффективные реквизиты: приоритет — явно переданные параметры,
    // затем `organization.effective()` (подставит дефолтный бренд, если
    // пользователь ничего не вводил), и уж потом — константы.
    final org = (organization ?? const OrganizationSettings()).effective();
    final effectiveStage = stage ?? org.stage;
    final effectiveCompany = company ?? org.companyName;
    final effectiveCompanyPhone = companyPhone ?? org.companyContacts;
    final effectiveSignatories = signatories ??
        [
          for (final s in org.signatories)
            TitleBlockSignatory(role: s.role, name: s.name, date: s.date),
        ];
    // Шрифты масштабируем пропорционально, но не ниже 4.5pt — иначе
    // на печати ничего не разобрать.
    double fs(double size) => (size * scale).clamp(4.5, 999.0);
    // Длина в пт: миллиметры × коэффициент масштабирования штампа.
    double mmS(double mm) => _mm(mm) * scale;
    final base = pw.TextStyle(fontSize: fs(7), font: font);
    final baseBold = pw.TextStyle(
      fontSize: fs(7),
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final titleStyle = pw.TextStyle(
      fontSize: fs(10),
      font: fontBold,
      fontWeight: pw.FontWeight.bold,
    );
    final sectionStyle = pw.TextStyle(fontSize: fs(8), font: font);

    // Заполняем недостающие строки исполнителей пустыми — штамп всегда
    // содержит фиксированное количество строк (в форме 3 их обычно 5).
    const rows = 5;
    // Если пользователь не задал исполнителей — подставляем скелет
    // стандартных ролей по ГОСТ Р 21.101 форма 3, но без ФИО/даты
    // (ячейки останутся пустыми, их при необходимости подпишут от руки).
    final inputSignatories = effectiveSignatories.isEmpty
        ? const <TitleBlockSignatory>[
            TitleBlockSignatory(role: 'Разраб.', name: '', date: ''),
            TitleBlockSignatory(role: 'Пров.', name: '', date: ''),
            TitleBlockSignatory(role: 'Н.контр.', name: '', date: ''),
            TitleBlockSignatory(role: 'Утв.', name: '', date: ''),
          ]
        : effectiveSignatories;
    final sigs = <TitleBlockSignatory>[
      ...inputSignatories.take(rows),
      for (int i = inputSignatories.length; i < rows; i++)
        const TitleBlockSignatory(role: '', name: '', date: ''),
    ];

    pw.Widget cell({
      required pw.Widget child,
      required double widthMm,
      required double heightMm,
      pw.Alignment alignment = pw.Alignment.center,
      pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(horizontal: 2),
    }) {
      // Внутренний padding ячейки тоже масштабируем, чтобы текст не обрезался.
      final scaledPadding = pw.EdgeInsets.fromLTRB(
        padding.left * scale,
        padding.top * scale,
        padding.right * scale,
        padding.bottom * scale,
      );
      return pw.Container(
        width: mmS(widthMm),
        height: mmS(heightMm),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            width: (0.5 * scale).clamp(0.3, 0.5),
            color: PdfColors.black,
          ),
        ),
        padding: scaledPadding,
        alignment: alignment,
        child: child,
      );
    }

    // История изменений: 5 узких столбцов, 4 строки изменений.
    // Ширина ячеек: Изм(7) Кол(7) Лист(10) № док(10) Подп.(15) Дата(15) = 64 мм
    final revColumnsHeaders = <({String label, double widthMm})>[
      (label: 'Изм', widthMm: 7),
      (label: 'Кол', widthMm: 7),
      (label: 'Лист', widthMm: 10),
      (label: '№ док', widthMm: 10),
      (label: 'Подп.', widthMm: 15),
      (label: 'Дата', widthMm: 15),
    ];

    pw.Widget revisionHeader() {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          for (final c in revColumnsHeaders)
            cell(
              widthMm: c.widthMm,
              heightMm: 5,
              child: pw.Text(c.label, style: base),
            ),
        ],
      );
    }

    pw.Widget revisionRow() {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          for (final c in revColumnsHeaders)
            cell(
              widthMm: c.widthMm,
              heightMm: 5,
              child: pw.SizedBox(),
            ),
        ],
      );
    }

    // Левая часть штампа (64 мм × 30 мм) — исполнители и изменения.
    pw.Widget signatoriesBlock() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          revisionHeader(),
          for (int i = 0; i < 4; i++) revisionRow(),
          // Строки исполнителей: Должность(17) ФИО(22) Подпись(10) Дата(15).
          for (final s in sigs)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                cell(
                  widthMm: 17,
                  heightMm: 5,
                  alignment: pw.Alignment.centerLeft,
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 1),
                  child: pw.Text(s.role, style: base),
                ),
                cell(
                  widthMm: 22,
                  heightMm: 5,
                  alignment: pw.Alignment.centerLeft,
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 1),
                  child: pw.Text(s.name, style: base),
                ),
                cell(
                  widthMm: 10,
                  heightMm: 5,
                  child: pw.SizedBox(),
                ),
                cell(
                  widthMm: 15,
                  heightMm: 5,
                  child: pw.Text(s.date, style: base),
                ),
              ],
            ),
        ],
      );
    }

    // Правая часть штампа (121 мм × 55 мм) — наименования и реквизиты.
    pw.Widget titleColumn() {
      // 65 мм — название объекта + раздел + лист;
      // 40 мм — стадия / лист / листов;
      // 16 мм — реквизиты организации.
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // 70 мм — наименование объекта + раздел + лист
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              cell(
                widthMm: 70,
                heightMm: 15,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(projectName, style: titleStyle),
                ),
              ),
              cell(
                widthMm: 70,
                heightMm: 8,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(sectionTitle, style: sectionStyle),
                ),
              ),
              cell(
                widthMm: 70,
                heightMm: 27,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    sheetTitle,
                    textAlign: pw.TextAlign.center,
                    style: sectionStyle,
                  ),
                ),
              ),
              cell(
                widthMm: 70,
                heightMm: 5,
                child: pw.Text(sheetCode, style: base),
              ),
            ],
          ),
          // 51 мм — стадия / лист / листов + реквизиты
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  cell(
                    widthMm: 17,
                    heightMm: 5,
                    child: pw.Text('Стадия', style: base),
                  ),
                  cell(
                    widthMm: 17,
                    heightMm: 5,
                    child: pw.Text('Лист', style: base),
                  ),
                  cell(
                    widthMm: 17,
                    heightMm: 5,
                    child: pw.Text('Листов', style: base),
                  ),
                ],
              ),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  cell(
                    widthMm: 17,
                    heightMm: 10,
                    child: pw.Text(effectiveStage, style: baseBold),
                  ),
                  cell(
                    widthMm: 17,
                    heightMm: 10,
                    child: pw.Text('$sheetNumber', style: baseBold),
                  ),
                  cell(
                    widthMm: 17,
                    heightMm: 10,
                    child: pw.Text('$totalSheets', style: baseBold),
                  ),
                ],
              ),
              cell(
                widthMm: 51,
                heightMm: 25,
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      child: pw.Text(effectiveCompany, style: baseBold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      child: pw.Text(effectiveCompanyPhone, style: base),
                    ),
                  ],
                ),
              ),
              cell(
                widthMm: 51,
                heightMm: 15,
                child: pw.Text('', style: base),
              ),
            ],
          ),
        ],
      );
    }

    return pw.Container(
      width: mmS(widthMm),
      height: mmS(heightMm),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          width: (0.8 * scale).clamp(0.5, 0.8),
          color: PdfColors.black,
        ),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // Левая часть 64 мм (история изменений + исполнители) — ширина
          // строго равна сумме столбцов внутренних Row: 7+7+10+10+15+15
          // для шапки изменений и 17+22+10+15 для строк исполнителей.
          pw.SizedBox(
            width: mmS(64),
            height: mmS(55),
            child: signatoriesBlock(),
          ),
          // Правая часть 121 мм: 70 (название / раздел / лист / шифр)
          // + 51 (стадия/лист/листов, реквизиты организации, подпись
          // главного инженера проекта). Итого штамп 64 + 121 = 185 мм,
          // как требует ГОСТ Р 21.101 форма 3.
          pw.SizedBox(
            width: mmS(121),
            height: mmS(55),
            child: titleColumn(),
          ),
        ],
      ),
    );
  }
}

/// Одна строка исполнителей в штампе (ГАП, ГИП, Архитектор, …).
class TitleBlockSignatory {
  const TitleBlockSignatory({
    required this.role,
    required this.name,
    required this.date,
  });

  final String role;
  final String name;
  final String date;
}
