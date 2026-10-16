# Note and coin features

The app speaks a short feature after each value ("500 Kenyan shillings. Green, with the lion.")
and reads the full description when the user says "details" / "maelezo", or taps a note in
Home → Learn your money → a currency. The data lives in `app/lib/core/note_facts.dart`.

Check every entry against the issuing central bank before a public release.

| Currency | What is covered | Source | Confidence |
|---|---|---|---|
| KES notes (2019) | Colour, Big Five animal, back theme, shared front (KICC, Kenyatta statue) | CBK launch speech (BIS r190613j), Wikipedia "Kenyan shilling", Coin World | Animals and themes: two sources. Colours: Wikipedia and Coin World |
| KES coins (2018) | Animal, size order (5 smallest, 20 largest), metals | Wikipedia, Coin World, CoinsWeekly | Good |
| UGX notes (2010) | Colour; shared front (map, equator, Independence Monument, Karimojong headdress); raised marks on 1,000–5,000 | Wikipedia "Ugandan shilling" | Good |
| UGX note backs | 5,000 weaver nest; 10,000 banana plant; 20,000 drums and long-horned cattle; 50,000 gorilla | Catalogue pages (koguja.ee, Numista, leftovercurrency) | Medium. 1,000 and 2,000 backs not confirmed, so not described |
| UGX coins | Size, colour; 200 fish, 500 crested crane | Wikipedia | Medium. **Not recognised by the camera yet** (no free training photos); users can teach them |
| INR notes | Colour, heritage site on the back, raised edge lines | RBI | Good |
| USD | Portraits, back buildings, coin edges | BEP, US Mint | Good |
| EGP | Not described yet | — | — |

To add or fix a fact, edit `noteFacts` in `note_facts.dart`; `test/logic_test.dart` checks that every
Kenyan and Ugandan note and coin, and every model label, has one.
