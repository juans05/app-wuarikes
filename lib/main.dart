import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/geofence_sync_service.dart';
import 'core/notification_service.dart';
import 'core/reward_ready_notifier.dart';
import 'state/auth_provider.dart';
import 'screens/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WuarikesApp());
  NotificationService().scheduleMealReminders().catchError((Object e) {
    debugPrint('Meal reminders not scheduled: $e');
  });
  // After the first frame so the plugin has an Activity to start its service.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    GeofenceSyncService().resumeIfEnabled();
    checkCompletedStamps();
  });
  _onResume = AppLifecycleListener(onResume: checkCompletedStamps);
}

// Se guarda para que el listener viva lo que dura la app.
// ignore: unused_element
late final AppLifecycleListener _onResume;

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
