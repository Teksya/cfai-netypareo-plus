import 'package:netypareo_plus/data/parsers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  test("paramètres de l'explorateur de documents", () {
    const page = '''<script>var currentFsParams = 'abc123==';</script>
      <div id="explorer-app-42"></div>''';
    final home = parseDocumentsHome(page);
    expect(home?.fsParams, 'abc123==');
    expect(home?.explorerId, 'explorer-app-42');
    expect(parseDocumentsHome('<html></html>'), isNull);
  });

  test('contenu d\'un dossier : dossiers, fichiers, sans la ligne "dossier précédent"', () {
    final doc = html_parser.parse('''<table><tbody>
      <tr><td><a data-resource-type="directory" data-file-system-params="p0" data-file-system-path="up" title="..">
        <i class="icon document-level-up"></i></a></td></tr>
      <tr><td><a data-resource-type="directory" data-file-system-params="p1" data-file-system-path="L2E=" title="Bulletins">
        Bulletins <span class="text-small">(3)</span></a></td></tr>
      <tr>
        <td><i class="icon document-pdf"></i></td>
        <td><a href="/netypareo/index.php/document/telecharger/xyz/" title="Convention.pdf">Convention.pdf</a></td>
        <td>Convention</td><td>Apprenant</td><td>Le CFA</td><td>27/04/2026 à 16:19</td>
      </tr>
    </tbody></table>''');
    final entries = parseDocumentList(doc);
    expect(entries, hasLength(2));
    expect(entries[0].isFolder, isTrue);
    expect(entries[0].name, 'Bulletins');
    expect(entries[0].count, 3);
    expect(entries[0].path, 'L2E=');
    expect(entries[1].isFolder, isFalse);
    expect(entries[1].name, 'Convention.pdf');
    expect(entries[1].download?.path, '/netypareo/index.php/document/telecharger/xyz/');
    expect(entries[1].type, 'Convention');
    expect(entries[1].modified, '27/04/2026 à 16:19');
    expect(entries[1].kind, 'pdf');
  });

  test('documents de liaison : JSON trié du plus récent au plus ancien', () {
    final docs = parseDocsLiaison('''[
      {"codeNetDocLiaisonDepot": 1, "nomDepot": "Ancien", "dateCreation": "02/09/2026",
       "emetteur": {"abregeCivilite": "M.", "nom": "Martin", "prenom": "Paul"}, "dateLu": "03/09/2026"},
      {"codeNetDocLiaisonDepot": 2, "nomDepot": "Fiche entreprise", "dateCreation": "2026-09-20 10:00:00",
       "isARetourner": true, "dateEcheance": "30/09/2026", "dateLu": null}
    ]''');
    expect(docs.map((d) => d.code), [2, 1]);
    expect(docs[0].toReturn, isTrue);
    expect(docs[0].read, isFalse);
    expect(docs[0].due, DateTime(2026, 9, 30));
    expect(docs[1].sender, 'M. Martin Paul');
    expect(docs[1].read, isTrue);
    expect(parseDocsLiaison('{}'), isEmpty);
  });
}
