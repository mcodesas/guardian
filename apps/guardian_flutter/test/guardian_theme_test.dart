import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/guardian_components.dart';

void main() {
  testWidgets('GuardianLogo uses branded shield and renders', (tester) async {
    await tester.pumpWidget(MaterialApp(theme:guardianTheme(),
      home:const Scaffold(body:GuardianLogo())));
    expect(find.byIcon(Icons.shield_rounded),findsOneWidget);
  });
  test('Guardian brand palette is dark and high contrast', () {
    expect(GuardianPalette.bg.computeLuminance(),lessThan(.1));
    expect(GuardianPalette.teal.computeLuminance(),greaterThan(.5));
  });
}
