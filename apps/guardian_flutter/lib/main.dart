import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/auth_screen.dart';
import 'package:guardian_app/ui/guardian_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GuardianApp());
}

class GuardianApp extends StatefulWidget {
  const GuardianApp({super.key});
  @override State<GuardianApp> createState() => _GuardianAppState();
}

class _GuardianAppState extends State<GuardianApp> {
  final GuardianController controller = GuardianController();
  @override
  void initState() {
    super.initState();
    controller.initialize();
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:controller,
      builder:(context,_)=>MaterialApp(
        title:'Guardian by MCode',
        theme:guardianTheme(),
        debugShowCheckedModeBanner:false,
        home:!controller.initialized
          ? const Scaffold(body:Center(child:CircularProgressIndicator()))
          : controller.authenticated
            ? GuardianShell(controller:controller)
            : AuthScreen(controller:controller),
      ),
    );
  }
}