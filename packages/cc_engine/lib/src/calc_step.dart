/// Один шаг расчёта, пригодный для отображения в UI и PDF.
///
/// Такой шаг — это одна строка «вычислил: формула → подстановка → результат
/// со ссылкой на пункт СП и набором исходных величин». Показ одинаковой
/// структуры на экране и в пояснительной записке гарантирует, что данные
/// не разъедутся между UI и документом.
class CalcStep {
  const CalcStep({
    required this.title,
    required this.formula,
    required this.substitution,
    required this.formattedResult,
    this.reference,
    this.note,
    this.inputs = const [],
  });

  /// Заголовок шага, например «Снеговая нагрузка».
  final String title;

  /// Символьная запись формулы, например `S = Sg · μ · ce · ct`.
  final String formula;

  /// Подстановка конкретных чисел, например `S = 1.5 · 1.0 · 1.0 · 1.0`.
  final String substitution;

  /// Готовый форматированный результат, например `S = 1.50 кН/м²`.
  final String formattedResult;

  /// Ссылка на пункт СП / формулу, если применимо.
  final String? reference;

  /// Свободный комментарий (исключения, допущения).
  final String? note;

  /// Исходные величины для шага — позволяет пользователю увидеть «откуда
  /// взялось каждое число».
  final List<CalcInput> inputs;
}

/// Одна исходная величина для [CalcStep].
class CalcInput {
  const CalcInput({
    required this.symbol,
    required this.value,
    required this.origin,
    this.reference,
  });

  /// Символ переменной, например `Sg`.
  final String symbol;

  /// Отформатированное значение + единицы, например `1.5 кН/м²`.
  final String value;

  /// Откуда взяли: «из ТЗ → Москва → III район по СП 20».
  final String origin;

  /// Необязательная ссылка на СП / таблицу / пункт.
  final String? reference;
}
