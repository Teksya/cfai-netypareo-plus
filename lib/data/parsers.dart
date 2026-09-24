import 'dart:convert';

import 'package:html/dom.dart';

import 'models.dart';

// -----------------------------------------------------------------------------
// iCalendar

/// Lit le flux iCal NetYParéo. [codeApprenant] sert à retrouver le code séance dans l'UID
/// (format `{codeApprenant}{codeSeance}@NetYpareo`).
List<Seance> parseIcal(String ics, {int? codeApprenant}) {
  final lines = _unfold(ics);
  final seances = <Seance>[];
  Map<String, String>? event;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      event = {};
    } else if (line == 'END:VEVENT') {
      final seance = _eventToSeance(event!, codeApprenant);
      if (seance != null) seances.add(seance);
      event = null;
    } else if (event != null) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).split(';').first;
      event[key] = line.substring(colon + 1);
    }
  }
  seances.sort((a, b) => a.start.compareTo(b.start));
  return seances;
}

List<String> _unfold(String ics) {
  final out = <String>[];
  for (final raw in ics.split(RegExp(r'\r?\n'))) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else if (raw.isNotEmpty) {
      out.add(raw);
    }
  }
  return out;
}

Seance? _eventToSeance(Map<String, String> e, int? codeApprenant) {
  final start = _icalDate(e['DTSTART']);
  final end = _icalDate(e['DTEND']);
  if (start == null || end == null) return null;
  final uid = e['UID'] ?? '${e['DTSTART']}${e['SUMMARY']}';
  final summary = _icalText(e['SUMMARY'] ?? '');
  final dash = summary.indexOf(' - ');
  return Seance(
    uid: uid,
    codeSeance: _codeSeanceFromUid(uid, codeApprenant),
    subject: dash < 0 ? summary : summary.substring(0, dash).trim(),
    teachers: dash < 0 ? '' : summary.substring(dash + 3).trim(),
    room: _icalText(e['LOCATION'] ?? ''),
    group: _icalText(e['DESCRIPTION'] ?? ''),
    start: start,
    end: end,
  );
}

int? _codeSeanceFromUid(String uid, int? codeApprenant) {
  final digits = uid.split('@').first;
  if (codeApprenant == null) return null;
  final prefix = '$codeApprenant';
  if (!digits.startsWith(prefix)) return null;
  return int.tryParse(digits.substring(prefix.length));
}

/// Dates en heure locale Europe/Paris (le téléphone est supposé dans ce fuseau), ou UTC si suffixe Z.
DateTime? _icalDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$').firstMatch(value.trim());
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.tryParse(m.group(i) ?? '0') ?? 0];
  if (m.group(7) == 'Z') {
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).toLocal();
  }
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}

String _icalText(String value) => value
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\')
    .trim();

// -----------------------------------------------------------------------------
// Pages HTML

