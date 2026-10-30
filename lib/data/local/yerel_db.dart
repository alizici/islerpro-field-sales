import 'dart:convert';

import 'package:drift/drift.dart';

import 'ac_stub.dart' if (dart.library.io) 'ac_native.dart';

part 'yerel_db.g.dart';

/// K43 · Yazma kuyruğu — sözleşmenin KALICI olan tarafı.
///
/// Kuyruk sunucuda değil burada durur: uygulama kapansa, cihaz yeniden başlasa
/// da kayıt kaybolmaz. `localSeq` otomatik artar ve `client_id` ile birlikte
/// idempotency anahtarını oluşturur — aynı satır iki kez yüklenirse sunucu
/// ikincisini işlemez.
class Kuyruk extends Table {
  IntColumn get localSeq => integer().autoIncrement()();
  TextColumn get fn => text()();
  TextColumn get args => text()();                       // json
  /// bekliyor · yuklendi · hata
  TextColumn get durum => text().withDefault(const Constant('bekliyor'))();
  TextColumn get hata => text().nullable()();
  /// Kullanıcıya gösterilecek satır: "Y Lisesi · 3 kalem talep".
  /// Kuyruğu ham fonksiyon adıyla göstermek kimseye bir şey anlatmaz.
  TextColumn get ozet => text()();
  /// Cihaz saati (K43 · kural 4). Sıralama ipucudur, rapor kaynağı değildir.
  DateTimeColumn get olusturmaLocal => dateTime()();
  IntColumn get deneme => integer().withDefault(const Constant(0))();
  TextColumn get sonucJson => text().nullable()();
}

/// Referans veri — offline okuma için. Hepsi sunucudan İNER, burada üretilmez.
class YerelCari extends Table {
  TextColumn get id => text()();
  TextColumn get unvan => text()();
  TextColumn get tip => text()();
  TextColumn get durum => text()();
  TextColumn get kurumId => text().nullable()();
  RealColumn get bakiye => real().withDefault(const Constant(0))();
  RealColumn get krediLimiti => real().withDefault(const Constant(0))();
  TextColumn get kademe => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class YerelKurum extends Table {
  TextColumn get id => text()();
  TextColumn get ad => text()();
  TextColumn get il => text().nullable()();
  TextColumn get ilce => text().nullable()();
  TextColumn get tip => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class YerelKisi extends Table {
  TextColumn get id => text()();
  TextColumn get kurumId => text()();
  TextColumn get adSoyad => text()();
  TextColumn get gorev => text().nullable()();
  TextColumn get brans => text().nullable()();
  TextColumn get telefon => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class YerelUrun extends Table {
  TextColumn get id => text()();
  TextColumn get ad => text()();
  TextColumn get barkod => text().nullable()();
  TextColumn get yayinevi => text().nullable()();
  TextColumn get kategori => text().nullable()();
  TextColumn get ders => text().nullable()();
  RealColumn get satisFiyat => real().nullable()();
  RealColumn get varsayilanIskonto => real().withDefault(const Constant(0))();
  IntColumn get stokAdedi => integer().withDefault(const Constant(0))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Tek satırlık anahtar/değer: son senkron zamanı, katalog imleci, cihaz kimliği.
class Ayar extends Table {
  TextColumn get anahtar => text()();
  TextColumn get deger => text()();
  @override
  Set<Column> get primaryKey => {anahtar};
}

@DriftDatabase(
    tables: [Kuyruk, YerelCari, YerelKurum, YerelKisi, YerelUrun, Ayar])
class YerelDb extends _$YerelDb {
  YerelDb() : super(yerelDosya());
  YerelDb.test(super.e);

  @override
  int get schemaVersion => 1;

  // ── Kuyruk ───────────────────────────────────────────────────────────────
  Future<int> kuyrugaYaz(String fn, Map<String, dynamic> args, String ozet,
          {DateTime? saat}) =>
      into(kuyruk).insert(KuyrukCompanion.insert(
        fn: fn,
        args: jsonEncode(args),
        ozet: ozet,
        olusturmaLocal: saat ?? DateTime.now(),
      ));

  Future<List<KuyrukData>> bekleyenler({int limit = 200}) =>
      (select(kuyruk)
            ..where((k) => k.durum.isNotValue('yuklendi'))
            ..orderBy([(k) => OrderingTerm(expression: k.localSeq)])
            ..limit(limit))
          .get();

  Future<int> bekleyenSayisi() async {
    final s = kuyruk.localSeq.count();
    final q = selectOnly(kuyruk)
      ..addColumns([s])
      ..where(kuyruk.durum.isNotValue('yuklendi'));
    return (await q.getSingle()).read(s) ?? 0;
  }

  Future<void> yuklendiIsaretle(int seq, String? sonucJson) =>
      (update(kuyruk)..where((k) => k.localSeq.equals(seq))).write(
          KuyrukCompanion(durum: const Value('yuklendi'),
                          hata: const Value(null),
                          sonucJson: Value(sonucJson)));

  Future<void> hataIsaretle(int seq, String hata) async {
    final satir = await (select(kuyruk)
          ..where((k) => k.localSeq.equals(seq))).getSingleOrNull();
    await (update(kuyruk)..where((k) => k.localSeq.equals(seq))).write(
        KuyrukCompanion(durum: const Value('hata'), hata: Value(hata),
                        deneme: Value((satir?.deneme ?? 0) + 1)));
  }

  Future<void> kuyruktanSil(int seq) =>
      (delete(kuyruk)..where((k) => k.localSeq.equals(seq))).go();

  /// Yüklenmişleri temizler; hata verenler DURUR — kullanıcı görsün diye.
  Future<int> yuklenenleriTemizle() =>
      (delete(kuyruk)..where((k) => k.durum.equals('yuklendi'))).go();

  // ── Ayarlar (anahtar/değer) ──────────────────────────────────────────────
  Future<String?> ayarOku(String anahtar) async =>
      (await (select(ayar)..where((a) => a.anahtar.equals(anahtar)))
              .getSingleOrNull())
          ?.deger;

  Future<void> ayarYaz(String anahtar, String deger) =>
      into(ayar).insertOnConflictUpdate(
          AyarData(anahtar: anahtar, deger: deger));

  /// K42 · İptal edilen cihazda yerel verinin TAMAMI silinir. Kuyruk dâhil:
  /// iptal edilmiş bir cihazın bekleyen yazmaları da güvenilmez sayılır.
  ///
  /// `pragma secure_delete` açık olduğu için silinen satırların içeriği boş
  /// sayfalarda okunabilir hâlde kalmaz (bkz. `ac_native.dart`).
  Future<void> herSeyiSil() => transaction(() async {
        await delete(kuyruk).go();
        await delete(yerelCari).go();
        await delete(yerelKurum).go();
        await delete(yerelKisi).go();
        await delete(yerelUrun).go();
        await delete(ayar).go();
      });

}
