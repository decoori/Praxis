import 'package:flutter/material.dart';

import '../constants/avatars_config.dart';

class AvatarWidget extends StatelessWidget {
  final String? avatarId;
  final double size;
  final bool showGlow;
  final VoidCallback? onTap;

  const AvatarWidget({
    super.key,
    required this.avatarId,
    this.size = 50,
    this.showGlow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = getAvatarById(avatarId);

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: avatar.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: avatar.glowColor.withValues(alpha: 0.8),
          width: size > 80 ? 3.5 : 2,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: avatar.glowColor.withValues(alpha: 0.4),
                  blurRadius: size * 0.25,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Center(
        child: Icon(avatar.icon, size: size * 0.52, color: Colors.white),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: content,
      );
    }

    return content;
  }
}
