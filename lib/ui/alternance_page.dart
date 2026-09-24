import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../main.dart';
import 'cached_view.dart';
import 'expressive.dart';
import 'format.dart';

/// Calendrier de formation : l'année jour par jour, au centre ou en entreprise.
class AlternancePage extends StatelessWidget {
  const AlternancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CachedView<Alternance>(
        load: AppScope.read(context).alternance,
        loading: (context) => const _Frame(
          slivers: [SliverFillRemaining(child: Center(child: ExpressiveLoader()))],
        ),
        failed: (context, error, retry) => _Frame(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Chargement impossible',
                message: AppState.errorMessage(error),
                action: FilledButton.tonal(onPressed: retry, child: const Text('Réessayer')),
              ),
            ),
          ],
        ),
        builder: (context, alternance, status) => _AlternanceView(alternance: alternance, status: status),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.slivers, this.subtitle, this.controller});

  final List<Widget> slivers;
  final String? subtitle;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return CustomScrollView(
      controller: controller,
      slivers: [
        const SliverAppBar(pinned: true),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alternance', style: text.headlineLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ...slivers,
      ],
    );
  }
}

/// Couleurs d'un type de journée, tirées du thème.
({Color bg, Color fg, String label, IconData icon}) _style(ColorScheme scheme, DayKind kind) => switch (kind) {
  DayKind.centre => (
    bg: scheme.primaryContainer,
    fg: scheme.onPrimaryContainer,
    label: 'Au centre',
    icon: Icons.school_rounded,
  ),
  DayKind.entreprise => (
    bg: scheme.tertiaryContainer,
    fg: scheme.onTertiaryContainer,
    label: 'En entreprise',
    icon: Icons.business_center_rounded,
  ),
  DayKind.off => (
    bg: scheme.surfaceContainerHighest,
    fg: scheme.onSurfaceVariant,
    label: 'Indisponible',
    icon: Icons.event_busy_rounded,
  ),
};

class _AlternanceView extends StatefulWidget {
  const _AlternanceView({required this.alternance, required this.status});

  final Alternance alternance;
  final CacheStatus status;

  @override
  State<_AlternanceView> createState() => _AlternanceViewState();
}

class _AlternanceViewState extends State<_AlternanceView> {
  final _currentMonth = GlobalKey();
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.alternance.days;
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = days.keys.toList()..sort();

    if (dates.isEmpty) {
      return _Frame(
        slivers: [
          SliverToBoxAdapter(child: CacheBanner(status: widget.status)),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.date_range_rounded,
              title: 'Calendrier vide',
              message: "Le CFA n'a pas encore saisi ton calendrier de formation.",
            ),
          ),
        ],
      );
    }

    final months = <DateTime>[];
    for (
      var m = DateTime(dates.first.year, dates.first.month);
      !m.isAfter(DateTime(dates.last.year, dates.last.month));
      m = DateTime(m.year, m.month + 1)
    ) {
      months.add(m);
    }
    final thisMonth = DateTime(today.year, today.month);

    // Une fois dessiné, on descend jusqu'au mois en cours.
    // Pas la peine si le mois est déjà en haut de l'écran, sous le résumé.
    if (!_scrolled && months.indexOf(thisMonth) >= 2) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _currentMonth.currentContext;
        if (target == null) return;
        Scrollable.ensureVisible(
          target,
          alignment: 0.1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return RefreshIndicator(
      onRefresh: widget.status.refresh,
      edgeOffset: 80,
      child: _Frame(
        controller: _scroll,
        subtitle: _period(dates.first, dates.last),
        slivers: [
          SliverToBoxAdapter(child: CacheBanner(status: widget.status)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList.list(
              children: [
                _NowCard(days: days, today: today),
                const SizedBox(height: 16),
                _Legend(alternance: widget.alternance),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.list(
              children: [
                for (final month in months)
                  _MonthGrid(key: month == thisMonth ? _currentMonth : null, month: month, days: days, today: today),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _period(DateTime first, DateTime last) {
    final format = DateFormat.yMMMd();
    return 'Du ${format.format(first)} au ${format.format(last)}';
  }
}

/// Où l'on est cette semaine, et quand ça change.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.days, required this.today});

  final Map<DateTime, DayKind> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dates = days.keys.where((d) => !d.isBefore(today)).toList()..sort();
    if (dates.isEmpty) return const SizedBox.shrink();

    // Aujourd'hui, ou le prochain jour renseigné (le week-end, c'est le lundi).
    final current = dates.first;
    final kind = days[current]!;
    final change = dates.firstWhere((d) => days[d] != kind && days[d] != DayKind.off, orElse: () => current);
    final style = _style(scheme, kind);
    final when = current == today ? "Aujourd'hui" : capitalize(DateFormat.MMMMEEEEd().format(current));
    final format = DateFormat.MMMMEEEEd();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: ShapeDecoration(color: style.fg, shape: const CookieBorder(lobes: 8, depth: 0.08)),
            child: Icon(style.icon, color: style.bg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(when, style: text.labelLarge?.copyWith(color: style.fg.withValues(alpha: 0.8))),
                Text(style.label, style: text.titleLarge?.copyWith(color: style.fg)),
                if (change != current)
                  Text(
                    '${days[change] == DayKind.centre ? 'Retour au centre' : 'En entreprise'} '
                    '${change.difference(today).inDays <= 1 ? (change == today ? "aujourd'hui" : 'demain') : 'le ${format.format(change)}'}',
                    style: text.bodyMedium?.copyWith(color: style.fg),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nombre de jours de chaque type sur l'année.
class _Legend extends StatelessWidget {
  const _Legend({required this.alternance});

  final Alternance alternance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final kinds = DayKind.values.where((k) => alternance.count(k) > 0).toList();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, kind) in kinds.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  final style = _style(scheme, kind);
                  final n = alternance.count(kind);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$n',
                          style: text.headlineSmall?.copyWith(color: style.fg, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${n > 1 ? 'jours' : 'jour'} ${switch (kind) {
                            DayKind.centre => 'au centre',
                            DayKind.entreprise => 'en entreprise',
                            DayKind.off => 'indisponible${n > 1 ? 's' : ''}',
                          }}',
                          style: text.labelMedium?.copyWith(color: style.fg),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({super.key, required this.month, required this.days, required this.today});

  final DateTime month;
  final Map<DateTime, DayKind> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month);
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = first.weekday - 1;
    final cells = offset + count;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(capitalize(DateFormat.yMMMM().format(month)), style: text.titleMedium),
          ),
          Row(
            children: [
              for (final d in const ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row * 7 < cells; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final index = row * 7 + col - offset;
                        if (index < 0 || index >= count) return const SizedBox(height: 44);
                        final day = DateTime(month.year, month.month, index + 1);
                        return _DayCell(day: day, kind: days[day], isToday: day == today);
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.kind, required this.isToday});

  final DateTime day;
  final DayKind? kind;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = kind == null ? null : _style(scheme, kind!);
    return Semantics(
      label: '${DateFormat.MMMMEEEEd().format(day)}${style == null ? '' : ', ${style.label.toLowerCase()}'}',
      excludeSemantics: true,
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: style?.bg,
          borderRadius: BorderRadius.circular(12),
          border: isToday ? Border.all(color: scheme.primary, width: 2.5) : null,
        ),
        child: Text(
          '${day.day}',
          style: text.bodyMedium?.copyWith(
            color: style?.fg ?? scheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: isToday ? FontWeight.w800 : null,
            decoration: kind == DayKind.off ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}
