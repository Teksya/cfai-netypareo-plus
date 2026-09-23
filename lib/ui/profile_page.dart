import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import 'expressive.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: const Text('Se déconnecter ?'),
        content: const Text('Tes identifiants et le planning enregistrés sur ce téléphone seront effacés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok == true && context.mounted) await AppScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final profile = state.profile;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final initials = (profile?.displayName ?? '?')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: PageHeader(title: 'Plus')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.list(
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(color: scheme.primary, shape: const CookieBorder(lobes: 10, depth: 0.06)),
                          child: Text(initials, style: text.headlineSmall?.copyWith(color: scheme.onPrimary)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile?.displayName ?? '', style: text.titleLarge?.copyWith(color: scheme.onPrimaryContainer)),
                              if (profile?.period.isNotEmpty ?? false)
                                Text(profile!.period, style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Bientôt disponible', style: text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Ces fonctions sont repérées sur NetYParéo mais pas encore testées : elles arrivent.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                const _UpcomingGrid(),
                const SizedBox(height: 24),
                Text('Compte', style: text.titleLarge),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      if (profile?.formation.isNotEmpty ?? false)
                        ListTile(
                          leading: const Icon(Icons.school_rounded),
                          title: const Text('Formation'),
                          subtitle: Text(profile!.formation),
                        ),
                      ListTile(
                        leading: const Icon(Icons.sync_rounded),
                        title: const Text('Planning synchronisé'),
                        subtitle: Text(
                          state.lastSync == null
                              ? 'Jamais'
                              : DateFormat('d MMMM \'à\' HH:mm').format(state.lastSync!),
                        ),
                        trailing: state.syncing
                            ? const ExpressiveLoader(size: 24)
                            : IconButton(
                                tooltip: 'Synchroniser',
                                onPressed: () => state.sync(force: true),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.event_note_rounded),
                        title: const Text('Cours en mémoire'),
                        subtitle: Text('${state.seances.length} séances, consultables hors ligne'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SpringPress(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogout(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Se déconnecter'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'NetYParéo+ est un projet non officiel, sans lien avec YMAG ni avec le CFA.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fonctions prévues mais pas encore prêtes : visibles, grisées, non cliquables.
class _UpcomingGrid extends StatelessWidget {
  const _UpcomingGrid();

  static const _features = [
    (Icons.grade_rounded, 'Notes et bulletin'),
    (Icons.assignment_rounded, 'Travail à faire'),
    (Icons.folder_rounded, 'Documents'),
    (Icons.date_range_rounded, 'Calendrier centre / entreprise'),
    (Icons.swap_horiz_rounded, 'Documents de liaison'),
    (Icons.notifications_active_rounded, 'Alertes de changement de cours'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        for (final (icon, label) in _features)
          Semantics(
            label: '$label, bientôt disponible',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Opacity(
                opacity: 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: scheme.onSurfaceVariant),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outline),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('Bientôt', style: text.labelSmall),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(label, style: text.titleSmall, maxLines: 2),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
