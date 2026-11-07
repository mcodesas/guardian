import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/guardian_shell.dart';

void main() {
  testWidgets('Security notifications can be filtered by severity',
      (WidgetTester tester) async {
    tester.view.physicalSize=const Size(420,930);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller=GuardianController();
    addTearDown(controller.dispose);
    controller.profile={'id':'account-demo','name':'Propietario',
      'email':'demo@example.com'};
    controller.notifications=[
      {
        'id':'n1','type':'INTRUSION','title':'Posible intrusión',
        'body':'Se detectó actividad sospechosa en tu computador.',
        'createdAt':'2026-11-07T16:00:00Z','read':false,
      },
      {
        'id':'n2','type':'APPROVAL_REQUIRED','title':'¿Autorizas este acceso?',
        'body':'Requiere aprobación desde el teléfono.',
        'createdAt':'2026-11-07T15:59:00Z','read':true,
      },
    ];

    await tester.pumpWidget(MaterialApp(theme:guardianTheme(),
      home:GuardianShell(controller:controller)));
    await tester.tap(find.byIcon(Icons.notifications_active_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Posible intrusión'),findsOneWidget);
    expect(find.text('¿Autorizas este acceso?'),findsOneWidget);

    await tester.ensureVisible(find.text('Críticas'));
    await tester.tap(find.text('Críticas'));
    await tester.pumpAndSettle();
    expect(find.text('Posible intrusión'),findsOneWidget);
    expect(find.text('¿Autorizas este acceso?'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
