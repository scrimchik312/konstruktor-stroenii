import 'building_footprint.dart';
import 'client_brief.dart';
import 'construction_type.dart';
import 'drawings_collection.dart';
import 'floor_slabs_design.dart';
import 'foundation_design.dart';
import 'roof_design.dart';
import 'staircase_design.dart';
import 'title_page_info.dart';
import 'walls_design.dart';

/// Корневая модель проекта.
///
/// Один [HouseProject] — это «папка» со всеми данными по одному
/// проектируемому объекту: техническое задание клиента, элементы конструктива (фундамент,
/// стены, крыша, лестница) и сгенерированные чертежи.
///
/// Принцип «единого источника правды»: любые расчёты и любые чертежи
/// строятся именно из этого объекта, а не из локального состояния отдельных
/// экранов. Это позволяет легко сохранить/восстановить проект и не
/// рассинхронизировать данные.
class HouseProject {
  final String id;
  String name;
  final ConstructionType constructionType;
  final DateTime createdAt;
  DateTime updatedAt;

  ClientBrief brief;
  FoundationDesign foundation;
  WallsDesign walls;
  FloorSlabsDesign floorSlabs;
  RoofDesign roof;
  StaircaseDesign staircase;
  DrawingsCollection drawings;
  TitlePageInfo titlePage;

  /// Полигональный контур пятна застройки на уровне всего проекта
  /// (Phase-3b §17.2.1). Если задан — все этажи, генерируемые из
  /// этого проекта, наследуют этот контур (по умолчанию). Если `null` —
  /// проект остаётся прямоугольным с габаритами `brief.footprintWidth ×
  /// brief.footprintLength` (старая совместимая модель v64.x). Поле
  /// сериализуется в JSON, поэтому миграция старых проектов проходит
  /// без потерь — отсутствующее поле трактуется как `null`.
  BuildingFootprint? architectureFootprint;

  /// Эффективный полигон пятна застройки: либо явно заданный
  /// `architectureFootprint`, либо прямоугольник
  /// `brief.footprintWidth × brief.footprintLength`. Используется
  /// генератором планов и расчётом ТЭП.
  BuildingFootprint get effectiveArchitectureFootprint {
    final fp = architectureFootprint;
    if (fp != null) return fp;
    final w = brief.footprintWidth ?? 0;
    final h = brief.footprintLength ?? 0;
    if (w <= 0 || h <= 0) {
      return BuildingFootprint.rect(10, 8);
    }
    return BuildingFootprint.rect(w, h);
  }

  /// Ручные правки цен в смете: ключ — `PriceItem.id`, значение —
  /// цена в ₽/ед. Если строка переопределена, при пересчёте сметы
  /// этот ключ берётся вместо `basePrice`. Региональный коэффициент
  /// применяется уже к итогу.
  ///
  /// Сохраняется в JSON и переживает перезагрузку приложения.
  final Map<String, double> priceOverrides;

  /// Ручной выбор единицы измерения для строки сметы:
  /// ключ — `PriceItem.id`, значение — подпись варианта из
  /// `kUnitVariants[id]`. Если ключа нет — используется базовая
  /// единица из `kPriceCatalog`.
  ///
  /// При смене единицы количество умножается на `factor`, а цена
  /// делится на `factor` — итог по строке (qty × price) остаётся
  /// тем же. Это гарантирует целостность связанных расчётов:
  /// физический объём заказа не меняется, меняется только подача.
  final Map<String, String> unitOverrides;

  /// Phase-3b §17.2.3 — список предупреждений, накопленных в
  /// процессе работы над проектом. Например:
  /// «Этаж 1, спальня недоступна — путь шириной < 0.9 м».
  /// Сейчас наполняется только из `ReachabilityValidator`, в будущем
  /// сюда добавятся пред-проверки конструктива (фундамент / кровля
  /// без расчёта). Поле сериализуется в JSON.
  final List<String> warnings;

