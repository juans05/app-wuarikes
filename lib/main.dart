import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'state/auth_provider.dart';
import 'screens/main_shell.dart';

void main() {
  runApp(const WuarikesApp());
}

class WuarikesApp extends StatelessWidget {
  const WuarikesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(ApiClient())..bootstrap()),
      ],
      child: MaterialApp(
        title: 'Wuarikes',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const MainShell(),
      ),
    );
  }
}
