import 'package:flutter/material.dart';

/// Tasarım belirteçleri — `design/web-panel.dc.html` referans alınarak çıkarıldı.
/// Renkler tek kaynaktan gelir; hiçbir widget kendi rengini uydurmaz.
abstract final class T {
  // ── Bordo (marka) ────────────────────────────────────────────────────────
  static const bordoKoyu   = Color(0xFF3F0F1B);   // sidebar zemini
  static const bordo       = Color(0xFF6E1B2C);   // primary
  static const bordoOrta   = Color(0xFF8E2740);   // hover / vurgu
  static const bordoSoft   = Color(0xFFF4E0E4);   // rozet zemini
  static const bordoSofter = Color(0xFFFDF8F8);   // seçili satır

  // ── Mürekkep (sıcak nötr) ────────────────────────────────────────────────
  static const ink      = Color(0xFF1A1518);      // başlık
  static const ink2     = Color(0xFF2A2024);      // gövde
  static const ink3     = Color(0xFF5C5155);      // ikincil
  static const muted    = Color(0xFF8A7E82);      // etiket
  static const muted2   = Color(0xFF9C8F92);      // en soluk (mikro-etiket)

  // ── Zemin ve kenarlık ────────────────────────────────────────────────────
  static const zemin    = Color(0xFFFCFAF9);      // ana yüzey
  static const zemin2   = Color(0xFFF1EAE7);      // katman
  static const kart     = Color(0xFFFFFFFF);
  static const kenar    = Color(0xFFE9E1DE);      // ana kenarlık
  static const kenarKoyu= Color(0xFFE5DBD7);

  // ── Semantik ─────────────────────────────────────────────────────────────
  static const basarili     = Color(0xFF2E6A4F);
  static const basariliSoft = Color(0xFFEAF2ED);
  static const uyari        = Color(0xFFA2661B);
  static const uyariSoft    = Color(0xFFFDF3E7);
  static const tehlike      = Color(0xFFB0332B);
  static const tehlikeSoft  = Color(0xFFFBF0EF);
  static const bilgi        = Color(0xFF3E6E8E);
  static const bilgiSoft    = Color(0xFFF0F4F7);

  // ── Koyu tema karşılıkları ───────────────────────────────────────────────
  static const dZemin  = Color(0xFF171214);
  static const dKart   = Color(0xFF1F191B);
  static const dKart2  = Color(0xFF261F21);
  static const dKenar  = Color(0xFF352B2E);
  static const dInk    = Color(0xFFEFE7E4);
  static const dInk2   = Color(0xFFCFC3C0);
  static const dMuted  = Color(0xFF9C8F92);
  static const dBordo  = Color(0xFFD98C9E);       // koyu zeminde okunur bordo

  // ── Ölçüler ──────────────────────────────────────────────────────────────
  static const rKart = 11.0, rDugme = 8.0, rCip = 6.0, rKucuk = 5.0;

  /// Cam yüzeylerin yuvarlaklığı. Kartınkinden (11) belirgin biçimde büyük:
  /// cam kalın bir malzeme, keskin köşe kalınlığı yalanlar.
  static const rCam = 20.0;

  /// Giriş alanı. Düğmeler kapsül ama alanlar değil: çok satırlı bir metin
  /// kutusunun uçları yuvarlanınca ilk ve son harf kenara yapışıyor.
  static const rGiris = 12.0;
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;
  static const minTouch = 48.0;

  static const fontSans = 'IBMPlexSans';
  static const fontMono = 'IBMPlexMono';
}
