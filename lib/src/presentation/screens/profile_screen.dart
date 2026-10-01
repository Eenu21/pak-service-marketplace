import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/services/formatters.dart';
import '../../core/services/google_places_service.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../widgets/google_address_search_sheet.dart';

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

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _paymentController = TextEditingController();
  final _defaultAddressController = TextEditingController();
  final _uuid = const Uuid();
  final _imagePicker = ImagePicker();
  String? _profileImageValue;
  GooglePlaceDetails? _selectedDefaultAddress;
  String _initialDefaultAddress = '';
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _paymentController.dispose();
    _defaultAddressController.dispose();
    super.dispose();
  }

  SavedLocation? _latestSavedLocation(AppUser user) {
    if (user.savedLocations.isEmpty) {
      return null;
    }
    return user.savedLocations.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
  }

  void _initFromUser(AppUser user) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _nameController.text = user.fullName;
    _phoneController.text = user.phone;
    _profileImageValue = user.profileImageUrl;
    _paymentController.text = user.paymentAccount ?? '';
    final latestAddress = _latestSavedLocation(user)?.address ?? '';
    _defaultAddressController.text = latestAddress;
    _initialDefaultAddress = latestAddress;
  }

  String _normalizeAddress(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  Future<SavedLocation?> _resolveDefaultAddress(AppUser user) async {
    final typedAddress = _defaultAddressController.text.trim();
    if (typedAddress.isEmpty) {
      return null;
    }

    final latestLocation = _latestSavedLocation(user);
    final selectedAddress = _selectedDefaultAddress;
    final locationId = latestLocation?.id ?? _uuid.v4();
    final label = latestLocation?.label ?? 'Default Address';

    if (selectedAddress != null &&
        _normalizeAddress(selectedAddress.formattedAddress) ==
            _normalizeAddress(typedAddress)) {
      return SavedLocation(
        id: locationId,
        label: label,
        latitude: selectedAddress.latitude,
        longitude: selectedAddress.longitude,
        address: selectedAddress.formattedAddress,
        createdAt: DateTime.now(),
      );
    }

    GooglePlaceDetails? resolved;
    try {
      resolved = await ref
          .read(googlePlacesServiceProvider)
          .geocodeAddress(typedAddress);
    } catch (_) {
      resolved = null;
    }

    if (resolved != null) {
      return SavedLocation(
        id: locationId,
        label: label,
        latitude: resolved.latitude,
        longitude: resolved.longitude,
        address: resolved.formattedAddress,
        createdAt: DateTime.now(),
      );
    }

    if (latestLocation == null) {
      final locationResult = await ref
          .read(locationServiceProvider)
          .getCurrentPosition(
            aggressive: true,
            requestPermissionIfNeeded: true,
          );
      final position = locationResult.position;
      if (position == null) {
        return null;
      }
      return SavedLocation(
        id: locationId,
        label: label,
        latitude: position.latitude,
        longitude: position.longitude,
        address: typedAddress,
        createdAt: DateTime.now(),
      );
    }

    return SavedLocation(
      id: latestLocation.id,
      label: label,
      latitude: latestLocation.latitude,
      longitude: latestLocation.longitude,
      address: typedAddress,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _pickDefaultAddress() async {
    final selected = await showGoogleAddressSearchSheet(
      context,
      initialQuery: _defaultAddressController.text,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDefaultAddress = selected;
      _defaultAddressController.text = selected.formattedAddress;
    });
  }

  Future<bool> _requestGalleryPermission() async {
    final photos = await Permission.photos.request();
    if (photos.isGranted || photos.isLimited) {
      return true;
    }
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<bool> _requestCameraPermission() async {
    final camera = await Permission.camera.request();
    return camera.isGranted;
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final t = AppLocalizations.of(context);
    final granted = source == ImageSource.gallery
        ? await _requestGalleryPermission()
        : await _requestCameraPermission();
    if (!granted) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.gallery
                ? t.t('gallery_permission_required')
                : t.t('camera_permission_required'),
          ),
        ),
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 72,
        maxWidth: 900,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.t('image_read_error'))));
        return;
      }
      final encoded = base64Encode(bytes);
      setState(() => _profileImageValue = 'data:image/jpeg;base64,$encoded');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorMessage(error))));
    }
  }

  Future<void> _showPhotoSourceSheet() async {
    final t = AppLocalizations.of(context);
    final hasPhoto = resolveAvatarProvider(_profileImageValue) != null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.t('change_profile_photo'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.t('choose_photo_source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(t.t('upload_from_gallery')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickProfilePhoto(ImageSource.gallery);
                  },
                ),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(t.t('take_picture')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickProfilePhoto(ImageSource.camera);
                  },
                ),
                if (hasPhoto)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.delete_outline),
                    title: Text(t.t('remove_photo')),
                    onTap: () {
                      Navigator.of(context).pop();
                      _removeProfilePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removeProfilePhoto() {
    setState(() => _profileImageValue = null);
  }

  Future<void> _save(AppUser user) async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final typedDefaultAddress = _defaultAddressController.text.trim();
      final defaultAddressChanged =
          _normalizeAddress(typedDefaultAddress) !=
          _normalizeAddress(_initialDefaultAddress);
      var savedLocations = user.savedLocations;

      if (defaultAddressChanged) {
        final resolvedAddress = await _resolveDefaultAddress(user);
        if (resolvedAddress == null) {
          throw const AddressLookupException(
            'We could not confirm this address yet. Try a fuller address, use Google search, or allow location once so we can save it.',
          );
        }
        savedLocations = <SavedLocation>[
          ...user.savedLocations.where(
            (existing) => existing.id != resolvedAddress.id,
          ),
          resolvedAddress,
        ];
        _defaultAddressController.text = resolvedAddress.address;
        _initialDefaultAddress = resolvedAddress.address;
      }

      final updated = user.copyWith(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        profileImageUrl:
            (_profileImageValue == null || _profileImageValue!.trim().isEmpty)
            ? null
            : _profileImageValue!.trim(),
        paymentAccount: _paymentController.text.trim().isEmpty
            ? null
            : _paymentController.text.trim(),
        savedLocations: savedLocations,
      );
      await ref.read(authControllerProvider.notifier).updateProfile(updated);
      _selectedDefaultAddress = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('profile_updated'))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final t = AppLocalizations.of(context);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.t('change_password')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: currentController,
                decoration: InputDecoration(labelText: t.t('current_password')),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newController,
                decoration: InputDecoration(labelText: t.t('new_password')),
                obscureText: true,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref
                      .read(authControllerProvider.notifier)
                      .changePassword(
                        currentPassword: currentController.text,
                        newPassword: newController.text,
                      );
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.t('password_updated'))),
                  );
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_friendlyErrorMessage(error))),
                  );
                }
              },
              child: Text(t.t('update')),
            ),
          ],
        );
      },
    );
    currentController.dispose();
    newController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final googleSearchEnabled = ref
        .watch(googlePlacesServiceProvider)
        .isConfigured;
    if (user == null) {
      return Scaffold(body: Center(child: Text(t.t('not_logged_in'))));
    }
    _initFromUser(user);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F8FE),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/home');
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(t.t('profile')),
        actions: <Widget>[
          IconButton(
            tooltip: t.t('settings'),
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          child: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 16),
            children: <Widget>[
              _ProfileHeader(
                user: user,
                avatarProvider: resolveAvatarProvider(_profileImageValue),
                onAvatarTap: _showPhotoSourceSheet,
              ),
              const SizedBox(height: 10),
              _ProfileSnapshot(user: user),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 900;
                  final accountForm = _AccountForm(
                    user: user,
                    nameController: _nameController,
                    phoneController: _phoneController,
                    paymentController: _paymentController,
                    defaultAddressController: _defaultAddressController,
                    saving: _saving,
                    googleSearchEnabled: googleSearchEnabled,
                    onPickAddress: _pickDefaultAddress,
                    onSave: () => _save(user),
                  );
                  final actions = _ActionsCard(
                    user: user,
                    onChangePassword: _showChangePasswordDialog,
                  );

                  if (!wide) {
                    return Column(
                      children: <Widget>[
                        accountForm,
                        const SizedBox(height: 10),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 7, child: accountForm),
                      const SizedBox(width: 12),
                      Expanded(flex: 5, child: actions),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.avatarProvider,
    required this.onAvatarTap,
  });

  final AppUser user;
  final ImageProvider<Object>? avatarProvider;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final initials = user.fullName.trim().isEmpty
        ? '?'
        : user.fullName.trim().substring(0, 1).toUpperCase();
    final roleLabel = switch (user.role) {
      UserRole.customer => t.t('customer'),
      UserRole.pro => t.t('professional'),
      UserRole.admin => t.t('admin'),
    };
    final statusLabel = user.isOnline
        ? t.t('online')
        : user.lastSeenAt == null
        ? 'Offline'
        : 'Last seen ${formatDateTime(user.lastSeenAt!)}';
    final statusColor = user.isOnline
        ? const Color(0xFF2FBF71)
        : const Color(0xFF9AA6B2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.brandNavy, AppTheme.brandBlue],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(42),
                onTap: onAvatarTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 2.4,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.white,
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.brandNavy,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.8),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            user.fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _HeaderMetaTag(
                          icon: Icons.badge_outlined,
                          text: roleLabel,
                        ),
                        _HeaderMetaTag(
                          icon: Icons.mail_outline_rounded,
                          text: user.email,
                        ),
                        _HeaderMetaTag(
                          icon: Icons.call_outlined,
                          text: user.phone.trim().isEmpty ? '-' : user.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.role == UserRole.pro &&
                              user.preferredCategories.isNotEmpty
                          ? 'Specializes in ${user.preferredCategories.length} category${user.preferredCategories.length == 1 ? '' : 'ies'}'
                          : 'Keep your profile updated for stronger trust.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.83),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _BadgeChip(
                icon: Icons.workspace_premium_outlined,
                label: user.cnicVerified
                    ? t.t('cnic_verified')
                    : t.t('cnic_pending'),
              ),
              if (user.role == UserRole.pro)
                _BadgeChip(
                  icon: Icons.local_police_outlined,
                  label: user.policeVerified
                      ? t.t('police_badge')
                      : t.t('police_badge_optional'),
                ),
              _BadgeChip(
                icon: Icons.star_rounded,
                label:
                    '${t.t('rating')} ${user.rating.toStringAsFixed(1)} (${user.totalReviews})',
              ),
              _BadgeChip(
                icon: Icons.gavel_outlined,
                label:
                    '${t.t('terms_records')} ${user.termsAcceptanceHistory.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetaTag extends StatelessWidget {
  const _HeaderMetaTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text.trim().isEmpty ? '-' : text.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSnapshot extends StatelessWidget {
  const _ProfileSnapshot({required this.user});

  final AppUser user;

  List<_ProfileQualityCheck> _qualityChecks(AppUser user) {
    return <_ProfileQualityCheck>[
      _ProfileQualityCheck(
        label: 'Phone added',
        done: user.phone.trim().isNotEmpty,
        weight: 15,
      ),
      _ProfileQualityCheck(
        label: 'Profile photo set',
        done: (user.profileImageUrl ?? '').trim().isNotEmpty,
        weight: 15,
      ),
      _ProfileQualityCheck(
        label: 'Terms accepted',
        done: user.termsAcceptanceHistory.isNotEmpty,
        weight: 20,
      ),
      _ProfileQualityCheck(
        label: 'Address saved',
        done: user.savedLocations.isNotEmpty,
        weight: 15,
      ),
      _ProfileQualityCheck(
        label: 'CNIC verified',
        done: user.cnicVerified,
        weight: 20,
      ),
      _ProfileQualityCheck(
        label: user.role == UserRole.pro
            ? 'Pro category selected'
            : 'Language selected',
        done: user.role == UserRole.pro
            ? user.preferredCategories.isNotEmpty
            : user.languageCode.trim().isNotEmpty,
        weight: 15,
      ),
    ];
  }

  int _trustScore(List<_ProfileQualityCheck> checks) {
    final totalWeight = checks.fold<int>(0, (sum, check) => sum + check.weight);
    if (totalWeight <= 0) {
      return 0;
    }
    final earned = checks
        .where((check) => check.done)
        .fold<int>(0, (sum, check) => sum + check.weight);
    return ((earned / totalWeight) * 100).round().clamp(0, 100);
  }

  String _strengthLabel(int score) {
    if (score >= 85) {
      return 'Strong';
    }
    if (score >= 60) {
      return 'Good';
    }
    return 'Needs Attention';
  }

  Color _strengthColor(int score) {
    if (score >= 85) {
      return const Color(0xFF1FA968);
    }
    if (score >= 60) {
      return const Color(0xFF2B90D9);
    }
    return AppTheme.accentOrange;
  }

  String _improvementHint(List<_ProfileQualityCheck> checks) {
    final missing = checks
        .where((check) => !check.done)
        .toList(growable: false);
    if (missing.isEmpty) {
      return 'Everything important is complete. Your account is in great shape.';
    }
    if (missing.length == 1) {
      return 'Complete "${missing.first.label}" to max out your profile strength.';
    }
    return 'Complete "${missing.first.label}" and "${missing[1].label}" to boost profile trust.';
  }

  @override
  Widget build(BuildContext context) {
    final checks = _qualityChecks(user);
    final memberSince = user.createdAt == null
        ? 'Unknown'
        : formatDateTime(user.createdAt!);
    final trust = _trustScore(checks);
    final strengthLabel = _strengthLabel(trust);
    final strengthColor = _strengthColor(trust);
    final language = user.languageCode.toLowerCase() == 'ur'
        ? 'Urdu'
        : 'English';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.verified_user_outlined,
                  color: AppTheme.brandBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  'Account Snapshot',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: strengthColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$strengthLabel | $trust%',
                    style: TextStyle(
                      color: strengthColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _SnapshotChip(
                  icon: Icons.calendar_month_outlined,
                  label: 'Member Since',
                  value: memberSince,
                ),
                _SnapshotChip(
                  icon: Icons.language_outlined,
                  label: 'Language',
                  value: language,
                ),
                _SnapshotChip(
                  icon: Icons.location_on_outlined,
                  label: 'Saved Locations',
                  value: '${user.savedLocations.length}',
                ),
                _SnapshotChip(
                  icon: Icons.rule_outlined,
                  label: 'Terms Records',
                  value: '${user.termsAcceptanceHistory.length}',
                ),
                if (user.role == UserRole.pro)
                  _SnapshotChip(
                    icon: Icons.work_outline,
                    label: 'Pro Categories',
                    value: '${user.preferredCategories.length}',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ProfileStrengthBar(value: trust / 100, color: strengthColor),
            const SizedBox(height: 8),
            Text(
              _improvementHint(checks),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4E5E73)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: checks
                  .map((check) => _ProfileQualityChip(check: check))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileQualityCheck {
  const _ProfileQualityCheck({
    required this.label,
    required this.done,
    required this.weight,
  });

  final String label;
  final bool done;
  final int weight;
}

class _ProfileStrengthBar extends StatelessWidget {
  const _ProfileStrengthBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 12,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(color: const Color(0xFFDCE9F8)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: safeValue,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[color.withValues(alpha: 0.85), color],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileQualityChip extends StatelessWidget {
  const _ProfileQualityChip({required this.check});

  final _ProfileQualityCheck check;

  @override
  Widget build(BuildContext context) {
    final bg = check.done ? const Color(0xFFEAF8F1) : const Color(0xFFF3F6FB);
    final border = check.done
        ? const Color(0xFFB8E7CF)
        : const Color(0xFFD9E2EF);
    final iconColor = check.done
        ? const Color(0xFF178C54)
        : const Color(0xFF6B7C92);
    final icon = check.done ? Icons.check_circle : Icons.radio_button_unchecked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 6),
          Text(
            check.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: check.done
                  ? const Color(0xFF26523A)
                  : const Color(0xFF41566E),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  const _SnapshotChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: AppTheme.brandBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5B6C81),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF182A43),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountForm extends StatelessWidget {
  const _AccountForm({
    required this.user,
    required this.nameController,
    required this.phoneController,
    required this.paymentController,
    required this.defaultAddressController,
    required this.saving,
    required this.googleSearchEnabled,
    required this.onPickAddress,
    required this.onSave,
  });

  final AppUser user;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController paymentController;
  final TextEditingController defaultAddressController;
  final bool saving;
  final bool googleSearchEnabled;
  final VoidCallback onPickAddress;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final username = user.username.trim();
    final usernameDisplay = username.isEmpty ? '-' : '@$username';
    final emailDisplay = user.email.trim().isEmpty ? '-' : user.email.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Profile Settings',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              t.t('profile_trust_message'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: 'Basic Information',
              icon: Icons.person_outline,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final split = constraints.maxWidth > 620;
                  if (!split) {
                    return Column(
                      children: <Widget>[
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: t.t('full_name'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: phoneController,
                          decoration: InputDecoration(labelText: t.t('phone')),
                        ),
                        const SizedBox(height: 10),
                        _ReadOnlyProfileValue(
                          label: 'Email',
                          value: emailDisplay,
                          icon: Icons.mail_outline,
                        ),
                        const SizedBox(height: 10),
                        _ReadOnlyProfileValue(
                          label: 'Username',
                          value: usernameDisplay,
                          icon: Icons.alternate_email,
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: t.t('full_name'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: phoneController,
                              decoration: InputDecoration(
                                labelText: t.t('phone'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _ReadOnlyProfileValue(
                              label: 'Email',
                              value: emailDisplay,
                              icon: Icons.mail_outline,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ReadOnlyProfileValue(
                              label: 'Username',
                              value: usernameDisplay,
                              icon: Icons.alternate_email,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _SettingsSection(
              title: 'Address Defaults',
              icon: Icons.location_on_outlined,
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: defaultAddressController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Default Address',
                      helperText: googleSearchEnabled
                          ? 'Used when posting jobs. Type manually or refine with Google search.'
                          : 'Used when posting jobs. Type your default address here.',
                      suffixIcon: googleSearchEnabled
                          ? IconButton(
                              onPressed: onPickAddress,
                              icon: const Icon(Icons.search),
                              tooltip: 'Search address',
                            )
                          : null,
                    ),
                  ),
                  if (googleSearchEnabled) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onPickAddress,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Search Address with Google'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (user.role == UserRole.pro) ...<Widget>[
              const SizedBox(height: 8),
              _SettingsSection(
                title: 'Payout Details',
                icon: Icons.payments_outlined,
                child: TextField(
                  controller: paymentController,
                  decoration: InputDecoration(
                    labelText: t.t('linked_payment_account'),
                    helperText: t.t('payment_account_helper'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _SettingsSection(
              title: t.t('profile_photo'),
              icon: Icons.photo_camera_back_outlined,
              child: Text(
                t.t('tap_profile_photo_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(t.t('save_profile_changes')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5E3F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: AppTheme.brandBlue),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ReadOnlyProfileValue extends StatelessWidget {
  const _ReadOnlyProfileValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E1ED)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: AppTheme.brandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends ConsumerWidget {
  const _ActionsCard({required this.user, required this.onChangePassword});

  final AppUser user;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Quick Actions',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                _ActionTile(
                  icon: Icons.lock_outline,
                  title: t.t('change_password'),
                  subtitle: t.t('change_password_subtitle'),
                  onTap: onChangePassword,
                ),
                _ActionTile(
                  icon: Icons.settings_outlined,
                  title: t.t('settings'),
                  subtitle: t.t('settings_subtitle'),
                  onTap: () => context.push('/settings'),
                ),
                if (user.role == UserRole.pro)
                  _ActionTile(
                    icon: Icons.payments_outlined,
                    title: t.t('earnings'),
                    subtitle: t.t('earnings_dashboard'),
                    onTap: () => context.push('/earnings'),
                  ),
                _ActionTile(
                  icon: Icons.history_outlined,
                  title: t.t('job_payment_history'),
                  subtitle: t.t('job_payment_history_subtitle'),
                  onTap: () => context.push('/history'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Security & Account',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F3FF),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: AppTheme.brandBlue,
                    ),
                  ),
                  title: Text(
                    user.role == UserRole.pro
                        ? '${t.t('verification')}: ${user.cnicVerified ? t.t('cnic_verified') : t.t('pending')}'
                        : t.t('account_trust_status'),
                  ),
                  subtitle: Text(
                    user.role == UserRole.pro
                        ? '${t.t('police_badge')}: ${user.policeVerified ? t.t('verified') : t.t('optional')}'
                        : '${t.t('terms_acceptance_records')}: ${user.termsAcceptanceHistory.length}',
                  ),
                ),
                _ActionTile(
                  icon: Icons.logout,
                  title: t.t('logout'),
                  subtitle: t.t('sign_out_subtitle'),
                  danger: true,
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final iconColor = danger ? const Color(0xFFB3261E) : AppTheme.brandBlue;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: CircleAvatar(
        backgroundColor: danger
            ? const Color(0xFFFDEDED)
            : const Color(0xFFE8F3FF),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
