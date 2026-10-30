import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sifreleme.dart';
import 'yerel_anahtar.dart';

/// K42 · Yerel veri ŞİFRELİ tutulur; anahtar cihazın kasasındadır.
///
/// Şifreli sqlite (SQLite3MultipleCiphers) `pubspec.yaml`'daki
/// `hooks: user_defines: sqlite3: source: sqlite3mc` ile geliyor. Ayrı bir
/// `*_flutter_libs` paketi YOK: iki farklı sqlite aynı anda yüklenirse
/// hangisinin kazandığı belirsizleşir ve uygulama sessizce şifresiz yazabilir.
///
/// Dosya adı `saha.db`; şifresiz dönemden kalan `islerpro.sqlite` ilk açılışta
/// silinir. İçindeki her şey sunucudaki verinin kopyasıydı — şifresiz durması
/// için bir sebep yok.
QueryExecutor yerelDosya() => LazyDatabase(() async {
      final dizin = await getApplicationDocumentsDirectory();
      final eski = File(p.join(dizin.path, 'islerpro.sqlite'));
      if (eski.existsSync()) eski.deleteSync();

      final dosya = File(p.join(dizin.path, 'saha.db'));
      // Ölçüm işlevini yerine koy: bundan sonra ekran gerçek dosyaya bakar.
      sifrelemeOlc = () async => sifrelemeDurumu(dosya);

      final anahtar = await const YerelAnahtar().al();
      return NativeDatabase.createInBackground(
        dosya,
        setup: (db) => anahtariUygula(db, anahtar),
      );
    });

/// Anahtarı uygular. İlk ifade olmak zorunda: sonrasında çalıştırılan hiçbir
/// pragma dosyayı geriye dönük şifrelemez.
///
/// Anahtar 64 karakterlik hex dizidir ve buraya PAROLA olarak veriliyor
/// (`x'...'` ham bayt biçimi yerine): kütüphaneler arasında en taşınabilir
/// olan bu. Dizi kriptografik rastgele 32 bayttan üretildiği için entropi
/// kaybı yok, ve içinde tırnak geçemeyeceğinden enjeksiyon da doğmuyor.
void anahtariUygula(dynamic db, String hexAnahtar) {
  db.execute("pragma key = '$hexAnahtar'");
  // Silinen satırın içeriği boş sayfada kalmasın. Cihaz iptal edilince
  // `herSeyiSil()` satırları siliyor; secure_delete olmadan o satırların
  // içeriği serbest sayfalarda okunabilir hâlde kalırdı.
  db.execute('pragma secure_delete = on');
  // Anahtarın doğruluğu ancak bir okuma denenince anlaşılır.
  db.execute('select count(*) from sqlite_master');
}

/// Şifrelemenin GERÇEKTEN devrede olduğunu doğrular.
///
/// Sessiz başarısızlık buradaki en kötü sonuçtur: "şifreli" yazan ama
/// şifrelemeyen bir uygulama, hiç şifrelemeyenden daha tehlikelidir çünkü
/// güven verir. Bu yüzden doğrulama bir pragma'nın SÖZÜNE değil dosyanın
/// KENDİSİNE bakıyor: düz sqlite dosyası ilk 16 baytta "SQLite format 3" +
/// NUL taşır, şifreli dosyada o alan da şifrelenmiştir.
///
/// Karşılaştırma BAYT bazlıdır. Metinle yapıldığında son bayt (NUL) yanlışlıkla
/// boşlukla eşleştirilmişti ve kontrol düz dosyayı "şifreli" sayıyordu —
/// tam da uyarmak için var olduğu durumu kaçıran bir kontrol.
const _sqliteBasligi = <int>[
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
];

SifrelemeDurumu sifrelemeDurumu(File dosya) {
  if (!dosya.existsSync() || dosya.lengthSync() < 16) {
    return SifrelemeDurumu.veriYok;
  }
  final oku = dosya.openSync();
  final ilk = oku.readSync(16);
  oku.closeSync();
  for (var i = 0; i < 16; i++) {
    if (ilk[i] != _sqliteBasligi[i]) return SifrelemeDurumu.sifreli;
  }
  return SifrelemeDurumu.sifresiz;
}

bool sifreliMi(File dosya) =>
    sifrelemeDurumu(dosya) == SifrelemeDurumu.sifreli;

bool get yerelDbVar => true;
