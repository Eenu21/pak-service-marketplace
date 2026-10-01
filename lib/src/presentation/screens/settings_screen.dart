import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../controllers/app_settings_controller.dart';
import '../controllers/auth_controller.dart';
import '../controllers/notification_runtime_controller.dart';

String _friendlyErrorMessage(Object error) {
  final text = error.toString().trim();
  if (text.startsWith('Bad state:')) {
    return text.substring('Bad state:'.length).trim();
  }
  if (text.startsWith('Exception:')) {
    return text.substring('Exception:'.length).trim();
  }
  return text;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final user = ref.watch(currentUserProvider);
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                _HeaderIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go('/home');
                  },
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: Color(0xFF1B1956),
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Control language, privacy and notification preferences',
                        style: TextStyle(
                          color: Color(0xFF6F7498),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SettingsCard(
              title: 'Preferences',
              child: Column(
                children: <Widget>[
                  _SettingsValueRow(
                    icon: Icons.language_rounded,
                    iconBg: const Color(0xFFF2ECFF),
                    iconColor: const Color(0xFF7C5CFF),
                    title: t.t('language'),
                    subtitle: 'Choose the language used throughout the app',
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: settings.locale.languageCode,
                        borderRadius: BorderRadius.circular(16),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(t.t('english')),
                          ),
                          DropdownMenuItem(
                            value: 'ur',
                            child: Text(t.t('urdu')),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value == null) {
                            return;
                          }
                          try {
                            await ref
                                .read(appSettingsControllerProvider.notifier)
                                .setLocale(value);
                            if (user != null) {
                              await ref
                                  .read(authControllerProvider.notifier)
                                  .updateProfile(
                                    user.copyWith(languageCode: value),
                                  );
                            }
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_friendlyErrorMessage(error)),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const _SettingsDivider(),
                  _SettingsSwitchRow(
                    icon: Icons.notifications_active_outlined,
                    iconBg: const Color(0xFFEFF4FF),
                    iconColor: const Color(0xFF4E78FF),
                    title: t.t('push_notifications'),
                    subtitle: t.t('push_notifications_desc'),
                    value: settings.pushNotifications,
                    onChanged: (value) async {
                      try {
                        if (value) {
                          final granted = await ref
                              .read(notificationRuntimeProvider)
                              .requestPermissionFromSettings();
                          if (!context.mounted) {
                            return;
                          }
                          if (!granted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  t.t('notification_permission_denied'),
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        await ref
                            .read(appSettingsControllerProvider.notifier)
                            .setPushNotifications(value);
                        if (user != null) {
                          await ref
                              .read(authControllerProvider.notifier)
                              .updateProfile(
                                user.copyWith(notificationsEnabled: value),
                              );
                        }
                      } catch (error) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_friendlyErrorMessage(error)),
                          ),
                        );
                      }
                    },
                  ),
                  const _SettingsDivider(),
                  _SettingsSwitchRow(
                    icon: Icons.privacy_tip_outlined,
                    iconBg: const Color(0xFFEAF8EE),
                    iconColor: const Color(0xFF37A95E),
                    title: t.t('privacy_mode'),
                    subtitle: t.t('privacy_mode_desc'),
                    value: settings.privacyMode,
                    onChanged: (value) => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setPrivacyMode(value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SettingsCard(
              title: 'Support & Alerts',
              child: Column(
                children: <Widget>[
                  _ActionSettingRow(
                    icon: Icons.send_outlined,
                    iconBg: const Color(0xFFFFF1E8),
                    iconColor: const Color(0xFFFF8A2A),
                    title: t.t('send_test_notification'),
                    subtitle: t.t('send_test_notification_desc'),
                    onTap: () async {
                      if (user == null) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t.t('not_logged_in'))),
                        );
                        return;
                      }
                      final sent = await ref
                          .read(notificationRuntimeProvider)
                          .sendWorkerJobTestNotification(workerUserId: user.id);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            sent
                                ? t.t('test_notification_sent')
                                : t.t('notification_permission_denied'),
                          ),
                        ),
                      );
                    },
                  ),
                  const _SettingsDivider(),
                  const _ActionSettingRow(
                    icon: Icons.support_agent_outlined,
                    iconBg: Color(0xFFF2ECFF),
                    iconColor: Color(0xFF7C5CFF),
                    title: 'Help & Support',
                    subtitle: 'Use in-app chat and notifications for support updates',
                  ),
                  const _SettingsDivider(),
                  const _ActionSettingRow(
                    icon: Icons.gavel_outlined,
                    iconBg: Color(0xFFEFF4FF),
                    iconColor: Color(0xFF4E78FF),
                    title: 'Cancellation & Disputes',
                    subtitle: 'Review app rules before cancelling or raising disputes',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x100E1330),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF1B1956)),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100E1330),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1B1956),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SettingsValueRow extends StatelessWidget {
  const _SettingsValueRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SettingsLeadingIcon(
          icon: icon,
          background: iconBg,
          color: iconColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1B1956),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF70759B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SettingsLeadingIcon(
          icon: icon,
          background: iconBg,
          color: iconColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1B1956),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF70759B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ActionSettingRow extends StatelessWidget {
  const _ActionSettingRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            _SettingsLeadingIcon(
              icon: icon,
              background: iconBg,
              color: iconColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1B1956),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF70759B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFFB1B5CD),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLeadingIcon extends StatelessWidget {
  const _SettingsLeadingIcon({
    required this.icon,
    required this.background,
    required this.color,
  });

  final IconData icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: Color(0xFFEDECF6)),
    );
  }
}
