import 'package:flutter/material.dart';
import 'home_page.dart';
import 'room_library.dart';
import 'tvos_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RoomLibrary.instance.initialize();
  await restoreTvosCookies(MethodChannelTvosSessionStore());
  runApp(const SimpleLiveTvosApp());
}

class SimpleLiveTvosApp extends StatelessWidget {
  const SimpleLiveTvosApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Simple Live tvOS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D111B),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF508AF9),
            brightness: Brightness.dark,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        home: const HomePage(),
      );
}
