import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/auth_screen.dart';

void main() {
  testWidgets('Guardian login and registration adapt to narrow displays',
      (WidgetTester tester) async {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller=GuardianController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(theme:guardianTheme(),
      home:AuthScreen(controller:controller)));
    expect(find.text('Bienvenido de nuevo'),findsOneWidget);
    expect(find.byType(TextFormField),findsNWidgets(2));
    expect(tester.takeException(),isNull);

    await tester.ensureVisible(find.text('Regístrate'));
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Crea tu espacio seguro'),findsOneWidget);
    expect(find.byType(TextFormField),findsNWidgets(3));
    expect(tester.takeException(),isNull);
  });

  testWidgets('Desktop login uses two panel layout', (WidgetTester tester) async {
    tester.view.physicalSize=const Size(1300,860);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller=GuardianController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme:guardianTheme(),
      home:AuthScreen(controller:controller)));
    expect(find.text('Tu mundo,\nbajo protección.'),findsOneWidget);
    expect(find.text('Bienvenido de nuevo'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
