import '../data/soil_types.dart';

/// Один слой грунта в инженерно-геологическом разрезе участка.
///
/// Все поля — опциональные. Клиент обычно заполнит только тип грунта
/// и (возможно) мощность. Проектировщик внесёт физико-механические
/// показатели по результатам инженерно-геологических изысканий
/// (СП 47.13330.2016, СП 22.13330.2016).
class SoilLayer {
  /// Тип грунта верхнего/основного слоя.
  SoilType? type;

  /// Глубина залегания кровли слоя от поверхности земли, м.
  double? topDepth;

  /// Мощность слоя, м.
  double? thickness;

  // ===== Физические показатели =====

  /// ρ — плотность грунта, г/см³ (обычно 1.6 … 2.1).
  double? density;

  /// ρₛ — плотность частиц грунта, г/см³ (обычно 2.65 … 2.75).
  double? particleDensity;

  /// W — естественная влажность, доли единицы (0..1) или %, на усмотрение
  /// пользователя; для расчётов используем как введено.
  double? naturalMoisture;

  /// e — коэффициент пористости (безразм., обычно 0.5 … 1.2).
  double? voidRatio;

  /// Wₗ — влажность на границе текучести (для глинистых грунтов).
  double? liquidLimit;

  /// Wₚ — влажность на границе раскатывания (для глинистых грунтов).
  double? plasticLimit;

  /// Iₚ — число пластичности (W_L − W_P).
  double? plasticityIndex;

  /// Iₗ — показатель текучести.
  double? liquidityIndex;

  // ===== Механические показатели =====

  /// E — модуль деформации, МПа.
  double? deformationModulus;

  /// φ — угол внутреннего трения, °.
  double? frictionAngle;

  /// c — удельное сцепление, кПа.
  double? cohesion;

  SoilLayer({
    this.type,
    this.topDepth,
    this.thickness,
    this.density,
    this.particleDensity,
    this.naturalMoisture,
    this.voidRatio,
    this.liquidLimit,
    this.plasticLimit,
    this.plasticityIndex,
    this.liquidityIndex,
    this.deformationModulus,
    this.frictionAngle,
    this.cohesion,
  });

  bool get isEmpty =>
      type == null &&
      topDepth == null &&
      thickness == null &&
      density == null &&
      particleDensity == null &&
      naturalMoisture == null &&
      voidRatio == null &&
      liquidLimit == null &&
      plasticLimit == null &&
      plasticityIndex == null &&
      liquidityIndex == null &&
      deformationModulus == null &&
      frictionAngle == null &&
      cohesion == null;

  String get summary {
    final parts = <String>[];
    if (type != null) parts.add(type!.title);
    if (thickness != null) parts.add('${thickness!.toStringAsFixed(1)} м');
    if (deformationModulus != null) {
      parts.add('E ${deformationModulus!.toStringAsFixed(0)} МПа');
    }
    if (parts.isEmpty) return 'Слой не описан';
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'topDepth': topDepth,
        'thickness': thickness,
        'density': density,
        'particleDensity': particleDensity,
        'naturalMoisture': naturalMoisture,
        'voidRatio': voidRatio,
        'liquidLimit': liquidLimit,
        'plasticLimit': plasticLimit,
        'plasticityIndex': plasticityIndex,
        'liquidityIndex': liquidityIndex,
        'deformationModulus': deformationModulus,
        'frictionAngle': frictionAngle,
        'cohesion': cohesion,
      };

  static SoilLayer fromJson(Map<String, dynamic> json) {
    double? n(dynamic v) => (v as num?)?.toDouble();
    return SoilLayer(
      type: SoilType.fromName(json['type'] as String?),
      topDepth: n(json['topDepth']),
      thickness: n(json['thickness']),
      density: n(json['density']),
      particleDensity: n(json['particleDensity']),
      naturalMoisture: n(json['naturalMoisture']),
      voidRatio: n(json['voidRatio']),
      liquidLimit: n(json['liquidLimit']),
      plasticLimit: n(json['plasticLimit']),
      plasticityIndex: n(json['plasticityIndex']),
      liquidityIndex: n(json['liquidityIndex']),
      deformationModulus: n(json['deformationModulus']),
      frictionAngle: n(json['frictionAngle']),
      cohesion: n(json['cohesion']),
    );
  }
}
