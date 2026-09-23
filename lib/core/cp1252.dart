/// Décodeur Windows-1252 : NetYParéo renvoie ses pages HTML dans cet encodage.
///
/// Identique à latin1, sauf la plage 0x80-0x9F (€, apostrophes typographiques, œ...).
String decodeCp1252(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    if (byte >= 0x80 && byte <= 0x9F) {
      buffer.writeCharCode(_high[byte - 0x80]);
    } else {
      buffer.writeCharCode(byte);
    }
  }
  return buffer.toString();
}

const List<int> _high = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178, //
];
