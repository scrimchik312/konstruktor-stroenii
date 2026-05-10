/// Библиотека строительных материалов и сортаментов.
///
/// Все значения — справочные, по действующим российским стандартам:
/// - бетон: ГОСТ 26633-2015, СП 63.13330.2018;
/// - арматура: ГОСТ 34028-2016, СП 63.13330.2018;
/// - сталь профильная: ГОСТ 8239-89 (двутавр), ГОСТ 8240-97 (швеллер),
///   ГОСТ 8509-93 (равнополочный уголок);
/// - стеновые материалы: ГОСТ 530-2012 (кирпич), ГОСТ 31360-2007
///   (автоклавный газобетон), ГОСТ 6133-2019 (бетонные стеновые камни);
/// - кровельные материалы: ГОСТ Р 58153-2018 (металлочерепица),
///   ГОСТ 30547-97 (битумные рулонные), ГОСТ 24045-2016 (профлист);
/// - утеплители: ГОСТ 4640-2011 (минеральная вата), ГОСТ 15588-2014
///   (пенополистирол).
///
/// Используется на странице «Спецификация материалов» в PDF и при
/// расчётах нагрузок / подборе сечений (для подстановки физических и
/// механических характеристик).

/// Класс прочности бетона на сжатие.
class ConcreteGrade {
  /// Маркировка по ГОСТ (B7.5, B15, B20, B25, B30, B35, …).
  final String grade;

  /// Расчётное сопротивление осевому сжатию Rb, МПа (СП 63.13330.2018).
  final double rb;

  /// Расчётное сопротивление осевому растяжению Rbt, МПа.
  final double rbt;

  /// Начальный модуль упругости Eb, ГПа.
  final double eb;

  /// Соответствует марке по прочности (М-маркировка, СП).
  final String mGrade;

  /// Типичное применение.
  final String useCase;

  const ConcreteGrade({
    required this.grade,
    required this.rb,
    required this.rbt,
    required this.eb,
    required this.mGrade,
    required this.useCase,
  });
}

/// Каталог классов бетона.
const List<ConcreteGrade> concreteGrades = [
  ConcreteGrade(
    grade: 'B7,5',
    rb: 4.5,
    rbt: 0.48,
    eb: 16,
    mGrade: 'M100',
    useCase: 'Подбетонка, бетонная подготовка под фундамент',
  ),
  ConcreteGrade(
    grade: 'B15',
    rb: 8.5,
    rbt: 0.75,
    eb: 24,
    mGrade: 'M200',
    useCase: 'Малоэтажные ленточные фундаменты, отмостки, крыльцо',
  ),
  ConcreteGrade(
    grade: 'B20',
    rb: 11.5,
    rbt: 0.90,
    eb: 27.5,
    mGrade: 'M250',
    useCase: 'Ленточные/плитные фундаменты ИЖС, монолитные перекрытия',
  ),
  ConcreteGrade(
    grade: 'B25',
    rb: 14.5,
    rbt: 1.05,
    eb: 30,
    mGrade: 'M350',
    useCase: 'Плитные фундаменты, плиты перекрытия, армокаркас',
  ),
  ConcreteGrade(
    grade: 'B30',
    rb: 17.0,
    rbt: 1.15,
    eb: 32.5,
    mGrade: 'M400',
    useCase: 'Колонны, ригели многоэтажных зданий',
  ),
  ConcreteGrade(
    grade: 'B35',
    rb: 19.5,
    rbt: 1.30,
    eb: 34.5,
    mGrade: 'M450',
    useCase: 'Монолитные конструкции с большой нагрузкой, сваи',
  ),
];

/// Класс арматурной стали (ГОСТ 34028-2016).
class RebarGrade {
  /// Класс по ГОСТ (A240, A400, A500С, B500С, …).
  final String grade;

  /// Расчётное сопротивление растяжению Rs, МПа.
  final double rs;

  /// Соответствие старым обозначениям (A-I, A-III, …).
  final String legacy;

