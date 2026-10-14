/// Parses unified model labels (`KES_100`, `KES_20_coin`, `USD_25c_coin`,
/// `background`) into notes and coins. This must match the label format
/// produced by training/prepare_dataset.py (see training/config.py).
library;

import 'strings.dart';

const String backgroundLabel = 'background';

class Note {
  final String currency; // ISO code
  final num value; // in main units: 0.25 for a quarter
  final bool coin;
  final bool cents; // value came from a "c" label (25c)
  const Note(this.currency, this.value, {this.coin = false, this.cents = false});

  String get label {
    final v = cents ? '${(value * 100).round()}c' : '${value.toInt()}';
    return coin ? '${currency}_${v}_coin' : '${currency}_$v';
  }

  /// English text for TTS, for example "100 Kenyan shillings" or "20 Kenyan shillings coin".
  String get spoken => spokenIn(const S('en'));

  String spokenIn(S s) => s.noteName(currency, cents ? (value * 100).round() : value, coin: coin, cents: cents);

  /// Parses a label. Returns null for background or unknown labels. Extra
  /// suffixes such as `USD_20_front` are accepted, so separate front and back
  /// classes still announce one denomination.
  static Note? parse(String label) {
    final parts = label.split('_');
    if (parts.length < 2) return null;
    final coin = parts.skip(2).contains('coin');
    final raw = parts[1].toLowerCase();
    if (raw.endsWith('c')) {
      final c = int.tryParse(raw.substring(0, raw.length - 1));
      if (c == null) return null;
      return Note(parts[0].toUpperCase(), c / 100, coin: true, cents: true);
    }
    final value = int.tryParse(raw);
    if (value == null) return null;
    return Note(parts[0].toUpperCase(), value, coin: coin);
  }

  @override
  bool operator ==(Object other) => other is Note && other.label == label;

  @override
  int get hashCode => label.hashCode;
}

String currencyName(String iso, [S s = const S('en')]) => s.currencyName(iso);

class CurrencyInfo {
  final String iso;
  final String country;
  final String flag;
  final String symbol;
  final List<int> notes;
  final List<String> coins; // display names, e.g. "1", "5", "25c"
  const CurrencyInfo(this.iso, this.country, this.flag, this.symbol, this.notes, [this.coins = const []]);
}

/// Notes and coins the model is trained to recognise. Must match training/config.py.
const currencyCatalog = <CurrencyInfo>[
  CurrencyInfo('KES', 'Kenya', '🇰🇪', 'KSh', [50, 100, 200, 500, 1000], ['1', '5', '10', '20']),
  CurrencyInfo('UGX', 'Uganda', '🇺🇬', 'USh', [1000, 2000, 5000, 10000, 20000, 50000], ['100', '200', '500', '1000']),
  CurrencyInfo('INR', 'India', '🇮🇳', '₹', [10, 20, 50, 100, 200, 500, 2000], ['1', '2', '5', '10', '20']),
  CurrencyInfo('EGP', 'Egypt', '🇪🇬', 'E£', [1, 5, 10, 20, 50, 100, 200], ['25c', '50c', '1']),
  CurrencyInfo('USD', 'United States', '🇺🇸', r'$', [1, 2, 5, 10, 20, 50, 100], ['1c', '5c', '10c', '25c']),
];

CurrencyInfo? currencyInfo(String iso) {
  for (final c in currencyCatalog) {
    if (c.iso == iso) return c;
  }
  return null;
}

/// "KSh 1,000", "$ 0.25"
String formatAmount(String iso, num value) {
  final whole = value.truncate();
  final s = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final frac = value - whole;
  final cents = frac.abs() < 0.005 ? '' : '.${((frac * 100).round()).toString().padLeft(2, '0')}';
  return '${currencyInfo(iso)?.symbol ?? iso} $s$cents';
}
