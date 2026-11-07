import 'package:flutter_test/flutter_test.dart';
import 'package:wuarikes_app/screens/place_detail_screen.dart';

void main() {
  test('timeAgo', () {
    final now = DateTime.utc(2026, 9, 21, 12);
    String? ago(Duration d) =>
        timeAgo(now.subtract(d).toIso8601String(), now: now);

    expect(ago(const Duration(minutes: 5)), 'Hace un momento');
    expect(ago(const Duration(hours: 1)), 'Hace 1 hora');
    expect(ago(const Duration(days: 2)), 'Hace 2 días');
    expect(ago(const Duration(days: 7)), 'Hace 1 semana');
    expect(ago(const Duration(days: 65)), 'Hace 2 meses');
    expect(timeAgo('no-es-fecha'), isNull);
  });
}
