import 'package:flutter_test/flutter_test.dart';
import 'package:netypareo_plus/ui/format.dart';

void main() {
  test('matières abrégées pour la vue semaine', () {
    expect(shortSubject('CULTURE ECONOMIQUE JURIDIQUE ET MANAGERIALE'), 'CEJM');
    expect(shortSubject('CULTURE GENERALE ET EXPRESSION'), 'CGE');
    expect(shortSubject('MATHEMATIQUES / ALGO'), 'Maths / ALGO');
    expect(shortSubject('ANGLAIS'), 'Anglais');
    expect(shortSubject('SLAM'), 'SLAM');
  });
}
