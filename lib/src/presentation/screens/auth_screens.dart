import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/repository_provider.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/device_context_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import 'admin_dashboard_screen.dart';
import 'home_shell_screen.dart';

String _authErrorMessage(Object error) {
  if (error is StateError) {
    return error.message;
  }
  final text = error.toString().trim();
  if (text.startsWith('Bad state: ')) {
    return text.substring('Bad state: '.length).trim();
  }
  if (text.startsWith('Exception: ')) {
    return text.substring('Exception: '.length).trim();
  }
  return text;
}

final RegExp _emailPattern = RegExp(
  r'^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$',
  caseSensitive: false,
);
final RegExp _phonePattern = RegExp(r'^\+?[0-9]{7,15}$');

bool _isStrongPassword(String value) {
  if (value.length < 10) {
    return false;
  }
  final hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
  final hasLowercase = RegExp(r'[a-z]').hasMatch(value);
  final hasDigit = RegExp(r'[0-9]').hasMatch(value);
  final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
  return hasUppercase && hasLowercase && hasDigit && hasSpecial;
}

String? _validateEmailInput(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Email is required.';
  }
  if (!_emailPattern.hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? _validatePhoneInput(String? value) {
  final phone = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
  if (phone.isEmpty) {
    return 'Phone is required.';
  }
  if (!_phonePattern.hasMatch(phone)) {
    return 'Enter a valid phone number.';
  }
  return null;
}

String? _validateStrongPasswordInput(String? value) {
  final password = value ?? '';
  if (!_isStrongPassword(password)) {
    return 'Use 10+ chars with upper, lower, number, and symbol.';
  }
  return null;
}

class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.maybeWhen(data: (value) => value, orElse: () => null);
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return const LoginScreen();
    }
    if (user.role == UserRole.admin) {
      return const AdminDashboardScreen();
    }
    return const HomeShellScreen();
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            LoginInput(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            ),
          );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_authErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppTheme.brandNavy,
              AppTheme.brandBlue,
              AppTheme.brandTeal,
            ],
          ),
        ),
        child: SafeArea(
          child: ResponsiveContainer(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1050),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 850;
                    final intro = const _AuthIntroCard();
                    final form = _LoginForm(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      obscure: _obscure,
                      submitting: _submitting,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmit: _submit,
                    );

                    if (!wide) {
                      return SingleChildScrollView(
                        child:
                            Column(
                                  children: <Widget>[
                                    intro,
                                    const SizedBox(height: 12),
                                    form,
                                  ],
                                )
                                .animate()
                                .fadeIn(duration: 420.ms)
                                .slideY(begin: 0.05, end: 0),
                      );
                    }

                    return Row(
                          children: <Widget>[
                            Expanded(flex: 5, child: intro),
                            const SizedBox(width: 16),
                            Expanded(flex: 6, child: form),
                          ],
                        )
                        .animate()
                        .fadeIn(duration: 420.ms)
                        .slideY(begin: 0.05, end: 0);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthIntroCard extends StatelessWidget {
  const _AuthIntroCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.t('app_name'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.t('auth_intro_subtitle'),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          _AuthPoint(
            icon: Icons.verified_user_outlined,
            text: t.t('auth_point_verified_pros'),
          ),
          _AuthPoint(
            icon: Icons.map_outlined,
            text: t.t('auth_point_nearby_map'),
          ),
          _AuthPoint(
            icon: Icons.attach_money_outlined,
            text: t.t('auth_point_payments'),
          ),
          _AuthPoint(
            icon: Icons.history_edu_outlined,
            text: t.t('auth_point_audit'),
          ),
        ],
      ),
    );
  }
}

