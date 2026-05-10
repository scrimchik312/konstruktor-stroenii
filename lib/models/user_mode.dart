/// Режим работы приложения.
///
/// От режима зависит подача интерфейса и состав выходных документов:
/// клиенту мы готовим эскизный проект, проектировщику — рабочие чертежи
/// со штампами, спецификациями и узлами по СП/ГОСТ.
enum UserMode {
  client,
  designer;

  String get title {
    switch (this) {
      case UserMode.client:
        return 'Клиент';
      case UserMode.designer:
        return 'Проектировщик';
    }
  }

  String get description {
    switch (this) {
      case UserMode.client:
        return 'Эскизный проект для согласования с проектировщиком и подрядчиком.';
      case UserMode.designer:
        return 'Рабочие чертежи со штампом, спецификациями и узлами по СП/ГОСТ.';
    }
  }

  static UserMode fromName(String name) {
    return UserMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => UserMode.client,
    );
  }
}
