import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:netypareo_plus/data/models.dart';
import 'package:netypareo_plus/data/notifications.dart';
import 'package:netypareo_plus/data/planning_diff.dart';

Seance _seance(String uid, DateTime start, {String room = 'SALLE A', String teachers = 'M. DUPONT'}) => Seance(
      uid: uid,
      codeSeance: null,
      subject: 'MATHEMATIQUES',
      teachers: teachers,
      room: room,
      group: 'BTS SIO 1',
      start: start,
      end: start.add(const Duration(hours: 2)),
    );

void main() {
  final now = DateTime(2026, 9, 23, 12);
  final past = _seance('passe', DateTime(2026, 9, 22, 8));
  final lundi = _seance('lundi', DateTime(2026, 9, 28, 8));
  final mardi = _seance('mardi', DateTime(2026, 9, 29, 8));

  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('rien ne change', () {
    expect(diffSeances([past, lundi], [past, lundi], now: now), isEmpty);
  });

  test('ajout et retrait', () {
    final changes = diffSeances([past, lundi], [mardi], now: now);
    expect(changes.map((c) => (c.kind, c.seance.uid)), [
      (ChangeKind.removed, 'lundi'),
      (ChangeKind.added, 'mardi'),
    ]);
  });

  test('un cours passé qui disparaît est ignoré', () {
    expect(diffSeances([past, lundi], [lundi], now: now), isEmpty);
  });

  test('changement de salle et d\'horaire', () {
    final moved = _seance('lundi', DateTime(2026, 9, 28, 10), room: 'SALLE B');
    final changes = diffSeances([lundi], [moved], now: now);
    expect(changes, hasLength(1));
    final change = changes.single;
    expect(change.kind, ChangeKind.modified);
    expect(change.timeChanged, isTrue);
    expect(change.roomChanged, isTrue);
    expect(change.teachersChanged, isFalse);

    final (title, body) = PlanningNotifications.describe(change);
    expect(title, 'Cours modifié : Mathematiques');
    expect(body, contains('08:00–10:00 → '));
    expect(body, contains('Salle : SALLE A → SALLE B'));
  });

  test('un cours passé déplacé dans le futur est une modification', () {
    final moved = _seance('passe', DateTime(2026, 9, 30, 8));
    final changes = diffSeances([past], [moved], now: now);
    expect(changes.single.kind, ChangeKind.modified);
  });

  test('le lien de notification survit à l\'aller-retour', () {
    final request = OpenRequest(day: DateTime(2026, 9, 28), uid: 'lundi');
    final back = OpenRequest.fromPayload(request.toPayload())!;
    expect(back.day, request.day);
    expect(back.uid, 'lundi');
    expect(OpenRequest.fromPayload('pas du json'), isNull);
  });
}
