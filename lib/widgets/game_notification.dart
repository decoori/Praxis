import 'package:flutter/material.dart';

enum NotificationType { success, error, info, reward }

void showGameNotification(
  BuildContext context, {
  required String message,
  NotificationType type = NotificationType.success,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  Color accentColor;
  IconData icon;

  switch (type) {
    case NotificationType.success:
      accentColor = const Color(0xFF00E676);
      icon = Icons.check_circle_rounded;
      break;
    case NotificationType.error:
      accentColor = const Color(0xFFFF5252);
      icon = Icons.error_outline_rounded;
      break;
    case NotificationType.reward:
      accentColor = const Color(0xFFF5A623);
      icon = Icons.auto_awesome_rounded;
      break;
    case NotificationType.info:
      accentColor = const Color(0xFF00B0FF);
      icon = Icons.bolt_rounded;
      break;
  }

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF14171E),
      elevation: 10,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      duration: duration,
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
