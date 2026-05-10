import 'weight_component.dart';

/// Каталог типовых постоянных нагрузок от конструктивных элементов.
///
/// Значения укрупнённые, ориентированы на первичный расчёт ИЖС и
/// полностью соответствуют подходу СП 20.13330.2016 «Нагрузки и воздействия»
/// (постоянная нагрузка = сумма собственного веса по слоям).
class PermanentLoadCalculator {
  PermanentLoadCalculator._();

  static const Map<String, WeightComponent> defaults = <String, WeightComponent>{
    // ---- стены ----
    'walls_brick': WeightComponent(
      id: 'walls_brick',
      title: 'Кирпичная кладка',
      loadKnPerM2: 3.6,
      origin: 'СП 20, прил. А: γ·b = 18 кН/м³ · 0.2 м = 3.6 кН/м²',
    ),
    'walls_aerated': WeightComponent(
      id: 'walls_aerated',
      title: 'Газобетонные блоки',
      loadKnPerM2: 1.8,
      origin: 'СП 20, прил. А: γ·b = 6 кН/м³ · 0.3 м = 1.8 кН/м²',
    ),
    'walls_timber': WeightComponent(
      id: 'walls_timber',
      title: 'Брусовые / бревенчатые стены',
      loadKnPerM2: 1.2,
      origin: 'Справочные данные для сосны плотностью 600 кг/м³ · 0.2 м',
    ),
    'walls_frame': WeightComponent(
      id: 'walls_frame',
      title: 'Каркасная стена с утеплителем',
      loadKnPerM2: 0.8,
      origin: 'Каркас + минеральная вата + обшивки OSB/гипс',
    ),

    // ---- перекрытия ----
    'floor_timber_joists': WeightComponent(
      id: 'floor_timber_joists',
      title: 'Перекрытие по деревянным балкам',
      loadKnPerM2: 1.5,
      origin: 'Сосновые балки 150·50 с шагом 600 + чистый пол + утеплитель',
    ),
    'floor_monolith': WeightComponent(
      id: 'floor_monolith',
      title: 'Монолитное ж/б перекрытие 200 мм',
      loadKnPerM2: 5.0,
      origin: 'ρ = 25 кН/м³ · 0.2 м = 5.0 кН/м²',
    ),
    'floor_precast': WeightComponent(
      id: 'floor_precast',
      title: 'Сборное ж/б перекрытие (ПК 220 мм)',
      loadKnPerM2: 3.6,
      origin: 'Типовая плита ПК: 3.0 кН/м² + пол 0.6 кН/м²',
    ),
    'floor_metal_beams': WeightComponent(
      id: 'floor_metal_beams',
      title: 'Перекрытие по стальным балкам',
      loadKnPerM2: 2.4,
      origin: 'Двутавр 20Б1 + профнастил + стяжка 60 мм',
    ),

    // ---- кровля ----
    'roof_metal_tile': WeightComponent(
      id: 'roof_metal_tile',
      title: 'Металлочерепица',
      loadKnPerM2: 0.55,
      origin: 'Покрытие 0.05 + обрешётка 0.1 + стропила 0.2 + утепл. 0.2',
    ),
    'roof_soft_bitumen': WeightComponent(
      id: 'roof_soft_bitumen',
      title: 'Битумная черепица по ОСП',
      loadKnPerM2: 0.65,
      origin: 'Покрытие 0.15 + OSB 0.1 + стропила 0.2 + утепл. 0.2',
    ),
    'roof_clay_tile': WeightComponent(
      id: 'roof_clay_tile',
      title: 'Керамическая черепица',
      loadKnPerM2: 0.95,
      origin: 'Покрытие 0.5 + обрешётка 0.1 + стропила 0.2 + утепл. 0.15',
    ),
  };
}
