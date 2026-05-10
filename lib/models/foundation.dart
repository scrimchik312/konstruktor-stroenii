/// Тип фундамента, выбираемый на первом шаге визарда «Частный дом».
enum FoundationType {
  pile,
  slab,
  strip,
  columnar,
  pileWithGrillage;

  String get title {
    switch (this) {
      case FoundationType.pile:
        return 'Свайный';
      case FoundationType.slab:
        return 'Плитный';
      case FoundationType.strip:
        return 'Ленточный';
      case FoundationType.columnar:
        return 'Столбчатый';
      case FoundationType.pileWithGrillage:
        return 'Сваи с ростверком';
    }
  }

  String get description {
    switch (this) {
      case FoundationType.pile:
        return 'Сваи без жёсткого верхнего обвязочного элемента.';
      case FoundationType.slab:
        return 'Сплошная плита под всей площадью здания.';
      case FoundationType.strip:
        return 'Лента под несущими стенами здания.';
      case FoundationType.columnar:
        return 'Отдельные столбы под несущими элементами.';
      case FoundationType.pileWithGrillage:
        return 'Сваи, объединённые ростверком.';
    }
  }
}

/// Конкретное устройство фундамента, выбираемое на втором шаге.
/// Набор допустимых вариантов зависит от выбранного [FoundationType].
enum FoundationDevice {
  // Свайный / сваи с ростверком
  screwPile,
  boredPile,
  // Плитный / ленточный / столбчатый
  monolithic,
  prefabricated;

  String get title {
    switch (this) {
      case FoundationDevice.screwPile:
        return 'Винтовые сваи';
      case FoundationDevice.boredPile:
        return 'Буронабивные сваи';
      case FoundationDevice.monolithic:
        return 'Монолитный';
      case FoundationDevice.prefabricated:
        return 'Сборный';
    }
  }
}

/// Материал ростверка для варианта «сваи с ростверком».
enum GrillageMaterial {
  monolithic,
  prefabricated;

  String get title {
    switch (this) {
      case GrillageMaterial.monolithic:
        return 'Монолитный ростверк';
      case GrillageMaterial.prefabricated:
        return 'Сборный ростверк';
    }
  }
}

/// Допустимые устройства для каждого типа фундамента.
List<FoundationDevice> devicesForType(FoundationType type) {
  switch (type) {
    case FoundationType.pile:
    case FoundationType.pileWithGrillage:
      return const [FoundationDevice.screwPile, FoundationDevice.boredPile];
    case FoundationType.slab:
    case FoundationType.strip:
    case FoundationType.columnar:
      return const [
        FoundationDevice.monolithic,
        FoundationDevice.prefabricated,
      ];
  }
}
