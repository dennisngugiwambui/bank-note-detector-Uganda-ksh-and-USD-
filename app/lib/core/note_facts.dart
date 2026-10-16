/// What each note and coin looks and feels like: its colour, the animal or
/// picture that sets it apart, and what can be felt by hand. The app speaks
/// the short form after naming a note ("Red, with the buffalo") and reads
/// the full form on request ("details" / "maelezo").
///
/// Sources: Central Bank of Kenya 2019 note launch and 2018 coin series,
/// Bank of Uganda 2010 series, Reserve Bank of India Mahatma Gandhi (New)
/// series, US Bureau of Engraving and Printing and US Mint. Re-check against
/// the issuing bank before each release; see docs/NOTE_FEATURES.md.
library;

import 'currency.dart';
import 'strings.dart';

class NoteFact {
  /// A few words said after the value: "Red, with the buffalo".
  final String briefEn, briefSw;

  /// Full description: pictures front and back, what to feel for.
  final String detailEn, detailSw;

  /// Main colour, for low-vision users and the on-screen swatch.
  final int? colour;

  /// False when the camera model cannot recognise it yet (no training photos).
  final bool recognised;

  const NoteFact(this.briefEn, this.briefSw, this.detailEn, this.detailSw, {this.colour, this.recognised = true});

  String brief(S s) => s.t(briefEn, briefSw);
  String detail(S s) => s.t(detailEn, detailSw);
}

/// Facts shared by every note of a currency, said after the note's own facts.
const currencyFacts = <String, (String, String)>{
  'KES': (
    'All Kenyan notes from 2019 show the Kenyatta International Convention Centre and the statue of Jomo Kenyatta on the front. Each note carries one of the Big Five animals.',
    'Noti zote za Kenya za 2019 zina jengo la KICC na sanamu ya Jomo Kenyatta upande wa mbele. Kila noti ina mmoja wa wanyama watano wakubwa.',
  ),
  'UGX': (
    'All Ugandan notes from 2010 show the map of Uganda with the equator line, the Independence Monument and a man wearing a Karimojong headdress. The one thousand, two thousand and five thousand notes have raised marks you can feel.',
    'Noti zote za Uganda za 2010 zina ramani ya Uganda yenye mstari wa ikweta, Mnara wa Uhuru na mtu aliyevaa vazi la kichwa la Karimojong. Noti za elfu moja, elfu mbili na elfu tano zina alama zilizoinuka unazoweza kuhisi.',
  ),
  'INR': (
    'Indian notes of the new series show Mahatma Gandhi on the front and a heritage site on the back. Notes of one hundred rupees and above have raised angled lines at the left and right edges, more lines for higher values.',
    'Noti mpya za India zina picha ya Mahatma Gandhi mbele na eneo la urithi nyuma. Noti za rupia mia moja na zaidi zina mistari iliyoinuka pembeni kushoto na kulia, mistari mingi zaidi kwa thamani kubwa.',
  ),
  'USD': (
    'All US notes are the same size and feel the same, so the app is the best way to tell them apart. Many blind people fold each value differently to recognise it later.',
    'Noti zote za Marekani zina ukubwa sawa na zinahisika sawa, kwa hiyo programu hii ndiyo njia bora ya kuzitofautisha. Watu wengi wasioona hukunja kila thamani kwa njia tofauti ili kuitambua baadaye.',
  ),
};

const _red = 0xFFD9493F, _violet = 0xFF8B5CF6, _blue = 0xFF3B82F6, _green = 0xFF22A06B, _brown = 0xFF9A6B3F;
const _yellow = 0xFFE8C547, _purple = 0xFF9B59B6, _grey = 0xFF8E9AA6, _magenta = 0xFFD63384;
const _silver = 0xFFC0C6CC, _gold = 0xFFD4A84A, _copper = 0xFFB87333;

