import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';

/// Диалог активации промокода.
///
/// Вся проверка кода (существование, срок, лимиты, повторная активация)
/// выполняется в БД функцией `redeem_promo_code`. Диалог только отправляет
/// введённое значение и показывает итог.
class PromoCodeDialog extends StatefulWidget {
  final GameController controller;
  final Color primaryColor;
  final VoidCallback? onRedeemed;

  const PromoCodeDialog({
    super.key,
    required this.controller,
    required this.primaryColor,
    this.onRedeemed,
  });

  @override
  State<PromoCodeDialog> createState() => _PromoCodeDialogState();
}

class _PromoCodeDialogState extends State<PromoCodeDialog> {
  final _codeController = TextEditingController();
  bool _isRedeeming = false;
  String? _errorMessage;
  PromoRedeemResult? _success;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Введите промокод.');
      return;
    }

    setState(() {
      _isRedeeming = true;
      _errorMessage = null;
    });

    final result = await widget.controller.redeemPromoCode(code);
    if (!mounted) return;

    setState(() {
      _isRedeeming = false;
      if (result.applied) {
        _success = result;
        _errorMessage = null;
        _codeController.clear();
      } else {
        _errorMessage = result.message;
      }
    });

    if (result.applied) {
      widget.onRedeemed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14171E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x28FFFFFF)),
      ),
      title: Row(
        children: [
          Icon(Icons.redeem_rounded, color: widget.primaryColor, size: 24),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Промокод',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Код из новости или розыгрыша. Награда — один раз на аккаунт.',
              style: TextStyle(
                color: Color(0xFF8E95A5),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              enabled: !_isRedeeming,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isRedeeming ? null : _redeem(),
              inputFormatters: [
                // Код состоит из латиницы, цифр, дефиса и подчёркивания.
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'PRAXIS2026',
                hintStyle: const TextStyle(
                  color: Color(0xFF5D6475),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1D24),
                prefixIcon: const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFFF5A623),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_isRedeeming) ...[
              const SizedBox(height: 18),
              const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_success != null) ...[
              const SizedBox(height: 14),
              _successCard(_success!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRedeeming ? null : () => Navigator.pop(context),
          child: const Text(
            'Закрыть',
            style: TextStyle(color: Color(0xFF8E95A5)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _isRedeeming ? null : _redeem,
          child: Text(
            _success == null ? 'Активировать' : 'Активировать ещё',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _successCard(PromoRedeemResult result) {
    final rewards = <Widget>[];
    if (result.goldAdded > 0) {
      rewards.add(
        _rewardChip(
          Icons.monetization_on_rounded,
          '+${result.goldAdded}',
          const Color(0xFFF5A623),
        ),
      );
    }
    if (result.xpAdded > 0) {
      rewards.add(
        _rewardChip(
          Icons.auto_awesome_rounded,
          '+${result.xpAdded} XP',
          widget.primaryColor,
        ),
      );
    }
    if (result.energyAdded > 0) {
      rewards.add(
        _rewardChip(
          Icons.bolt_rounded,
          '+${result.energyAdded}',
          const Color(0xFF00B0FF),
        ),
      );
    }
    if (result.shieldsAdded > 0) {
      rewards.add(
        _rewardChip(
          Icons.shield_rounded,
          '+${result.shieldsAdded}',
          const Color(0xFF00E676),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF00E676),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.title ?? result.message,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rewards.isEmpty)
            const Text(
              'Всё уже на максимуме',
              style: TextStyle(color: Color(0xFF8E95A5), fontSize: 12),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: rewards),
        ],
      ),
    );
  }

  Widget _rewardChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14171E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
