/// Желаемый материал стен.
enum WallMaterial {
  brick,
  aerated, // газобетон
  expandedClay, // керамзитоблок
  timber, // брус
  frame; // каркас

  String get title {
    switch (this) {
      case WallMaterial.brick:
        return 'Кирпич';
      case WallMaterial.aerated:
        return 'Газобетон';
      case WallMaterial.expandedClay:
        return 'Керамзитоблок';
      case WallMaterial.timber:
        return 'Брус';
      case WallMaterial.frame:
        return 'Каркас';
    }
  }

  static WallMaterial? fromName(String? name) {
    if (name == null) return null;
    for (final v in WallMaterial.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
