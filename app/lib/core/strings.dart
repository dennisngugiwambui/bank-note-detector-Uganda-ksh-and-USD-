/// Everything NoteLens says or shows, in English and Kiswahili.
///
/// Spoken text matters most here: a blind user hears every string. To add a
/// language, add its code to [appLanguages], a branch to [S._p] and an
/// object-name table, then fill each `_p(...)` call.
library;

/// code -> (name in that language, TTS locale, speech-recognition locale)
const appLanguages = <String, (String, String, String)>{
  'en': ('English', 'en-US', 'en_US'),
  'sw': ('Kiswahili', 'sw-KE', 'sw_KE'),
};

class S {
  final String lang;
  const S(this.lang);

  bool get isSw => lang == 'sw';
  String _p(String en, String sw) => isSw ? sw : en;

  /// For one-off sentences that do not need a named getter.
  String t(String en, String sw) => _p(en, sw);

  // ------------------------------------------------------------ navigation
  String get home => _p('Home', 'Nyumbani');
  String get activity => _p('Activity', 'Historia');
  String get scan => _p('Scan', 'Changanua');
  String get wallet => _p('Wallet', 'Pochi');
  String get settings => _p('Settings', 'Mipangilio');
  String unread(int n) => _p('$n unread', '$n hazijasomwa');
  String tabHint(String tab) => _p('$tab tab', 'Kichupo cha $tab');

  // ------------------------------------------------------------ home
  String get scanMoney => _p('Scan money', 'Soma pesa');
  String get scanMoneyHint => _p('Double tap to start scanning money.', 'Gusa mara mbili kuanza kusoma pesa.');
  String get aroundMe => _p('What is in front of me?', 'Nini kiko mbele yangu?');
  String get aroundMeHint =>
      _p('Double tap to describe your surroundings.', 'Gusa mara mbili kuelezwa mazingira yako.');
  String get voiceCommand => _p('Voice command', 'Amri ya sauti');
  String get voiceCommandHint => _p('Double tap, then say what you want.', 'Gusa mara mbili, kisha sema unachotaka.');

  // ------------------------------------------------------------ scanning
  String get moneyMode => _p('Money mode. Point the camera at a note or coin.',
      'Hali ya pesa. Elekeza kamera kwenye noti au sarafu.');
  String get objectsMode => _p('Objects mode. Hold the phone at chest height and walk slowly.',
      'Hali ya vitu. Shika simu usawa wa kifua na utembee polepole.');
  String get pointAtNote => _p('Point the camera at a note', 'Elekeza kamera kwenye noti');
  String get describing => _p('Describing your surroundings', 'Ninaeleza mazingira yako');
  String get modelMissing => _p('Money recognition is missing from this version. Please update NoteLens.',
      'Utambuzi wa pesa haupo kwenye toleo hili. Tafadhali sasisha NoteLens.');
  String gettingReady(int seconds) => _p('Getting NoteLens ready. About ${secondsWords(seconds)}.',
      'Natayarisha NoteLens. Takriban ${secondsWords(seconds)}.');
  String secondsWords(int n) => n <= 1
      ? _p('one second', 'sekunde moja')
      : n < 60
          ? _p('$n seconds', 'sekunde $n')
          : _p('${(n / 60).ceil()} minutes', 'dakika ${(n / 60).ceil()}');
  String loadingStatus(int percent, int seconds) => _p('Getting ready, $percent percent, about ${secondsWords(seconds)} left',
      'Inatayarishwa, asilimia $percent, takriban ${secondsWords(seconds)} zimebaki');
  String get noNote => _p('No note in view', 'Hakuna noti');
  String get tooDark => _p('Too dark. Move to better light.', 'Giza sana. Nenda kwenye mwanga zaidi.');
  String get lowLightTorch => _p('Low light. Turning the light on.', 'Mwanga hafifu. Ninawasha tochi.');
  String get holdSteady => _p('Hold steady', 'Shika simu bila kutikisa');
  String get lightOn => _p('Light on', 'Tochi imewashwa');
  String get lightOff => _p('Light off', 'Tochi imezimwa');
  String get light => _p('Light', 'Tochi');
  String get repeat => _p('Repeat', 'Rudia');
  String get add => _p('Add', 'Ongeza');
  String get checkFake => _p('Check fake', 'Kagua bandia');
  String get cameraView => _p('Camera view', 'Kamera');
  String get cameraHint => _p('Double tap to repeat. Press and hold for a voice command.',
      'Gusa mara mbili kurudia. Bonyeza na ushikilie kwa amri ya sauti.');
  String get nothingRecognized => _p('Nothing recognized', 'Sijatambua kitu');
  String get pathClear => _p('Path looks clear', 'Njia inaonekana wazi');
  String get pointingDown => _p('Camera is pointing down', 'Kamera inaelekea chini');
  String cameraUnavailable(String why) => _p('Camera unavailable: $why', 'Kamera haipatikani: $why');
  String get noNoteYet => _p('No note identified yet', 'Bado sijatambua noti');
  String get firstIdentify =>
      _p('First point the camera at a note until it is identified.', 'Kwanza elekeza kamera kwenye noti hadi itambuliwe.');
  String added(String note) => _p('Added $note.', 'Nimeongeza $note.');
  String addedTotal(String note, String total) => _p('Added $note. Total $total.', 'Nimeongeza $note. Jumla $total.');
  String banknoteFound(String note) => _p('Money: $note', 'Pesa: $note');

