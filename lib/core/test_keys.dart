import 'package:flutter/widgets.dart';

/// Test kimlikleri — tek kaynaktan.
///
/// Testler metne göre arama yapmaz: etiket değiştiğinde test kırılmasın diye
/// widget'lara sabit kimlik verilir. Bu dosya hem widget'ların hem testlerin
/// baktığı tek yerdir; yazım hatası derleme zamanında yakalanır.
abstract final class K {
  // Giriş
  static const girisYolTelefon = Key('giris.yol.telefon');
  static const girisYolEposta = Key('giris.yol.eposta');
  static const girisYolParola = Key('giris.yol.parola');
  static const girisKimlik = Key('giris.kimlik');
  static const girisKod = Key('giris.kod');
  static const girisGonder = Key('giris.gonder');

  // Kurulum
  static const kurulumUnvan = Key('kurulum.unvan');
  static const kurulumDukkan = Key('kurulum.dukkan');
  static const kurulumIl = Key('kurulum.il');
  static const kurulumIlce = Key('kurulum.ilce');
  static const kurulumKur = Key('kurulum.kur');
  static const kurulumDavetKodu = Key('kurulum.davet.kod');
  static const kurulumDavetKullan = Key('kurulum.davet.kullan');

  // Ayarlar
  static const ayarlarKimlik = Key('ayarlar.kimlik');
  static const ayarlarDukkanlar = Key('ayarlar.dukkanlar');
  static const ayarlarDukkanEkle = Key('ayarlar.dukkan.ekle');
  static const ayarlarEkip = Key('ayarlar.ekip');
  static const ayarlarDavetEt = Key('ayarlar.davet.et');
  static const ayarlarDonemler = Key('ayarlar.donemler');
  static const ayarlarSonrakiDonem = Key('ayarlar.donem.sonraki');
  static const ayarlarBekleyenler = Key('ayarlar.bekleyenler');
  static const ayarlarCikis = Key('ayarlar.cikis');
  static ValueKey ekipSatiri(String userId) => ValueKey('ayarlar.ekip.$userId');
  static ValueKey ekipPasifeAl(String userId) => ValueKey('ayarlar.ekip.pasif.$userId');
  static ValueKey onaylaButonu(String userId) => ValueKey('ayarlar.onayla.$userId');

  // Öğretmen onay diyaloğu (K3 · Y-15)
  static const onayKurumAdina = Key('onay.kurum.adina');
  static const onayOnayla = Key('onay.onayla');

  // Davet diyaloğu
  static const davetRol = Key('davet.rol');
  static const davetAd = Key('davet.ad');
  static const davetUret = Key('davet.uret');
  static const davetKod = Key('davet.kod');
  static const davetKopyala = Key('davet.kopyala');

  // Kurum dizini (K18 · Ö-8)
  static const kurumArama = Key('kurum.arama');
  static const kurumListesi = Key('kurum.listesi');
  static const kurumEkle = Key('kurum.ekle');
  static const kurumEkleAd = Key('kurum.ekle.ad');
  static const kurumEkleTip = Key('kurum.ekle.tip');
  static const kurumEkleIlce = Key('kurum.ekle.ilce');
  static const kurumEkleKaydet = Key('kurum.ekle.kaydet');
  static const kurumBenzerUyari = Key('kurum.benzer.uyari');
  static const kurumDetayCariler = Key('kurum.detay.cariler');
  static const kurumDetayKisiler = Key('kurum.detay.kisiler');
  static const kurumOgretmenDavet = Key('kurum.ogretmen.davet');

  // KVKK (K44)
  static const kvkkOnayla = Key('kvkk.onayla');
  static const kvkkMetin = Key('kvkk.metin');


  // Katalog (K12 · K15 · K25)
  static const katalogArama = Key('katalog.arama');
  static const katalogListesi = Key('katalog.listesi');
  static const katalogFiltreKitap = Key('katalog.filtre.kitap');
  static const katalogFiltreDeneme = Key('katalog.filtre.deneme');
  static const katalogFiltreFiyatsiz = Key('katalog.filtre.fiyatsiz');
  static const katalogUrunEkle = Key('katalog.urun.ekle');
  static ValueKey urunSatiri(String id) => ValueKey('katalog.urun.$id');

  // Fiyat katmanı diyaloğu (K12)
  static const fiyatSatis = Key('fiyat.satis');
  static const fiyatAlis = Key('fiyat.alis');
  static const fiyatIskonto = Key('fiyat.iskonto');
  static const fiyatStokTakibi = Key('fiyat.stok.takibi');
  static const fiyatKaydet = Key('fiyat.kaydet');
  static const fiyatOnizleme = Key('fiyat.onizleme');