  /// Типичное применение.
  final String useCase;

  /// Доступные диаметры, мм.
  final List<int> diameters;

  const RebarGrade({
    required this.grade,
    required this.rs,
    required this.legacy,
    required this.useCase,
    required this.diameters,
  });
}

/// Каталог классов арматуры.
const List<RebarGrade> rebarGrades = [
  RebarGrade(
    grade: 'A240 (A-I)',
    rs: 215,
    legacy: 'A-I',
    useCase: 'Гладкая, конструктивная арматура, хомуты, монтажные петли',
    diameters: [6, 8, 10, 12],
  ),
  RebarGrade(
    grade: 'A400 (A-III)',
    rs: 365,
    legacy: 'A-III',
    useCase: 'Рабочая арматура железобетонных конструкций',
    diameters: [6, 8, 10, 12, 14, 16, 18, 20, 22, 25, 28, 32, 36, 40],
  ),
  RebarGrade(
    grade: 'A500С',
    rs: 435,
    legacy: '—',
    useCase: 'Современная свариваемая рабочая арматура (стандарт ИЖС)',
    diameters: [6, 8, 10, 12, 14, 16, 18, 20, 22, 25, 28, 32, 36, 40],
  ),
  RebarGrade(
    grade: 'A600',
    rs: 520,
    legacy: 'A-IV',
    useCase: 'Высокопрочная рабочая арматура',
    diameters: [10, 12, 14, 16, 18, 20, 22, 25, 28, 32, 36, 40],
  ),
  RebarGrade(
    grade: 'B500С',
    rs: 435,
    legacy: 'B-III (хол.)',
    useCase: 'Холоднотянутая, кладочные сетки, тонкостенные конструкции',
    diameters: [4, 5, 6, 8, 10, 12],
  ),
];

/// Сортамент горячекатаного двутавра (ГОСТ 8239-89, фрагмент).
class IBeamProfile {
  final String name; // Например, '20Б1'
  final double heightMm;
  final double widthMm;
  final double webThicknessMm;
  final double flangeThicknessMm;
  final double linearMassKgM;
  final double iX_cm4; // момент инерции относительно X-X
  final double wX_cm3; // момент сопротивления X-X
  const IBeamProfile({
    required this.name,
    required this.heightMm,
    required this.widthMm,
    required this.webThicknessMm,
    required this.flangeThicknessMm,
    required this.linearMassKgM,
    required this.iX_cm4,
    required this.wX_cm3,
  });
}

/// Базовый сортамент двутавров (балочный профиль Б).
const List<IBeamProfile> iBeamProfiles = [
  IBeamProfile(
    name: '10Б1',
    heightMm: 100,
    widthMm: 55,
    webThicknessMm: 4.1,
    flangeThicknessMm: 5.7,
    linearMassKgM: 8.10,
    iX_cm4: 171,
    wX_cm3: 34.2,
  ),
  IBeamProfile(
    name: '12Б1',
    heightMm: 120,
    widthMm: 64,
    webThicknessMm: 4.4,
    flangeThicknessMm: 6.3,
    linearMassKgM: 11.0,
    iX_cm4: 318,
    wX_cm3: 53.0,
  ),
  IBeamProfile(
    name: '14Б1',
    heightMm: 140,
    widthMm: 73,
    webThicknessMm: 4.7,
    flangeThicknessMm: 6.9,
    linearMassKgM: 13.7,
    iX_cm4: 541,
    wX_cm3: 77.3,
  ),
  IBeamProfile(
    name: '16Б1',
    heightMm: 160,
    widthMm: 82,
    webThicknessMm: 5.0,
    flangeThicknessMm: 7.4,
    linearMassKgM: 17.0,
    iX_cm4: 869,
    wX_cm3: 109,
  ),
  IBeamProfile(
    name: '18Б1',
    heightMm: 180,
    widthMm: 91,
    webThicknessMm: 5.3,
    flangeThicknessMm: 8.0,
    linearMassKgM: 19.4,
    iX_cm4: 1290,
    wX_cm3: 143,
  ),
  IBeamProfile(
    name: '20Б1',
    heightMm: 200,
    widthMm: 100,
    webThicknessMm: 5.6,
    flangeThicknessMm: 8.5,
    linearMassKgM: 22.4,
    iX_cm4: 1844,
    wX_cm3: 184,
  ),
  IBeamProfile(
    name: '25Б1',
    heightMm: 248,
    widthMm: 124,
    webThicknessMm: 5.0,
    flangeThicknessMm: 8.0,
    linearMassKgM: 25.7,
    iX_cm4: 2996,
    wX_cm3: 242,
  ),
  IBeamProfile(
    name: '30Б1',
    heightMm: 296,
    widthMm: 140,
    webThicknessMm: 5.8,
    flangeThicknessMm: 8.5,
    linearMassKgM: 32.9,
    iX_cm4: 5260,
    wX_cm3: 356,
  ),
];

