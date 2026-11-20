import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/guardian_components.dart';

/// This explicit test also prevents 'flutter create .' from generating its
/// default MyApp widget test, which is not valid for this application's
/// GuardianApp entrypoint.
void main() {
  testWidgets('Guardian branding loads without a native plugin',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: guardianTheme(),
        home: const Scaffold(body: Center(child: GuardianLogo())),
      ),
    );
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
