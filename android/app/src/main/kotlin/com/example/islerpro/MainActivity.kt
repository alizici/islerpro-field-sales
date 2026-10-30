package com.example.islerpro

import io.flutter.embedding.android.FlutterFragmentActivity

// K42 · local_auth biyometri diyalogunu bir FragmentActivity üzerinde açar.
// FlutterActivity ile çalıştırıldığında doğrulama sessizce başarısız olur —
// yani kilit hiç sorulmadan "geçemedi" der.
class MainActivity : FlutterFragmentActivity()