/// Кладочные стеновые материалы.
class WallMaterialSpec {
  final String key;
  final String title;
  final String standard; // ГОСТ
  final double densityKgM3; // средняя плотность ρ
  final double thermalConductivity; // λ при условиях эксплуатации Б, Вт/(м·К)
  final double compressiveStrengthMpa; // прочность на сжатие, МПа
  final String typicalSize; // 250×120×65 мм и т. п.
  final String useCase;
  const WallMaterialSpec({
    required this.key,
    required this.title,
    required this.standard,
    required this.densityKgM3,
    required this.thermalConductivity,
    required this.compressiveStrengthMpa,
    required this.typicalSize,
    required this.useCase,
  });
}

/// Каталог стеновых материалов.
const List<WallMaterialSpec> wallMaterialsLibrary = [
  WallMaterialSpec(
    key: 'brick_solid',
    title: 'Кирпич керамический полнотелый М150',
    standard: 'ГОСТ 530-2012',
    densityKgM3: 1800,
    thermalConductivity: 0.81,
    compressiveStrengthMpa: 15.0,
    typicalSize: '250×120×65 мм',
    useCase: 'Несущие стены, цоколь, дымовые трубы',
  ),
  WallMaterialSpec(
    key: 'brick_hollow',
    title: 'Кирпич керамический пустотелый М125',
    standard: 'ГОСТ 530-2012',
    densityKgM3: 1400,
    thermalConductivity: 0.50,
    compressiveStrengthMpa: 12.5,
    typicalSize: '250×120×88 мм',
    useCase: 'Самонесущие и наружные стены ИЖС',
  ),
  WallMaterialSpec(
    key: 'aerated_d500',
    title: 'Газобетон автоклавный D500 B2,5',
    standard: 'ГОСТ 31360-2007',
    densityKgM3: 500,
    thermalConductivity: 0.14,
    compressiveStrengthMpa: 2.5,
    typicalSize: '600×300×250 мм',
    useCase: 'Несущие наружные стены до 3-х этажей, ИЖС',
  ),
  WallMaterialSpec(
    key: 'aerated_d600',
    title: 'Газобетон автоклавный D600 B3,5',
    standard: 'ГОСТ 31360-2007',
    densityKgM3: 600,
    thermalConductivity: 0.18,
    compressiveStrengthMpa: 3.5,
    typicalSize: '600×300×250 мм',
    useCase: 'Несущие стены 2–3 этажа, перегородки',
  ),
  WallMaterialSpec(
    key: 'foam_d600',
    title: 'Пенобетон D600 B2,0',
    standard: 'ГОСТ 25485-2019',
    densityKgM3: 600,
    thermalConductivity: 0.20,
    compressiveStrengthMpa: 2.0,
    typicalSize: '600×300×200 мм',
    useCase: 'Самонесущие стены, утепляющий слой',
  ),
  WallMaterialSpec(
    key: 'expanded_clay',
    title: 'Керамзитобетонный блок D1000',
    standard: 'ГОСТ 6133-2019',
    densityKgM3: 1000,
    thermalConductivity: 0.41,
    compressiveStrengthMpa: 3.5,
    typicalSize: '390×190×188 мм',
    useCase: 'Несущие стены ИЖС, цокольный этаж',
  ),
  WallMaterialSpec(
    key: 'timber_glulam',
    title: 'Клеёный брус (сосна) КБ150',
    standard: 'ГОСТ 20850-2014',
    densityKgM3: 500,
    thermalConductivity: 0.18,
    compressiveStrengthMpa: 25.0,
    typicalSize: '180×200×6000 мм',
    useCase: 'Несущие стены деревянных домов, балки',
  ),
  WallMaterialSpec(
    key: 'timber_solid',
    title: 'Брус естественной влажности (сосна)',
    standard: 'ГОСТ 8486-86',
    densityKgM3: 520,
    thermalConductivity: 0.18,
    compressiveStrengthMpa: 30.0,
    typicalSize: '150×150×6000 мм',
    useCase: 'Несущие стены ИЖС, бани, каркасы',
  ),
  WallMaterialSpec(
    key: 'log',
    title: 'Бревно оцилиндрованное (сосна) Ø220 мм',
    standard: 'ГОСТ Р 56711-2015',
    densityKgM3: 520,
    thermalConductivity: 0.18,
    compressiveStrengthMpa: 28.0,
    typicalSize: 'Ø220×6000 мм',
    useCase: 'Срубы, бани',
  ),
  WallMaterialSpec(
    key: 'frame_sip',
    title: 'СИП-панель 174 мм (OSB-3 + ППС)',
    standard: 'ГОСТ Р 56935-2016',
    densityKgM3: 60,
    thermalConductivity: 0.041,
    compressiveStrengthMpa: 0.18,
    typicalSize: '2500×1250×174 мм',
    useCase: 'Каркасные дома, утепление наружных стен',
  ),
];