class _AuthPoint extends StatelessWidget {
  const _AuthPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Icon(icon, color: Colors.white, size: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscure,
    required this.submitting,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final bool submitting;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                t.t('login'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.t('login_welcome_back'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(labelText: t.t('email')),
                validator: _validateEmailInput,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: passwordController,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: t.t('password'),
                  suffixIcon: IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Password is required.'
                    : null,
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.t('login')),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => context.go('/register'),
                child: Text(t.t('register')),
              ),
              const SizedBox(height: 8),
              const _DemoCredentials(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoCredentials extends ConsumerWidget {
  const _DemoCredentials();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final useFirebase = ref.watch(useFirebaseRepositoryProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(useFirebase ? 'Firebase mode is active.' : t.t('demo_accounts')),
          const SizedBox(height: 4),
          if (useFirebase)
            const Text(
              'The demo accounts only work in local mode. Use a real Firebase account here.',
            )
          else ...<Widget>[
            Text(t.t('demo_customer_creds')),
            Text(t.t('demo_pro_creds')),
            Text(t.t('demo_locked_pro_creds')),
            Text(t.t('demo_admin_creds')),
          ],
        ],
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  UserRole _role = UserRole.customer;
  bool _accepted = false;
  bool _submitting = false;
  final Set<JobCategory> _preferredCategories = <JobCategory>{};

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_accepted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('terms_privacy_required'))));
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('password_mismatch'))));
      return;
    }
    if (_role == UserRole.pro && _preferredCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('preferred_categories_required'))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final config = ref.read(appConfigProvider);
      final deviceContext = await ref
          .read(deviceContextServiceProvider)
          .resolve()
          .timeout(
            const Duration(milliseconds: 800),
            onTimeout: () => const DeviceContext(
              deviceInfo: 'unavailable',
              ipAddress: 'unavailable',
            ),
          );
      await ref
          .read(authControllerProvider.notifier)
          .register(
            RegisterInput(
              fullName: _nameController.text.trim(),
              email: _emailController.text.trim(),
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              role: _role,
              acceptance: TermsAcceptance(
                termsVersion: config.termsVersion,
                privacyVersion: config.privacyVersion,
                acceptedAt: DateTime.now(),
                ipAddress: deviceContext.ipAddress,
                deviceInfo: deviceContext.deviceInfo,
                checkboxConfirmed: true,
              ),
              preferredCategories: _preferredCategories.toList(growable: false),
            ),
          );
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_authErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFEDF4FF), Color(0xFFF8FBFF)],
          ),
        ),
        child: SafeArea(
          child: ResponsiveContainer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth > 900;
                        final intro = _RegisterIntroPanel(role: _role);
                        final form = _RegisterForm(
                          nameController: _nameController,
                          emailController: _emailController,
                          phoneController: _phoneController,
                          passwordController: _passwordController,
                          confirmPasswordController: _confirmPasswordController,
                          role: _role,
                          accepted: _accepted,
                          preferredCategories: _preferredCategories,
                          submitting: _submitting,
                          onRoleChanged: (value) =>
                              setState(() => _role = value),
                          onPreferredChanged: (category, selected) =>
                              setState(() {
                                if (selected) {
                                  _preferredCategories.add(category);
                                } else {
                                  _preferredCategories.remove(category);
                                }
                              }),
                          onAcceptedChanged: (value) =>
                              setState(() => _accepted = value ?? false),
                          onSubmit: _submit,
                          registerLabel: t.t('register'),
                          fullNameLabel: t.t('full_name'),
                          emailLabel: t.t('email'),
                          phoneLabel: t.t('phone'),
                          passwordLabel: t.t('password'),
                          confirmPasswordLabel: t.t('confirm_password'),
                          acceptTermsLabel: t.t('accept_terms'),
                        );

                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              intro,
                              const SizedBox(height: 12),
                              form,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 4, child: intro),
                            const SizedBox(width: 16),
                            Expanded(flex: 7, child: form),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 380.ms).slideY(begin: 0.04, end: 0),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterIntroPanel extends StatelessWidget {
  const _RegisterIntroPanel({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final subtitle = role == UserRole.pro
        ? t.t('register_subtitle_pro')
        : t.t('register_subtitle_customer');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.brandNavy, AppTheme.brandBlue],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.t('create_account'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
          ),
          const SizedBox(height: 12),
          _AuthPoint(
            icon: Icons.verified_user_outlined,
            text: t.t('auth_point_identity_trust'),
          ),
          _AuthPoint(
            icon: Icons.gavel_outlined,
            text: t.t('auth_point_legal_acceptance'),
          ),
          _AuthPoint(
            icon: Icons.location_on_outlined,
            text: t.t('auth_point_privacy_address'),
          ),
        ],
      ),
    );
  }
}