String cleanText(String? text) => (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Texte riche (paragraphes, listes) vers texte brut avec retours à la ligne.
String richText(Element? element) {
  if (element == null) return '';
  final buffer = StringBuffer();
  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.text.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    if (node is! Element) return;
    final tag = node.localName;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    if (tag == 'li') buffer.write('\n• ');
    for (final child in node.nodes) {
      walk(child);
    }
    if (tag == 'p' || tag == 'div' || tag == 'ul' || tag == 'ol' || tag == 'h1' || tag == 'h2' || tag == 'h3') {
      buffer.write('\n');
    }
  }

  walk(element);
  return buffer
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

/// Profil à partir de la page d'accueil (nom, période, code apprenant).
({String name, String period, int? codeApprenant}) parseAccueil(Document doc) {
  final label = doc.querySelector('.user-info-label');
  final period = cleanText(label?.querySelector('span')?.text);
  final name = cleanText(label?.nodes.whereType<Text>().map((t) => t.text).join(' '));
  int? code;
  for (final a in doc.querySelectorAll('a[href]')) {
    final m = RegExp(r'/apprenant/(?:bulletin|calendrier)/(\d+)/').firstMatch(a.attributes['href']!);
    if (m != null) {
      code = int.parse(m.group(1)!);
      break;
    }
  }
  code ??= int.tryParse(RegExp(r'/apprenant/photo/\d+/(\d+)').firstMatch(doc.outerHtml)?.group(1) ?? '');
  return (name: name, period: period, codeApprenant: code);
}

/// Code et libellé de l'inscription courante (page Assiduité).
({int? codeInscription, String formation}) parseInscription(Document doc) {
  final field = doc.querySelector('[name="codeInscription"]');
  int? code = int.tryParse(field?.attributes['value'] ?? '');
  var formation = '';
  if (field?.localName == 'select') {
    final option = field!.querySelector('option[selected]') ?? field.querySelector('option');
    code ??= int.tryParse(option?.attributes['value'] ?? '');
    formation = cleanText(option?.text);
  }
  if (formation.isEmpty) {
    final m = RegExp(r"inscription (.+?) \(\d{4}-\d{4}\)").firstMatch(cleanText(doc.body?.text));
    formation = m?.group(1) ?? '';
  }
  return (codeInscription: code, formation: formation);
}

String? parseIcalUrl(String html) =>
    RegExp(r'https?://[^\s"<>]+/planning/ical/[A-Za-z0-9-]+/?').firstMatch(html)?.group(0);

List<Absence> parseAbsences(Document doc) {
  final table = doc.querySelectorAll('table').where((t) => cleanText(t.querySelector('thead')?.text).contains('Motif')).firstOrNull;
  if (table == null) return const [];
  final absences = <Absence>[];
  for (final row in table.querySelectorAll('tbody tr')) {
    final cells = row.querySelectorAll('td').map((td) => cleanText(td.text)).toList();
    if (cells.length < 4) continue;
    absences.add(Absence(
      from: cells[0],
      to: cells[1],
      duration: cells[2],
      reason: cells[3],
      detail: cells.length > 4 ? cells[4] : '',
    ));
  }
  return absences;
}

SeanceDetail parseSeanceDetail(Document doc) {
  final title = cleanText(doc.querySelector('.modal-title')?.text);
  final infos = <String, String>{};
  for (final row in doc.querySelectorAll('.section-content .row')) {
    final columns = row.children.where((c) => c.classes.contains('columns')).toList();
    for (var i = 0; i + 1 < columns.length; i += 2) {
      final value = richText(columns[i + 1]).replaceAll('\n', ', ');
      if (value.isNotEmpty && value != '-') infos[cleanText(columns[i].text)] = value;
    }
  }
  final cahiers = doc.querySelectorAll('.js-net-cahier').map((cahier) {
    return CahierEntry(
      title: cleanText(cahier.querySelector('.category-header-title')?.text),
      content: richText(cahier.querySelector('.formated-text')),
      resources: _documentLinks(cahier),
    );
  }).toList();
  return SeanceDetail(title: title, infos: infos, cahiers: cahiers);
}

/// Page "Consultation libre" du cahier de textes.
List<CahierEntry> parseCahierDeTextes(Document doc) {
  final entries = <CahierEntry>[];
  for (final matiere in doc.querySelectorAll('.js-matiere')) {
    final subject = cleanText(matiere.querySelector('.category-header-title')?.text);
    for (final cahier in matiere.querySelectorAll('.js-cahier')) {
      final seanceLink = cahier.querySelector('[data-code-seance]');
      final info = cleanText(cahier.querySelector('.net-cahier-info')?.text);
      final teacher = RegExp(r' par (.+)$').firstMatch(info)?.group(1) ?? '';
      // data-node-list-sort : début de la séance, en secondes Unix.
      final timestamp = int.tryParse(seanceLink?.attributes['data-node-list-sort'] ?? '');
      entries.add(CahierEntry(
        title: cleanText(cahier.querySelector('.category-header-title')?.text),
        content: richText(cahier.querySelector('.formated-text')),
        subject: subject,
        when: cleanText(seanceLink?.text),
        teacher: teacher,
        codeSeance: int.tryParse(seanceLink?.attributes['data-code-seance'] ?? ''),
        date: timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
        resources: _documentLinks(cahier),
      ));
    }
  }
  // Le plus récent d'abord.
  entries.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
  return entries;
}

/// Page `/travail-a-faire/` : groupes par jour d'échéance, précédés de titres
/// "Aujourd'hui", "A venir" (et "En retard" quand il y en a).
List<TravailAFaire> parseTravailAFaire(Document doc) {
  final feed = doc.querySelector('.newsfeed-by-day');
  if (feed == null) return const [];
  final result = <TravailAFaire>[];
  var section = '';
  for (final child in feed.children) {
    if (child.localName == 'h1') {
      section = cleanText(child.text).toLowerCase();
      continue;
    }
    if (!child.classes.contains('newsfeed-group')) continue;
    final day = RegExp(r'(\d{2})/(\d{2})/(\d{4})').firstMatch(child.querySelector('.newsfeed-group-title')?.text ?? '');
    if (day == null) continue;
    final due = DateTime(int.parse(day[3]!), int.parse(day[2]!), int.parse(day[1]!));
    for (final item in child.querySelectorAll('.js-taf-apprenant')) {
      final code = int.tryParse(item.attributes['data-code-taf'] ?? '');
      if (code == null) continue;
      final body = item.querySelector('.newsfeed-item-body');
      final seanceLink = body?.querySelector('a[data-code-seance]');
      // La consigne, sans les documents ni les boutons.
      final consigne = body?.querySelector('.margin-top-1lh')?.clone(true);
      consigne?.querySelectorAll('.section, button, .text-right').forEach((e) => e.remove());
      final undo = item.querySelector('.js-btn-annuler-tfp');
      result.add(TravailAFaire(
        code: code,
        subject: cleanText(item.querySelector('.newsfeed-item-header > div')?.text),
        codeMatiere: int.tryParse(item.attributes['data-code-matiere'] ?? ''),
        dueDate: due,
        givenOn: cleanText(seanceLink?.text),
        codeSeance: int.tryParse(seanceLink?.attributes['data-code-seance'] ?? ''),
        teacher: cleanText(body?.querySelector('b')?.text),
        content: richText(consigne).trim(),
        documents: _documentLinks(item),
        late: section.contains('retard'),
        done: undo != null,
        codeTravailFait: int.tryParse(undo?.attributes['data-code-tfp'] ?? ''),
        toHandIn: item.querySelector('.js-btn-rendre-taf, .btn-edit-tfp') != null,
      ));
    }
  }
  return result;
}

/// Page `/apprenant/documents/` : paramètres signés de l'explorateur, à renvoyer à `/document/liste/`.
({String fsParams, String explorerId})? parseDocumentsHome(String page) {
  final fs = RegExp(r"currentFsParams\s*=\s*'([^']+)'").firstMatch(page)?.group(1);
  final explorer = RegExp(r'explorer-app-\d+').firstMatch(page)?.group(0);
  if (fs == null || explorer == null) return null;
  return (fsParams: fs, explorerId: explorer);
}

/// Contenu d'un dossier (`/document/liste/`) : dossiers d'abord, puis fichiers.
List<DocEntry> parseDocumentList(Document doc) {
  final entries = <DocEntry>[];
  for (final row in doc.querySelectorAll('tbody tr')) {
    final cells = row.querySelectorAll('td');
    final folder = row.querySelector('a[data-resource-type="directory"]');
    if (folder != null) {
      final name = cleanText(folder.attributes['title'] ?? folder.text);
      // La ligne "Dossier précédent" : la navigation se fait dans l'application.
      if (row.querySelector('.document-level-up') != null) continue;
      final count = RegExp(r'\((\d+)\)').firstMatch(folder.querySelector('.text-small')?.text ?? '')?.group(1);
      entries.add(DocEntry(
        name: name,
        isFolder: true,
        count: count == null ? null : int.parse(count),
        fsParams: folder.attributes['data-file-system-params'],
        path: folder.attributes['data-file-system-path'],
      ));
      continue;
    }
    final link = row.querySelector('a[href*="/document/telecharger/"]');
    if (link == null) continue;
    final name = cleanText(link.attributes['title'] ?? link.text);
    final icon = row.querySelector('.icon')?.classes.firstWhere((c) => c.startsWith('document-'), orElse: () => '') ?? '';
    entries.add(DocEntry(
      name: name,
      isFolder: false,
      download: DocumentLink(name, link.attributes['href']!),
      type: cells.length > 2 ? cleanText(cells[2].text) : '',
      modified: cells.length > 5 ? cleanText(cells[5].text) : '',
      kind: icon.replaceFirst('document-', ''),
    ));
  }
  return entries;
}

/// Liste JSON des documents de liaison (`/pedagogie/documents-liaison/lister-ressource/ajax/`).
List<DocLiaison> parseDocsLiaison(String json) {
  final data = jsonDecode(json);
  if (data is! List) return const [];
  return [
    for (final raw in data.whereType<Map<String, dynamic>>())
      DocLiaison(
        code: (raw['codeNetDocLiaisonDepot'] as num?)?.toInt() ?? 0,
        name: '${raw['nomDepot'] ?? ''}'.trim(),
        created: _jsonDate(raw['dateCreation']),
        sender: _personne(raw['emetteur']),
        toReturn: raw['isARetourner'] == true,
        read: raw['dateLu'] != null,
        returned: raw['dateRetour'] != null,
        due: _jsonDate(raw['dateEcheance']),
      ),
  ]..sort((a, b) => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)));
}

