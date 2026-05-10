/// Один пункт обоснования: причина + ссылка на нормативный документ.
class RationaleItem {
  /// Текст пояснения, например «Несущий слой — глина при 2 этажах».
  final String text;

  /// Ссылка на пункт СП, например «СП 22.13330.2016, п. 5.7».
  /// Может быть пустой, если правило конструкторское и без явной ссылки.
  final String? codeReference;

  const RationaleItem({required this.text, this.codeReference});

  Map<String, dynamic> toJson() => {
        'text': text,
        if (codeReference != null) 'codeReference': codeReference,
      };

  factory RationaleItem.fromJson(Map<String, dynamic> json) => RationaleItem(
        text: json['text'] as String? ?? '',
        codeReference: json['codeReference'] as String?,
      );
}

/// Обоснование выбора фундамента — список пунктов.
///
/// Используется в режиме «Проектировщик» для отображения подкорневой логики
/// под карточкой фундамента: какие правила сработали, какие пункты СП
/// послужили основанием. Не показывается в режиме «Клиент».
class FoundationRationale {
  final List<RationaleItem> items;

  const FoundationRationale({required this.items});

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory FoundationRationale.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List?) ?? const [];
    return FoundationRationale(
      items: [
        for (final e in list)
          if (e is Map<String, dynamic>) RationaleItem.fromJson(e),
      ],
    );
  }

  static const empty = FoundationRationale(items: []);
}
