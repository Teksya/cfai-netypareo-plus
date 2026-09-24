import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'planning_page.dart';
import 'seance_sheet.dart';
import 'theme.dart';

/// Dispositions du planning, au choix dans l'en-tête (le choix est retenu).
enum PlanningLayout {
  day('Jour', Icons.view_day_rounded),
  threeDays('3 jours', Icons.view_column_rounded),
  week('Semaine', Icons.calendar_view_week_rounded),
  list('Liste', Icons.view_agenda_rounded);

  const PlanningLayout(this.label, this.icon);

  final String label;
  final IconData icon;

  static PlanningLayout fromName(String? name) =>
      values.where((l) => l.name == name).firstOrNull ?? PlanningLayout.day;
}

// -----------------------------------------------------------------------------
// Grille horaire (3 jours, semaine)

/// Les jours côte à côte, les heures en colonne : chaque cours est un bloc placé à son horaire.
class PlanningGrid extends StatefulWidget {
  const PlanningGrid({super.key, required this.days, required this.onOpenDay, this.compact = false});

  final List<DateTime> days;

  /// Appui sur l'en-tête d'un jour : ouvre ce jour en vue Jour.
  final ValueChanged<DateTime> onOpenDay;

  /// Colonnes étroites (semaine) : matières abrégées.
  final bool compact;

  @override
  State<PlanningGrid> createState() => _PlanningGridState();
}

class _PlanningGridState extends State<PlanningGrid> {
  static const _gutter = 34.0;
  static const _headerHeight = 56.0;

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Fait avancer la ligne "maintenant".
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final byDay = {for (final d in widget.days) d: state.seancesOn(d)};
    final all = byDay.values.expand((s) => s).toList();

    // Plage horaire : 8h-17h au moins, élargie si un cours déborde.
    var first = 8;
    var last = 17;
    for (final s in all) {
      first = math.min(first, s.start.hour);
      last = math.max(last, s.end.hour + (s.end.minute > 0 ? 1 : 0));
    }
    final hours = last - first;
    final today = DateUtils.dateOnly(DateTime.now());

