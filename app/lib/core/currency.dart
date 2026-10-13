/// Parses unified model labels (`KES_100`, `background`) into spoken text.
/// This must match the label format produced by training/prepare_dataset.py.
library;

const String backgroundLabel = 'background';

class Note {
  final String currency; // ISO code
  final int value;
  const Note(this.currency, this.value);

  String get label => '${currency}_$value';

  /// Text for TTS, for example "100 Kenyan shillings" or "1 US dollar".
  String get spoken {
    final names = _names[currency];
    if (names == null) return '$value $currency';
    return '$value ${value == 1 ? names.$1 : names.$2}';
  }

  /// Parses a label. Returns null for background or unknown labels. A side
  /// suffix such as `USD_20_front` is accepted, so you can train separate
  /// front and back classes and still announce one denomination.
  static Note? parse(String label) {
    final parts = label.split('_');
    if (parts.length < 2) return null;
    final value = int.tryParse(parts[1]);
    if (value == null) return null;
    return Note(parts[0].toUpperCase(), value);
  }

  @override
  bool operator ==(Object other) => other is Note && other.label == label;

  @override
  int get hashCode => label.hashCode;
}

/// (singular, plural). To add a currency, add one line here and retrain.
const Map<String, (String, String)> _names = {
  'INR': ('rupee', 'rupees'),
  'KES': ('Kenyan shilling', 'Kenyan shillings'),
  'EGP': ('Egyptian pound', 'Egyptian pounds'),
  'UGX': ('Ugandan shilling', 'Ugandan shillings'),
  'USD': ('US dollar', 'US dollars'),
};

String currencyName(String iso) => _names[iso]?.$2 ?? iso;

class CurrencyInfo {
  final String iso;
  final String country;
  final String flag;
  final String symbol;
  final List<int> notes;
  const CurrencyInfo(this.iso, this.country, this.flag, this.symbol, this.notes);
}

/// Notes the model is trained to recognise. Must match training/config.py.
const currencyCatalog = <CurrencyInfo>[
  CurrencyInfo('KES', 'Kenya', '🇰🇪', 'KSh', [50, 100, 200, 500, 1000]),
  CurrencyInfo('UGX', 'Uganda', '🇺🇬', 'USh', [1000, 2000, 5000, 10000, 20000, 50000]),
  CurrencyInfo('INR', 'India', '🇮🇳', '₹', [10, 20, 50, 100, 200, 500, 2000]),
  CurrencyInfo('EGP', 'Egypt', '🇪🇬', 'E£', [1, 5, 10, 20, 50, 100, 200]),
  CurrencyInfo('USD', 'United States', '🇺🇸', r'$', [1, 2, 5, 10, 20, 50, 100]),
];

CurrencyInfo? currencyInfo(String iso) {
  for (final c in currencyCatalog) {
    if (c.iso == iso) return c;
  }
  return null;
}

/// "KSh 1,000"
String formatAmount(String iso, int value) {
  final s = value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${currencyInfo(iso)?.symbol ?? iso} $s';
}
