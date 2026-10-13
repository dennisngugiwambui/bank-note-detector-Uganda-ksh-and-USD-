import 'package:flutter/services.dart';

import 'tflite_model.dart';

/// ImageNet classifier (EfficientNet-Lite0, 1000 classes) for things the COCO
/// detector does not know: shoes, clothes, windows, doors, street signs...
///
/// ImageNet splits one everyday thing over many fine labels ("space bar",
/// "computer keyboard"), so probabilities are summed per spoken name.
class SceneClassifier {
  static const modelAsset = 'assets/scene/model.tflite';
  static const labelsAsset = 'assets/scene/labels.txt';

  final TfliteModel _model;
  final List<String> _names; // spoken name per class index
  SceneClassifier._(this._model, this._names);

  int get inputSize => _model.inputWidth;

  static Future<SceneClassifier?> load() async {
    final model = await TfliteModel.load(modelAsset);
    if (model == null) return null;
    final labels = (await rootBundle.loadString(labelsAsset)).split('\n').map((l) => l.trim()).toList();
    return SceneClassifier._(model, [for (final l in labels) spokenName(l)]);
  }

  /// Best guess as (name, probability), or null if nothing reaches [minScore].
  Future<(String, double)?> classify(Uint8List rgb, {double minScore = 0.3}) async {
    final probs = (await _model.run(rgb)).first;
    final byName = <String, double>{};
    for (var i = 0; i < probs.length && i < _names.length; i++) {
      if (_names[i].isEmpty) continue;
      byName[_names[i]] = (byName[_names[i]] ?? 0) + probs[i];
    }
    if (byName.isEmpty) return null;
    final best = byName.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value >= minScore ? (best.key, best.value) : null;
  }

  void close() => _model.close();
}

/// Everyday name for an ImageNet label. Labels not listed keep their own
/// name; animals and other things a user is unlikely to point at stay as-is.
String spokenName(String imagenetLabel) => imagenetGroups[imagenetLabel] ?? imagenetLabel.toLowerCase();

const imagenetGroups = <String, String>{
  // Footwear
  'running shoe': 'shoes', 'sandal': 'shoes', 'Loafer': 'shoes', 'clog': 'shoes', 'cowboy boot': 'boots',
  'sock': 'socks',
  // Clothes
  'jersey': 'T-shirt', 'sweatshirt': 'sweatshirt', 'cardigan': 'sweater', 'jean': 'jeans',
  'suit': 'suit', 'trench coat': 'coat', 'fur coat': 'coat', 'lab coat': 'coat', 'gown': 'dress',
  'academic gown': 'gown', 'miniskirt': 'skirt', 'overskirt': 'skirt', 'hoopskirt': 'skirt',
  'pajama': 'pyjamas', 'kimono': 'robe', 'apron': 'apron', 'cowboy hat': 'hat', 'sombrero': 'hat',
  'bonnet': 'hat', 'shower cap': 'cap', 'bathing cap': 'cap', 'sunglass': 'sunglasses', 'sunglasses': 'sunglasses',
  'backpack': 'backpack', 'purse': 'handbag', 'wallet': 'wallet',
  // Home
  'window screen': 'window', 'window shade': 'window blind', 'sliding door': 'door', 'shower curtain': 'curtain',
  'theater curtain': 'curtain', 'doormat': 'doormat', 'studio couch': 'sofa', 'folding chair': 'chair',
  'rocking chair': 'chair', 'barber chair': 'chair', 'dining table': 'table', 'desk': 'desk',
  'wardrobe': 'wardrobe', 'bookcase': 'bookshelf', 'china cabinet': 'cabinet', 'pillow': 'pillow',
  'table lamp': 'lamp', 'lampshade': 'lamp', 'refrigerator': 'fridge', 'stove': 'cooker', 'microwave': 'microwave',
  'toilet seat': 'toilet', 'toilet tissue': 'toilet paper', 'wall clock': 'clock', 'analog clock': 'clock',
  'digital clock': 'clock', 'stone wall': 'wall', 'tile roof': 'roof', 'picket fence': 'fence',
  'chainlink fence': 'fence', 'worm fence': 'fence', 'turnstile': 'turnstile',
  // Kitchen
  'water bottle': 'bottle', 'pop bottle': 'bottle', 'beer bottle': 'bottle', 'wine bottle': 'bottle',
  'pill bottle': 'pill bottle', 'coffee mug': 'cup', 'cup': 'cup', 'measuring cup': 'cup', 'beer glass': 'glass',
  'plate': 'plate', 'teapot': 'teapot', 'coffeepot': 'kettle', 'pot': 'pot', 'Crock Pot': 'pot',
  'wooden spoon': 'spoon',
  // Electronics
  'computer keyboard': 'keyboard', 'space bar': 'keyboard', 'typewriter keyboard': 'keyboard',
  'laptop': 'laptop', 'notebook': 'laptop', 'desktop computer': 'computer', 'monitor': 'screen',
  'screen': 'screen', 'television': 'television', 'cellular telephone': 'phone', 'dial telephone': 'phone',
  'pay-phone': 'phone', 'remote control': 'remote control', 'mouse': 'computer mouse', 'digital watch': 'watch',
  'stopwatch': 'watch', 'microphone': 'microphone',
  // Street
  'street sign': 'street sign', 'traffic light': 'traffic light', 'manhole cover': 'manhole cover',
  'park bench': 'bench', 'cab': 'taxi', 'minivan': 'van', 'police van': 'police van', 'moving van': 'van',
  'minibus': 'minibus', 'school bus': 'bus', 'trolleybus': 'bus', 'streetcar': 'tram', 'moped': 'motorbike',
  'motor scooter': 'motorbike', 'mountain bike': 'bicycle', 'bicycle-built-for-two': 'bicycle',
  'garbage truck': 'truck', 'tow truck': 'truck', 'trailer truck': 'truck', 'car wheel': 'car',
  'car mirror': 'car',
  // Reading and writing
  'ballpoint': 'pen', 'fountain pen': 'pen', 'comic book': 'book', 'book jacket': 'book', 'umbrella': 'umbrella',
};
