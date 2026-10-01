import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/address_formatters.dart';
import '../../core/services/google_places_service.dart';
import '../../core/services/location_service.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/jobs_controller.dart';
import '../widgets/google_address_search_sheet.dart';

enum _JobAddressSource { profile, custom }

enum _JobUrgency { flexible, today, tomorrow, urgent }

class CreateJobScreen extends ConsumerStatefulWidget {
  const CreateJobScreen({super.key});

  @override
  ConsumerState<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends ConsumerState<CreateJobScreen> {
  static const String _draftStorageKey = 'create_job_draft_v2';

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _maskedAddressController = TextEditingController();
  final _exactAddressController = TextEditingController();
  final _imagePicker = ImagePicker();

  final List<String> _attachments = <String>[];

  JobCategory _category = JobCategory.electrician;
  _JobAddressSource _addressSource = _JobAddressSource.profile;
  _JobUrgency _urgency = _JobUrgency.flexible;
  bool _posting = false;
  bool _draftReady = false;
  bool _addressInitialized = false;
  int _currentStep = 0;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String _resolvedExactAddress = '';
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _maskedAddressController.dispose();
    _exactAddressController.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_draftStorageKey);
    if (raw == null || raw.trim().isEmpty || !mounted) {
      setState(() => _draftReady = true);
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _category = JobCategoryX.fromValue(
          (map['category'] ?? JobCategory.electrician.value).toString(),
        );
        _titleController.text = (map['title'] ?? '').toString();
        _descriptionController.text = (map['description'] ?? '').toString();
        _priceController.text = (map['budget'] ?? '').toString();
        _maskedAddressController.text = (map['maskedAddress'] ?? '').toString();
        _exactAddressController.text = (map['exactAddress'] ?? '').toString();
        _selectedLatitude = (map['latitude'] as num?)?.toDouble();
        _selectedLongitude = (map['longitude'] as num?)?.toDouble();
        _resolvedExactAddress = (map['resolvedExactAddress'] ?? '').toString();
        _currentStep = (map['currentStep'] as num?)?.toInt().clamp(0, 3) ?? 0;
        _urgency = _urgencyFromValue((map['urgency'] ?? 'flexible').toString());
        _addressSource = (map['addressSource'] ?? 'profile').toString() == 'custom'
            ? _JobAddressSource.custom
            : _JobAddressSource.profile;
        _attachments
          ..clear()
          ..addAll(
            (map['attachments'] as List<dynamic>? ?? const <dynamic>[])
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty),
          );
        final scheduledDateRaw = map['scheduledDate'] as String?;
        if (scheduledDateRaw != null && scheduledDateRaw.isNotEmpty) {
          _scheduledDate = DateTime.tryParse(scheduledDateRaw);
        }
        final hour = (map['scheduledHour'] as num?)?.toInt();
        final minute = (map['scheduledMinute'] as num?)?.toInt();
        if (hour != null && minute != null) {
          _scheduledTime = TimeOfDay(hour: hour, minute: minute);
        }
        _draftReady = true;
      });
    } catch (_) {
      setState(() => _draftReady = true);
    }
  }

  Future<void> _saveDraft({String message = 'Draft saved.'}) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'category': _category.value,
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'budget': _priceController.text.trim(),
      'maskedAddress': _maskedAddressController.text.trim(),
      'exactAddress': _exactAddressController.text.trim(),
      'latitude': _selectedLatitude,
      'longitude': _selectedLongitude,
      'resolvedExactAddress': _resolvedExactAddress,
      'currentStep': _currentStep,
      'urgency': _urgency.value,
      'addressSource': _addressSource == _JobAddressSource.custom
          ? 'custom'
          : 'profile',
      'attachments': _attachments,
      'scheduledDate': _scheduledDate?.toIso8601String(),
      'scheduledHour': _scheduledTime?.hour,
      'scheduledMinute': _scheduledTime?.minute,
    };
    await preferences.setString(_draftStorageKey, jsonEncode(payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_draftStorageKey);
  }

  SavedLocation? _latestSavedLocation(AppUser user) {
    if (user.savedLocations.isEmpty) {
      return null;
    }
    return user.savedLocations.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
  }

  void _prefillFromProfileAddress(SavedLocation location) {
    _selectedLatitude = location.latitude;
    _selectedLongitude = location.longitude;
    _exactAddressController.text = location.address;
    _resolvedExactAddress = location.address;
    if (_maskedAddressController.text.trim().isEmpty) {
      _maskedAddressController.text = deriveMaskedAddress(location.address);
    }
  }

  String _normalizeAddress(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  Future<void> _searchCustomAddress() async {
    final selected = await showGoogleAddressSearchSheet(
      context,
      initialQuery: _exactAddressController.text,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _selectedLatitude = selected.latitude;
      _selectedLongitude = selected.longitude;
      _exactAddressController.text = selected.formattedAddress;
      _resolvedExactAddress = selected.formattedAddress;
      if (_maskedAddressController.text.trim().isEmpty) {
        _maskedAddressController.text = deriveMaskedAddress(
          selected.formattedAddress,
        );
      }
    });
  }

  Future<bool> _resolveCoordinatesFromAddress() async {
    final exactAddress = _exactAddressController.text.trim();
    if (_selectedLatitude != null && _selectedLongitude != null) {
      return true;
    }
    if (exactAddress.isEmpty) {
      return false;
    }

    final places = ref.read(googlePlacesServiceProvider);
    GooglePlaceDetails? resolved;
    try {
      resolved = await places.geocodeAddress(exactAddress);
    } catch (_) {
      resolved = null;
    }

    if (resolved != null) {
      _selectedLatitude = resolved.latitude;
      _selectedLongitude = resolved.longitude;
      _exactAddressController.text = resolved.formattedAddress;
      _resolvedExactAddress = resolved.formattedAddress;
      if (_maskedAddressController.text.trim().isEmpty) {
        _maskedAddressController.text = deriveMaskedAddress(
          resolved.formattedAddress,
        );
      }
      return true;
    }

    final locationResult = await ref.read(locationServiceProvider).getCurrentPosition(
          aggressive: true,
          requestPermissionIfNeeded: true,
        );
    final position = locationResult.position;
    if (position == null) {
      return false;
    }
    _selectedLatitude = position.latitude;
    _selectedLongitude = position.longitude;
    _resolvedExactAddress = exactAddress;
    if (_maskedAddressController.text.trim().isEmpty) {
      _maskedAddressController.text = deriveMaskedAddress(exactAddress);
    }
    return true;
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

  Future<void> _pickAttachment(ImageSource source) async {
    if (_attachments.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 photos only.')),
      );
      return;
    }

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
                ? 'Gallery permission is required.'
                : 'Camera permission is required.',
          ),
        ),
      );
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 72,
        maxWidth: 1280,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _attachments.add('data:image/jpeg;base64,${base64Encode(bytes)}');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showImageSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Upload from gallery'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAttachment(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take picture'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAttachment(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _scheduledDate = picked);
  }

  Future<void> _pickScheduleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _scheduledTime = picked);
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty) {
        _showValidationMessage('Please add a job title.');
        return false;
      }
      if (_descriptionController.text.trim().isEmpty) {
        _showValidationMessage('Please describe the job in more detail.');
        return false;
      }
    }

    if (_currentStep == 1) {
      if (_exactAddressController.text.trim().isEmpty) {
        _showValidationMessage('Please enter the job address.');
        return false;
      }
    }

    return true;
  }

  void _showValidationMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _goNext() async {
    if (!_validateCurrentStep()) {
      return;
    }
    if (_currentStep == 3) {
      await _submit();
      return;
    }
    setState(() => _currentStep += 1);
  }

  void _goBack() {
    if (_currentStep == 0) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
      return;
    }
    setState(() => _currentStep -= 1);
  }

  String _scheduleSummary() {
    if (_scheduledDate == null && _scheduledTime == null) {
      return 'No preferred schedule selected';
    }
    final date = _scheduledDate == null
        ? 'No date'
        : '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}';
    final time = _scheduledTime == null
        ? 'Any time'
        : _scheduledTime!.format(context);
    return '$date, $time';
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }

    final profileLocation = _latestSavedLocation(user);
    var latitude = _selectedLatitude;
    var longitude = _selectedLongitude;
    if (_addressSource == _JobAddressSource.profile && profileLocation != null) {
      latitude = profileLocation.latitude;
      longitude = profileLocation.longitude;
      if (_exactAddressController.text.trim().isEmpty) {
        _exactAddressController.text = profileLocation.address;
      }
      if (_maskedAddressController.text.trim().isEmpty) {
        _maskedAddressController.text = deriveMaskedAddress(profileLocation.address);
      }
    }

    if (latitude == null || longitude == null) {
      final resolved = await _resolveCoordinatesFromAddress();
      if (resolved) {
        latitude = _selectedLatitude;
        longitude = _selectedLongitude;
      }
    }

    if (latitude == null || longitude == null) {
      if (profileLocation != null) {
        latitude = profileLocation.latitude;
        longitude = profileLocation.longitude;
      } else {
        latitude = 0;
        longitude = 0;
      }
    }

    final exactAddressInput = _exactAddressController.text.trim();
    final maskedAddressInput = _maskedAddressController.text.trim();
    final exactAddress = exactAddressInput.isEmpty
        ? (maskedAddressInput.isEmpty
              ? 'Address shared after booking.'
              : maskedAddressInput)
        : exactAddressInput;
    final maskedAddress = maskedAddressInput.isEmpty
        ? deriveMaskedAddress(exactAddress)
        : maskedAddressInput;

    final amount = _effectiveBudget();
    final enrichedDescription = _buildFinalDescription();

    setState(() => _posting = true);
    try {
      await ref.read(jobsControllerProvider).postJob(
            JobPostInput(
              customerId: user.id,
              category: _category,
              title: _titleController.text.trim(),
              description: enrichedDescription,
              fixedPrice: amount,
              latitude: latitude,
              longitude: longitude,
              maskedAddress: maskedAddress,
              exactAddress: exactAddress,
              imageAttachments: _attachments,
            ),
          );
      await _clearDraft();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job posted successfully.')),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  String _buildFinalDescription() {
    final base = _descriptionController.text.trim();
    final extra = <String>[
      'Urgency: ${_urgency.label}',
      'Preferred schedule: ${_scheduleSummary()}',
    ];
    return '$base\n\n${extra.join('\n')}';
  }

  double _effectiveBudget() {
    final parsed = double.tryParse(_priceController.text.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    return switch (_category) {
      JobCategory.electrician => 1500,
      JobCategory.plumbing => 1200,
      JobCategory.cleaning => 1800,
      JobCategory.applianceRepair => 1400,
      JobCategory.acRepair => 2000,
      JobCategory.carpenter => 1600,
      JobCategory.painter => 2200,
      JobCategory.registeredNurse => 2500,
    };
  }

  Future<void> _showMoreCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: JobCategory.values.map((category) {
              return ListTile(
                leading: Icon(
                  _categoryIcon(category),
                  color: _categoryColor(category),
                ),
                title: Text(category.displayName),
                onTap: () {
                  setState(() => _category = category);
                  Navigator.of(context).pop();
                },
              );
            }).toList(growable: false),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final googleSearchEnabled = ref.watch(googlePlacesServiceProvider).isConfigured;
    if (user == null) {
      return Scaffold(body: Center(child: Text(t.t('not_authenticated'))));
    }

    final profileLocation = _latestSavedLocation(user);
    if (!_addressInitialized && _draftReady) {
      _addressInitialized = true;
      if (_exactAddressController.text.trim().isNotEmpty) {
        _addressSource = _exactAddressController.text.trim().isNotEmpty &&
                _resolvedExactAddress.trim().isNotEmpty
            ? _addressSource
            : _JobAddressSource.custom;
      } else if (profileLocation != null) {
        _addressSource = _JobAddressSource.profile;
        _prefillFromProfileAddress(profileLocation);
      } else {
        _addressSource = _JobAddressSource.custom;
      }
    }

    if (!_draftReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final steps = <String>[
      'Job Details',
      'Location',
      'Schedule',
      'Review & Post',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _TopIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: _goBack,
                      ),
                      const Spacer(),
                      Text(
                        'Post a Job',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFF1E2058),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const Spacer(),
                      _TopTextButton(
                        icon: Icons.bookmarks_outlined,
                        label: 'Save Draft',
                        onTap: () => _saveDraft(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _StepProgress(
                    currentStep: _currentStep,
                    steps: steps,
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildCurrentStep(
                      context: context,
                      googleSearchEnabled: googleSearchEnabled,
                      profileLocation: profileLocation,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[Color(0xFF6C4CF7), Color(0xFF8B63FF)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x226B4CF7),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _posting ? null : _goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(62),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: _posting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(_currentStep == 3
                                ? Icons.publish_rounded
                                : Icons.arrow_forward_rounded),
                        label: Text(
                          _posting
                              ? 'Posting job...'
                              : _currentStep == 0
                                  ? 'Continue to Location'
                                  : _currentStep == 1
                                      ? 'Continue to Schedule'
                                      : _currentStep == 2
                                          ? 'Continue to Review'
                                          : 'Review & Post Job',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep({
    required BuildContext context,
    required bool googleSearchEnabled,
    required SavedLocation? profileLocation,
  }) {
    return switch (_currentStep) {
      0 => _buildJobDetailsStep(context),
      1 => _buildLocationStep(
          context: context,
          googleSearchEnabled: googleSearchEnabled,
          profileLocation: profileLocation,
        ),
      2 => _buildScheduleStep(context),
      _ => _buildReviewStep(context),
    };
  }

  Widget _buildJobDetailsStep(BuildContext context) {
    return Column(
      key: const ValueKey<String>('job-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'What do you\nneed help with?',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          height: 1.06,
                          color: const Color(0xFF171952),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tell us about your job and we’ll match you with the best pros.',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      color: Color(0xFF747191),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: Container(
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFF5F1FF), Color(0xFFF8F6FF)],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    const Positioned(
                      right: 18,
                      top: 18,
                      child: Icon(
                        Icons.assignment_rounded,
                        size: 112,
                        color: Color(0x33A185FF),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      bottom: 18,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE4FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.build_circle_outlined,
                          color: Color(0xFF7E5DFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const _StepSectionTitle(
          index: 1,
          title: 'Select a Category',
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _jobCategoriesForWizard.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = _jobCategoriesForWizard[index];
              return SizedBox(
                width: 148,
              child: _CategoryWizardCard(
                  item: item,
                  selected: item.isMore ? false : _category == item.category,
                  onTap: () {
                    if (item.isMore) {
                      _showMoreCategories();
                      return;
                    }
                    setState(() => _category = item.category);
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        const _StepSectionTitle(
          index: 2,
          title: 'Describe Your Job',
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Job Title',
          trailing: Text(
            '${_titleController.text.trim().length}/60',
            style: const TextStyle(color: Color(0xFF8E89A8)),
          ),
          child: TextField(
            controller: _titleController,
            maxLength: 60,
            buildCounter: (
              context, {
              required currentLength,
              required isFocused,
              maxLength,
            }) => null,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'e.g. Fix bathroom sink leakage',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Detailed Description',
          trailing: Text(
            '${_descriptionController.text.trim().length}/500',
            style: const TextStyle(color: Color(0xFF8E89A8)),
          ),
          child: TextField(
            controller: _descriptionController,
            minLines: 5,
            maxLines: 7,
            maxLength: 500,
            buildCounter: (
              context, {
              required currentLength,
              required isFocused,
              maxLength,
            }) => null,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'Please provide more details about the issue or work you need done...',
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Add Photos (Optional)',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1B1D55),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add photos to help pros understand the job better',
                    style: TextStyle(
                      color: Color(0xFF7B7793),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_attachments.length}/5',
              style: const TextStyle(
                color: Color(0xFF7B5CFF),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: Row(
            children: List<Widget>.generate(5, (index) {
              final hasPhoto = index < _attachments.length;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 4 ? 0 : 12),
                  child: hasPhoto
                      ? _PhotoPreviewCard(
                          encoded: _attachments[index],
                          onRemove: () => setState(() => _attachments.removeAt(index)),
                        )
                      : _PhotoEmptyCard(
                          primary: index == _attachments.length,
                          onTap: _showImageSourceSheet,
                        ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),
        const _StepSectionTitle(
          index: 3,
          title: 'Choose Additional Options',
        ),
        const SizedBox(height: 14),
        _OptionCard(
          icon: Icons.verified_outlined,
          iconColor: const Color(0xFF7B5CFF),
          iconBackground: const Color(0xFFF0EAFF),
          title: 'Set a Budget (Optional)',
          subtitle: 'Help pros give you accurate quotes',
          trailing: SizedBox(
            width: 140,
            child: TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: 'Add Budget',
                prefixText: 'Rs ',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          icon: Icons.access_time_rounded,
          iconColor: const Color(0xFF4DAE5C),
          iconBackground: const Color(0xFFEAF6E8),
          title: 'Add Job Urgency',
          subtitle: 'Let pros know how urgent this is',
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<_JobUrgency>(
              value: _urgency,
              items: _JobUrgency.values
                  .map(
                    (item) => DropdownMenuItem<_JobUrgency>(
                      value: item,
                      child: Text(item.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _urgency = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep({
    required BuildContext context,
    required bool googleSearchEnabled,
    required SavedLocation? profileLocation,
  }) {
    return Column(
      key: const ValueKey<String>('location'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Where should the job happen?',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                height: 1.08,
                color: const Color(0xFF171952),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose your saved address or enter a custom location for this request.',
          style: TextStyle(
            color: Color(0xFF747191),
            fontSize: 17,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        _LocationChoiceCard(
          title: 'Use profile default address',
          subtitle: profileLocation?.address ?? 'No saved profile address yet.',
          selected: _addressSource == _JobAddressSource.profile,
          enabled: profileLocation != null,
          icon: Icons.home_work_outlined,
          onTap: profileLocation == null
              ? null
              : () {
                  setState(() {
                    _addressSource = _JobAddressSource.profile;
                    _prefillFromProfileAddress(profileLocation);
                  });
                },
        ),
        const SizedBox(height: 14),
        _LocationChoiceCard(
          title: 'Use a custom address',
          subtitle: googleSearchEnabled
              ? 'Type it yourself or refine it with Google search.'
              : 'Type the address manually for this job.',
          selected: _addressSource == _JobAddressSource.custom,
          enabled: true,
          icon: Icons.location_on_outlined,
          onTap: () {
            setState(() {
              _addressSource = _JobAddressSource.custom;
              _selectedLatitude = null;
              _selectedLongitude = null;
              _resolvedExactAddress = '';
            });
          },
        ),
        const SizedBox(height: 20),
        _LabeledField(
          label: 'Public Area Address',
          child: TextField(
            controller: _maskedAddressController,
            decoration: const InputDecoration(
              hintText: 'e.g. DHA Phase 5, Lahore',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Exact Address',
          child: TextField(
            controller: _exactAddressController,
            readOnly: _addressSource == _JobAddressSource.profile,
            minLines: 2,
            maxLines: 3,
            onChanged: (_) {
              if (_addressSource == _JobAddressSource.custom &&
                  _normalizeAddress(_exactAddressController.text) !=
                      _normalizeAddress(_resolvedExactAddress) &&
                  (_selectedLatitude != null || _selectedLongitude != null)) {
                setState(() {
                  _selectedLatitude = null;
                  _selectedLongitude = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: _addressSource == _JobAddressSource.profile
                  ? 'Using your saved address'
                  : 'House number, street, area, city',
            ),
          ),
        ),
        if (_addressSource == _JobAddressSource.custom && googleSearchEnabled) ...<Widget>[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _searchCustomAddress,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search address with Google'),
            ),
          ),
        ],
        if (_selectedLatitude != null && _selectedLongitude != null) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F0FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Location pinned at ${_selectedLatitude!.toStringAsFixed(5)}, ${_selectedLongitude!.toStringAsFixed(5)}',
              style: const TextStyle(
                color: Color(0xFF6D5DE8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleStep(BuildContext context) {
    return Column(
      key: const ValueKey<String>('schedule'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'When do you need it done?',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                height: 1.08,
                color: const Color(0xFF171952),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Add urgency and an optional preferred date and time so pros can plan better.',
          style: TextStyle(
            color: Color(0xFF747191),
            fontSize: 17,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Job Urgency',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1B1D55),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _JobUrgency.values.map((item) {
            return _UrgencyCard(
              urgency: item,
              selected: _urgency == item,
              onTap: () => setState(() => _urgency = item),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            Expanded(
              child: _ScheduleActionCard(
                icon: Icons.calendar_today_outlined,
                title: 'Preferred Date',
                subtitle: _scheduledDate == null
                    ? 'Select date'
                    : '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}',
                onTap: _pickScheduleDate,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ScheduleActionCard(
                icon: Icons.schedule_rounded,
                title: 'Preferred Time',
                subtitle: _scheduledTime == null
                    ? 'Any time'
                    : _scheduledTime!.format(context),
                onTap: _pickScheduleTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    return Column(
      key: const ValueKey<String>('review'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Review your job post',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                height: 1.08,
                color: const Color(0xFF171952),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Check the details below before publishing your request.',
          style: TextStyle(
            color: Color(0xFF747191),
            fontSize: 17,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        _ReviewCard(
          title: 'Category',
          value: _category.displayName,
          icon: _categoryIcon(_category),
          accent: _categoryColor(_category),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Job title',
          value: _titleController.text.trim().isEmpty
              ? '-'
              : _titleController.text.trim(),
          icon: Icons.edit_note_rounded,
          accent: const Color(0xFF7B5CFF),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Description',
          value: _descriptionController.text.trim().isEmpty
              ? '-'
              : _descriptionController.text.trim(),
          icon: Icons.notes_rounded,
          accent: const Color(0xFF6B7A99),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Budget',
          value: _priceController.text.trim().isEmpty
              ? 'Not set manually, using recommended ${_effectiveBudget().toStringAsFixed(0)}'
              : 'Rs ${_priceController.text.trim()}',
          icon: Icons.payments_outlined,
          accent: const Color(0xFF44A96B),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Address',
          value: _exactAddressController.text.trim().isEmpty
              ? 'Not set'
              : _exactAddressController.text.trim(),
          icon: Icons.location_on_outlined,
          accent: const Color(0xFFF08A30),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Urgency & schedule',
          value: '${_urgency.label}\n${_scheduleSummary()}',
          icon: Icons.access_time_rounded,
          accent: const Color(0xFF5FAD67),
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Photos',
          value: _attachments.isEmpty
                ? 'No photos added'
                : '${_attachments.length} photo(s) attached',
          icon: Icons.photo_camera_back_outlined,
          accent: const Color(0xFF8B63FF),
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: const Color(0xFF25245A)),
      ),
    );
  }
}

class _TopTextButton extends StatelessWidget {
  const _TopTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: const Color(0xFF4A4A73)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2D2D5F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.currentStep,
    required this.steps,
  });

  final int currentStep;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(steps.length, (index) {
        final selected = index == currentStep;
        final completed = index < currentStep;
        return Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected || completed
                            ? const Color(0xFF7B5CFF)
                            : const Color(0xFFEFEDFA),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: selected || completed
                              ? Colors.white
                              : const Color(0xFF5E5C78),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      steps[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF7B5CFF)
                            : const Color(0xFF7E7A98),
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != steps.length - 1)
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 32),
                    child: Divider(
                      color: Color(0xFFD9D4F2),
                      thickness: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _StepSectionTitle extends StatelessWidget {
  const _StepSectionTitle({
    required this.index,
    required this.title,
  });

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$index. $title',
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: Color(0xFF1A1C54),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF49496E),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CategoryWizardCard extends StatelessWidget {
  const _CategoryWizardCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _WizardCategoryItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? const Color(0xFF8B63FF) : const Color(0xFFEAE6F7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: <Widget>[
            if (selected)
              const Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xFF8B63FF),
                  child: Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 8),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: item.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(item.icon, color: item.accent, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: Color(0xFF1E2057),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF7C7894),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreviewCard extends StatelessWidget {
  const _PhotoPreviewCard({
    required this.encoded,
    required this.onRemove,
  });

  final String encoded;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              base64Decode(encoded.split(',').last),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoEmptyCard extends StatelessWidget {
  const _PhotoEmptyCard({
    required this.primary,
    required this.onTap,
  });

  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: primary ? const Color(0xFFC8B5FF) : const Color(0xFFE8E5F4),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              primary ? Icons.camera_alt_rounded : Icons.add_photo_alternate_outlined,
              color: primary ? const Color(0xFF7B5CFF) : const Color(0xFFC7C4D8),
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              primary ? 'Upload Photo' : '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primary ? const Color(0xFF7B5CFF) : const Color(0xFFB8B4CA),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1C1E55),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF7C7894),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(width: 180, child: trailing),
        ],
      ),
    );
  }
}

class _LocationChoiceCard extends StatelessWidget {
  const _LocationChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF6F5FA),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF8B63FF) : const Color(0xFFE7E3F3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAFF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: const Color(0xFF7B5CFF)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFF1B1D55)
                          : const Color(0xFF9C98B0),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFF7C7894)
                          : const Color(0xFFB8B4C8),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFF8B63FF) : const Color(0xFFC5C1D3),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrgencyCard extends StatelessWidget {
  const _UrgencyCard({
    required this.urgency,
    required this.selected,
    required this.onTap,
  });

  final _JobUrgency urgency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0EAFF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF8B63FF) : const Color(0xFFE7E3F3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(urgency.icon, color: urgency.color),
            const SizedBox(height: 10),
            Text(
              urgency.label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1D56),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              urgency.helper,
              style: const TextStyle(
                color: Color(0xFF7C7894),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleActionCard extends StatelessWidget {
  const _ScheduleActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF7B5CFF)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF1C1D56),
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF7C7894),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF7C7894),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1B1D55),
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WizardCategoryItem {
  const _WizardCategoryItem({
    required this.category,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.isMore = false,
  });

  final JobCategory category;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool isMore;
}

const List<_WizardCategoryItem> _jobCategoriesForWizard = <_WizardCategoryItem>[
  _WizardCategoryItem(
    category: JobCategory.electrician,
    label: 'Electrical',
    subtitle: 'Wiring, lights, switches & more',
    icon: Icons.bolt_rounded,
    accent: Color(0xFF7B5CFF),
  ),
  _WizardCategoryItem(
    category: JobCategory.plumbing,
    label: 'Plumbing',
    subtitle: 'Leak, pipes, faucets & more',
    icon: Icons.plumbing_rounded,
    accent: Color(0xFF2E7AF0),
  ),
  _WizardCategoryItem(
    category: JobCategory.cleaning,
    label: 'Cleaning',
    subtitle: 'Home, kitchen, bathroom & more',
    icon: Icons.cleaning_services_rounded,
    accent: Color(0xFFF38C34),
  ),
  _WizardCategoryItem(
    category: JobCategory.applianceRepair,
    label: 'Appliances',
    subtitle: 'Repair & installation',
    icon: Icons.local_laundry_service_outlined,
    accent: Color(0xFF56B05E),
  ),
  _WizardCategoryItem(
    category: JobCategory.carpenter,
    label: 'More',
    subtitle: 'View all categories',
    icon: Icons.grid_view_rounded,
    accent: Color(0xFFA6A3C8),
    isMore: true,
  ),
];

extension on _JobUrgency {
  String get value => switch (this) {
        _JobUrgency.flexible => 'flexible',
        _JobUrgency.today => 'today',
        _JobUrgency.tomorrow => 'tomorrow',
        _JobUrgency.urgent => 'urgent',
      };

  String get label => switch (this) {
        _JobUrgency.flexible => 'Flexible',
        _JobUrgency.today => 'Today',
        _JobUrgency.tomorrow => 'Tomorrow',
        _JobUrgency.urgent => 'Urgent',
      };

  String get helper => switch (this) {
        _JobUrgency.flexible => 'Can be scheduled anytime',
        _JobUrgency.today => 'Need someone today',
        _JobUrgency.tomorrow => 'Tomorrow works best',
        _JobUrgency.urgent => 'Immediate attention needed',
      };

  IconData get icon => switch (this) {
        _JobUrgency.flexible => Icons.event_available_outlined,
        _JobUrgency.today => Icons.today_outlined,
        _JobUrgency.tomorrow => Icons.event_outlined,
        _JobUrgency.urgent => Icons.warning_amber_rounded,
      };

  Color get color => switch (this) {
        _JobUrgency.flexible => const Color(0xFF5C7CFA),
        _JobUrgency.today => const Color(0xFF43A047),
        _JobUrgency.tomorrow => const Color(0xFFF59E0B),
        _JobUrgency.urgent => const Color(0xFFE85D5D),
      };
}

_JobUrgency _urgencyFromValue(String value) {
  return switch (value.trim().toLowerCase()) {
    'today' => _JobUrgency.today,
    'tomorrow' => _JobUrgency.tomorrow,
    'urgent' => _JobUrgency.urgent,
    _ => _JobUrgency.flexible,
  };
}

IconData _categoryIcon(JobCategory category) {
  return switch (category) {
    JobCategory.plumbing => Icons.plumbing_rounded,
    JobCategory.electrician => Icons.bolt_rounded,
    JobCategory.acRepair => Icons.ac_unit_rounded,
    JobCategory.carpenter => Icons.carpenter_rounded,
    JobCategory.painter => Icons.format_paint_rounded,
    JobCategory.cleaning => Icons.cleaning_services_rounded,
    JobCategory.applianceRepair => Icons.local_laundry_service_outlined,
    JobCategory.registeredNurse => Icons.medical_services_outlined,
  };
}

Color _categoryColor(JobCategory category) {
  return switch (category) {
    JobCategory.plumbing => const Color(0xFF2E7AF0),
    JobCategory.electrician => const Color(0xFF7B5CFF),
    JobCategory.acRepair => const Color(0xFF56B05E),
    JobCategory.carpenter => const Color(0xFFB97A41),
    JobCategory.painter => const Color(0xFFE05C74),
    JobCategory.cleaning => const Color(0xFFF38C34),
    JobCategory.applianceRepair => const Color(0xFF56B05E),
    JobCategory.registeredNurse => const Color(0xFF2FA6A0),
  };
}