  // Ürün ekleme
  static const urunEkleAd = Key('urun.ekle.ad');
  static const urunEkleBarkod = Key('urun.ekle.barkod');
  static const urunEkleYayinevi = Key('urun.ekle.yayinevi');
  static const urunEkleEtiketFiyat = Key('urun.ekle.etiket');
  static const urunEkleKaydet = Key('urun.ekle.kaydet');

  // Baskı grupları (K23)
  static const baskiAc = Key('baski.ac');
  static const baskiListesi = Key('baski.listesi');
  static const baskiEkle = Key('baski.ekle');
  static const baskiEtiket = Key('baski.etiket');
  static const baskiBarkod = Key('baski.barkod');
  static const baskiEtiketFiyat = Key('baski.etiket.fiyat');
  static const baskiArsivle = Key('baski.arsivle');
  static const baskiKaydet = Key('baski.kaydet');
  static const baskiUyari = Key('baski.uyari');
  static ValueKey baskiSatiri(String id) => ValueKey('baski.satir.$id');

  // Dükkan düzenleme / pasifleştirme (0018)
  static const dukkanAd = Key('dukkan.ad');
  static const dukkanIl = Key('dukkan.il');
  static const dukkanIlce = Key('dukkan.ilce');
  static const dukkanKaydet = Key('dukkan.kaydet');
  static const dukkanPasifOnay = Key('dukkan.pasif.onay');
  static const dukkanPasifUyari = Key('dukkan.pasif.uyari');
  static ValueKey dukkanSatiri(String id) => ValueKey('ayarlar.dukkan.$id');
  static ValueKey dukkanMenu(String id) => ValueKey('ayarlar.dukkan.menu.$id');

  // Toplu aktarma (K49)
  static const aktarmaTur = Key('aktarma.tur');
  static const aktarmaDosyaSec = Key('aktarma.dosya.sec');
  static const aktarmaEslesme = Key('aktarma.eslesme');
  static const aktarmaOnizle = Key('aktarma.onizle');
  static const aktarmaOzet = Key('aktarma.ozet');
  static const aktarmaUygula = Key('aktarma.uygula');
  static const aktarmaPolitika = Key('aktarma.politika');
  static const aktarmaHatalar = Key('aktarma.hatalar');
  static const aktarmaHataIndir = Key('aktarma.hata.indir');
  static const aktarmaYeniden = Key('aktarma.yeniden');
  static const aktarmaGecmis = Key('aktarma.gecmis');
  static const aktarmaAnahtarUyari = Key('aktarma.anahtar.uyari');
  static ValueKey aktarmaSutun(String b) => ValueKey('aktarma.sutun.$b');
  static ValueKey aktarmaGeriAl(String id) => ValueKey('aktarma.geri.$id');

  // Cari yönetimi (K5 · K6 · K7 · K11)
  static const cariArama = Key('cari.arama');
  static const cariListesi = Key('cari.listesi');
  static const cariEkle = Key('cari.ekle');
  static const cariFiltreKurum = Key('cari.filtre.kurum');
  static const cariFiltreOgretmen = Key('cari.filtre.ogretmen');
  static const cariFiltreBorclu = Key('cari.filtre.borclu');
  static const cariFiltreAtanmamis = Key('cari.filtre.atanmamis');
  static const cariSecimModu = Key('cari.secim.modu');
  static const cariSecimCubugu = Key('cari.secim.cubugu');
  static const cariPortfoyAta = Key('cari.portfoy.ata');
  static const cariPortfoyOzeti = Key('cari.portfoy.ozeti');
  static const cariDetayKardesler = Key('cari.detay.kardesler');
  static const cariDetayRisk = Key('cari.detay.risk');
  static const cariDetayTasimalar = Key('cari.detay.tasimalar');
  static const cariTasi = Key('cari.tasi');
  static const cariTasiHedef = Key('cari.tasi.hedef');
  static const cariTasiGerekce = Key('cari.tasi.gerekce');
  static const cariTasiOnay = Key('cari.tasi.onay');
  static const cariTasiEngel = Key('cari.tasi.engel');
  static const cariEkleUnvan = Key('cari.ekle.unvan');
  static const cariEkleTip = Key('cari.ekle.tip');
  static const cariEkleLimit = Key('cari.ekle.limit');
  static const cariEkleKaydet = Key('cari.ekle.kaydet');
  static const atamaAday = Key('atama.aday');
  static const atamaOnay = Key('atama.onay');
  static ValueKey cariSatiri(String id) => ValueKey('cari.$id');

