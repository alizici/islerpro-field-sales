import 'package:integration_test/integration_test_driver.dart';

/// `flutter drive` için sürücü. Web'de chromedriver, mobilde cihaz üzerinden
/// integration_test/ altındaki testleri çalıştırır.
Future<void> main() => integrationDriver();
