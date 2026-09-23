import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/format.dart';
import 'models.dart';

/// Copie du planning dans un agenda "NetYParéo+" du téléphone. Google Agenda, Samsung Agenda
/// et les autres applications d'agenda l'affichent comme n'importe quel agenda local.
///
/// On retient, pour chaque séance, l'événement créé et une empreinte de son contenu : à chaque
/// synchronisation, seuls les cours ajoutés, modifiés ou retirés touchent l'agenda.
class CalendarMirror {
  CalendarMirror._();

  static const _kEnabled = 'calendarMirror';
  static const _kCalendarId = 'calendarMirrorId';
  static const _kEvents = 'calendarMirrorEvents';
  static const _name = 'NetYParéo+';

  static final _calendar = DeviceCalendar.instance;

  static bool enabled(SharedPreferences prefs) => prefs.getBool(_kEnabled) ?? false;

  /// Crée l'agenda et y copie le planning. Renvoie false si Android refuse l'accès à l'agenda.
  static Future<bool> enable(SharedPreferences prefs, List<Seance> seances) async {
    final status = await _calendar.requestPermissions();
    if (status != CalendarPermissionStatus.granted) return false;
    await prefs.setBool(_kEnabled, true);
    await sync(prefs, seances);
    return true;
  }

  /// Supprime l'agenda "NetYParéo+" et tous ses cours.
  static Future<void> disable(SharedPreferences prefs) async {
    await prefs.setBool(_kEnabled, false);
    final id = prefs.getString(_kCalendarId);
    await prefs.remove(_kCalendarId);
    await prefs.remove(_kEvents);
    if (id == null) return;
    try {
      await _calendar.deleteCalendar(id);
    } catch (e) {
      debugPrint('Agenda déjà supprimé : $e');
    }
  }

  static Future<void> _queue = Future.value();

  /// Une seule copie à la fois, sinon deux synchronisations proches créeraient des doublons.
  static Future<void> sync(SharedPreferences prefs, List<Seance> seances) {
    final run = _queue.then((_) => _sync(prefs, seances));
    _queue = run.catchError((_) {});
    return run;
  }

  static Future<void> _sync(SharedPreferences prefs, List<Seance> seances) async {
    if (!enabled(prefs)) return;
    if (await _calendar.hasPermissions() != CalendarPermissionStatus.granted) return;
    final calendarId = await _ensureCalendar(prefs);
    final known = <String, List<String>>{
      for (final e in (jsonDecode(prefs.getString(_kEvents) ?? '{}') as Map<String, dynamic>).entries)
        e.key: (e.value as List).cast<String>(),
    };
    final next = <String, List<String>>{};
    for (final s in seances) {
      final stamp = _fingerprint(s);
      final existing = known.remove(s.uid);
      if (existing != null && existing[1] == stamp) {
        next[s.uid] = existing;
        continue;
      }
      if (existing != null) await _delete(existing[0]);
      final id = await _calendar.createEvent(
        calendarId: calendarId,
        title: capitalizeWords(s.subject),
        startDate: s.start,
        endDate: s.end,
        location: s.room.isEmpty ? null : s.room,
        description: [
          if (s.teachers.isNotEmpty) 'Formateur : ${s.teachers}',
          if (s.group.isNotEmpty) 'Groupe : ${s.group}',
        ].join('\n'),
      );
      next[s.uid] = [id, stamp];
    }
    // Ce qui reste dans `known` n'est plus au planning.
    for (final gone in known.values) {
      await _delete(gone[0]);
    }
    await prefs.setString(_kEvents, jsonEncode(next));
  }

  static Future<String> _ensureCalendar(SharedPreferences prefs) async {
    final calendars = await _calendar.listCalendars();
    final stored = prefs.getString(_kCalendarId);
    if (stored != null && calendars.any((c) => c.id == stored)) return stored;
    // Agenda supprimé à la main (ou réinstallation) : on repart de zéro.
    final id = await _calendar.createCalendar(name: _name, colorHex: '#6D5BF7');
    await prefs.setString(_kCalendarId, id);
    await prefs.remove(_kEvents);
    return id;
  }

  static Future<void> _delete(String eventId) async {
    try {
      await _calendar.deleteEvent(eventId: eventId);
    } catch (e) {
      debugPrint('Événement déjà supprimé : $e');
    }
  }

  static String _fingerprint(Seance s) =>
      [s.subject, s.start.toIso8601String(), s.end.toIso8601String(), s.room, s.teachers, s.group].join('|');
}