  // Talep akışı (K36 · K37 · K41)
  static const talepListesi = Key('talep.listesi');
  static const talepFiltreAcik = Key('talep.filtre.acik');
  static const talepFiltreGecikmis = Key('talep.filtre.gecikmis');
  static const talepEleAl = Key('talep.ele.al');
  static const talepKararVer = Key('talep.karar.ver');
  static const talepKalemler = Key('talep.kalemler');
  static const talepCariRisk = Key('talep.cari.risk');
  static const talepOzet = Key('talep.ozet');
  static const talepYeni = Key('talep.yeni');
  static const talepMuhatap = Key('talep.muhatap');
  static const talepUrunAra = Key('talep.urun.ara');
  static const talepNot = Key('talep.not');
  static const talepGonder = Key('talep.gonder');
  static const redNedeni = Key('talep.red.nedeni');
  static const redOnay = Key('talep.red.onay');
  static ValueKey talepSatiri(String id) => ValueKey('talep.$id');
  static ValueKey kalemOnay(String id) => ValueKey('talep.kalem.onay.$id');
  static ValueKey kalemRed(String id) => ValueKey('talep.kalem.red.$id');
  static ValueKey talepKalemi(String id) => ValueKey('talep.kalem.$id');

  // Bildirimler (K41)
  static const bildirimZili = Key('bildirim.zil');
  static const bildirimSayaci = Key('bildirim.sayac');
  static const bildirimListesi = Key('bildirim.listesi');
  static const bildirimHepsiniOku = Key('bildirim.hepsini.oku');
  static ValueKey bildirimSatiri(String id) => ValueKey('bildirim.$id');

  // Sipariş · teslimat · tahsilat (K26 · K28 · K46 · K48)
  static const siparisListesi = Key('siparis.listesi');
  static const siparisHazirlikKutusu = Key('siparis.hazirlik.kutusu');
  static const siparisKalemler = Key('siparis.kalemler');
  static const siparisHazirla = Key('siparis.hazirla');
  static const siparisHazir = Key('siparis.hazir');
  static const siparisSevk = Key('siparis.sevk');
  static const siparisTeslimEt = Key('siparis.teslim.et');
  static const siparisOnayla = Key('siparis.onayla');
  static const siparisOnayUyari = Key('siparis.onay.uyari');
  static const teslimatKaydet = Key('teslimat.kaydet');
  static const teslimatAlan = Key('teslimat.alan');
  static const teslimatKonsinye = Key('teslimat.konsinye');
  static ValueKey siparisSatiri(String id) => ValueKey('siparis.$id');
  static ValueKey teslimatAdet(String id) => ValueKey('teslimat.adet.$id');

  static const tahsilatListesi = Key('tahsilat.listesi');
  static const tahsilatTutar = Key('tahsilat.tutar');
  static const tahsilatYontem = Key('tahsilat.yontem');
  static const tahsilatCekVade = Key('tahsilat.cek.vade');
  static const tahsilatMahsup = Key('tahsilat.mahsup');
  static const tahsilatKaydet = Key('tahsilat.kaydet');
  static const tahsilatUyari = Key('tahsilat.uyari');
  static const ekstreListesi = Key('ekstre.listesi');
  static ValueKey borcluSatiri(String id) => ValueKey('borclu.$id');

  // Raporlar (K50) ve makbuz (B1)
  static const raporSekmeler = Key('rapor.sekmeler');
  static const raporYaslandirma = Key('rapor.yaslandirma');
  static const raporTahsilat = Key('rapor.tahsilat');
  static const raporCiro = Key('rapor.ciro');
  static const raporCiroKirilim = Key('rapor.ciro.kirilim');
  static const raporIndir = Key('rapor.indir');
  static const makbuzGovde = Key('makbuz.govde');
  static const makbuzIndir = Key('makbuz.indir');

  // Ekstre ve stok
  static const ekstreAc = Key('ekstre.ac');
  static const ekstreSatirlar = Key('ekstre.satirlar');
  static const stokListesi = Key('stok.listesi');
  static const stokFiltre = Key('stok.filtre');
  static const eritmeListesi = Key('eritme.listesi');

