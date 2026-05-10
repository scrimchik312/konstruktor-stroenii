/// Тип чертежа.
enum DrawingKind {
  sketch, // эскиз (для клиента)
  workingPlan, // рабочий план (для проектировщика)
  workingSection, // разрез
  workingDetail, // узел
  facade, // фасад
  schematicPlan, // схематический план этажа (рисуется)
  foundationPlan; // план фундамента (с осями, размерами, маркировками)

  String get title {
    switch (this) {
      case DrawingKind.sketch:
        return 'Эскиз';
      case DrawingKind.workingPlan:
        return 'План';
      case DrawingKind.workingSection:
        return 'Разрез';
      case DrawingKind.workingDetail:
        return 'Узел';
      case DrawingKind.facade:
        return 'Фасад';
      case DrawingKind.schematicPlan:
        return 'Схематический план';
      case DrawingKind.foundationPlan:
        return 'План фундамента';
    }
  }

  static DrawingKind fromName(String? name) {
    return DrawingKind.values.firstWhere(
      (v) => v.name == name,
      orElse: () => DrawingKind.sketch,
    );
  }
}

/// Один чертёж/эскиз в проекте.
///
/// На текущей итерации [payload] хранится как простой текст (заглушка для
/// будущей реальной отрисовки). Когда мы дойдём до автогенерации,
/// поле станет, например, JSON-описанием листа в каком-то внутреннем формате.
class Drawing {
  final String id;
  final String title;
  final DrawingKind kind;
  final DateTime createdAt;

  /// Содержимое чертежа. Сейчас — короткое текстовое описание, в будущем
  /// заменится на структурированное представление листа.
  final String payload;

  /// `true`, если этот чертёж — результат ручной правки на эскизе
  /// (редактор плана в режиме «Проектировщик»). Чертежи, сгенерированные
  /// автоматически из технического задания, имеют `false`.
  final bool isManualEdit;

  Drawing({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.payload,
    this.isManualEdit = false,
  });

  Drawing copyWith({
    String? id,
    String? title,
    DrawingKind? kind,
    DateTime? createdAt,
    String? payload,
    bool? isManualEdit,
  }) =>
      Drawing(
        id: id ?? this.id,
        title: title ?? this.title,
        kind: kind ?? this.kind,
        createdAt: createdAt ?? this.createdAt,
        payload: payload ?? this.payload,
        isManualEdit: isManualEdit ?? this.isManualEdit,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        if (isManualEdit) 'isManualEdit': true,
      };

  static Drawing fromJson(Map<String, dynamic> json) => Drawing(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: DrawingKind.fromName(json['kind'] as String?),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        payload: json['payload'] as String? ?? '',
        isManualEdit: json['isManualEdit'] as bool? ?? false,
      );
}
