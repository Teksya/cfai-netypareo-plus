const _smallWords = {'ET', 'DE', 'DU', 'DES', 'LA', 'LE', 'LES', 'EN', 'A', 'AU', 'AUX'};

/// "CULTURE ECONOMIQUE ET JURIDIQUE" -> "Culture Economique et Juridique".
/// Les sigles courts (SISR, SLAM, ALGO) restent en majuscules.
String capitalizeWords(String s) {
  final words = s.split(' ');
  return [
    for (var i = 0; i < words.length; i++)
      if (words[i].toUpperCase() != words[i])
        words[i]
      else if (i > 0 && _smallWords.contains(words[i]))
        words[i].toLowerCase()
      else if (words[i].length <= 4)
        words[i]
      else
        words[i][0] + words[i].substring(1).toLowerCase(),
  ].join(' ');
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
