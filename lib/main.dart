import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_settings.dart';
import 'services/guidance_controller.dart';
import 'ui/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait for stable camera-to-head guidance alignment
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set high-contrast system bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final settings = await AppSettings.load();
  final controller = GuidanceController(settings: settings);

  // Initialize camera, audio session, TTS, STT, and Gemini Nano detection
  await controller.initialize();

  runApp(EyePhoneApp(controller: controller));
}

class EyePhoneApp extends StatelessWidget {
  final GuidanceController controller;

  const EyePhoneApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EyePhone - AI Vision Guide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: HomeScreen(controller: controller),
    );
  }
}