    return RefreshIndicator(
      onRefresh: () => state.sync(force: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hourHeight = math.max(44.0, (constraints.maxHeight - _headerHeight - 26) / hours);
          return Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    const SizedBox(width: _gutter),
                    for (final day in widget.days)
                      Expanded(
                        child: _GridDayHeader(
                          day: day,
                          isToday: day == today,
                          onTap: () => widget.onOpenDay(day),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Place pour les libellés de la première et de la dernière heure.
                  padding: const EdgeInsets.only(top: 10, bottom: 16),
                  child: SizedBox(
                    height: hourHeight * hours,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var h = 0; h <= hours; h++)
                          Positioned(
                            top: h * hourHeight,
                            left: 0,
                            right: 0,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: _gutter,
                                  child: Transform.translate(
                                    offset: const Offset(0, -8),
                                    child: Text(
                                      '${first + h}h',
                                      textAlign: TextAlign.center,
                                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                                Expanded(child: Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
                              ],
                            ),
                          ),
                        Positioned.fill(
                          left: _gutter,
                          right: 4,
                          child: Row(
                            children: [
                              for (final day in widget.days)
                                Expanded(
                                  child: _GridDayColumn(
                                    seances: byDay[day]!,
                                    isToday: day == today,
                                    firstHour: first,
                                    hourHeight: hourHeight,
                                    compact: widget.compact,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GridDayHeader extends StatelessWidget {
  const _GridDayHeader({required this.day, required this.isToday, required this.onTap});

  final DateTime day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: DateFormat.MMMMEEEEd().format(day),
      excludeSemantics: true,
      child: SpringPress(
        onTap: onTap,
        pressedScale: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat.E().format(day).substring(0, 2).toUpperCase(),
              style: text.labelSmall?.copyWith(color: isToday ? scheme.primary : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: isToday ? scheme.primary : Colors.transparent,
                shape: const CookieBorder(lobes: 8, depth: 0.08),
              ),
              child: Text(
                '${day.day}',
                style: text.titleSmall?.copyWith(color: isToday ? scheme.onPrimary : scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridDayColumn extends StatelessWidget {
  const _GridDayColumn({
    required this.seances,
    required this.isToday,
    required this.firstHour,
    required this.hourHeight,
    required this.compact,
  });

  final List<Seance> seances;
  final bool isToday;
  final int firstHour;
  final double hourHeight;
  final bool compact;

  double _y(DateTime t) => ((t.hour - firstHour) + t.minute / 60) * hourHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Cours qui se chevauchent : côte à côte dans la colonne.
    final lanes = <List<Seance>>[];
    final laneOf = <Seance, int>{};
    for (final s in [...seances]..sort((a, b) => a.start.compareTo(b.start))) {
      var lane = lanes.indexWhere((l) => !l.last.end.isAfter(s.start));
      if (lane == -1) {
        lanes.add([s]);
        lane = lanes.length - 1;
      } else {
        lanes[lane].add(s);
      }
      laneOf[s] = lane;
    }
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: isToday ? scheme.primary.withValues(alpha: 0.05) : null,
        border: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneWidth = constraints.maxWidth / math.max(1, lanes.length);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final s in seances)
                Positioned(
                  top: _y(s.start) + 1,
                  height: math.max(20, _y(s.end) - _y(s.start) - 2),
                  left: laneOf[s]! * laneWidth + 2,
                  width: laneWidth - 4,
                  child: _GridBlock(seance: s, compact: compact),
                ),
              if (isToday && now.hour >= firstHour && _y(now) <= constraints.maxHeight)
                Positioned(
                  top: _y(now) - 4,
                  left: -4,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                        ),
                        Expanded(child: Container(height: 2, color: scheme.error)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GridBlock extends StatelessWidget {
  const _GridBlock({required this.seance, required this.compact});

  final Seance seance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = seance;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = subjectColors(s.subject, theme.brightness);
    final now = DateTime.now();
    final ongoing = now.isAfter(s.start) && now.isBefore(s.end);
    final past = now.isAfter(s.end);
    final subject = compact ? shortSubject(s.subject) : capitalizeWords(s.subject);

    return Semantics(
      button: true,
      label: '${capitalizeWords(s.subject)}, ${DateFormat.Hm().format(s.start)} à ${DateFormat.Hm().format(s.end)}'
          '${s.room.isEmpty ? '' : ', salle ${s.room}'}',
      excludeSemantics: true,
      child: Opacity(
        opacity: past ? 0.55 : 1,
        child: SpringPress(
          pressedScale: 0.94,
          onTap: () => showSeanceSheet(context, s),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.container,
              borderRadius: BorderRadius.circular(compact ? 10 : 14),
              border: ongoing ? Border.all(color: colors.accent, width: 2) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: colors.accent),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 4 : 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.Hm().format(s.start),
                          maxLines: 1,
                          style: text.labelSmall?.copyWith(color: colors.onContainer.withValues(alpha: 0.75)),
                        ),
                        Flexible(
                          child: Text(
                            subject,
                            overflow: TextOverflow.fade,
                            style: (compact ? text.labelMedium : text.labelLarge)?.copyWith(
                              color: colors.onContainer,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ),
                        if (s.room.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              // "(CITE) POLYNESIE" : le site est toujours le même, seule la salle compte.
                              compact ? s.room.replaceFirst(RegExp(r'^\([^)]*\)\s*'), '') : s.room,
                              maxLines: 1,
                              style: text.labelSmall?.copyWith(color: colors.onContainer.withValues(alpha: 0.75)),
                            ),
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Liste continue

/// Tous les cours à venir à la suite, un en-tête collant par jour. Les jours ouvrés sans cours
/// (entreprise, vacances) sont résumés entre deux jours de cours.
class PlanningList extends StatelessWidget {
  const PlanningList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = <DateTime, List<Seance>>{};
    for (final s in state.seances) {
      final day = DateUtils.dateOnly(s.start);
      if (day.isBefore(today)) continue;
      days.putIfAbsent(day, () => []).add(s);
    }
    final ordered = days.keys.toList()..sort();

    if (ordered.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => state.sync(force: true),
        child: ListView(
          children: const [
            SizedBox(
              height: 420,
              child: EmptyState(
                icon: Icons.event_available_rounded,
                title: 'Aucun cours à venir',
                message: 'Tire vers le bas pour synchroniser.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => state.sync(force: true),
      child: CustomScrollView(
        slivers: [
          for (final (i, day) in ordered.indexed) ...[
            if (i > 0) ..._gap(context, ordered[i - 1], day),
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(pinned: true, delegate: _ListDayHeader(day: day, today: today)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      for (final s in days[day]!..sort((a, b) => a.start.compareTo(b.start)))
                        Padding(padding: const EdgeInsets.only(bottom: 12), child: SeanceCard(seance: s)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// Jours ouvrés sans cours entre deux jours de cours.
  List<Widget> _gap(BuildContext context, DateTime previous, DateTime next) {
    final free = [
      for (var d = DateUtils.addDaysToDate(previous, 1); d.isBefore(next); d = DateUtils.addDaysToDate(d, 1))
        if (d.weekday <= DateTime.friday) d,
    ];
    if (free.isEmpty) return const [];
    final scheme = Theme.of(context).colorScheme;
    final format = DateFormat('EEE d MMM');
    final label = free.length == 1
        ? 'Pas de cours au centre le ${format.format(free.first)}'
        : 'Pas de cours au centre du ${format.format(free.first)} au ${format.format(free.last)}';
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.work_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

class _ListDayHeader extends SliverPersistentHeaderDelegate {
  _ListDayHeader({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final inDays = day.difference(today).inDays;
    final relative = switch (inDays) {
      0 => "Aujourd'hui",
      1 => 'Demain',
      _ => null,
    };
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(capitalize(DateFormat.MMMMEEEEd().format(day)), style: text.titleMedium),
          if (relative != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(99)),
              child: Text(relative, style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_ListDayHeader oldDelegate) => oldDelegate.day != day || oldDelegate.today != today;
}
