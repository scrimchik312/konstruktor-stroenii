import 'dart:convert';

/// Настройки организации, подставляемые в штамп чертежей
/// (ГОСТ Р 21.101-2020, форма 3).
///
/// Сохраняется локально (в будущем — на сервере мульти-пользовательского
/// backend). Все поля опциональны; пустые значения отображаются как
/// пустые ячейки штампа.
class OrganizationSettings {
  /// Наименование организации («ООО «Пример»»).
  final String companyName;

  /// Контакты: сайт/телефон/адрес (вторая строка блока реквизитов).
  final String companyContacts;

  /// Стадия проектирования («РП», «П», «Р»).
  final String stage;

  /// Исполнители (до 5 строк). Отображаются в левой части штампа:
  /// «Должность | Фамилия | Подпись | Дата».
  final List<OrganizationSignatory> signatories;

  const OrganizationSettings({
    this.companyName = '',
    this.companyContacts = '',
    this.stage = 'РП',
    this.signatories = const [],
  });

  /// Значения по умолчанию — подставляются, если пользователь ещё
  /// не задал собственные реквизиты. Совместимо со старым поведением
  /// (`Конструктор строений` / `konstruktor-stroenii.ru`).
  static const OrganizationSettings fallback = OrganizationSettings(
    companyName: 'Конструктор строений',
    companyContacts: 'konstruktor-stroenii.ru',
    stage: 'РП',
    signatories: [],
  );

  /// Возвращает this, если companyName непустой, иначе — [fallback].
  OrganizationSettings effective() {
    if (companyName.trim().isNotEmpty) return this;
    return fallback;
  }

  OrganizationSettings copyWith({
    String? companyName,
    String? companyContacts,
    String? stage,
    List<OrganizationSignatory>? signatories,
  }) =>
      OrganizationSettings(
        companyName: companyName ?? this.companyName,
        companyContacts: companyContacts ?? this.companyContacts,
        stage: stage ?? this.stage,
        signatories: signatories ?? this.signatories,
      );

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'companyContacts': companyContacts,
        'stage': stage,
        'signatories': signatories.map((s) => s.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static OrganizationSettings fromJson(Map<String, dynamic> j) =>
      OrganizationSettings(
        companyName: (j['companyName'] as String?) ?? '',
        companyContacts: (j['companyContacts'] as String?) ?? '',
        stage: (j['stage'] as String?) ?? 'РП',
        signatories: [
          for (final s in (j['signatories'] as List? ?? const []))
            OrganizationSignatory.fromJson(
                Map<String, dynamic>.from(s as Map)),
        ],
      );

  static OrganizationSettings? tryDecode(String payload) {
    try {
      final m = jsonDecode(payload);
      if (m is Map<String, dynamic>) return OrganizationSettings.fromJson(m);
    } catch (_) {}
    return null;
  }
}

/// Одна строка подписи в штампе («Разраб.», «Пров.», «Н.контр.», «Утв.»,
/// «ГИП» и т. п.).
class OrganizationSignatory {
  final String role;
  final String name;
  final String date;

  const OrganizationSignatory({
    required this.role,
    required this.name,
    this.date = '',
  });

  OrganizationSignatory copyWith({
    String? role,
    String? name,
    String? date,
  }) =>
      OrganizationSignatory(
        role: role ?? this.role,
        name: name ?? this.name,
        date: date ?? this.date,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        'date': date,
      };

  static OrganizationSignatory fromJson(Map<String, dynamic> j) =>
      OrganizationSignatory(
        role: (j['role'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        date: (j['date'] as String?) ?? '',
      );
}
