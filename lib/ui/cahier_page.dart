import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'seance_sheet.dart';
import 'theme.dart';

/// Cahier de textes des dernières semaines : une frise par jour, du plus récent au plus ancien,
/// filtrable par matière.
class CahierPage extends StatefulWidget {
  const CahierPage({super.key});

  @override
  State<CahierPage> createState() => _CahierPageState();
}

class _CahierPageState extends State<CahierPage> {
  late Future<List<CahierEntry>> _future = AppScope.read(context).cahierDeTextes();
  String? _subject;
  bool _upcoming = false;

  /// Plus proches d'aujourd'hui en premier (la plus récente, ou la prochaine), sinon l'inverse.
  bool _nearestFirst = true;

  Future<void> _refresh() async {
    final future = AppScope.read(context).cahierDeTextes();
    setState(() {
      _future = future;
    });
    await future.catchError((_) => <CahierEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 80,
        child: FutureBuilder<List<CahierEntry>>(
          future: _future,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <CahierEntry>[];
            final loading = snapshot.connectionState != ConnectionState.done;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: PageHeader(
                    title: 'Cahier de textes',
                    subtitle: loading || entries.isEmpty ? null : '${entries.length} séances saisies',
                  ),
                ),
                if (loading)
                  const SliverFillRemaining(child: Center(child: ExpressiveLoader()))
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Chargement impossible',
                      message: AppState.errorMessage(snapshot.error!),
                      action: FilledButton.tonal(onPressed: _refresh, child: const Text('Réessayer')),
                    ),
                  )
                else if (entries.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.menu_book_rounded,
                      title: 'Cahier vide',
                      message: 'Aucun contenu saisi par les formateurs sur les dernières semaines.',
                    ),
                  )
                else ...() {
                  final now = DateTime.now();
                  final past = entries.where((e) => e.date == null || !e.date!.isAfter(now)).toList();
                  // Les formateurs saisissent parfois l'année entière à l'avance : à venir = la plus proche d'abord.
                  final upcoming = entries.where((e) => e.date != null && e.date!.isAfter(now)).toList().reversed.toList();
                  final nearest = _upcoming ? upcoming : past;
                  final shown = _nearestFirst ? nearest : nearest.reversed.toList();
                  final filtered = shown.where((e) => _subject == null || e.subject == _subject).toList();
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(value: false, icon: const Icon(Icons.history_rounded), label: Text('Passées (${past.length})')),
                            ButtonSegment(value: true, icon: const Icon(Icons.upcoming_rounded), label: Text('À venir (${upcoming.length})')),
                          ],
                          selected: {_upcoming},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => setState(() {
                            _upcoming = s.first;
                            _subject = null;
                          }),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SubjectFilter(entries: shown, selected: _subject, onSelect: (s) => setState(() => _subject = s)),
                    ),
                    SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: TextButton.icon(
                            onPressed: () => setState(() => _nearestFirst = !_nearestFirst),
                            icon: const Icon(Icons.swap_vert_rounded),
                            label: Text(_nearestFirst ? 'Plus proches d\'abord' : 'Plus lointaines d\'abord'),
                          ),
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: _upcoming ? Icons.upcoming_rounded : Icons.history_rounded,
                          title: _upcoming ? 'Rien de prévu' : 'Rien pour l\'instant',
                        ),
                      )
                    else
                      ..._timeline(filtered),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ];
                }(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Une section par jour : en-tête de date, puis les séances du jour.
  List<Widget> _timeline(List<CahierEntry> entries) {
    final days = <DateTime?, List<CahierEntry>>{};
    for (final e in entries) {
      days.putIfAbsent(e.date == null ? null : DateUtils.dateOnly(e.date!), () => []).add(e);
    }
    var index = 0;
    return [
      for (final day in days.entries) ...[
        SliverToBoxAdapter(child: _DayHeader(day: day.key)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: day.value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => EnterAnimation(index: index++, child: _EntryTile(entry: day.value[i])),
          ),
        ),
      ],
    ];
  }
}

class _SubjectFilter extends StatelessWidget {
  const _SubjectFilter({required this.entries, required this.selected, required this.onSelect});

  final List<CahierEntry> entries;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final counts = <String, int>{};
    for (final e in entries) {
      counts[e.subject] = (counts[e.subject] ?? 0) + 1;
    }
    final subjects = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ChoiceChip(
            label: Text('Tout (${entries.length})'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
            shape: const StadiumBorder(),
          ),
          for (final s in subjects)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                avatar: CircleAvatar(backgroundColor: subjectColors(s, brightness).accent, radius: 6),
                label: Text('${capitalizeWords(s)} (${counts[s]})'),
                selected: selected == s,
                onSelected: (_) => onSelect(selected == s ? null : s),
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final d = day;
    final ago = d == null ? 0 : today.difference(d).inDays;
    final relative = switch (ago) {
      0 => 'Aujourd\'hui',
      1 => 'Hier',
      -1 => 'Demain',
      < 0 => 'Dans ${-ago} jours',
      _ => 'Il y a $ago jours',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: ago == 0 ? scheme.primary : scheme.secondaryContainer,
              shape: const CookieBorder(lobes: 8, depth: 0.07),
            ),
            child: Text(
              d == null ? '?' : '${d.day}',
              style: text.titleMedium?.copyWith(
                color: ago == 0 ? scheme.onPrimary : scheme.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d == null ? 'Date inconnue' : capitalize(DateFormat.MMMMEEEEd().format(d)), style: text.titleMedium),
                if (d != null) Text(relative, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final CahierEntry entry;

  String get _hours {
    final m = RegExp(r'de (\d{1,2}h\d{2}) à (\d{1,2}h\d{2})').firstMatch(entry.when);
    return m == null ? '' : '${m.group(1)} - ${m.group(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final colors = subjectColors(entry.subject, theme.brightness);
    final preview = entry.content == entry.title
        ? ''
        : entry.content
            .split('\n')
            .map((line) => line.replaceFirst(RegExp(r'^[•\-\s]+'), '').trim())
            .where((line) => line.isNotEmpty && line != entry.title)
            .join(' · ');

    return SpringPress(
      pressedScale: 0.97,
      onTap: () => _showEntry(context, entry),
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              capitalizeWords(entry.subject),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelLarge?.copyWith(color: colors.accent),
                            ),
                          ),
                          if (_hours.isNotEmpty)
                            Text(_hours, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(entry.title.isEmpty ? 'Sans titre' : entry.title, style: text.titleMedium),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (entry.resources.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.attach_file_rounded, size: 16, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              entry.resources.length == 1 ? '1 pièce jointe' : '${entry.resources.length} pièces jointes',
                              style: text.labelMedium?.copyWith(color: scheme.primary),
                            ),
                          ],
                        ),
                      ],
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

void _showEntry(BuildContext context, CahierEntry entry) {
  final state = AppScope.read(context);
  final seance = state.seances.where((s) => s.codeSeance != null && s.codeSeance == entry.codeSeance).firstOrNull;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (sheetContext, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          CahierCard(entry: entry, showSubject: true),
          if (seance != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                showSeanceSheet(context, seance);
              },
              icon: const Icon(Icons.event_rounded),
              label: const Text('Voir la séance'),
            ),
          ],
        ],
      ),
    ),
  );
}
