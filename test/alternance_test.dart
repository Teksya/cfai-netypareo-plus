import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:netypareo_plus/data/models.dart';
import 'package:netypareo_plus/data/parsers.dart';

void main() {
  test('calendrier de formation : types de journée retrouvés par la couleur de la légende', () {
    final doc = html.parse('''
      <main>
        <h1>Calendrier du 14/09/2026 au 02/07/2027</h1>
        <a class="agenda-cell" style="background-color: rgb(168,255,168);" data-date="14/09/2026" data-identifiant="150">14</a>
        <a class="agenda-cell" style="background-color: rgb(255,128,128);" data-date="21/09/2026" data-identifiant="153">21</a>
        <a class="agenda-cell" style="background-color: rgb(255,125,125);" data-date="11/11/2026" data-identifiant="151">11</a>
        <span class="agenda-cell">19</span>
        <div class="legende">
          <div class="legende-item"><span class="legende-item-color" style="background-color: #FF8080;"></span>
            <span class="legende-item-text">Présence en entreprise</span></div>
          <div class="legende-item"><span class="legende-item-color" style="background-color: #A8FFA8;"></span>
            <span class="legende-item-text">Présence au centre de formation</span></div>
          <div class="legende-item"><span class="legende-item-color" style="background-color: #FF7D7D;"></span>
            <span class="legende-item-text">Créneaux indisponibles</span></div>
        </div>
      </main>''');
    final alternance = parseAlternance(doc);
    expect(alternance.days, {
      DateTime(2026, 9, 14): DayKind.centre,
      DateTime(2026, 9, 21): DayKind.entreprise,
      DateTime(2026, 11, 11): DayKind.off,
    });
    expect(alternance.period, 'Calendrier du 14/09/2026 au 02/07/2027');
    expect(alternance.count(DayKind.centre), 1);
  });
}
