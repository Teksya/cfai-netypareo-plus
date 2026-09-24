import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'planning_views.dart';
import 'seance_sheet.dart';
import 'theme.dart';

/// Un lundi : les pages "jour" et "semaine" comptent à partir de là.
final DateTime _origin = DateTime.utc(2024, 1, 1);

int _pageOf(DateTime day) => DateTime.utc(day.year, day.month, day.day).difference(_origin).inDays;
DateTime _dayOf(int page) {
  final d = _origin.add(Duration(days: page));
  return DateTime(d.year, d.month, d.day);
}

/// Jours ouvrés numérotés depuis l'origine (le week-end compte comme le lundi suivant).
int _workdayOf(DateTime day) {
  final page = _pageOf(day);
  final week = page ~/ 7;
  final dow = page % 7;
  return dow >= 5 ? (week + 1) * 5 : week * 5 + dow;
}

DateTime _dateOfWorkday(int workday) => _dayOf(workday ~/ 5 * 7 + workday % 5);

/// Page de départ des vues "3 jours" : on peut glisser dans les deux sens.
const _threeDaysHome = 10000;

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => PlanningPageState();
}

class PlanningPageState extends State<PlanningPage> {
  late DateTime _selected = _initialDay();
  late PlanningLayout _layout = PlanningLayout.fromName(AppScope.read(context).planningLayout);
  late PageController _pages = PageController(initialPage: _initialPage(_selected));

  /// Vue "3 jours" : premier jour ouvré de la page [_threeDaysHome].
  late int _threeAnchor = _workdayOf(_selected);

  /// Le week-end, on ouvre directement le lundi suivant.
  static DateTime _initialDay() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (today.weekday == DateTime.saturday) return today.add(const Duration(days: 2));
    if (today.weekday == DateTime.sunday) return today.add(const Duration(days: 1));
    return today;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int _initialPage(DateTime day) => switch (_layout) {
        PlanningLayout.day || PlanningLayout.list => _pageOf(day),
        PlanningLayout.week => _pageOf(day) ~/ 7,
        PlanningLayout.threeDays => _threeDaysHome,
      };

  /// Jours affichés par une page de la vue courante.
  List<DateTime> _daysOfPage(int page) {
    final state = AppScope.read(context);
    switch (_layout) {
      case PlanningLayout.week:
        final monday = _dayOf(page * 7);
        final days = [for (var i = 0; i < 7; i++) DateUtils.addDaysToDate(monday, i)];
        // Samedi et dimanche seulement s'il y a cours.
        return days.where((d) => d.weekday <= DateTime.friday || state.seancesOn(d).isNotEmpty).toList();
      case PlanningLayout.threeDays:
        final start = _threeAnchor + 3 * (page - _threeDaysHome);
        return [for (var i = 0; i < 3; i++) _dateOfWorkday(start + i)];
      case PlanningLayout.day:
      case PlanningLayout.list:
        return [_dayOf(page)];
    }
  }

  List<DateTime> get _visibleDays => _daysOfPage(_pages.hasClients ? _pages.page!.round() : _pages.initialPage);

  void _prefetch() {
    if (!mounted || _layout == PlanningLayout.list) return;
    final state = AppScope.read(context);
    // En série : un jour après l'autre, sans multiplier les requêtes en parallèle.
    Future.forEach(_daysOfPage(_pages.hasClients ? _pages.page!.round() : _pages.initialPage), state.prefetchSeanceDetails);
  }

