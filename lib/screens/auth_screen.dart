import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'game_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tagController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final rawTag = _tagController.text.trim().replaceAll('@', '').toLowerCase();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Введите email и пароль');
      return;
    }

    if (_isSignUp) {
      if (rawTag.isEmpty) {
        setState(() => _errorMessage = 'Придумайте ID');
        return;
      }
      if (rawTag.length < 3 || rawTag.length > 16) {
        setState(() => _errorMessage = 'ID: от 3 до 16 символов');
        return;
      }
      final tagRegex = RegExp(r'^[a-z0-9_]+$');
      if (!tagRegex.hasMatch(rawTag)) {
        setState(() => _errorMessage = 'Только латиница, цифры и _');
        return;
      }
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Пароль: минимум 6 символов');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final supabase = Supabase.instance.client;

    try {
      if (_isSignUp) {
        // Быстрая проверка для понятного сообщения. Авторитетная защита —
        // UNIQUE-индекс на profiles.user_tag (см. migrations/001_security_hardening.sql):
        // между этой проверкой и вставкой тег может занять другой игрок.
        final checkTag = await supabase
            .from('profiles')
            .select('id')
            .eq('user_tag', rawTag)
            .maybeSingle();

        if (checkTag != null) {
          setState(() => _errorMessage = 'ID @$rawTag занят');
          return;
        }

        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'user_tag': rawTag, 'username': rawTag},
        );

        final user = res.user;
        if (user != null) {
          // Профиль создаётся здесь; при гонке за тег БД вернёт нарушение
          // уникальности — показываем понятную ошибку вместо «Ошибка сети».
          await supabase.from('profiles').upsert({
            'id': user.id,
            'user_tag': rawTag,
            'username': rawTag,
          });
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      if (_isSignUp) {
        try {
          await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } catch (_) {}

        // Если email требует подтверждения, сессия будет null
        if (supabase.auth.currentSession == null) {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Письмо со ссылкой отправлено на $email';
          });
          return;
        }
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const GameScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      // Гонка за ID игрока: тег занял кто-то другой между проверкой и вставкой.
      final text = e.toString();
      final isDuplicateTag =
          text.contains('23505') ||
          text.toLowerCase().contains('duplicate') ||
          text.contains('profiles_user_tag');
      setState(() {
        _errorMessage = isDuplicateTag
            ? 'ID только что заняли. Выберите другой.'
            : 'Нет связи';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryGold = Color(0xFFF5A623);
    const primaryOrange = Color(0xFFFF5722);
    const cardBg = Color(0xFF1A1D24);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1015),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Аура логотипа
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryGold.withValues(alpha: 0.25),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(48),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primaryGold.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          size: 48,
                          color: primaryGold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'PRAXIS',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isSignUp ? 'Начало' : 'PER ASPERA AD ASTRA',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFF8E95A5),
                  ),
                ),
                const SizedBox(height: 36),
                if (_isSignUp) ...[
                  TextField(
                    controller: _tagController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cardBg,
                      labelText: 'ID игрока',
                      hintText: 'alex_warrior',
                      hintStyle: const TextStyle(color: Color(0xFF5D6475)),
                      prefixText: '',
                      prefixStyle: const TextStyle(
                        color: primaryGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      labelStyle: const TextStyle(color: Color(0xFF8E95A5)),
                      prefixIcon: const Icon(
                        Icons.alternate_email_rounded,
                        color: primaryGold,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: primaryGold,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Поле Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cardBg,
                    labelText: 'Почта',
                    labelStyle: const TextStyle(color: Color(0xFF8E95A5)),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: primaryGold,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Поле Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cardBg,
                    labelText: 'Пароль',
                    labelStyle: const TextStyle(color: Color(0xFF8E95A5)),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: primaryGold,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // Игровая кнопка действия с золотым градиентом
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [primaryGold, primaryOrange],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryGold.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _isSignUp ? 'Создать аккаунт' : 'Войти',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Color(0xFF0F1015),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _errorMessage = null;
                          });
                        },
                  child: Text(
                    _isSignUp
                        ? 'Уже есть аккаунт? Войти'
                        : 'Нет аккаунта? Создать',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
