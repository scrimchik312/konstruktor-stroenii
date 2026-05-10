/// Реквизиты титульного листа альбома рабочих чертежей по ГОСТ Р
/// 21.101-2020. Все поля редактируются пользователем до генерации
/// PDF. Дефолтные значения вычисляются из проекта (см.
/// [TitlePageInfo.defaults]).
class TitlePageInfo {
  /// Наименование объекта строительства (по ТЗ заказчика). Печатается
  /// крупно в верхней части листа. Пример: «Индивидуальный жилой дом».
  String objectTitle;

  /// Шифр комплекта. Пример: «29/01-2010-АС».
  String code;

  /// Наименование альбома. Пример: «Архитектурно-строительная часть».
  String albumName;

  /// Стадия проектирования: «Проектная документация» / «Рабочая
  /// документация» / «Рабочий проект».
  String stage;

  /// Город (для подписи внизу). Берётся из `project.brief.region`.
  String city;

  /// Год выпуска альбома (печатается рядом с городом).
  int year;

  TitlePageInfo({
    required this.objectTitle,
    required this.code,
    required this.albumName,
    required this.stage,
    required this.city,
    required this.year,
  });

  /// Рассчитывает дефолтные значения исходя из проекта. Все поля
  /// можно дальше править в UI. Если что-то не задано — берётся
  /// общеупотребительная подстановка.
  static TitlePageInfo defaults({
    required String projectName,
    required String? region,
    required DateTime now,
  }) {
    return TitlePageInfo(
      objectTitle: projectName.isEmpty
          ? 'Индивидуальный жилой дом'
          : projectName,
      code: '${_padNumber(now.day)}/${_padNumber(now.month)}-'
          '${now.year}-АС',
      albumName: 'Архитектурно-строительная часть',
      stage: 'Рабочий проект',
      city: (region == null || region.trim().isEmpty)
          ? 'Москва'
          : region.trim(),
      year: now.year,
    );
  }

  static String _padNumber(int n) => n.toString().padLeft(2, '0');

  TitlePageInfo copyWith({
    String? objectTitle,
    String? code,
    String? albumName,
    String? stage,
    String? city,
    int? year,
  }) {
    return TitlePageInfo(
      objectTitle: objectTitle ?? this.objectTitle,
      code: code ?? this.code,
      albumName: albumName ?? this.albumName,
      stage: stage ?? this.stage,
      city: city ?? this.city,
      year: year ?? this.year,
    );
  }

  Map<String, dynamic> toJson() => {
        'objectTitle': objectTitle,
        'code': code,
        'albumName': albumName,
        'stage': stage,
        'city': city,
        'year': year,
      };

  static TitlePageInfo fromJson(Map<String, dynamic> json) {
    return TitlePageInfo(
      objectTitle: (json['objectTitle'] as String?)?.trim().isEmpty ?? true
          ? 'Индивидуальный жилой дом'
          : json['objectTitle'] as String,
      code: (json['code'] as String?) ?? '',
      albumName:
          (json['albumName'] as String?) ?? 'Архитектурно-строительная часть',
      stage: (json['stage'] as String?) ?? 'Рабочий проект',
      city: (json['city'] as String?) ?? 'Москва',
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
    );
  }
}
