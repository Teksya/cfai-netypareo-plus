import 'models.dart';

enum ChangeKind { added, removed, modified }

/// Un changement de l'emploi du temps entre deux synchronisations.
class SeanceChange {
  const SeanceChange(this.kind, {this.before, this.after});

  final ChangeKind kind;
  final Seance? before;
  final Seance? after;

  /// La séance telle qu'elle est maintenant (ou telle qu'elle était, si elle a été retirée).
  Seance get seance => after ?? before!;

  bool get timeChanged => before!.start != after!.start || before!.end != after!.end;
  bool get roomChanged => before!.room != after!.room;
  bool get teachersChanged => before!.teachers != after!.teachers;
  bool get subjectChanged => before!.subject != after!.subject;
}

/// Compare deux versions du planning, séance par séance (même UID = même séance).
///
/// Seuls les cours pas encore terminés à [now] comptent : un cours passé qui disparaît du
/// flux n'intéresse personne. Le groupe n'est pas comparé, il change sans effet pour l'apprenant.
List<SeanceChange> diffSeances(List<Seance> before, List<Seance> after, {required DateTime now}) {
  bool upcoming(Seance s) => s.end.isAfter(now);
  final old = {for (final s in before.where(upcoming)) s.uid: s};
  final changes = <SeanceChange>[];
  final seen = <String>{};
  for (final s in after) {
    seen.add(s.uid);
    final previous = old[s.uid];
    if (previous == null) {
      // Un cours déplacé du passé vers le futur n'est pas dans `old` : on le compare quand même.
      final wasPast = before.where((b) => b.uid == s.uid).firstOrNull;
      if (!upcoming(s)) continue;
      changes.add(wasPast == null
          ? SeanceChange(ChangeKind.added, after: s)
          : SeanceChange(ChangeKind.modified, before: wasPast, after: s));
      continue;
    }
    final change = SeanceChange(ChangeKind.modified, before: previous, after: s);
    if (change.timeChanged || change.roomChanged || change.teachersChanged || change.subjectChanged) {
      changes.add(change);
    }
  }
  for (final s in old.values) {
    if (!seen.contains(s.uid)) changes.add(SeanceChange(ChangeKind.removed, before: s));
  }
  changes.sort((a, b) => a.seance.start.compareTo(b.seance.start));
  return changes;
}
