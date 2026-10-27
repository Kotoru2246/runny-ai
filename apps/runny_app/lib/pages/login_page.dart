import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/password_recovery_service.dart';
import '../widgets/ui_components.dart';
import '../widgets/password_requirements_checklist.dart';
import '../l10n/app_localizations.dart';
import '../utils/unsigned_text_input_formatter.dart';

class LoginPage extends StatefulWidget {
  final bool initialIsSignUp;
  final RegistrationService? registrationService;

  const LoginPage({
    super.key,
    this.initialIsSignUp = false,
    this.registrationService,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _passwordGuidanceKey = GlobalKey();
  late final RegistrationService _registrationService;
  bool _isLoading = false;
  late bool _isSignUp = widget.initialIsSignUp;
  bool _hasSubmitted = false;
  bool _obscurePassword = true;
  String? _pendingConfirmationEmail;

  @override
  void initState() {
    super.initState();
    _registrationService =
        widget.registrationService ?? SupabaseRegistrationService();
    _passwordFocusNode.addListener(_onPasswordFocusChanged);
  }

  void _onPasswordFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_passwordFocusNode.hasFocus && _isSignUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_revealPasswordGuidance());
      });
    }
  }

  Future<void> _revealPasswordGuidance() async {
    if (!mounted || !_passwordFocusNode.hasFocus || !_isSignUp) return;

    final guidanceContext = _passwordGuidanceKey.currentContext;
    if (guidanceContext == null) return;
    await Scrollable.ensureVisible(
      guidanceContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleAuth() async {
    if (_isLoading) return;

    setState(() => _hasSubmitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        final email = _emailController.text.trim();
        final result = await _registrationService.signUp(
          email: email,
          password: _passwordController.text,
        );

        if (!mounted) return;
        switch (result.status) {
          case RegistrationStatus.signedIn:
            _clearPasswords();
            // Confirm email TẮT: đã đăng nhập ngay. LoginPage được push đè lên
            // AuthGate, nên phải pop về gốc để AuthGate điều hướng vào onboarding.
            Navigator.of(context).popUntil((route) => route.isFirst);
            break;
          case RegistrationStatus.emailAlreadyRegistered:
            // Supabase trả về user "giả" khi email đã tồn tại (chống dò email).
            _showError('email_already_registered');
            setState(() {
              _isSignUp = false;
              _hasSubmitted = false;
              _formKey = GlobalKey<FormState>();
              _clearPasswords();
            });
            break;
          case RegistrationStatus.confirmationRequired:
            // Confirm email BẬT: cần xác thực qua email trước khi đăng nhập.
            setState(() {
              _pendingConfirmationEmail = email;
              _clearPasswords();
            });
            break;
          case RegistrationStatus.invalidEmail:
            _showError('invalid_email');
            break;
          case RegistrationStatus.disposableEmail:
            _showError('disposable_email_not_allowed');
            break;
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        // Đăng nhập thành công: pop LoginPage để AuthGate (gốc) vào dashboard.
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } on TimeoutException {
      _showError('auth_request_timeout');
    } on AuthException catch (e) {
      if (mounted) {
        // Email chưa xác thực: cho phép gửi lại email xác thực ngay từ snackbar.
        final notConfirmed =
            e.message.toLowerCase().contains('not confirmed') ||
            e.message.toLowerCase().contains('not been confirmed');
        final message = notConfirmed
            ? context.translate('email_not_confirmed')
            : !_isSignUp
            ? context.translate('invalid_login_credentials')
            : context.translate(_registrationErrorKey(e));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            action: notConfirmed
                ? SnackBarAction(
                    label: context.translate('resend_confirmation'),
                    textColor: Colors.white,
                    onPressed: _resendConfirmation,
                  )
                : null,
          ),
        );
      }
    } catch (error) {
      _showError(_unexpectedErrorKey(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _registrationErrorKey(AuthException error) {
    if (error is AuthRetryableFetchException) return 'auth_network_error';

    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'email_already_registered';
    }
    if (code == 'email_address_invalid' || message.contains('invalid email')) {
      return 'invalid_email';
    }
    if (error is AuthWeakPasswordException ||
        code == 'weak_password' ||
        message.contains('password') && message.contains('weak')) {
      return 'password_requirements_error';
    }
    if (_looksLikeTimeout(message)) return 'auth_request_timeout';
    if (_looksLikeNetworkFailure(message)) return 'auth_network_error';
    return 'signup_failed';
  }

  String _unexpectedErrorKey(Object error) {
    final message = error.toString().toLowerCase();
    if (_looksLikeTimeout(message)) return 'auth_request_timeout';
    if (_looksLikeNetworkFailure(message)) return 'auth_network_error';
    return _isSignUp ? 'signup_failed' : 'error_occurred';
  }

  bool _looksLikeTimeout(String message) => message.contains('timeout');

  bool _looksLikeNetworkFailure(String message) =>
      message.contains('network') ||
      message.contains('failed host lookup') ||
      message.contains('connection') ||
      message.contains('socket') ||
      message.contains('failed to fetch');

  void _showError(String messageKey) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.translate(messageKey)),
          backgroundColor: Colors.redAccent,
        ),
      );
  }

  void _clearPasswords() {
    _passwordController.clear();
  }

  void _setAuthMode(bool isSignUp) {
    if (_isSignUp == isSignUp) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSignUp = isSignUp;
      _hasSubmitted = false;
      _formKey = GlobalKey<FormState>();
      _obscurePassword = true;
    });
  }

  Future<void> _resendConfirmation() async {
    final email = _pendingConfirmationEmail ?? _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.translate('enter_email_first'))),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.translate('confirmation_resent'))),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void dispose() {
    _passwordFocusNode
      ..removeListener(_onPasswordFocusChanged)
      ..dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return context.translate('email_required');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return context.translate('invalid_email');
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return context.translate('password_required');
    if (_isSignUp && !PasswordRequirementsChecklist.isValid(password)) {
      return context.translate('password_requirements_error');
    }
    return null;
  }

  void _onPasswordChanged(String _) {
    setState(() {});
  }

  Future<void> _handleForgotPassword() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.translate('reset_password_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dialogContext.translate('reset_password_hint')),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: themedInputDecoration(
                  dialogContext,
                  dialogContext.translate('email'),
                  icon: Icons.email,
                  isRequired: true,
                ),
                inputFormatters: [UnsignedTextInputFormatter()],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.translate('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(dialogContext.translate('send')),
            ),
          ],
        );
      },
    );

    if (email == null || email.isEmpty || !mounted) return;

    try {
      await PasswordRecoveryService(
        Supabase.instance.client.auth,
      ).sendResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.translate('reset_email_sent'))),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasPassword = _passwordController.text.isNotEmpty;
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardVisible = mediaQuery.viewInsets.bottom > 0;
    final isCompact = isKeyboardVisible || mediaQuery.size.height < 700;
    final isNarrow = mediaQuery.size.width < 400;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: sportPlatformGradient(context)),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFA6B27).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              key: const ValueKey('auth-scroll-view'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                isNarrow ? 16 : 24,
                isKeyboardVisible
                    ? 12
                    : isCompact
                    ? 76
                    : 92,
                isNarrow ? 16 : 24,
                isKeyboardVisible ? 20 : 36,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: glassCard(
                  context: context,
                  padding: EdgeInsets.all(isCompact ? 20 : 28),
                  borderRadius: BorderRadius.circular(isNarrow ? 22 : 28),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _hasSubmitted
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isKeyboardVisible) ...[
                            FittedBox(
                              key: const ValueKey('auth-brand'),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: RunnyLogo(fontSize: isCompact ? 26 : 32),
                            ),
                            SizedBox(height: isCompact ? 20 : 28),
                          ],
                          if (_pendingConfirmationEmail != null)
                            _ConfirmationPendingContent(
                              email: _pendingConfirmationEmail!,
                              isLoading: _isLoading,
                              onResend: _resendConfirmation,
                              onBackToLogin: () => setState(() {
                                _isSignUp = false;
                                _clearPasswords();
                                _pendingConfirmationEmail = null;
                              }),
                            )
                          else ...[
                            _AuthModeSwitcher(
                              isSignUp: _isSignUp,
                              enabled: !_isLoading,
                              onChanged: _setAuthMode,
                            ),
                            SizedBox(height: isCompact ? 16 : 22),
                            TextFormField(
                              key: const ValueKey('auth-email-field'),
                              controller: _emailController,
                              decoration: themedInputDecoration(
                                context,
                                context.translate('email'),
                                icon: Icons.email_outlined,
                                isRequired: true,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: _validateEmail,
                              onFieldSubmitted: (_) =>
                                  _passwordFocusNode.requestFocus(),
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              inputFormatters: [UnsignedTextInputFormatter()],
                            ),
                            const SizedBox(height: 16),
                            _PasswordFormField(
                              fieldKey: const ValueKey('auth-password-field'),
                              controller: _passwordController,
                              focusNode: _passwordFocusNode,
                              label: context.translate('password'),
                              obscureText: _obscurePassword,
                              visibilityToggleKey: const ValueKey(
                                'auth-password-visibility-toggle',
                              ),
                              textInputAction: TextInputAction.done,
                              autofillHints: [
                                _isSignUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              scrollPadding: EdgeInsets.only(
                                top: 24,
                                bottom: _isSignUp ? 180 : 40,
                              ),
                              validator: _validatePassword,
                              onChanged: _onPasswordChanged,
                              onFieldSubmitted: (_) => _handleAuth(),
                              onToggleVisibility: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              alignment: Alignment.topCenter,
                              child:
                                  _isSignUp &&
                                      (_passwordFocusNode.hasFocus ||
                                          hasPassword)
                                  ? KeyedSubtree(
                                      key: _passwordGuidanceKey,
                                      child: PasswordRequirementsChecklist(
                                        password: _passwordController.text,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            if (!_isSignUp)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _handleForgotPassword,
                                  child: Text(
                                    context.translate('forgot_password'),
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              height: _isSignUp
                                  ? isCompact
                                        ? 18
                                        : 24
                                  : 8,
                            ),
                            GradientButton(
                              key: const ValueKey('auth-submit-button'),
                              onPressed: _isLoading ? null : _handleAuth,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isSignUp
                                          ? context.translate('signup')
                                          : context.translate('login'),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isKeyboardVisible)
            Positioned(
              top: mediaQuery.padding.top + 8,
              right: 12,
              child: Row(
                children: [const LanguageSwitcher(), const ThemeToggle()],
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthModeSwitcher extends StatelessWidget {
  final bool isSignUp;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AuthModeSwitcher({
    required this.isSignUp,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeButton(
              buttonKey: const ValueKey('auth-login-mode'),
              label: context.translate('login'),
              selected: !isSignUp,
              enabled: enabled,
              onPressed: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _AuthModeButton(
              buttonKey: const ValueKey('auth-signup-mode'),
              label: context.translate('signup'),
              selected: isSignUp,
              enabled: enabled,
              onPressed: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  final Key buttonKey;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  const _AuthModeButton({
    required this.buttonKey,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      key: buttonKey,
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: selected ? accentPulseGradient : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFA6B27).withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordFormField extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool obscureText;
  final Key visibilityToggleKey;
  final TextInputAction textInputAction;
  final Iterable<String> autofillHints;
  final EdgeInsets scrollPadding;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback onToggleVisibility;

  const _PasswordFormField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.visibilityToggleKey,
    required this.textInputAction,
    required this.autofillHints,
    required this.scrollPadding,
    required this.validator,
    required this.onToggleVisibility,
    this.focusNode,
    this.onChanged,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: theme.colorScheme.error, width: 1.2),
    );
    final visibilityLabel = context.translate(
      obscureText ? 'show_password' : 'hide_password',
    );

    return TextFormField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      decoration:
          themedInputDecoration(
            context,
            label,
            icon: Icons.lock,
            isRequired: true,
          ).copyWith(
            errorMaxLines: 2,
            errorBorder: errorBorder,
            focusedErrorBorder: errorBorder.copyWith(
              borderSide: BorderSide(
                color: theme.colorScheme.error,
                width: 1.6,
              ),
            ),
            suffixIcon: Semantics(
              button: true,
              label: visibilityLabel,
              child: ExcludeSemantics(
                child: IconButton(
                  key: visibilityToggleKey,
                  tooltip: visibilityLabel,
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
          ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: autofillHints,
      scrollPadding: scrollPadding,
      style: TextStyle(
        color: theme.brightness == Brightness.dark
            ? Colors.white
            : Colors.black87,
      ),
      inputFormatters: [UnsignedTextInputFormatter()],
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}

class _ConfirmationPendingContent extends StatelessWidget {
  final String email;
  final bool isLoading;
  final VoidCallback onResend;
  final VoidCallback onBackToLogin;

  const _ConfirmationPendingContent({
    required this.email,
    required this.isLoading,
    required this.onResend,
    required this.onBackToLogin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.white70 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          context.translate('confirm_email_title'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: primaryText,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.translate('confirm_email_desc', [email]),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: secondaryText,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          onPressed: isLoading ? null : onResend,
          child: Text(context.translate('resend_confirmation')),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: isLoading ? null : onBackToLogin,
          child: Text(
            context.translate('back_to_login'),
            style: TextStyle(color: secondaryText, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
