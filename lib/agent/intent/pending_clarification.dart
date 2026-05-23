import 'coach_intent.dart';

const pendingClarificationTtl = Duration(minutes: 10);

class PendingClarification {
  const PendingClarification({
    required this.intent,
    required this.filledSlots,
    required this.missingSlots,
    required this.createdAt,
  });

  final CoachIntentType intent;
  final Map<String, dynamic> filledSlots;
  final List<String> missingSlots;
  final DateTime createdAt;

  bool isExpired(DateTime now) =>
      now.difference(createdAt) > pendingClarificationTtl;
}
