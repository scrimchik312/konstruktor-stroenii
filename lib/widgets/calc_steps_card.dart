import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/material.dart';

/// Карточка с журналом расчёта.
///
/// Рендерит список [CalcStep] с расширенным блоком «Откуда что взялось»
/// (input.origin) под каждой формулой. Это нужно, чтобы пользователь
/// (особенно проектировщик при проверке) видел источник каждой
/// величины: «Sg = 1.5 кН/м² — из технического задания: Москва → III снеговой район
/// по СП 20». Без этого расчёт превращается в «чёрный ящик».
class CalcStepsCard extends StatelessWidget {
  const CalcStepsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.steps,
  });

  final String title;
  final IconData icon;
  final List<CalcStep> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final s in steps) _StepBlock(step: s),
          ],
        ),
      ),
    );
  }
}

class _StepBlock extends StatelessWidget {
  const _StepBlock({required this.step});
  final CalcStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step.title,
              style: theme.textTheme.bodyMedium!
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Формула: ${step.formula}',
                    style: theme.textTheme.bodyMedium),
                Text('Подстановка: ${step.substitution}',
                    style: theme.textTheme.bodyMedium),
                Text('Результат: ${step.formattedResult}',
                    style: theme.textTheme.bodyMedium!
                        .copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (step.reference != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(step.reference!,
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: theme.colorScheme.primary)),
            ),
          if (step.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child:
                  Text(step.note!, style: theme.textTheme.bodySmall),
            ),
          if (step.inputs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
                title: Text(
                  'Откуда взяты исходные значения и какие формулы используются',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                initiallyExpanded: true,
                children: [
                  for (final inp in step.inputs)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                _InlineKey(label: inp.symbol),
                                Text(
                                  '= ${inp.value}',
                                  style: theme.textTheme.bodyMedium!
                                      .copyWith(
                                          fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              inp.origin,
                              style: theme.textTheme.bodySmall,
                            ),
                            if (inp.reference != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 2),
                                child: Text(
                                  inp.reference!,
                                  style: theme.textTheme.bodySmall!
                                      .copyWith(
                                    color: theme.colorScheme.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineKey extends StatelessWidget {
  const _InlineKey({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
