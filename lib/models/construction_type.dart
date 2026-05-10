/// Тип проектируемой конструкции.
///
/// На текущей итерации полностью разрабатывается только частный дом.
/// Многоквартирный дом и металлические конструкции — заглушки на будущее.
enum ConstructionType {
  privateHouse,
  apartmentBuilding,
  commercialBuilding,
  commercialStructure,
  metalStructure,
  undergroundStructure;

  String get title {
    switch (this) {
      case ConstructionType.privateHouse:
        return 'Частный дом';
      case ConstructionType.apartmentBuilding:
        return 'Многоквартирный дом';
      case ConstructionType.commercialBuilding:
        return 'Коммерческое здание';
      case ConstructionType.commercialStructure:
        return 'Коммерческое сооружение';
      case ConstructionType.metalStructure:
        return 'Металлические конструкции';
      case ConstructionType.undergroundStructure:
        return 'Подземные сооружения';
    }
  }

  bool get isImplemented => this == ConstructionType.privateHouse;

  static ConstructionType fromName(String name) {
    return ConstructionType.values.firstWhere(
      (c) => c.name == name,
      orElse: () => ConstructionType.privateHouse,
    );
  }
}