  // ------------------------------------------------------------ money
  String noteName(String iso, num value, {bool coin = false, bool cents = false}) {
    final v = _number(value);
    if (cents) {
      return _p('$v cent coin', 'sarafu ya senti $v');
    }
    final names = isSw ? _currencySw[iso] : _currencyEn[iso];
    final name = names == null ? iso : (value == 1 && !isSw ? names.$1 : names.$2);
    if (isSw) return coin ? 'sarafu ya $name $v' : '$name $v';
    return coin ? '$v $name coin' : '$v $name';
  }

  String currencyName(String iso) => (isSw ? _currencySw[iso] : _currencyEn[iso])?.$2 ?? iso;

  String _number(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static const _currencyEn = <String, (String, String)>{
    'INR': ('rupee', 'rupees'),
    'KES': ('Kenyan shilling', 'Kenyan shillings'),
    'EGP': ('Egyptian pound', 'Egyptian pounds'),
    'UGX': ('Ugandan shilling', 'Ugandan shillings'),
    'USD': ('US dollar', 'US dollars'),
  };
  static const _currencySw = <String, (String, String)>{
    'INR': ('rupia', 'rupia'),
    'KES': ('shilingi ya Kenya', 'shilingi za Kenya'),
    'EGP': ('pauni ya Misri', 'pauni za Misri'),
    'UGX': ('shilingi ya Uganda', 'shilingi za Uganda'),
    'USD': ('dola ya Marekani', 'dola za Marekani'),
  };

  // ------------------------------------------------------------ surroundings
  /// Object name in this language (COCO and the scene-classifier names).
  String object(String english) => isSw ? (_objectsSw[english] ?? english) : english;

  String count(int n, String name) => n == 1 ? name : (isSw ? '$name $n' : '$n ${_plural(name)}');

  static String _plural(String w) {
    if (w.endsWith('s') || w.endsWith('es')) return w;
    if (w == 'person') return 'people';
    if (w.endsWith('sh') || w.endsWith('ch') || w.endsWith('x')) return '${w}es';
    if (w.endsWith('y') && !'aeiou'.contains(w[w.length - 2])) return '${w.substring(0, w.length - 1)}ies';
    if (w.endsWith('knife')) return '${w.substring(0, w.length - 2)}ves';
    return '${w}s';
  }

  String get ahead => _p('ahead', 'mbele');
  String get slightlyLeft => _p('slightly left', 'kushoto kidogo');
  String get slightlyRight => _p('slightly right', 'kulia kidogo');
  String get left => _p('on your left', 'kushoto kwako');
  String get right => _p('on your right', 'kulia kwako');
  String oclock(int h) => _p("at $h o'clock", 'saa $h');
  String metres(double m) {
    final v = m < 2 ? (m * 2).round() / 2 : m.round().toDouble();
    final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return _p(v == 1 ? '1 metre' : '$s metres', 'mita $s');
  }

  String steps(double m) {
    final n = (m / 0.7).round().clamp(1, 99);
    return _p(n == 1 ? '1 step' : '$n steps', n == 1 ? 'hatua 1' : 'hatua $n');
  }

  String get veryClose => _p('very close', 'karibu sana');
  String get approaching => _p('coming towards you', 'inakukaribia');
  String get inYourPath => _p('in your path', 'njiani mwako');
  String get stop => _p('Stop!', 'Simama!');
  String get caution => _p('Caution.', 'Tahadhari.');
  String looksLike(String what) => _p('Looks like $what', 'Inaonekana kama $what');

  // ------------------------------------------------------------ voice guide
  String get doubleTapToActivate => _p('double tap to activate', 'gusa mara mbili kuchagua');
  String get selected => _p('selected', 'imechaguliwa');
  String get on => _p('on', 'imewashwa');
  String get off => _p('off', 'imezimwa');
  String get button => _p('button', 'kitufe');
  String get heading => _p('heading', 'kichwa');
  String get disabled => _p('unavailable', 'haipatikani');
  String get endOfScreen => _p('End of screen', 'Mwisho wa skrini');
  String get startOfScreen => _p('Start of screen', 'Mwanzo wa skrini');
  String get voiceGuideOn => _p(
      'Voice guide is on. Touch anything to hear what it is. Double tap to choose it. '
          'Swipe right or left to move between items. Press and hold anywhere to give a voice command.',
      'Mwongozo wa sauti umewashwa. Gusa kitu chochote kusikia ni nini. Gusa mara mbili kukichagua. '
          'Telezesha kulia au kushoto kuhama kati ya vitu. Bonyeza na ushikilie popote kutoa amri ya sauti.');
  String get voiceGuideOff => _p('Voice guide off', 'Mwongozo wa sauti umezimwa');

  // ------------------------------------------------------------ voice commands
  String get listening => _p('Listening', 'Ninasikiliza');
  String get didNotCatch => _p("Sorry, I didn't catch that. Say help to hear the commands.",
      'Samahani, sijasikia. Sema msaada kusikia amri.');
  String get micUnavailable =>
      _p('Voice commands are not available on this phone.', 'Amri za sauti hazipatikani kwenye simu hii.');
  String get commandsHelp => _p(
      'You can say: scan money, tell me more about this note, what is in front of me, read my total, add, check fake, repeat, light, '
          'teach a note, home, wallet, settings, faster, slower, what time is it, or stop.',
      'Unaweza kusema: soma pesa, maelezo ya noti, nini kiko mbele yangu, jumla yangu, ongeza, kagua bandia, rudia, tochi, '
          'fundisha noti, nyumbani, pochi, mipangilio, haraka, polepole, saa ngapi, au simama.');
  String totals(String list) => _p('Your total is $list.', 'Jumla yako ni $list.');
  String get noTotals => _p('Your wallet is empty.', 'Pochi yako haina kitu.');
  String timeNow(int h, int m) {
    final mm = m.toString().padLeft(2, '0');
    if (isSw) {
      // Swahili time starts at 6 am: 7 am is "saa moja".
      final sw = ((h + 6) % 12 == 0) ? 12 : (h + 6) % 12;
      final part = h < 12 ? 'asubuhi' : h < 16 ? 'mchana' : h < 19 ? 'jioni' : 'usiku';
      return m == 0 ? 'Ni saa $sw $part.' : 'Ni saa $sw na dakika $m $part.';
    }
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return 'It is $h12:$mm ${h < 12 ? 'AM' : 'PM'}.';
  }

  String get speechFaster => _p('Speaking faster', 'Ninaongea haraka');
  String get speechSlower => _p('Speaking slower', 'Ninaongea polepole');
  String get stopped => _p('Stopped', 'Nimesimama');
  String welcomeBack(String name) => _p('Welcome, $name', 'Karibu, $name');
  String get appReady => _p('NoteLens is ready. Double tap Scan, or press and hold anywhere to speak.',
      'NoteLens iko tayari. Gusa mara mbili Changanua, au bonyeza na ushikilie popote kuongea.');

  // ------------------------------------------------------------ teach a note
  String get teachNote => _p('Teach a note', 'Fundisha noti');
  String get teachIntro => _p(
      'Teach NoteLens your own notes and coins. A sighted helper can do this once.',
      'Fundisha NoteLens noti na sarafu zako. Mtu anayeona anaweza kufanya hivi mara moja.');
  String teachFront(String note) => _p('Hold the front of the $note flat, filling the screen.',
      'Shika upande wa mbele wa $note, ijaze skrini.');
  String get teachBack => _p('Now turn it over.', 'Sasa igeuze.');
  String get teachTilt => _p('Now tilt it a little, and move it closer and further.',
      'Sasa iinamishe kidogo, na uisogeze karibu na mbali.');
  String teachDone(String note) => _p('Done. NoteLens now knows the $note.', 'Tayari. NoteLens sasa inaijua $note.');
  String taught(int n) => _p('$n samples', 'sampuli $n');

  // ------------------------------------------------------------ setup
  String get chooseLanguage => _p('Choose your language', 'Chagua lugha yako');
  String get chooseVoice => _p('Choose a voice', 'Chagua sauti');
  String get voiceMan => _p('Man', 'Mwanaume');
  String get voiceWoman => _p('Woman', 'Mwanamke');
  String get voiceYoung => _p('Young', 'Kijana');
  String get voiceSample => _p('Hello. I am your NoteLens voice. I will read your money and tell you what is around you.',
      'Habari. Mimi ni sauti yako ya NoteLens. Nitasoma pesa zako na kukueleza kilicho karibu nawe.');
  String get speechSpeed => _p('Speaking speed', 'Kasi ya kuongea');
  String get continueLabel => _p('Continue', 'Endelea');
  String get getStarted => _p('Get started', 'Anza');
  String get skip => _p('Skip', 'Ruka');
  String get voiceMissing => _p(
      'This voice is not installed on your phone. Open the text-to-speech settings to download it.',
      'Sauti hii haijasakinishwa kwenye simu yako. Fungua mipangilio ya sauti kuipakua.');
  String get languagePrompt => _p(
      'Welcome to NoteLens. Double tap English, or Kiswahili.', 'Karibu NoteLens. Gusa mara mbili Kiswahili, au English.');
}

const _objectsSw = <String, String>{
  // COCO
  'person': 'mtu', 'bicycle': 'baiskeli', 'car': 'gari', 'motorcycle': 'pikipiki', 'airplane': 'eropleni',
  'bus': 'basi', 'train': 'treni', 'truck': 'lori', 'boat': 'mashua', 'traffic light': 'taa za barabarani',
  'fire hydrant': 'bomba la zimamoto', 'stop sign': 'alama ya simama', 'parking meter': 'mita ya maegesho',
  'bench': 'benchi', 'bird': 'ndege', 'cat': 'paka', 'dog': 'mbwa', 'horse': 'farasi', 'sheep': 'kondoo',
  'cow': "ng'ombe", 'elephant': 'tembo', 'bear': 'dubu', 'zebra': 'punda milia', 'giraffe': 'twiga',
  'backpack': 'mkoba wa mgongoni', 'umbrella': 'mwavuli', 'handbag': 'mkoba', 'tie': 'tai',
  'suitcase': 'sanduku la safari', 'frisbee': 'frisbee', 'skis': 'skii', 'snowboard': 'ubao wa theluji',
  'sports ball': 'mpira', 'kite': 'tiara', 'baseball bat': 'gongo', 'baseball glove': 'glavu',
  'skateboard': 'ubao wa kuteleza', 'surfboard': 'ubao wa mawimbi', 'tennis racket': 'raketi',
  'bottle': 'chupa', 'wine glass': 'glasi', 'cup': 'kikombe', 'fork': 'uma', 'knife': 'kisu',
  'spoon': 'kijiko', 'bowl': 'bakuli', 'banana': 'ndizi', 'apple': 'tufaha', 'sandwich': 'sandwichi',
  'orange': 'chungwa', 'broccoli': 'brokoli', 'carrot': 'karoti', 'hot dog': 'hotdogi', 'pizza': 'piza',
  'donut': 'donati', 'cake': 'keki', 'chair': 'kiti', 'couch': 'kochi', 'potted plant': 'mmea wa chungu',
  'bed': 'kitanda', 'dining table': 'meza', 'toilet': 'choo', 'tv': 'televisheni',
  'laptop': 'kompyuta mpakato', 'mouse': 'kipanya', 'remote': 'rimoti', 'keyboard': 'kibodi',
  'cell phone': 'simu', 'microwave': 'maikrowevu', 'oven': 'oveni', 'toaster': 'tosta', 'sink': 'sinki',
  'refrigerator': 'friji', 'book': 'kitabu', 'clock': 'saa', 'vase': 'chombo cha maua', 'scissors': 'mkasi',
  'teddy bear': 'mwanasesere', 'hair drier': 'kikausha nywele', 'toothbrush': 'mswaki',
  // Scene classifier groups
  'shoes': 'viatu', 'boots': 'buti', 'socks': 'soksi', 'T-shirt': 'fulana', 'sweatshirt': 'sweta',
  'sweater': 'sweta', 'jeans': 'jinzi', 'suit': 'suti', 'coat': 'koti', 'dress': 'gauni', 'gown': 'joho',
  'skirt': 'sketi', 'pyjamas': 'nguo za kulalia', 'robe': 'joho', 'apron': 'aproni', 'hat': 'kofia',
  'cap': 'kofia', 'sunglasses': 'miwani ya jua', 'wallet': 'pochi', 'window': 'dirisha',
  'window blind': 'pazia la dirisha', 'door': 'mlango', 'curtain': 'pazia', 'doormat': 'kipangusa miguu',
  'sofa': 'kochi', 'table': 'meza', 'desk': 'dawati', 'wardrobe': 'kabati la nguo', 'bookshelf': 'rafu ya vitabu',
  'cabinet': 'kabati', 'pillow': 'mto', 'lamp': 'taa', 'fridge': 'friji', 'cooker': 'jiko',
  'toilet paper': 'karatasi ya chooni', 'wall': 'ukuta', 'roof': 'paa', 'fence': 'uzio',
  'turnstile': 'geti la kuzunguka', 'pill bottle': 'chupa ya dawa', 'glass': 'glasi', 'plate': 'sahani',
  'teapot': 'birika la chai', 'kettle': 'birika', 'pot': 'sufuria', 'computer': 'kompyuta', 'screen': 'skrini',
  'television': 'televisheni', 'phone': 'simu', 'remote control': 'rimoti', 'computer mouse': 'kipanya',
  'watch': 'saa ya mkono', 'microphone': 'kipaza sauti', 'street sign': 'alama ya barabarani',
  'manhole cover': 'mfuniko wa shimo', 'taxi': 'teksi', 'van': 'gari dogo', 'police van': 'gari la polisi',
  'minibus': 'matatu', 'tram': 'tramu', 'motorbike': 'pikipiki', 'pen': 'kalamu', 'stairs': 'ngazi',
};
