import 'package:flutter/material.dart';

import 'splash_screen.dart';
import 'home_gallery.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PcitrueApp());
}

class PcitrueApp extends StatefulWidget {
  const PcitrueApp({super.key});

  @override
  State<PcitrueApp> createState() => _PcitrueAppState();
}

class _PcitrueAppState extends State<PcitrueApp> {
  ThemeMode _mode = ThemeMode.system;
  bool _showSplash = true;

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pcitrue',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: _showSplash
          ? SplashScreen(onDone: () => setState(() => _showSplash = false))
          : HomeGallery(onToggleTheme: _toggleTheme),
    );
  }
}
