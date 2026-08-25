import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'net/room.dart';
import 'screens/home.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kOnlineEnabled) {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
  }

  runApp(const PenFightApp());
}

class PenFightApp extends StatelessWidget {
  const PenFightApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pen Fight',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: PF.sans,
          scaffoldBackgroundColor: PF.paper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: PF.blue,
            surface: PF.paper,
          ),
        ),
        home: const HomeScreen(),
      );
}
