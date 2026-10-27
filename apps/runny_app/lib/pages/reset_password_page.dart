import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/password_requirements_checklist.dart';
import '../widgets/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../utils/unsigned_text_input_formatter.dart';

/// Hiển thị khi người dùng bấm liên kết đặt lại mật khẩu trong email
/// (sự kiện `passwordRecovery`). Cho phép đặt mật khẩu mới rồi quay lại
/// luồng đăng nhập bình thường.
class ResetPasswordPage extends StatefulWidget {
  final VoidCallback onDone;
  final bool invalidLink;

  const ResetPasswordPage({
    super.key,
    required this.onDone,
    this.invalidLink = false,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();
    if (!PasswordRequirementsChecklist.isValid(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('password_requirements_error')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.translate('password_updated'))),
        );
      }
      if (mounted) widget.onDone();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: sportPlatformGradient(context)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: glassCard(
                  context: context,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const RunnyLogo(fontSize: 32),
                      const SizedBox(height: 28),
                      Text(
                        context.translate('set_new_password'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.invalidLink) ...[
                        Text(context.translate('reset_link_invalid')),
                        const SizedBox(height: 24),
                        GradientButton(
                          onPressed: widget.onDone,
                          child: Text(context.translate('back_to_login')),
                        ),
                      ] else ...[
                        TextField(
                          controller: _passwordController,
                          decoration: themedInputDecoration(
                            context,
                            context.translate('new_password'),
                            icon: Icons.lock,
                            isRequired: true,
                          ),
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          inputFormatters: [UnsignedTextInputFormatter()],
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_passwordController.text.isNotEmpty)
                          PasswordRequirementsChecklist(
                            password: _passwordController.text,
                          ),
                        const SizedBox(height: 24),
                        GradientButton(
                          onPressed:
                              _isLoading ||
                                  !PasswordRequirementsChecklist.isValid(
                                    _passwordController.text,
                                  )
                              ? null
                              : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(context.translate('update_password')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