String _personne(Object? raw) {
  if (raw is! Map) return '';
  return [raw['abregeCivilite'], raw['nom'], raw['prenom']].where((p) => p != null && '$p'.isNotEmpty).join(' ');
}

/// Dates du JSON NetYParéo : chaîne ISO ou "JJ/MM/AAAA", objet PHP `{date: ...}`, ou timestamp.
DateTime? _jsonDate(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw > 1e11 ? raw.toInt() : raw.toInt() * 1000);
  if (raw is Map) return _jsonDate(raw['date']);
  final text = '$raw';
  final fr = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(text);
  if (fr != null) return DateTime(int.parse(fr[3]!), int.parse(fr[2]!), int.parse(fr[1]!));
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

/// Détail d'un document de liaison : texte et pièces jointes.
({String text, List<DocumentLink> documents}) parseDocLiaisonDetail(Document doc) {
  final body = doc.querySelector('.modal-body, .content-body, body');
  final clone = body?.clone(true);
  clone?.querySelectorAll('script, style, button, a[href*="/document/telecharger/"]').forEach((e) => e.remove());
  return (text: richText(clone).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(), documents: body == null ? const [] : _documentLinks(body));
}

List<DocumentLink> _documentLinks(Element root) => root
    .querySelectorAll('a[href*="/document/telecharger/"]')
    .map((a) => DocumentLink(cleanText(a.text), a.attributes['href']!))
    .toList();