const noteFacts = <String, NoteFact>{
  // ------------------------------------------------------------ Kenya notes
  'KES_50': NoteFact('Red, with the buffalo', 'Nyekundu, ina nyati',
      'Red note. The buffalo. The back shows green energy: wind, geothermal and solar power.',
      'Noti nyekundu. Nyati. Nyuma kuna nishati safi: upepo, jotoardhi na jua.',
      colour: _red),
  'KES_100': NoteFact('Purple, with the leopard', 'Zambarau, ina chui',
      'Purple note. The leopard. The back shows farming: crops and livestock.',
      'Noti ya zambarau. Chui. Nyuma kuna kilimo: mazao na mifugo.',
      colour: _violet),
  'KES_200': NoteFact('Blue, with the rhino', 'Samawati, ina kifaru',
      'Blue note. The rhino. The back shows social services: health, education and sport.',
      'Noti ya samawati. Kifaru. Nyuma kuna huduma za jamii: afya, elimu na michezo.',
      colour: _blue),
  'KES_500': NoteFact('Green, with the lion', 'Kijani, ina simba',
      'Green note. The lion. The back shows tourism and wildlife.',
      'Noti ya kijani. Simba. Nyuma kuna utalii na wanyamapori.',
      colour: _green),
  'KES_1000': NoteFact('Brown, with the elephant', 'Kahawia, ina ndovu',
      'Brown note. The elephant. The back shows governance: the Parliament buildings in Nairobi.',
      'Noti ya kahawia. Ndovu. Nyuma kuna utawala: majengo ya Bunge, Nairobi.',
      colour: _brown),
  // ------------------------------------------------------------ Kenya coins
  'KES_1_coin': NoteFact('Silver, with the giraffe', 'Rangi ya fedha, ina twiga',
      'Silver coin of one colour, medium size. The giraffe.',
      'Sarafu ya rangi moja ya fedha, ukubwa wa kati. Twiga.',
      colour: _silver),
  'KES_5_coin': NoteFact('Smallest coin, with the rhino', 'Sarafu ndogo zaidi, ina kifaru',
      'The smallest Kenyan coin. Gold centre in a silver ring. The rhino.',
      'Sarafu ndogo kuliko zote za Kenya. Katikati ni dhahabu, pete ni ya fedha. Kifaru.',
      colour: _gold),
  'KES_10_coin': NoteFact('Silver centre, gold ring, with the lion', 'Katikati fedha, pete dhahabu, ina simba',
      'Medium coin. Silver centre in a gold ring. The lion.',
      'Sarafu ya ukubwa wa kati. Katikati ni fedha, pete ni dhahabu. Simba.',
      colour: _silver),
  'KES_20_coin': NoteFact('Largest coin, with the elephant', 'Sarafu kubwa zaidi, ina ndovu',
      'The largest and heaviest Kenyan coin. Gold centre in a silver ring. The elephant.',
      'Sarafu kubwa na nzito kuliko zote za Kenya. Katikati ni dhahabu, pete ni ya fedha. Ndovu.',
      colour: _gold),
  // ------------------------------------------------------------ Uganda notes
  'UGX_1000': NoteFact('Brown note', 'Noti ya kahawia',
      'Brown note with raised marks you can feel. The back shows the map of Uganda with the equator line.',
      'Noti ya kahawia yenye alama zilizoinuka. Nyuma kuna ramani ya Uganda na mstari wa ikweta.',
      colour: _brown),
  'UGX_2000': NoteFact('Blue note', 'Noti ya samawati',
      'Blue note with raised marks you can feel.',
      'Noti ya samawati yenye alama zilizoinuka unazoweza kuhisi.',
      colour: _blue),
  'UGX_5000': NoteFact('Green, with the weaver bird nest', 'Kijani, ina kiota cha ndege',
      'Green note with raised marks you can feel. The back shows weaver birds and their nest.',
      'Noti ya kijani yenye alama zilizoinuka. Nyuma kuna ndege wafumaji na kiota chao.',
      colour: _green),
  'UGX_10000': NoteFact('Purple, with the banana plant', 'Zambarau, ina mgomba',
      'Purple note. The back shows a banana plant beside the map of Uganda.',
      'Noti ya zambarau. Nyuma kuna mgomba kando ya ramani ya Uganda.',
      colour: _purple),
  'UGX_20000': NoteFact('Red, with drums and long-horned cattle', 'Nyekundu, ina ngoma na ng\'ombe',
      'Red note. The back shows drums and long-horned Ankole cattle.',
      'Noti nyekundu. Nyuma kuna ngoma na ng\'ombe wa Ankole wenye pembe ndefu.',
      colour: _red),
  'UGX_50000': NoteFact('Yellow, with the gorilla', 'Njano, ina sokwe',
      'Yellow note. The back shows a mountain gorilla.',
      'Noti ya njano. Nyuma kuna sokwe wa milimani.',
      colour: _yellow),
  // Ugandan coins: no training photos yet. Teach them in Settings.
  'UGX_100_coin': NoteFact('Large silver coin', 'Sarafu kubwa ya fedha',
      'Large silver coin, about the same size as the one thousand coin but of one colour.',
      'Sarafu kubwa ya fedha, karibu ukubwa sawa na ya elfu moja lakini ya rangi moja.',
      colour: _silver, recognised: false),
  'UGX_200_coin': NoteFact('Silver, with a fish', 'Fedha, ina samaki',
      'Silver coin, a little smaller than the one hundred. A fish.',
      'Sarafu ya fedha, ndogo kidogo kuliko ya mia moja. Samaki.',
      colour: _silver, recognised: false),
  'UGX_500_coin': NoteFact('Gold coloured, with the crested crane', 'Rangi ya dhahabu, ina korongo',
      'Small gold coloured coin. The crested crane.',
      'Sarafu ndogo ya rangi ya dhahabu. Korongo mwenye taji.',
      colour: _gold, recognised: false),
  'UGX_1000_coin': NoteFact('Large coin of two metals', 'Sarafu kubwa ya metali mbili',
      'Large coin with a centre and a ring of two different metals.',
      'Sarafu kubwa yenye katikati na pete za metali mbili tofauti.',
      colour: _gold, recognised: false),
  // ------------------------------------------------------------ India
  'INR_10': NoteFact('Chocolate brown, Konark Sun Temple', 'Kahawia, Hekalu la Jua la Konark',
      'Chocolate brown note. The back shows the Konark Sun Temple.', 'Noti ya kahawia. Nyuma kuna Hekalu la Jua la Konark.',
      colour: _brown),
  'INR_20': NoteFact('Greenish yellow, Ellora Caves', 'Njano kijani, Mapango ya Ellora',
      'Greenish yellow note. The back shows the Ellora Caves.', 'Noti ya njano kijani. Nyuma kuna Mapango ya Ellora.',
      colour: _yellow),
  'INR_50': NoteFact('Bright blue, Hampi stone chariot', 'Samawati, gari la mawe la Hampi',
      'Bright blue note. The back shows the stone chariot of Hampi.', 'Noti ya samawati. Nyuma kuna gari la mawe la Hampi.',
      colour: _blue),
  'INR_100': NoteFact('Lavender, Rani ki Vav', 'Zambarau hafifu, Rani ki Vav',
      'Lavender note. The back shows the Rani ki Vav stepwell. Four raised lines at each edge.',
      'Noti ya zambarau hafifu. Nyuma kuna kisima cha Rani ki Vav. Mistari minne iliyoinuka kila upande.',
      colour: _violet),
  'INR_200': NoteFact('Bright yellow, Sanchi Stupa', 'Njano, Sanchi Stupa',
      'Bright yellow note. The back shows the Sanchi Stupa. Four raised lines with two circles at each edge.',
      'Noti ya njano. Nyuma kuna Sanchi Stupa. Mistari minne na duara mbili zilizoinuka kila upande.',
      colour: _yellow),
  'INR_500': NoteFact('Stone grey, Red Fort', 'Kijivu, Ngome Nyekundu',
      'Stone grey note. The back shows the Red Fort. Five raised lines at each edge.',
      'Noti ya kijivu. Nyuma kuna Ngome Nyekundu. Mistari mitano iliyoinuka kila upande.',
      colour: _grey),
  'INR_2000': NoteFact('Magenta, Mangalyaan', 'Waridi, Mangalyaan',
      'Magenta note, now being withdrawn. The back shows the Mangalyaan Mars mission. Seven raised lines at each edge.',
      'Noti ya waridi, inaondolewa sasa. Nyuma kuna chombo cha Mangalyaan. Mistari saba iliyoinuka kila upande.',
      colour: _magenta),
  // ------------------------------------------------------------ United States
  'USD_1': NoteFact('George Washington', 'George Washington',
      'Green note. George Washington on the front, the Great Seal on the back.',
      'Noti ya kijani. George Washington mbele, Muhuri Mkuu nyuma.', colour: _green),
  'USD_2': NoteFact('Thomas Jefferson', 'Thomas Jefferson',
      'Green note. Thomas Jefferson on the front, the signing of the Declaration of Independence on the back.',
      'Noti ya kijani. Thomas Jefferson mbele, kutiwa saini kwa Azimio la Uhuru nyuma.', colour: _green),
  'USD_5': NoteFact('Abraham Lincoln', 'Abraham Lincoln',
      'Abraham Lincoln on the front, the Lincoln Memorial on the back. Has a large purple five.',
      'Abraham Lincoln mbele, Mnara wa Lincoln nyuma. Ina tano kubwa ya zambarau.', colour: _violet),
  'USD_10': NoteFact('Alexander Hamilton', 'Alexander Hamilton',
      'Alexander Hamilton on the front, the Treasury building on the back. Orange tint.',
      'Alexander Hamilton mbele, jengo la Hazina nyuma. Rangi ya machungwa.', colour: 0xFFE8913A),
  'USD_20': NoteFact('Andrew Jackson', 'Andrew Jackson',
      'Andrew Jackson on the front, the White House on the back. Green and peach tint.',
      'Andrew Jackson mbele, Ikulu ya White House nyuma.', colour: _green),
  'USD_50': NoteFact('Ulysses Grant', 'Ulysses Grant',
      'Ulysses Grant on the front, the Capitol on the back. Blue and red tint.',
      'Ulysses Grant mbele, jengo la Capitol nyuma.', colour: _red),
  'USD_100': NoteFact('Benjamin Franklin', 'Benjamin Franklin',
      'Benjamin Franklin on the front, Independence Hall on the back. A blue ribbon down the middle.',
      'Benjamin Franklin mbele, Ukumbi wa Uhuru nyuma. Utepe wa bluu katikati.', colour: _blue),
  'USD_1c_coin': NoteFact('Copper penny', 'Senti ya shaba',
      'Copper coloured coin with a smooth edge. Abraham Lincoln.',
      'Sarafu ya rangi ya shaba yenye ukingo laini. Abraham Lincoln.', colour: _copper),
  'USD_5c_coin': NoteFact('Thick, smooth edge', 'Nene, ukingo laini',
      'Nickel: a thick coin with a smooth edge, bigger than a dime and smaller than a quarter. Thomas Jefferson.',
      'Nickel: sarafu nene yenye ukingo laini. Thomas Jefferson.', colour: _silver),
  'USD_10c_coin': NoteFact('Smallest coin, ridged edge', 'Sarafu ndogo zaidi, ukingo wa mistari',
      'Dime: the smallest and thinnest US coin, with a ridged edge. Franklin Roosevelt.',
      'Dime: sarafu ndogo na nyembamba kuliko zote za Marekani, yenye ukingo wa mistari. Franklin Roosevelt.',
      colour: _silver),
  'USD_25c_coin': NoteFact('Large coin, ridged edge', 'Sarafu kubwa, ukingo wa mistari',
      'Quarter: a large coin with a ridged edge. George Washington.',
      'Quarter: sarafu kubwa yenye ukingo wa mistari. George Washington.', colour: _silver),
};

NoteFact? factFor(Note note) => noteFacts[note.label];

/// "Red, with the buffalo", or null when nothing is known.
String? briefFor(Note note, S s) => factFor(note)?.brief(s);

/// The full spoken description of a note: its own facts, then its currency's.
String detailsFor(Note note, S s) {
  final f = factFor(note);
  final shared = note.coin ? null : currencyFacts[note.currency];
  final parts = [
    note.spokenIn(s),
    if (f != null) f.detail(s),
    if (shared != null) s.t(shared.$1, shared.$2),
  ];
  return parts.join('. ').replaceAll('..', '.');
}

/// Every note and coin in [c] with a fact, for the "Know your money" lists.
List<(Note, NoteFact?)> factsOf(CurrencyInfo c) => [
      for (final v in c.notes) (Note(c.iso, v), noteFacts['${c.iso}_$v']),
      for (final v in c.coins) () {
        final n = Note.parse('${c.iso}_${v}_coin')!;
        return (n, noteFacts[n.label]);
      }(),
    ];
