import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Pencere yeterince geniş açılmalı ki kalıcı sidebar yerleşimi devreye
    // girsin (Breakpoints.masaustu = 1024). Daha darda uygulama tablet
    // yerleşimine düşüyor; çalışıyor ama masaüstü için tasarlanan ekran o değil.
    self.setContentSize(NSSize(width: 1280, height: 860))
    self.center()

    // Asgari boy: altında gezinme ve tablolar okunaksızlaşıyor. Kaydırma
    // eklendi (bkz. kabuk.dart) ama "kırılmıyor" ile "kullanılabilir" aynı
    // şey değil.
    self.minSize = NSSize(width: 900, height: 600)

    // Paket adı ASCII (imzalama şartı); kullanıcının gördüğü ad burada.
    self.title = "İşlerPro"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