  HouseProject({
    required this.id,
    required this.name,
    required this.constructionType,
    required this.createdAt,
    required this.updatedAt,
    ClientBrief? brief,
    FoundationDesign? foundation,
    WallsDesign? walls,
    FloorSlabsDesign? floorSlabs,
    RoofDesign? roof,
    StaircaseDesign? staircase,
    DrawingsCollection? drawings,
    TitlePageInfo? titlePage,
    this.architectureFootprint,
    Map<String, double>? priceOverrides,
    Map<String, String>? unitOverrides,
    List<String>? warnings,
  })  : brief = brief ?? ClientBrief(),
        foundation = foundation ?? FoundationDesign(),
        walls = walls ?? WallsDesign(),
        floorSlabs = floorSlabs ?? FloorSlabsDesign(),
        roof = roof ?? RoofDesign(),
        staircase = staircase ?? StaircaseDesign(),
        drawings = drawings ?? DrawingsCollection(),
        titlePage = titlePage ??
            TitlePageInfo.defaults(
              projectName: name,
              region: (brief ?? ClientBrief()).region,
              now: createdAt,
            ),
        priceOverrides = priceOverrides ?? <String, double>{},
        unitOverrides = unitOverrides ?? <String, String>{},
        warnings = warnings ?? <String>[];

  void touch() {
    updatedAt = DateTime.now();
  }

  /// Какие конструктивные элементы должны быть в составе сооружения.
  /// Лестница появляется только если её нужно строить (см. техническое задание).
  bool get includesStaircase => brief.requiresStaircase;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'constructionType': constructionType.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'brief': brief.toJson(),
        'foundation': foundation.toJson(),
        'walls': walls.toJson(),
        'floorSlabs': floorSlabs.toJson(),
        'roof': roof.toJson(),
        'staircase': staircase.toJson(),
        'drawings': drawings.toJson(),
        'titlePage': titlePage.toJson(),
        if (architectureFootprint != null)
          'architectureFootprint': architectureFootprint!.toJson(),
        if (priceOverrides.isNotEmpty) 'priceOverrides': priceOverrides,
        if (unitOverrides.isNotEmpty) 'unitOverrides': unitOverrides,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  static HouseProject fromJson(Map<String, dynamic> json) {
    return HouseProject(
      id: json['id'] as String,
      name: json['name'] as String,
      constructionType: ConstructionType.fromName(
        json['constructionType'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      brief: json['brief'] is Map<String, dynamic>
          ? ClientBrief.fromJson(json['brief'] as Map<String, dynamic>)
          : ClientBrief(),
      foundation: json['foundation'] is Map<String, dynamic>
          ? FoundationDesign.fromJson(
              json['foundation'] as Map<String, dynamic>,
            )
          : FoundationDesign(),
      walls: json['walls'] is Map<String, dynamic>
          ? WallsDesign.fromJson(json['walls'] as Map<String, dynamic>)
          : WallsDesign(),
      floorSlabs: json['floorSlabs'] is Map<String, dynamic>
          ? FloorSlabsDesign.fromJson(
              json['floorSlabs'] as Map<String, dynamic>,
            )
          : FloorSlabsDesign(),
      roof: json['roof'] is Map<String, dynamic>
          ? RoofDesign.fromJson(json['roof'] as Map<String, dynamic>)
          : RoofDesign(),
      staircase: json['staircase'] is Map<String, dynamic>
          ? StaircaseDesign.fromJson(json['staircase'] as Map<String, dynamic>)
          : StaircaseDesign(),
      drawings: json['drawings'] is Map<String, dynamic>
          ? DrawingsCollection.fromJson(
              json['drawings'] as Map<String, dynamic>,
            )
          : DrawingsCollection(),
      titlePage: json['titlePage'] is Map<String, dynamic>
          ? TitlePageInfo.fromJson(
              json['titlePage'] as Map<String, dynamic>,
            )
          : null,
      architectureFootprint: json['architectureFootprint'] is Map<String, dynamic>
          ? BuildingFootprint.fromJson(
              Map<String, dynamic>.from(
                json['architectureFootprint'] as Map,
              ),
            )
          : null,
      priceOverrides: json['priceOverrides'] is Map
          ? <String, double>{
              for (final e in (json['priceOverrides'] as Map).entries)
                if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
            }
          : <String, double>{},
      unitOverrides: json['unitOverrides'] is Map
          ? <String, String>{
              for (final e in (json['unitOverrides'] as Map).entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            }
          : <String, String>{},
      // §17.2.3: backward-compat — старые проекты без 'warnings'
      // десериализуются как пустой список.
      warnings: json['warnings'] is List
          ? <String>[
              for (final w in json['warnings'] as List)
                if (w != null) w.toString(),
            ]
          : <String>[],
    );
  }
}
