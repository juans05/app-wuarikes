import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationOnboardingScreen extends StatefulWidget {
  final VoidCallback onDismiss;

  const BatteryOptimizationOnboardingScreen({
    super.key,
    required this.onDismiss,
  });

  @override
  State<BatteryOptimizationOnboardingScreen> createState() =>
      _BatteryOptimizationOnboardingScreenState();
}

class _BatteryOptimizationOnboardingScreenState
    extends State<BatteryOptimizationOnboardingScreen> {
  late String _manufacturer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _detectManufacturer();
  }

  Future<void> _detectManufacturer() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    setState(() {
      _manufacturer = androidInfo.manufacturer.toUpperCase();
    });
  }

  Future<void> _openBatterySettings() async {
    setState(() => _isLoading = true);
    try {
      // Handled in MainActivity.kt.
      await const MethodChannel('wuarikes/battery').invokeMethod('openSettings');
    } catch (e) {
      debugPrint('Battery optimization settings error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_onboarding_shown', true);
    if (mounted) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? Colors.grey[900] : Colors.grey[50];
    final accentColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizar batería'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(Icons.battery_saver_outlined,
                    size: 50, color: accentColor),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Activa los avisos de proximidad',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Para que Wuarikes te avise cuando estés cerca de un huarique donde tienes sellos o premios, tu dispositivo necesita usar ubicación en segundo plano.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paso 1: Abre Ajustes de $_manufacturer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Algunos fabricantes desactivan automáticamente apps que usan ubicación. Desactiva las "Optimizaciones de batería" para Wuarikes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _openBatterySettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Abrir Ajustes'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _markShown,
                    child: const Text('Lo haré después'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _markShown,
                    child: const Text('Listo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