  void _setLayout(PlanningLayout layout) {
    if (layout == _layout) return;
    AppScope.read(context).setPlanningLayout(layout.name);
    setState(() {
      _layout = layout;
      _threeAnchor = _workdayOf(_selected);
      _pages.dispose();
      _pages = PageController(initialPage: _initialPage(_selected));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  /// Ouvre le jour demandé par une notification, et la séance si elle existe encore.
  Future<void> open(OpenRequest request) async {
    final state = AppScope.read(context);
    await state.reloadCache();
    if (!mounted) return;
    _jumpTo(DateUtils.dateOnly(request.day));
    final seance = state.seances.where((s) => s.uid == request.uid).firstOrNull;
    if (seance != null) await showSeanceSheet(context, seance);
  }

  void _jumpTo(DateTime day) {
    setState(() => _selected = day);
    if (_layout == PlanningLayout.threeDays) {
      setState(() => _threeAnchor = _workdayOf(day));
      if (_pages.hasClients) _pages.jumpToPage(_threeDaysHome);
    } else if (_layout != PlanningLayout.list && _pages.hasClients) {
      _pages.jumpToPage(_initialPage(day));
    }
  }

  void _goTo(DateTime day) {
    if (_layout == PlanningLayout.threeDays) return _jumpTo(day);
    _pages.animateToPage(_initialPage(day), duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  /// Depuis une grille : ouvre le jour touché en vue Jour.
  void _openDay(DateTime day) {
    _selected = day;
    _setLayout(PlanningLayout.day);
  }

  void _onPageChanged(int page) {
    final days = _daysOfPage(page);
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() => _selected = days.contains(today) ? today : days.first);
    _prefetch();
  }

  (String, String) _titles(DateTime today) {
    switch (_layout) {
      case PlanningLayout.day:
        return (
          capitalize(_selected == today ? "Aujourd'hui" : DateFormat.EEEE().format(_selected)),
          DateFormat.yMMMMd().format(_selected),
        );
      case PlanningLayout.list:
        final count = AppScope.read(context).seances.where((s) => s.end.isAfter(DateTime.now())).length;
        return ('À venir', count == 0 ? 'Aucun cours' : '$count cours');
      case PlanningLayout.week:
      case PlanningLayout.threeDays:
        final days = _visibleDays;
        final first = days.first;
        final last = days.last;
        final title = first.month == last.month
            ? capitalize(DateFormat.yMMMM().format(first))
            : '${capitalize(DateFormat.MMM().format(first))} – ${DateFormat.yMMM().format(last)}';
        final range = _layout == PlanningLayout.week
            ? 'Semaine du ${DateFormat.MMMd().format(first)} au ${DateFormat.MMMd().format(last)}'
            : 'Du ${DateFormat.MMMEd().format(first)} au ${DateFormat.MMMEd().format(last)}';
        return (title, range);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final (title, subtitle) = _titles(today);
    final showsToday = switch (_layout) {
      PlanningLayout.day => _selected == today,
      PlanningLayout.list => true,
      _ => _visibleDays.contains(today) || today.weekday > DateTime.friday,
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 4, 0),
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
                      key: ValueKey('$_layout$title$subtitle'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title, style: text.headlineLarge, maxLines: 1),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!showsToday)
                  IconButton.filledTonal(
                    tooltip: "Aujourd'hui",
                    onPressed: () => _goTo(today),
                    icon: const Icon(Icons.today_rounded),
                  ),
                _LayoutButton(layout: _layout, onChanged: _setLayout),
                _SyncButton(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_layout == PlanningLayout.day)
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
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(AppState state) {
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
    if (_layout == PlanningLayout.list) return const PlanningList();
    return PageView.builder(
      key: ValueKey(_layout),
      controller: _pages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, page) => switch (_layout) {
        PlanningLayout.day => _DayView(day: _dayOf(page)),
        _ => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PlanningGrid(
              days: _daysOfPage(page),
              compact: _layout == PlanningLayout.week,
              onOpenDay: _openDay,
            ),
          ),
      },
    );
  }
}

class _LayoutButton extends StatelessWidget {
  const _LayoutButton({required this.layout, required this.onChanged});

  final PlanningLayout layout;
  final ValueChanged<PlanningLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<PlanningLayout>(
      tooltip: 'Disposition : ${layout.label}',
      icon: Icon(layout.icon),
      initialValue: layout,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      itemBuilder: (context) => [
        for (final l in PlanningLayout.values)
          PopupMenuItem(
            value: l,
            child: Row(
              children: [
                Icon(l.icon, color: l == layout ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.label,
                    style: TextStyle(
                      color: l == layout ? scheme.primary : null,
                      fontWeight: l == layout ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                if (l == layout) Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
      ],
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
