import 'package:flutter/material.dart';

import '../data/models.dart';
import '../main.dart';
import 'async_list_page.dart';
import 'expressive.dart';

class AbsencesPage extends StatelessWidget {
  const AbsencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AsyncListPage<Absence>(
      title: 'Absences',
      load: AppScope.read(context).absences,
      itemBuilder: (context, absence, _) => _AbsenceCard(absence: absence),
      empty: const EmptyState(
        icon: Icons.verified_rounded,
        title: 'Aucune absence',
        message: 'Rien à signaler sur l\'année en cours.',
      ),
    );
  }
}

class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({required this.absence});

  final Absence absence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final justified = !absence.reason.toLowerCase().contains('non justifi') && absence.reason.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: ShapeDecoration(
                color: justified ? scheme.secondaryContainer : scheme.errorContainer,
                shape: const CookieBorder(lobes: 6, depth: 0.1),
              ),
              child: Icon(
                justified ? Icons.check_rounded : Icons.priority_high_rounded,
                color: justified ? scheme.onSecondaryContainer : scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(absence.from == absence.to ? absence.from : '${absence.from} au ${absence.to}', style: text.titleMedium),
                  if (absence.reason.isNotEmpty) Text(absence.reason, style: text.bodyMedium),
                  if (absence.detail.isNotEmpty)
                    Text(absence.detail, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (absence.duration.isNotEmpty) Text(absence.duration, style: text.titleMedium?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}
