import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../ui/format.dart';
import 'models.dart';

/// Widget "Prochain cours" de l'écran d'accueil (code natif : `NextCourseWidget.kt`).
///
/// On lui confie les cours des deux prochaines semaines ; il choisit lui-même lequel afficher.
/// Il est redessiné aux moments où l'affichage change (une heure avant un cours, à son début,
/// à sa fin), même application fermée.
class CourseWidget {
  CourseWidget._();

  static const _android = 'NextCourseWidget';

  static Future<void> update(List<Seance> seances) async {
    try {
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 14));
      final upcoming = seances.where((s) => s.end.isAfter(now) && s.start.isBefore(horizon)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      await HomeWidget.saveWidgetData(
        'seances',
        jsonEncode([
          for (final s in upcoming)
            {
              's': capitalizeWords(s.subject),
              'a': s.start.millisecondsSinceEpoch,
              'b': s.end.millisecondsSinceEpoch,
              'r': s.room,
            },
        ]),
      );
      await HomeWidget.updateWidget(androidName: _android);
      final times = <DateTime>{
        for (final s in upcoming.take(30)) ...[
          s.start.subtract(const Duration(hours: 1)),
          s.start.subtract(const Duration(minutes: 15)),
          s.start,
          s.end,
          // Minuit : "Demain" devient "Prochain cours".
          DateTime(s.start.year, s.start.month, s.start.day),
        ],
      }.where((t) => t.isAfter(now)).toList()
        ..sort();
      await HomeWidget.scheduleWidgetUpdates(times, androidName: _android);
    } catch (e) {
      debugPrint('Widget non mis à jour : $e');
    }
  }
}