class _RegisterForm extends StatelessWidget {
  const _RegisterForm({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.role,
    required this.accepted,
    required this.preferredCategories,
    required this.submitting,
    required this.onRoleChanged,
    required this.onPreferredChanged,
    required this.onAcceptedChanged,
    required this.onSubmit,
    required this.registerLabel,
    required this.fullNameLabel,
    required this.emailLabel,
    required this.phoneLabel,
    required this.passwordLabel,
    required this.confirmPasswordLabel,
    required this.acceptTermsLabel,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final UserRole role;
  final bool accepted;
  final Set<JobCategory> preferredCategories;
  final bool submitting;
  final ValueChanged<UserRole> onRoleChanged;
  final void Function(JobCategory category, bool selected) onPreferredChanged;
  final ValueChanged<bool?> onAcceptedChanged;
  final VoidCallback onSubmit;
  final String registerLabel;
  final String fullNameLabel;
  final String emailLabel;
  final String phoneLabel;
  final String passwordLabel;
  final String confirmPasswordLabel;
  final String acceptTermsLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          t.t('registration_form'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth > 620;
            if (!split) {
              return Column(
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: fullNameLabel),
                    validator: (value) =>
                        (value == null || value.trim().length < 2)
                        ? 'Enter your full name.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(labelText: phoneLabel),
                    validator: _validatePhoneInput,
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: fullNameLabel),
                    validator: (value) =>
                        (value == null || value.trim().length < 2)
                        ? 'Enter your full name.'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(labelText: phoneLabel),
                    validator: _validatePhoneInput,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: emailController,
          decoration: InputDecoration(labelText: emailLabel),
          validator: _validateEmailInput,
        ),
        const SizedBox(height: 10),
        Text(
          t.t('account_type'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final choices = <Widget>[
              _AccountTypeChoice(
                icon: Icons.home_repair_service_outlined,
                title: t.t('customer'),
                subtitle: t.t('register_subtitle_customer'),
                selected: role == UserRole.customer,
                onTap: () => onRoleChanged(UserRole.customer),
              ),
              _AccountTypeChoice(
                icon: Icons.handyman_outlined,
                title: t.t('professional'),
                subtitle: t.t('register_subtitle_pro'),
                selected: role == UserRole.pro,
                onTap: () => onRoleChanged(UserRole.pro),
              ),
            ];
            if (constraints.maxWidth < 460) {
              return Column(
                children: <Widget>[
                  choices[0],
                  const SizedBox(height: 8),
                  choices[1],
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: choices[0]),
                const SizedBox(width: 10),
                Expanded(child: choices[1]),
              ],
            );
          },
        ),
        if (role == UserRole.pro) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            t.t('preferred_categories'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: JobCategory.values
                .map(
                  (category) => FilterChip(
                    label: Text(t.categoryLabel(category.value)),
                    selected: preferredCategories.contains(category),
                    onSelected: (selected) =>
                        onPreferredChanged(category, selected),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth > 620;
            if (!split) {
              return Column(
                children: <Widget>[
                  TextFormField(
                    controller: passwordController,
                    decoration: InputDecoration(labelText: passwordLabel),
                    obscureText: true,
                    validator: _validateStrongPasswordInput,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: confirmPasswordLabel,
                    ),
                    obscureText: true,
                    validator: (value) => (value == null || value.isEmpty)
                        ? t.t('required_field')
                        : null,
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: passwordController,
                    decoration: InputDecoration(labelText: passwordLabel),
                    obscureText: true,
                    validator: _validateStrongPasswordInput,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: confirmPasswordLabel,
                    ),
                    obscureText: true,
                    validator: (value) => (value == null || value.isEmpty)
                        ? t.t('required_field')
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E1ED)),
          ),
          child: CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            value: accepted,
            onChanged: onAcceptedChanged,
            title: Text(acceptTermsLabel),
            subtitle: Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton(
                  onPressed: () => context.push('/terms'),
                  child: Text(t.t('terms')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(registerLabel),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text(t.t('already_have_account_login')),
          ),
        ),
      ],
    );
  }
}

class _AccountTypeChoice extends StatelessWidget {
  const _AccountTypeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : AppTheme.brandNavy;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Material(
        color: selected ? const Color(0xFFEAF3FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 94),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colorScheme.primary : AppTheme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  Future<String> _loadTerms(BuildContext context) async {
    try {
      return await rootBundle.loadString(
        'assets/policies/servicemen_terms_and_conditions.md',
      );
    } catch (_) {
      return AppLocalizations.of(context).t('terms_content');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _PolicyScaffold(
      title: t.t('terms_conditions'),
      content: FutureBuilder<String>(
        future: _loadTerms(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectableText(snapshot.data ?? '');
        },
      ),
    );
  }
}

class _PolicyScaffold extends StatelessWidget {
  const _PolicyScaffold({required this.title, required this.content});

  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style:
                Theme.of(context).textTheme.bodyLarge ??
                const TextStyle(fontSize: 16),
            child: content,
          ),
        ),
      ),
    );
  }
}
