import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:netypareo_plus/data/parsers.dart';

// Structure de /travail-a-faire/, données fictives.
const _page = '''
<div class="newsfeed-by-day">
  <h1>Aujourd'hui</h1>
  <div class="newsfeed-group">
    <div class="newsfeed-group-title js-jour-taf">Semaine 39<br><span>jeudi 24/09/2026</span></div>
    <div class="newsfeed-group-items"><div class="newsfeed-item">Aucun travail à faire pour aujourd'hui</div></div>
  </div>
  <h1>A venir</h1>
  <div class="newsfeed-group">
    <div class="newsfeed-group-title js-jour-taf">Semaine 42<br><span>vendredi 16/10/2026</span></div>
    <div class="newsfeed-group-items">
      <div class="newsfeed-item js-taf-apprenant" data-code-taf="111" data-code-matiere="222">
        <div class="newsfeed-item-header flex-row"><div> ANGLAIS </div><div></div></div>
        <div class="newsfeed-item-body">
          Donné pendant le cours du <a href="javascript:void(0);" data-code-seance="333"> Jeudi 24 septembre 2026 </a>
          par <b>Mme EXEMPLE Jeanne</b>
          <div class="margin-top-1lh">
            <p>Vocabulary exercise</p>
            <div class="section"><div class="section-title">Documents</div>
              <div class="section-content"><a href="/netypareo/index.php/document/telecharger/abc/">Exercice.pdf</a></div>
            </div>
            <div><div class="text-right"><button class="js-btn-faire-taf" data-code-taf="111">Déclarer comme fait</button></div></div>
          </div>
        </div>
      </div>
      <div class="newsfeed-item js-taf-apprenant" data-code-taf="112" data-code-matiere="223">
        <div class="newsfeed-item-header flex-row"><div>MATHEMATIQUES</div></div>
        <div class="newsfeed-item-body">
          <div class="margin-top-1lh"><p>Page 12</p>
            <button class="js-btn-annuler-tfp" data-code-tfp="999">Annuler</button></div>
        </div>
      </div>
    </div>
  </div>
</div>
''';

void main() {
  test('parseTravailAFaire', () {
    final list = parseTravailAFaire(html.parse(_page));
    expect(list, hasLength(2));
    final anglais = list.first;
    expect(anglais.code, 111);
    expect(anglais.subject, 'ANGLAIS');
    expect(anglais.codeMatiere, 222);
    expect(anglais.dueDate, DateTime(2026, 10, 16));
    expect(anglais.codeSeance, 333);
    expect(anglais.givenOn, 'Jeudi 24 septembre 2026');
    expect(anglais.teacher, 'Mme EXEMPLE Jeanne');
    expect(anglais.content, 'Vocabulary exercise');
    expect(anglais.documents.single.name, 'Exercice.pdf');
    expect(anglais.done, isFalse);
    expect(anglais.late, isFalse);

    final maths = list.last;
    expect(maths.done, isTrue);
    expect(maths.codeTravailFait, 999);
    expect(maths.content, 'Page 12');
  });

  test('page sans fil d\'actualité', () {
    expect(parseTravailAFaire(html.parse('<div></div>')), isEmpty);
  });
}
