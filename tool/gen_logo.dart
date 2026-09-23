// Génère le logo de NetYParéo+ en SVG : `dart run tool/gen_logo.dart`.
// Puis conversion en PNG avec Chrome headless (voir tool/README.md).
import 'dart:io';
import 'dart:math' as math;

const violet = '#6D5BF7';
const violetDark = '#4B37D9';
const lime = '#C6F432';
const ink = '#1E1B4B';

/// Chemin de la forme "cookie" M3 Expressive, centré en (cx, cy).
String cookie(double cx, double cy, double r, {int lobes = 9, double depth = 0.07}) {
  final b = StringBuffer();
  const steps = 360;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps * 2 * math.pi;
    final rr = r * (1 - depth + depth * math.cos(lobes * t));
    final x = cx + math.cos(t - math.pi / 2) * rr;
    final y = cy + math.sin(t - math.pi / 2) * rr;
    b.write('${i == 0 ? 'M' : 'L'}${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} ');
  }
  return '${b}Z';
}

/// Le motif : cookie violet, calendrier blanc, badge "+" citron. [scale] réduit l'ensemble
/// autour du centre (icône adaptative Android : tout doit tenir dans le cercle central de 66 %).
String motif({double scale = 1}) => '''
  <g transform="translate(512 512) scale($scale) translate(-512 -512)">
    <defs>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="$violet"/>
        <stop offset="1" stop-color="$violetDark"/>
      </linearGradient>
    </defs>
    <path d="${cookie(512, 512, 470)}" fill="url(#g)"/>
    <!-- Calendrier -->
    <rect x="262" y="300" width="500" height="440" rx="72" fill="#FFFFFF"/>
    <path d="M262 372 a72 72 0 0 1 72 -72 h356 a72 72 0 0 1 72 72 v44 h-500 z" fill="$ink"/>
    <rect x="352" y="248" width="44" height="108" rx="22" fill="#FFFFFF" stroke="$ink" stroke-width="16"/>
    <rect x="628" y="248" width="44" height="108" rx="22" fill="#FFFFFF" stroke="$ink" stroke-width="16"/>
    <rect x="322" y="480" width="170" height="60" rx="30" fill="$violet"/>
    <rect x="322" y="580" width="260" height="60" rx="30" fill="#D9D4FF"/>
    <!-- Badge + -->
    <path d="${cookie(724, 676, 142, lobes: 8, depth: 0.08)}" fill="$lime" stroke="$ink" stroke-width="18"/>
    <rect x="700" y="610" width="48" height="132" rx="24" fill="$ink"/>
    <rect x="658" y="652" width="132" height="48" rx="24" fill="$ink"/>
  </g>''';

void main() {
  final dir = Directory('assets/logo')..createSync(recursive: true);
  File('${dir.path}/logo.svg').writeAsStringSync(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">${motif()}\n</svg>\n',
  );
  File('${dir.path}/logo_foreground.svg').writeAsStringSync(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">${motif(scale: 0.62)}\n</svg>\n',
  );
  stdout.writeln('assets/logo/logo.svg et logo_foreground.svg générés.');
}
