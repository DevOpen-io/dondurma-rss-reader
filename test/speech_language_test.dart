import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/speech_language.dart';

/// Short news-style paragraphs, two per language, as articles start.
const _samples = <String, List<String>>{
  'en': [
    'The government announced on Monday that it will raise taxes for the '
        'largest companies, a move that is expected to bring in billions.',
    'Scientists say the new telescope has already found signs of water on '
        'a planet that is more than a hundred light years away from us.',
  ],
  'tr': [
    'Merkez Bankası faiz kararını açıkladı. Kurul, politika faizini yüzde '
        'elli seviyesinde sabit tutarken enflasyonla mücadeleye devam edecek.',
    // ASCII only, as some feeds strip Turkish letters.
    'Istanbul icin yeni bir metro hatti daha acildi ve bu hat ile birlikte '
        'sehirdeki toplam hat uzunlugu da artmis oldu, yetkililer bunun '
        'trafik icin onemli olarak gorulen bir adim oldugunu soyledi.',
    'İzmir\'de düzenlenen festival bu yıl da binlerce ziyaretçiyi ağırladı.',
  ],
  'es': [
    'El gobierno anunció el lunes que subirá los impuestos a las grandes '
        'empresas, una medida que según los expertos traerá millones.',
    'Los científicos dicen que el nuevo telescopio ya ha encontrado señales '
        'de agua en un planeta que está a más de cien años luz.',
  ],
  'pt': [
    'O governo anunciou na segunda-feira que vai aumentar os impostos das '
        'grandes empresas, uma medida que não agradou aos sindicatos.',
    'Os cientistas dizem que o novo telescópio já encontrou sinais de água '
        'num planeta que está a mais de cem anos-luz da Terra.',
  ],
  'de': [
    'Die Regierung hat am Montag angekündigt, dass sie die Steuern für die '
        'größten Unternehmen erhöhen wird, was Milliarden einbringen soll.',
    'Wissenschaftler sagen, dass das neue Teleskop bereits Spuren von Wasser '
        'auf einem Planeten gefunden hat, der nicht weit entfernt ist.',
  ],
  'fr': [
    'Le gouvernement a annoncé lundi qu\'il allait augmenter les impôts des '
        'plus grandes entreprises, une mesure qui doit rapporter des milliards.',
    'Les scientifiques disent que le nouveau télescope a déjà trouvé des '
        'traces d\'eau sur une planète qui est très loin de nous.',
  ],
  'it': [
    'Il governo ha annunciato lunedì che aumenterà le tasse per le grandi '
        'aziende, una misura che secondo gli esperti porterà miliardi.',
    'Gli scienziati dicono che il nuovo telescopio ha già trovato tracce di '
        'acqua su un pianeta che non è molto lontano da noi.',
  ],
  'nl': [
    'De regering heeft maandag aangekondigd dat ze de belastingen voor de '
        'grootste bedrijven gaat verhogen, wat miljarden moet opleveren.',
    'Wetenschappers zeggen dat de nieuwe telescoop al sporen van water heeft '
        'gevonden op een planeet die niet ver van ons verwijderd is.',
  ],
  'ru': [
    'Правительство в понедельник объявило, что повысит налоги для крупнейших '
        'компаний, что должно принести миллиарды.',
  ],
  'ar': ['أعلنت الحكومة يوم الاثنين أنها سترفع الضرائب على الشركات الكبرى.'],
  'el': ['Η κυβέρνηση ανακοίνωσε τη Δευτέρα ότι θα αυξήσει τους φόρους.'],
  'he': ['הממשלה הודיעה ביום שני כי תעלה את המסים על החברות הגדולות.'],
  'ja': ['政府は月曜日、大企業への税金を引き上げると発表しました。'],
  'ko': ['정부는 월요일 대기업에 대한 세금을 인상하겠다고 발표했다.'],
  'zh': ['政府周一宣布将提高大公司的税收，预计将带来数十亿收入。'],
  'hi': ['सरकार ने सोमवार को घोषणा की कि वह बड़ी कंपनियों पर कर बढ़ाएगी।'],
  'th': ['รัฐบาลประกาศเมื่อวันจันทร์ว่าจะขึ้นภาษีบริษัทขนาดใหญ่'],
};

void main() {
  group('detectLanguage', () {
    _samples.forEach((language, texts) {
      for (final (i, text) in texts.indexed) {
        test('$language sample ${i + 1}', () {
          expect(detectLanguage(text), language);
        });
      }
    });

    test('too little text to tell is null', () {
      expect(detectLanguage('Breaking news'), isNull);
      expect(detectLanguage(''), isNull);
      expect(detectLanguage('2026 — https://site.test/a/b 42%'), isNull);
    });

    test('a few quoted foreign words do not flip the language', () {
      expect(
        detectLanguage(
          'Bakan, "the show must go on" diyerek konuşmasını bitirdi ve '
          'toplantı bu sözlerle sona erdi, bir sonraki oturum için tarih '
          'verilmedi.',
        ),
        'tr',
      );
    });
  });

  group('resolveSpeechTag', () {
    const offered = ['en-GB', 'en-US', 'tr-TR', 'pt-BR', 'pt-PT', 'de-AT'];

    test('picks the main region of a language the engine offers', () {
      expect(resolveSpeechTag('en', offered), 'en-US');
      expect(resolveSpeechTag('tr', offered), 'tr-TR');
      expect(resolveSpeechTag('pt', offered), 'pt-BR');
      expect(resolveSpeechTag('de', offered), 'de-AT');
    });

    test('engine tags with underscores or other case still match', () {
      expect(resolveSpeechTag('tr', ['tr_TR']), 'tr_TR');
      expect(resolveSpeechTag('es', ['ES-es']), 'ES-es');
    });

    test('a language the engine lacks is null', () {
      expect(resolveSpeechTag('ru', offered), isNull);
    });

    test('an unknown offer passes the bare code through', () {
      expect(resolveSpeechTag('tr', const []), 'tr');
    });
  });

  group('offeredLanguages', () {
    test('one entry per named language, by native name; bare codes the '
        'reader cannot recognize are left out', () {
      expect(
        offeredLanguages(['tr-TR', 'en-US', 'en-GB', 'xx-YY', 'brx-IN', 'de']),
        ['de', 'en', 'tr'],
      );
    });

    test('the given languages come first, in their order', () {
      expect(
        offeredLanguages(['de', 'en-US', 'tr-TR', 'fr'], first: ['tr', 'en']),
        ['tr', 'en', 'de', 'fr'],
      );
    });
  });

  test('native names, with the code for unknown languages', () {
    expect(languageName('tr'), 'Türkçe');
    expect(languageName('en'), 'English');
    expect(languageName('es'), 'Español');
    expect(languageName('xx'), 'XX');
  });
}