  // Açılış ekranları
  static const panelKuyruk = Key('panel.kuyruk');
  static const panelPara = Key('panel.para');
  static const panelHuni = Key('panel.huni');
  static const panelEkip = Key('panel.ekip');
  static const bugunOzet = Key('bugun.ozet');
  static const bugunGecikmis = Key('bugun.gecikmis');
  static const bugunTahsilat = Key('bugun.tahsilat');
  static ValueKey panelKart(String k) => ValueKey('panel.kart.$k');

  // Saha · ziyaret ve rota (Faz 7)
  static const ziyaretCubugu = Key('ziyaret.cubuk');
  static const ziyaretBitir = Key('ziyaret.bitir');
  static const ziyaretBitirOnay = Key('ziyaret.bitir.onay');
  static const ziyaretNot = Key('ziyaret.not');
  static const ziyaretOzet = Key('ziyaret.ozet');
  static const ziyaretBaslik = Key('ziyaret.baslik');
  static const ziyaretCikti = Key('ziyaret.cikti');
  static const ziyaretListesi = Key('ziyaret.liste');
  static const rotaDuraklar = Key('rota.duraklar');
  static const rotaSiralama = Key('rota.siralama');
  static const rotaOneriler = Key('rota.oneriler');
  static const bugunRota = Key('bugun.rota');
  static ValueKey ziyaretSonuc(String k) => ValueKey('ziyaret.sonuc.$k');
  static ValueKey rotaDurak(String k) => ValueKey('rota.durak.$k');
  static ValueKey rotaGiris(String k) => ValueKey('rota.giris.$k');
  static ValueKey rotaBitir(String k) => ValueKey('rota.bitir.$k');
  static ValueKey rotaOneri(String k) => ValueKey('rota.oneri.$k');
  static ValueKey rotaEkle(String k) => ValueKey('rota.ekle.$k');

  // K43 · senkron · K42 · cihaz
  static const senkronDurum = Key('senkron.durum');
  static const senkronCalistir = Key('senkron.calistir');
  static const senkronKuyruk = Key('senkron.kuyruk');
  static const senkronCihazlar = Key('senkron.cihazlar');
  static const senkronCihazIptalOnay = Key('senkron.cihaz.iptal.onay');
  static const bugunKuyrukUyarisi = Key('bugun.kuyruk');
  /// Liste cihazdaki kopyadan geldiğinde görünen uyarı.
  static const yerelKopyaUyarisi = Key('yerel.kopya.uyarisi');
  static ValueKey senkronSatir(int s) => ValueKey('senkron.satir.$s');
  static ValueKey senkronSil(int s) => ValueKey('senkron.sil.$s');
  static ValueKey senkronCihaz(String k) => ValueKey('senkron.cihaz.$k');
  static ValueKey senkronCihazIptal(String k) =>
      ValueKey('senkron.cihaz.iptal.$k');

  // K42 · cihaz kilidi
  static const kilitEkrani = Key('kilit.ekran');
  static const kilitAc = Key('kilit.ac');
  static const senkronGuvenlik = Key('senkron.guvenlik');
  static const senkronYerelKopya = Key('senkron.yerel.kopya');

  // Faz 8 · ticari
  static const vadeOzet = Key('vade.ozet');
  static const vadeGecikmis = Key('vade.gecikmis');
  static const vadeTakvim = Key('vade.takvim');
  static const cekDiyalog = Key('cek.diyalog');
  static const cekCiroAlan = Key('cek.ciro');
  static const cekGerekce = Key('cek.gerekce');
  static const cekOnay = Key('cek.onay');
  static const konsinyeListesi = Key('konsinye.liste');
  static const konsinyeKalemler = Key('konsinye.kalemler');
  static const konsinyeOzet = Key('konsinye.ozet');
  static const konsinyeKapat = Key('konsinye.kapat');
  static const iadeDiyalog = Key('iade.diyalog');
  static const iadeOnay = Key('iade.onay');
  static const iadeGerekce = Key('iade.gerekce');
  static const cariIade = Key('cari.iade');

