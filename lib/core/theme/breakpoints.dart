import 'package:flutter/widgets.dart';

/// Üç kırılım — tek kod tabanı, üç yerleşim.
/// mobil: BottomNav · tablet: NavigationRail · masaüstü: kalıcı sidebar
enum FormFactor { mobil, tablet, masaustu }

abstract final class Breakpoints {
  static const double tablet = 600;
  static const double masaustu = 1024;

  static FormFactor of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static FormFactor fromWidth(double w) => switch (w) {
        < tablet => FormFactor.mobil,
        < masaustu => FormFactor.tablet,
        _ => FormFactor.masaustu,
      };
}

extension FormFactorX on BuildContext {
  FormFactor get formFactor => Breakpoints.of(this);
  bool get isMobil => formFactor == FormFactor.mobil;
  bool get isMasaustu => formFactor == FormFactor.masaustu;
}
