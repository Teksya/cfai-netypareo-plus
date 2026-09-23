import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/notifications.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'seance_sheet.dart';
import 'theme.dart';

final DateTime _origin = DateTime.utc(2024, 1, 1);

int _pageOf(DateTime day) => DateTime.utc(day.year, day.month, day.day).difference(_origin).inDays;
DateTime _dayOf(int page) {
  final d = _origin.add(Duration(days: page));
  return DateTime(d.year, d.month, d.day);
}

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => PlanningPageState();
}

class PlanningPageState extends State<PlanningPage> {
  late DateTime _selected = _initialDay();
  late final PageController _pages = PageController(initialPage: _pageOf(_selected));

  /// Le week-end, on ouvre directement le lundi suivant.
  static DateTime _initialDay() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (today.weekday == DateTime.saturday) return today.add(const Duration(days: 2));
    if (today.weekday == DateTime.sunday) return today.add(const Duration(days: 1));
    return today;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Ouvre le jour demandé par une notification, et la séance si elle existe encore.
  Future<void> open(OpenRequest request) async {
    final state = AppScope.read(context);
    await state.reloadCache();
    if (!mounted) return;
    _pages.jumpToPage(_pageOf(DateUtils.dateOnly(request.day)));
    final seance = state.seances.where((s) => s.uid == request.uid).firstOrNull;
    if (seance != null) await showSeanceSheet(context, seance);
  }