/// Calendrier de formation (`/apprenant/calendrier/{codeApprenant}/`).
///
/// Chaque jour est une case `a[data-date][data-identifiant]` colorée ; la légende associe ces
/// couleurs à « Présence au centre de formation », « Présence en entreprise » ou « Créneaux
/// indisponibles ». Les codes (150, 153, 151 ici) sont retrouvés par la couleur, pour ne pas
/// dépendre de leur valeur.
Alternance parseAlternance(Document doc) {
  String? rgb(String style) {
    final hex = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(style)?.group(1);
    if (hex != null) {
      return [for (var i = 0; i < 6; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)].join(',');
    }
    return RegExp(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)').firstMatch(style)?.let((m) => '${m[1]},${m[2]},${m[3]}');
  }

  DayKind? kindOf(String label) {
    final l = label.toLowerCase();
    if (l.contains('centre')) return DayKind.centre;
    if (l.contains('entreprise')) return DayKind.entreprise;
    if (l.contains('indisponible') || l.contains('férié') || l.contains('ferme')) return DayKind.off;
    return null;
  }

  final legend = <String, DayKind>{};
  for (final item in doc.querySelectorAll('.legende-item')) {
    final color = rgb(item.querySelector('.legende-item-color')?.attributes['style'] ?? '');
    final kind = kindOf(item.querySelector('.legende-item-text')?.text ?? '');
    if (color != null && kind != null) legend[color] = kind;
  }

  final days = <DateTime, DayKind>{};
  for (final cell in doc.querySelectorAll('[data-date][data-identifiant]')) {
    final date = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(cell.attributes['data-date'] ?? '');
    final color = rgb(cell.attributes['style'] ?? '');
    final kind = color == null ? null : legend[color];
    if (date == null || kind == null) continue;
    days[DateTime(int.parse(date[3]!), int.parse(date[2]!), int.parse(date[1]!))] = kind;
  }

  final period = RegExp(r'Calendrier du \d{2}/\d{2}/\d{4} au \d{2}/\d{2}/\d{4}').firstMatch(doc.body?.text ?? '')?.group(0);
  return Alternance(days: days, period: period ?? '');
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
