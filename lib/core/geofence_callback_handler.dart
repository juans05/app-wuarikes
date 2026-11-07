/// Notify on entering a stamp-program restaurant (including reward-ready,
/// stampsRemaining == 0), at most once per [cooldownHours].
bool shouldNotify(
  Map<String, dynamic> cachedCard,
  DateTime? lastNotifiedAt,
  DateTime now,
  int cooldownHours,
) {
  if (cachedCard['stampsRemaining'] == null) return false;
  if (lastNotifiedAt == null) return true;
  return now.difference(lastNotifiedAt) >= Duration(hours: cooldownHours);
}
