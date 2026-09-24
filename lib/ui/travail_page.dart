import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'seance_sheet.dart';
import 'theme.dart';

/// Travail à faire : les devoirs rangés par jour d'échéance, le plus proche en haut.
class TravailPage extends StatefulWidget {
  const TravailPage({super.key});

  @override
  State<TravailPage> createState() => _TravailPageState();
}

class _TravailPageState extends State<TravailPage> {
  Future<List<TravailAFaire>>? _future;
  String? _subject;
  bool _hideDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.read(context).travailAFaire();
  }

  Future<void> _refresh() async {
    final future = AppScope.read(context).travailAFaire();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<TravailAFaire>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: ExpressiveLoader());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Travail à faire indisponible',
              message: AppState.errorMessage(snapshot.error!),
              action: FilledButton.tonal(onPressed: _refresh, child: const Text('Réessayer')),
            );
          }
          return _buildList(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<TravailAFaire> all) {
    final todo = all.where((t) => !t.done).length;
    final subjects = <String, int>{};
    for (final t in all) {
      subjects[t.subject] = (subjects[t.subject] ?? 0) + 1;
    }
    final shown = all.where((t) => (_subject == null || t.subject == _subject) && !(_hideDone && t.done)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final byDay = <DateTime, List<TravailAFaire>>{};
    for (final t in shown) {
      byDay.putIfAbsent(t.dueDate, () => []).add(t);
    }

    return RefreshIndicator(
      edgeOffset: 80,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              title: 'Travail à faire',
              subtitle: switch (todo) {
                0 => 'Rien à faire, profites-en',
                1 => '1 travail à faire',
                _ => '$todo travaux à faire',
              },
            ),
          ),
          if (all.isNotEmpty)
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Tout (${all.length})'),
                      selected: _subject == null,
                      onSelected: (_) => setState(() => _subject = null),
                    ),
                    for (final entry in subjects.entries) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: subjectColors(entry.key, Theme.of(context).brightness).accent,
                          radius: 6,
                        ),
                        label: Text('${capitalizeWords(entry.key)} (${entry.value})'),
                        selected: _subject == entry.key,
                        onSelected: (_) => setState(() => _subject = entry.key),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Masquer les faits'),
                      selected: _hideDone,
                      onSelected: (on) => setState(() => _hideDone = on),
                    ),
                  ],
                ),
              ),
            ),
          if (shown.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Aucun travail à faire',
                message: 'Tire vers le bas pour vérifier à nouveau.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList.list(
                children: [
                  for (final MapEntry(key: day, value: items) in byDay.entries) ...[
                    _DueHeader(day: day, late: items.any((t) => t.late && !t.done)),
                    for (final (i, t) in items.indexed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: EnterAnimation(index: i, child: _TravailCard(travail: t, onChanged: _refresh)),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DueHeader extends StatelessWidget {
  const _DueHeader({required this.day, required this.late});

  final DateTime day;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final inDays = day.difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final relative = switch (inDays) {
      0 => 'Pour aujourd\'hui',
      1 => 'Pour demain',
      < 0 => 'En retard de ${-inDays} jour${inDays < -1 ? 's' : ''}',
      _ => 'Dans $inDays jours',
    };
    final urgent = late || inDays <= 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: urgent ? scheme.errorContainer : scheme.secondaryContainer,
              shape: const CookieBorder(lobes: 8, depth: 0.07),
            ),
            child: Text(
              '${day.day}',
              style: text.titleMedium?.copyWith(
                color: urgent ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(capitalize(DateFormat.MMMMEEEEd().format(day)), style: text.titleMedium),
                Text(
                  relative,
                  style: text.bodySmall?.copyWith(color: urgent ? scheme.error : scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TravailCard extends StatefulWidget {
  const _TravailCard({required this.travail, required this.onChanged});

  final TravailAFaire travail;
  final Future<void> Function() onChanged;

  @override
  State<_TravailCard> createState() => _TravailCardState();
}

class _TravailCardState extends State<_TravailCard> {
  bool _busy = false;

  Future<void> _toggleDone() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final t = widget.travail;
    setState(() => _busy = true);
    try {
      if (t.done) {
        await state.annulerFait(t);
      } else {
        await state.declarerFait(t);
      }
      await widget.onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppState.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final t = widget.travail;
    final colors = subjectColors(t.subject, theme.brightness);
    final seance = t.codeSeance == null
        ? null
        : AppScope.of(context).seances.where((s) => s.codeSeance == t.codeSeance).firstOrNull;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: t.done ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: colors.accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              capitalizeWords(t.subject),
                              style: text.labelLarge?.copyWith(color: colors.accent),
                            ),
                          ),
                          if (t.done)
                            _Badge(label: 'Fait', color: scheme.primary)
                          else if (t.late)
                            _Badge(label: 'En retard', color: scheme.error),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        t.content.isEmpty ? 'Pas de consigne écrite.' : t.content,
                        style: text.bodyLarge?.copyWith(
                          height: 1.4,
                          decoration: t.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (t.documents.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final doc in t.documents) AttachmentChip(link: doc)],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        [
                          if (t.givenOn.isNotEmpty) 'Donné le ${t.givenOn.toLowerCase()}',
                          if (t.teacher.isNotEmpty) 'par ${t.teacher}',
                        ].join(' '),
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (t.toHandIn && !t.done)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(Icons.upload_file_rounded, size: 16, color: scheme.tertiary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Travail à rendre : dépose ton fichier sur le site NetYParéo.',
                                  style: text.bodySmall?.copyWith(color: scheme.tertiary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (seance != null)
                            TextButton.icon(
                              onPressed: () => showSeanceSheet(context, seance),
                              icon: const Icon(Icons.event_rounded, size: 18),
                              label: const Text('Voir la séance'),
                            ),
                          const Spacer(),
                          SpringPress(
                            child: t.done
                                ? OutlinedButton.icon(
                                    onPressed: _busy || t.codeTravailFait == null ? null : _toggleDone,
                                    icon: _busy
                                        ? const ExpressiveLoader(size: 18)
                                        : const Icon(Icons.undo_rounded, size: 18),
                                    label: const Text('Pas fait'),
                                  )
                                : FilledButton.tonalIcon(
                                    onPressed: _busy ? null : _toggleDone,
                                    icon: _busy
                                        ? const ExpressiveLoader(size: 18)
                                        : const Icon(Icons.check_rounded, size: 18),
                                    label: const Text('Fait'),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      );
}