/// Кровельные материалы.
class RoofMaterialSpec {
  final String key;
  final String title;
  final String standard;
  final double weightKgM2; // удельный вес покрытия
  final double minSlopeDeg; // минимальный уклон ската, градусы
  final double servicePeriodYears;
  final String useCase;
  const RoofMaterialSpec({
    required this.key,
    required this.title,
    required this.standard,
    required this.weightKgM2,
    required this.minSlopeDeg,
    required this.servicePeriodYears,
    required this.useCase,
  });
}

const List<RoofMaterialSpec> roofMaterialsLibrary = [
  RoofMaterialSpec(
    key: 'metal_tile',
    title: 'Металлочерепица 0,5 мм с полимерным покрытием',
    standard: 'ГОСТ Р 58153-2018',
    weightKgM2: 5.0,
    minSlopeDeg: 14,
    servicePeriodYears: 30,
    useCase: 'Скатные кровли ИЖС, садовые дома',
  ),
  RoofMaterialSpec(
    key: 'profile_sheet',
    title: 'Профлист C21, 0,5 мм оцинкованный',
    standard: 'ГОСТ 24045-2016',
    weightKgM2: 5.4,
    minSlopeDeg: 8,
    servicePeriodYears: 25,
    useCase: 'Скатные кровли хоз. построек, гаражей',
  ),
  RoofMaterialSpec(
    key: 'soft_tile',
    title: 'Гибкая (битумная) черепица 4 мм',
    standard: 'ГОСТ Р 32806-2014',
    weightKgM2: 9.0,
    minSlopeDeg: 12,
    servicePeriodYears: 25,
    useCase: 'Скатные кровли сложной формы, ИЖС',
  ),
  RoofMaterialSpec(
    key: 'ceramic_tile',
    title: 'Натуральная керамическая черепица',
    standard: 'ГОСТ Р 56688-2015',
    weightKgM2: 45.0,
    minSlopeDeg: 22,
    servicePeriodYears: 100,
    useCase: 'Скатные кровли ИЖС, премиум-класс',
  ),
  RoofMaterialSpec(
    key: 'cement_tile',
    title: 'Цементно-песчаная черепица',
    standard: 'ГОСТ Р 58390-2019',
    weightKgM2: 42.0,
    minSlopeDeg: 22,
    servicePeriodYears: 50,
    useCase: 'Скатные кровли коттеджей',
  ),
  RoofMaterialSpec(
    key: 'rolled_bitumen',
    title: 'Рулонные битумно-полимерные материалы',
    standard: 'ГОСТ 30547-97',
    weightKgM2: 5.0,
    minSlopeDeg: 0,
    servicePeriodYears: 15,
    useCase: 'Плоские кровли многоквартирных и общественных зданий',
  ),
  RoofMaterialSpec(
    key: 'pvc_membrane',
    title: 'ПВХ-мембрана 1,5 мм',
    standard: 'ГОСТ Р 56586-2015',
    weightKgM2: 1.8,
    minSlopeDeg: 0,
    servicePeriodYears: 25,
    useCase: 'Плоские кровли ангарного типа',
  ),
  RoofMaterialSpec(
    key: 'seam_metal',
    title: 'Кровля фальцевая (сталь оцинк. 0,5 мм)',
    standard: 'ГОСТ 14918-80',
    weightKgM2: 4.5,
    minSlopeDeg: 7,
    servicePeriodYears: 50,
    useCase: 'Скатные кровли любых уклонов',
  ),
];

