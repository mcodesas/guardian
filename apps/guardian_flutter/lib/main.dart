import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/auth_screen.dart';
import 'package:guardian_app/ui/guardian_shell.dart';
import 'package:guardian_app/ui/guardian_components.dart';

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
          ? const Scaffold(body:SafeArea(child:Center(child:Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GuardianLogo(size: 156),
                SizedBox(height: 20),
                Text('Guardian', style: TextStyle(fontSize: 30,
                    fontWeight: FontWeight.w800, color: GuardianPalette.white)),
                SizedBox(height: 8),
                Text('Seguridad inteligente para tus dispositivos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GuardianPalette.muted)),
                SizedBox(height: 30),
                CircularProgressIndicator(),
              ],
            ))))
          : controller.authenticated
            ? GuardianShell(controller:controller)
            : AuthScreen(controller:controller),
      ),
    );
  }
}