  void _goTo(DateTime day) {
    _pages.animateToPage(_pageOf(day), duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_selected),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capitalize(_selected == today ? 'Aujourd\'hui' : DateFormat.EEEE().format(_selected)),
                          style: text.headlineLarge,
                        ),
                        Text(
                          DateFormat.yMMMMd().format(_selected),
                          style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_selected != today)
                  IconButton.filledTonal(
                    tooltip: 'Aujourd\'hui',
                    onPressed: () => _goTo(today),
                    icon: const Icon(Icons.today_rounded),
                  ),
                _SyncButton(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _WeekStrip(selected: _selected, onSelect: _goTo, hasCourses: (d) => state.seancesOn(d).isNotEmpty),
          if (state.syncError != null && state.seances.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Hors ligne : affichage de la dernière synchronisation.',
                style: text.bodySmall?.copyWith(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              onPageChanged: (page) => setState(() => _selected = _dayOf(page)),
              itemBuilder: (context, page) => _DayView(day: _dayOf(page)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.syncing) {
      return const Padding(padding: EdgeInsets.all(12), child: ExpressiveLoader(size: 24));
    }
    return IconButton(
      tooltip: 'Synchroniser',
      onPressed: () => state.sync(force: true),
      icon: Icon(state.syncError == null ? Icons.sync_rounded : Icons.sync_problem_rounded),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.selected, required this.onSelect, required this.hasCourses});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final bool Function(DateTime) hasCourses;

  @override
  Widget build(BuildContext context) {
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final today = DateUtils.dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Semaine précédente',
            onPressed: () => onSelect(selected.subtract(const Duration(days: 7))),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayPill(
                day: DateUtils.addDaysToDate(monday, i),
                selected: DateUtils.isSameDay(DateUtils.addDaysToDate(monday, i), selected),
                isToday: DateUtils.isSameDay(DateUtils.addDaysToDate(monday, i), today),
                hasCourses: hasCourses(DateUtils.addDaysToDate(monday, i)),
                onTap: () => onSelect(DateUtils.addDaysToDate(monday, i)),
              ),
            ),
          IconButton(
            tooltip: 'Semaine suivante',
            onPressed: () => onSelect(selected.add(const Duration(days: 7))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.hasCourses,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool hasCourses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = selected ? scheme.onPrimary : (isToday ? scheme.primary : scheme.onSurface);
    return Semantics(
      button: true,
      selected: selected,
      label: DateFormat.MMMMEEEEd().format(day),
      child: SpringPress(
        onTap: onTap,
        pressedScale: 0.88,
        child: Column(
          children: [
            Text(
              DateFormat.E().format(day).substring(0, 2).toUpperCase(),
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                shape: selected
                    ? const CookieBorder(lobes: 8, depth: 0.08)
                    : CookieBorder(
                        lobes: 8,
                        depth: 0,
                        side: isToday ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
                      ),
              ),
              child: Text('${day.day}', style: text.titleMedium?.copyWith(color: fg)),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: hasCourses ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: scheme.tertiary, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final seances = state.seancesOn(day);

    if (state.seances.isEmpty && state.syncing) {
      return const Center(child: ExpressiveLoader());
    }
    if (state.seances.isEmpty && state.syncError != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Planning indisponible',
        message: state.syncError,
        action: FilledButton.tonal(onPressed: () => state.sync(force: true), child: const Text('Réessayer')),
      );
    }

    return RefreshIndicator(
      onRefresh: () => state.sync(force: true),
      child: seances.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: 420,
                  child: EmptyState(
                    icon: day.weekday >= DateTime.saturday ? Icons.weekend_rounded : Icons.work_outline_rounded,
                    title: day.weekday >= DateTime.saturday ? 'Week-end' : 'Pas de cours au centre',
                    message: day.weekday >= DateTime.saturday ? null : 'Journée en entreprise ou libre.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: seances.length,
              itemBuilder: (context, i) {
                final gap = i == 0 ? Duration.zero : seances[i].start.difference(seances[i - 1].end);
                return EnterAnimation(
                  index: i,
                  child: Column(
                    children: [
                      if (gap.inMinutes >= 30) _Gap(gap: gap),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SeanceCard(seance: seances[i]),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({required this.gap});

  final Duration gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = gap.inMinutes >= 60
        ? 'Pause ${gap.inHours}h${(gap.inMinutes % 60).toString().padLeft(2, '0')}'
        : 'Pause ${gap.inMinutes} min';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.coffee_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

class SeanceCard extends StatefulWidget {
  const SeanceCard({super.key, required this.seance});

  final Seance seance;

  @override
  State<SeanceCard> createState() => _SeanceCardState();
}

class _SeanceCardState extends State<SeanceCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Rafraîchit la barre de progression du cours en cours.
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
    final s = widget.seance;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = subjectColors(s.subject, theme.brightness);
    final now = DateTime.now();
    final ongoing = now.isAfter(s.start) && now.isBefore(s.end);
    final past = now.isAfter(s.end);
    final hm = DateFormat.Hm();

    return Opacity(
      opacity: past ? 0.6 : 1,
      child: SpringPress(
        pressedScale: 0.97,
        onTap: () => showSeanceSheet(context, s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: colors.container,
            borderRadius: BorderRadius.circular(ongoing ? 32 : 24),
            border: ongoing ? Border.all(color: colors.accent, width: 2.5) : null,
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        hm.format(s.start),
                        maxLines: 1,
                        style: text.titleLarge?.copyWith(color: colors.onContainer, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(hm.format(s.end), style: text.bodyMedium?.copyWith(color: colors.onContainer.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Container(
                width: 4,
                height: 64,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ongoing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            'En cours',
                            style: text.labelSmall?.copyWith(color: colors.container, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    Text(
                      capitalizeWords(s.subject),
                      style: text.titleMedium?.copyWith(color: colors.onContainer),
                    ),
                    const SizedBox(height: 6),
                    if (s.teachers.isNotEmpty) _Info(icon: Icons.person_rounded, label: s.teachers, color: colors.onContainer),
                    if (s.room.isNotEmpty) _Info(icon: Icons.room_rounded, label: s.room, color: colors.onContainer),
                    if (ongoing) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: now.difference(s.start).inSeconds / s.duration.inSeconds,
                          minHeight: 6,
                          color: colors.accent,
                          backgroundColor: colors.onContainer.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.75)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ),
    );
  }
}
