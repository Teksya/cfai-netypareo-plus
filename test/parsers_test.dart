import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:netypareo_plus/core/cp1252.dart';
import 'package:netypareo_plus/data/parsers.dart';

// Données fictives, calquées sur les réponses réelles de NetYParéo (voir docs/netypareo-api.md).

const _ics = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:123456716572757@NetYpareo\r\n'
    'DESCRIPTION:BTS SIO 1 GR1 - SE - 26-27\r\n'
    'DTSTART;TZID=Europe/Paris:20260914T100000\r\n'
    'DTEND;TZID=Europe/Paris:20260914T120000\r\n'
    'LOCATION:(CITE) SALLE A\r\n'
    'SUMMARY:ANGLAIS - Mme FORMATRICE\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:123456716572764@NetYpareo\r\n'
    'DTSTART;TZID=Europe/Paris:20260914T090000\r\n'
    'DTEND;TZID=Europe/Paris:20260914T100000\r\n'
    'LOCATION:(CITE) SALLE A\r\n'
    'SUMMARY:ACCUEIL - Mme A - \r\n'
    ' Mme B\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  test('cp1252 décode les caractères spécifiques à Windows', () {
    expect(decodeCp1252([0x80, 0x20, 0xE9, 0x9C, 0x92]), '€ éœ’');
  });

  group('parseIcal', () {
    final seances = parseIcal(_ics, codeApprenant: 1234567);

    test('trie les séances et lit les dates locales', () {
      expect(seances, hasLength(2));
      expect(seances.first.subject, 'ACCUEIL');
      expect(seances.first.start, DateTime(2026, 9, 14, 9));
      expect(seances.last.end, DateTime(2026, 9, 14, 12));
    });

    test('sépare matière et formateurs, déplie les lignes longues', () {
      expect(seances.first.teachers, 'Mme A - Mme B');
      expect(seances.last.room, '(CITE) SALLE A');
      expect(seances.last.group, 'BTS SIO 1 GR1 - SE - 26-27');
    });

    test('retrouve le code séance dans l\'UID', () {
      expect(seances.last.codeSeance, 16572757);
      expect(parseIcal(_ics).first.codeSeance, isNull);
    });
  });

  test('parseSeanceDetail', () {
    final doc = html_parser.parse('''
      <div class="modal-title"><span>MATHEMATIQUES / ALGO de 10h00 à 12h00</span></div>
      <div class="modal-body"><div class="section"><div class="section-content">
        <div class="row"><div class="columns two">Groupe(s)</div><div class="columns four">G1<br>G2</div>
          <div class="columns two">Formateur(s)</div><div class="columns four"> M. PROF </div></div>
        <div class="row"><div class="columns two">Matériel(s)</div><div class="columns four"> - </div></div>
      </div></div>
      <div class="js-net-cahier"><div class="category-header-title"> Rappels </div>
        <div class="formated-text"><p>Puissances</p><ul><li><p>Racine carrée</p></li></ul></div>
        <a href="/netypareo/index.php/document/telecharger/abc/"> cours.pdf </a></div></div>''');
    final detail = parseSeanceDetail(doc);
    expect(detail.title, 'MATHEMATIQUES / ALGO de 10h00 à 12h00');
    expect(detail.infos, {'Groupe(s)': 'G1, G2', 'Formateur(s)': 'M. PROF'});
    expect(detail.cahiers.single.title, 'Rappels');
    expect(detail.cahiers.single.content, 'Puissances\n• Racine carrée');
    expect(detail.cahiers.single.resources.single.name, 'cours.pdf');
  });

  group('parseAbsences', () {
    const head = '<table><thead><tr><th>Du</th><th>Au</th><th>Durée</th><th>Motif</th><th>Détail</th></tr></thead>';

    test('aucune absence', () {
      final doc = html_parser.parse('$head<tbody><tr><td colspan="5">Aucune absence constatée.</td></tr></tbody></table>');
      expect(parseAbsences(doc), isEmpty);
    });

    test('lit une ligne', () {
      final doc = html_parser.parse(
          '$head<tbody><tr><td>02/10/2026</td><td>02/10/2026</td><td>4h00</td><td>Maladie</td><td>Certificat</td></tr></tbody></table>');
      final a = parseAbsences(doc).single;
      expect(a.from, '02/10/2026');
      expect(a.duration, '4h00');
      expect(a.reason, 'Maladie');
    });
  });

  test('parseCahierDeTextes', () {
    final doc = html_parser.parse('''
      <div class="js-matiere"><div class="category-header-title"> ANGLAIS </div>
        <div class="js-cahier"><div class="category-header-title"><div>Evaluation</div></div>
          <div class="net-cahier-info">Séance du <a data-code-seance="42"> Lundi 14 septembre 2026 de 10h00 à 12h00 </a> par Mme PROF</div>
          <div class="formated-text"><p>Oral</p></div></div></div>''');
    final entry = parseCahierDeTextes(doc).single;
    expect(entry.subject, 'ANGLAIS');
    expect(entry.title, 'Evaluation');
    expect(entry.when, 'Lundi 14 septembre 2026 de 10h00 à 12h00');
    expect(entry.teacher, 'Mme PROF');
    expect(entry.codeSeance, 42);
    expect(entry.content, 'Oral');
  });

  test('parseAccueil et parseIcalUrl', () {
    final doc = html_parser.parse('''
      <span class="user-info-label"> NOM Prénom <br><span>Période 2026-2027</span></span>
      <a href="/netypareo/index.php/apprenant/bulletin/1234567/">Bulletin</a>''');
    final accueil = parseAccueil(doc);
    expect(accueil.name, 'NOM Prénom');
    expect(accueil.period, 'Période 2026-2027');
    expect(accueil.codeApprenant, 1234567);
    expect(
      parseIcalUrl('<p>https://example.org/netypareo/index.php/planning/ical/AAAA-1111/</p>'),
      'https://example.org/netypareo/index.php/planning/ical/AAAA-1111/',
    );
  });
}