/// Теплоизоляционные материалы.
class InsulationMaterialSpec {
  final String key;
  final String title;
  final String standard;
  final double densityKgM3;
  final double thermalConductivity; // λ-Б
  final String typicalSize;
  final String useCase;
  const InsulationMaterialSpec({
    required this.key,
    required this.title,
    required this.standard,
    required this.densityKgM3,
    required this.thermalConductivity,
    required this.typicalSize,
    required this.useCase,
  });
}

const List<InsulationMaterialSpec> insulationLibrary = [
  InsulationMaterialSpec(
    key: 'mineral_wool_basalt',
    title: 'Минвата базальтовая 80 кг/м³',
    standard: 'ГОСТ 4640-2011',
    densityKgM3: 80,
    thermalConductivity: 0.040,
    typicalSize: '1200×600×100 мм',
    useCase: 'Утепление стен, кровель, перекрытий',
  ),
  InsulationMaterialSpec(
    key: 'mineral_wool_glass',
    title: 'Стекловата 15 кг/м³',
    standard: 'ГОСТ 4640-2011',
    densityKgM3: 15,
    thermalConductivity: 0.040,
    typicalSize: '1200×600×50 мм',
    useCase: 'Утепление мансард, лёгких перегородок',
  ),
  InsulationMaterialSpec(
    key: 'eps_25',
    title: 'Пенополистирол ППС-25',
    standard: 'ГОСТ 15588-2014',
    densityKgM3: 25,
    thermalConductivity: 0.039,
    typicalSize: '1000×1000×50 мм',
    useCase: 'Утепление цоколя, стен, кровель ИЖС',
  ),
  InsulationMaterialSpec(
    key: 'xps',
    title: 'Экструдированный пенополистирол ХПС-35',
    standard: 'ГОСТ 32310-2020',
    densityKgM3: 35,
    thermalConductivity: 0.030,
    typicalSize: '1185×585×50 мм',
    useCase: 'Утепление фундаментов, отмостки, плоских кровель',
  ),
  InsulationMaterialSpec(
    key: 'pir',
    title: 'PIR-плита 30 кг/м³',
    standard: 'ГОСТ Р 56590-2015',
    densityKgM3: 30,
    thermalConductivity: 0.022,
    typicalSize: '1200×600×50 мм',
    useCase: 'Высокоэффективное утепление кровель и стен',
  ),
];
