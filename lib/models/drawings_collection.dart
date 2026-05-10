import 'drawing.dart';

/// Коллекция чертежей и эскизов проекта.
///
/// Поддерживает «версионность»: при перегенерации старые чертежи не
/// удаляются, а в начале списка добавляются новые. Сортировка
/// «новейшие сверху» применяется автоматически.
class DrawingsCollection {
  final List<Drawing> drawings;

  DrawingsCollection({List<Drawing>? drawings})
      : drawings = drawings ?? <Drawing>[] {
    _sort();
  }

  bool get isEmpty => drawings.isEmpty;
  int get count => drawings.length;

  String get summary {
    if (isEmpty) return 'Пока пусто';
    return 'Листов: $count';
  }

  /// Добавить новую партию чертежей (например, после перегенерации).
  void addBatch(Iterable<Drawing> batch) {
    drawings.addAll(batch);
    _sort();
  }

  void _sort() {
    drawings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Map<String, dynamic> toJson() => {
        'drawings': drawings.map((d) => d.toJson()).toList(),
      };

  static DrawingsCollection fromJson(Map<String, dynamic> json) {
    final raw = json['drawings'];
    final list = <Drawing>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map<String, dynamic>) list.add(Drawing.fromJson(v));
      }
    }
    return DrawingsCollection(drawings: list);
  }
}