  // Faz 9 · deneme takvimi
  static const denemeBaslik = Key('deneme.baslik');
  static const denemeIzgara = Key('deneme.izgara');
  static const denemeGunPaneli = Key('deneme.gun.panel');
  static const denemeTarihsiz = Key('deneme.tarihsiz');
  static const denemeOncekiAy = Key('deneme.ay.onceki');
  static const denemeSonrakiAy = Key('deneme.ay.sonraki');
  static const denemeEksenStok = Key('deneme.eksen.stok');
  static const denemeEksenUygulama = Key('deneme.eksen.uygulama');
  static const denemePortfoy = Key('deneme.portfoy');
  static const onerBaslik = Key('oner.baslik');
  static const onerListe = Key('oner.liste');
  static const onerOzet = Key('oner.ozet');
  static const onerSonuc = Key('oner.sonuc');
  static const onerAc = Key('oner.ac');
  static const onerTumu = Key('oner.tumu');
  static const onerGecenSefer = Key('oner.gecensefer');
  static const mevcutDiyalog = Key('mevcut.diyalog');
  static const mevcutKaydet = Key('mevcut.kaydet');
  static const cariMevcut = Key('cari.mevcut');
  static const bugunDeneme = Key('bugun.deneme');
  static ValueKey denemeGun(int g) => ValueKey('deneme.gun.$g');
  static ValueKey denemeSatir(String k) => ValueKey('deneme.satir.$k');
  static ValueKey denemeOner(String k) => ValueKey('deneme.oner.$k');
  static ValueKey denemeKademe(String k) => ValueKey('deneme.kademe.$k');
  static ValueKey denemeTur(String k) => ValueKey('deneme.tur.$k');
  static ValueKey onerSec(String k) => ValueKey('oner.sec.$k');
  static ValueKey onerAdet(String k) => ValueKey('oner.adet.$k');
  static ValueKey mevcutSinif(int s) => ValueKey('mevcut.sinif.$s');

  // Faz 9 · abonelik programı
  static const programListe = Key('program.liste');
  static const programDonemOzeti = Key('program.donem.ozet');
  static const programBaslik = Key('program.baslik');
  static const programKalemler = Key('program.kalemler');
  static const programTeslimOnay = Key('program.teslim.onay');
  static const programTeslimEt = Key('program.teslim.et');
  static const programErteleGerekce = Key('program.ertele.gerekce');
  static const programErteleOnay = Key('program.ertele.onay');
  static ValueKey programSatir(String k) => ValueKey('program.satir.$k');
  static ValueKey programKalem(String k) => ValueKey('program.kalem.$k');
  static ValueKey programTeslim(String k) => ValueKey('program.teslim.$k');
  static ValueKey programDurum(String k) => ValueKey('program.durum.$k');
  static ValueKey cekSatir(String k) => ValueKey('cek.satir.$k');
  static ValueKey cekDurum(String k) => ValueKey('cek.durum.$k');
  static ValueKey konsinyeCari(String k) => ValueKey('konsinye.cari.$k');
  static ValueKey konsinyeSatildi(String k) => ValueKey('konsinye.satildi.$k');
  static ValueKey konsinyeIade(String k) => ValueKey('konsinye.iade.$k');
  static ValueKey iadeAdet(String k) => ValueKey('iade.adet.$k');

  // Portföy devri (K34 · W-2)
  static const devirAday = Key('devir.aday');
  static const devirOnay = Key('devir.onay');
  static const devirUyari = Key('devir.uyari');

  // Bağlam şeridi — hangi dükkan, hangi dönem
  static const baglamSeridi = Key('baglam.serit');
  static ValueKey menuHedef(String yol) => ValueKey('menu.$yol');
  static const baglamDukkan = Key('baglam.dukkan');
  static const baglamDonem = Key('baglam.donem');

  // Faz 10 · rapor motoru (K50)
  static const raporKatalog = Key('rapor.katalog');
  static const raporKayitlilar = Key('rapor.kayitlilar');
  static const raporTablo = Key('rapor.tablo');
  static const raporToplam = Key('rapor.toplam');
  static const raporUyari = Key('rapor.uyari');
  static const raporKirilim = Key('rapor.kirilim');
  static const raporSuzgec = Key('rapor.suzgec');
  static const raporExcel = Key('rapor.excel');
  static const raporPdf = Key('rapor.pdf');
  static const raporKaydet = Key('rapor.kaydet');
  static const raporKaydetAd = Key('rapor.kaydet.ad');
  static const raporKaydetOnay = Key('rapor.kaydet.onay');
  static const raporOnbellek = Key('rapor.onbellek');
  static ValueKey raporSatir(String k) => ValueKey('rapor.satir.$k');
  static ValueKey raporKart(String k) => ValueKey('rapor.kart.$k');
  static ValueKey raporKayitli(String k) => ValueKey('rapor.kayitli.$k');
  static ValueKey raporBoyut(String k) => ValueKey('rapor.boyut.$k');
}
