/// Montants en toutes lettres pour les factures
/// (« Arrêtée la présente facture à la somme de … francs CFA »).
class AmountWords {
  static const _units = [
    'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', //
    'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize',
  ];
  static const _tens = ['', 'dix', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

  /// 0 à 99.
  static String _below100(int n) {
    if (n < 17) return _units[n];
    if (n < 20) return 'dix-${_units[n - 10]}';
    if (n < 70) {
      final t = n ~/ 10, u = n % 10;
      if (u == 0) return _tens[t];
      if (u == 1) return '${_tens[t]} et un';
      return '${_tens[t]}-${_units[u]}';
    }
    if (n < 80) {
      if (n == 71) return 'soixante et onze';
      return 'soixante-${_below100(n - 60)}';
    }
    if (n == 80) return 'quatre-vingts';
    return 'quatre-vingt-${_below100(n - 80)}';
  }

  /// 0 à 999. [plural] : « cents » / « vingts » prennent un s en fin de nombre seulement.
  static String _below1000(int n, {bool endOfNumber = true}) {
    final h = n ~/ 100, r = n % 100;
    String rest = r == 0 ? '' : _below100(r);
    if (!endOfNumber && r == 80) rest = 'quatre-vingt';
    if (h == 0) return rest;
    final hundred = h == 1 ? 'cent' : '${_units[h]} cent${r == 0 && endOfNumber ? 's' : ''}';
    return r == 0 ? hundred : '$hundred $rest';
  }

  /// Entier positif en lettres (jusqu'à 999 999 999 999).
  static String integer(int n) {
    if (n < 0) return 'moins ${integer(-n)}';
    if (n == 0) return 'zéro';
    final parts = <String>[];
    final billions = n ~/ 1000000000;
    final millions = (n ~/ 1000000) % 1000;
    final thousands = (n ~/ 1000) % 1000;
    final rest = n % 1000;
    if (billions > 0) parts.add('${_below1000(billions)} milliard${billions > 1 ? 's' : ''}');
    if (millions > 0) parts.add('${_below1000(millions)} million${millions > 1 ? 's' : ''}');
    if (thousands > 0) {
      // « mille » est invariable et on ne dit pas « un mille ».
      parts.add(thousands == 1 ? 'mille' : '${_below1000(thousands, endOfNumber: false)} mille');
    }
    if (rest > 0) parts.add(_below1000(rest));
    return parts.join(' ');
  }

  /// « Cent vingt-cinq mille francs CFA » (arrondi au franc).
  static String francs(double amount) {
    final n = amount.round();
    final words = integer(n);
    return '${words[0].toUpperCase()}${words.substring(1)} franc${n > 1 ? 's' : ''} CFA';
  }
}
