import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/address_formatters.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/services/formatters.dart';
import '../../core/services/job_timer_utils.dart';
import '../../core/services/local_notification_service.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/jobs_controller.dart';
import '../controllers/payments_controller.dart';
import '../widgets/work_timer_badge.dart';
import '../widgets/google_address_search_sheet.dart';

enum _BidSortOption {
  priceLowToHigh,
  priceHighToLow,
  ratingHighToLow,
  worksDoneHighToLow,
}

extension _BidSortOptionX on _BidSortOption {
  String get label {
    return switch (this) {
      _BidSortOption.priceLowToHigh => 'Price: Low to High',
      _BidSortOption.priceHighToLow => 'Price: High to Low',
      _BidSortOption.ratingHighToLow => 'Ratings',
      _BidSortOption.worksDoneHighToLow => 'Works Done',
    };
  }
}

List<String> _jobImageAttachments(Job job) {
  for (final event in job.timeline) {
    final raw = event.metadata['image_attachments'];
    if (raw is List) {
      return raw
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
  }
  return const <String>[];
}

class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.jobId, this.initialJob});

  final String jobId;
  final Job? initialJob;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  final _bidController = TextEditingController();
  final _cancelReasonController = TextEditingController();
  final _disputeReasonController = TextEditingController();
  PaymentMethod _method = PaymentMethod.jazzCash;
  bool _processing = false;
  String? _syncedBidId;
  double? _syncedBidAmount;
  _BidSortOption _bidSortOption = _BidSortOption.priceLowToHigh;

  @override
  void dispose() {
    _bidController.dispose();
    _cancelReasonController.dispose();
    _disputeReasonController.dispose();
    super.dispose();
  }

  Future<void> _submitBid(Job job, AppUser user) async {
    final t = AppLocalizations.of(context);
    if (!user.preferredCategories.contains(job.category)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('bid_not_eligible'))));
      return;
    }
    final financial = ref.read(proFinancialStatusProvider);
    if (financial?.isLocked ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
          ),
        ),
      );
      return;
    }
    final amount =
        double.tryParse(_bidController.text.trim()) ?? job.fixedPrice;
    setState(() => _processing = true);
    try {
      final bid = await ref
          .read(jobsControllerProvider)
          .submitBid(BidInput(jobId: job.id, proId: user.id, amount: amount));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('bid_submitted'))));
      _bidController.text = bid.amount % 1 == 0
          ? bid.amount.toStringAsFixed(0)
          : bid.amount.toString();
      _syncedBidId = bid.id;
      _syncedBidAmount = bid.amount;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  void _syncBidEditor({
    required AppUser user,
    required AsyncValue<List<Bid>> bidsAsync,
  }) {
    if (user.role != UserRole.pro) {
      return;
    }
    final bids = bidsAsync.valueOrNull;
    if (bids == null) {
      return;
    }
    final mine =
        bids.where((bid) => bid.proId == user.id).toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mine.isEmpty) {
      if (_syncedBidId != null || _bidController.text.isNotEmpty) {
        _bidController.clear();
        _syncedBidId = null;
        _syncedBidAmount = null;
      }
      return;
    }
    final latest = mine.first;
    if (_syncedBidId == latest.id && _syncedBidAmount == latest.amount) {
      return;
    }
    _bidController.text = latest.amount % 1 == 0
        ? latest.amount.toStringAsFixed(0)
        : latest.amount.toString();
    _syncedBidId = latest.id;
    _syncedBidAmount = latest.amount;
  }

  Future<void> _requestCompletion(Job job, AppUser user) async {
    setState(() => _processing = true);
    try {
      await ref
          .read(jobsControllerProvider)
          .requestCompletion(jobId: job.id, proId: user.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completion request sent to customer.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<bool?> _askCustomerSatisfaction() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Are you satisfied?'),
          content: const Text(
            'Please confirm your satisfaction before rating this worker.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  Future<double?> _askCustomerRating({required int initialRating}) {
    var selected = initialRating.clamp(1, 5);
    return showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setStateDialog) {
            return AlertDialog(
              title: const Text('Rate this completed work'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('How many stars would you like to give?'),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: List<Widget>.generate(5, (index) {
                      final value = index + 1;
                      final selectedIcon = value <= selected;
                      return IconButton(
                        onPressed: () => setStateDialog(() => selected = value),
                        icon: Icon(
                          selectedIcon
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: selectedIcon
                              ? const Color(0xFFFFB300)
                              : Colors.grey,
                        ),
                      );
                    }),
                  ),
                  Text(
                    '$selected / 5',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selected.toDouble()),
                  child: const Text('Submit Rating'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _approveCompletionRequest(Job job, AppUser user) async {
    final satisfied = await _askCustomerSatisfaction();
    if (satisfied == null) {
      return;
    }
    final rating = await _askCustomerRating(initialRating: satisfied ? 5 : 2);
    if (rating == null) {
      return;
    }

    setState(() => _processing = true);
    try {
      await ref
          .read(jobsControllerProvider)
          .respondToCompletion(
            jobId: job.id,
            customerId: user.id,
            approved: true,
            rating: rating,
          );
      await ref
          .read(localNotificationServiceProvider)
          .cancelWorkTimerNotification(job.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job marked completed and worker rating submitted.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _rejectCompletionRequest(Job job, AppUser user) async {
    setState(() => _processing = true);
    try {
      await ref
          .read(jobsControllerProvider)
          .respondToCompletion(
            jobId: job.id,
            customerId: user.id,
            approved: false,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worker notified that the job is not completed yet.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _startWork(Job job, AppUser user) async {
    setState(() => _processing = true);
    try {
      await ref
          .read(jobsControllerProvider)
          .startWork(jobId: job.id, actorId: user.id);
      final notifications = ref.read(localNotificationServiceProvider);
      final allowed = await notifications.requestPermission();
      if (allowed) {
        await notifications.showWorkTimerNotification(
          jobId: job.id,
          title: job.title,
          startedAt: DateTime.now(),
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Work timer started.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _pay(Job job, AppUser user) async {
    final t = AppLocalizations.of(context);
    final amount = job.finalAmount ?? job.fixedPrice;
    setState(() => _processing = true);
    try {
      await ref
          .read(paymentsControllerProvider)
          .record(
            PaymentRequest(
              jobId: job.id,
              customerId: user.id,
              proId: job.assignedProId!,
              amount: amount,
              method: _method,
              externalReference: _method == PaymentMethod.cash
                  ? 'cash-entry'
                  : 'online-simulated-${DateTime.now().millisecondsSinceEpoch}',
            ),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.t('payment_recorded_closed'))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _showEditJobDialog(Job job, AppUser user) async {
    final rootContext = context;
    final titleController = TextEditingController(text: job.title);
    final descriptionController = TextEditingController(text: job.description);
    final priceController = TextEditingController(
      text: job.fixedPrice % 1 == 0
          ? job.fixedPrice.toStringAsFixed(0)
          : job.fixedPrice.toString(),
    );
    final maskedAddressController = TextEditingController(
      text: job.maskedAddress,
    );
    final exactAddressController = TextEditingController(
      text: job.exactAddress,
    );
    var latitude = job.latitude;
    var longitude = job.longitude;
    var saving = false;

    try {
      await showDialog<void>(
        context: rootContext,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (_, setStateDialog) {
              Future<void> selectAddressWithGoogle() async {
                final selected = await showGoogleAddressSearchSheet(
                  rootContext,
                  initialQuery: exactAddressController.text,
                );
                if (selected == null) {
                  return;
                }
                if (!dialogContext.mounted) {
                  return;
                }
                setStateDialog(() {
                  exactAddressController.text = selected.formattedAddress;
                  latitude = selected.latitude;
                  longitude = selected.longitude;
                  if (maskedAddressController.text.trim().isEmpty) {
                    maskedAddressController.text = deriveMaskedAddress(
                      selected.formattedAddress,
                    );
                  }
                });
              }

              Future<void> submit() async {
                final title = titleController.text.trim();
                final description = descriptionController.text.trim();
                final maskedAddress = maskedAddressController.text.trim();
                final exactAddress = exactAddressController.text.trim();
                final fixedPrice = double.tryParse(priceController.text.trim());

                if (title.isEmpty ||
                    description.isEmpty ||
                    maskedAddress.isEmpty ||
                    exactAddress.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('All fields are required.')),
                  );
                  return;
                }
                if (fixedPrice == null || fixedPrice <= 0) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Enter a valid price.')),
                  );
                  return;
                }

                if (!dialogContext.mounted) {
                  return;
                }
                setStateDialog(() => saving = true);
                try {
                  await ref
                      .read(jobsControllerProvider)
                      .updateJobDetails(
                        JobUpdateInput(
                          jobId: job.id,
                          actorId: user.id,
                          title: title,
                          description: description,
                          fixedPrice: fixedPrice,
                          latitude: latitude,
                          longitude: longitude,
                          maskedAddress: maskedAddress,
                          exactAddress: exactAddress,
                        ),
                      );
                  if (!mounted) {
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (rootContext.mounted) {
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(content: Text('Job details updated.')),
                    );
                  }
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  if (rootContext.mounted) {
                    ScaffoldMessenger.of(
                      rootContext,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setStateDialog(() => saving = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Edit Job Details'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Fixed Price (PKR)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: maskedAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Public Area Address',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: exactAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Exact Address',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : selectAddressWithGoogle,
                          icon: const Icon(Icons.search),
                          label: const Text('Search on Google Maps'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Lat/Lng: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: saving ? null : submit,
                    child: saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      maskedAddressController.dispose();
      exactAddressController.dispose();
    }
  }

  Widget _buildJobContent({
    required AppLocalizations t,
    required AppUser user,
    required Job job,
    required AsyncValue<List<Bid>> bidsAsync,
    required ProFinancialStatus? financial,
    required Map<String, AppUser> usersById,
    required Map<String, int> completedJobsByPro,
  }) {
    final visibleAddress = job.visibleAddressFor(user.id);
    final imageAttachments = _jobImageAttachments(job);
    final amount = job.finalAmount ?? job.fixedPrice;
    final paymentPreview = ref
        .read(paymentsControllerProvider)
        .calculate(amount, category: job.category);
    final postedBy = usersById[job.customerId]?.fullName ?? job.customerId;
    final assignedProName = job.assignedProId == null
        ? null
        : usersById[job.assignedProId!]?.fullName ?? job.assignedProId!;
    final canEditDetails =
        user.id == job.customerId &&
        (job.status == JobStatus.available || job.status == JobStatus.posted);
    final startedAt = workStartedAt(job);
    final stoppedAt = workStoppedAt(job);

    final canChat =
        job.assignedProId != null &&
        (user.id == job.customerId || user.id == job.assignedProId) &&
        job.status.allowsChat;
    final peerId = user.id == job.customerId
        ? job.assignedProId
        : job.customerId;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(job.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(job.description),
                if (imageAttachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 106,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: imageAttachments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final encoded = imageAttachments[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            base64Decode(encoded.split(',').last),
                            width: 106,
                            height: 106,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(label: Text(t.categoryLabel(job.category.value))),
                    Chip(
                      label: Text(
                        '${t.t('status')}: ${t.jobStatusLabel(job.status.value)}',
                      ),
                    ),
                    Chip(label: Text('${t.t('price')}: ${formatPkr(amount)}')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Posted by: $postedBy'),
                if (assignedProName != null)
                  Text('Assigned pro: $assignedProName'),
                if (assignedProName != null && user.id == job.customerId)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(
                        '/pro/${job.assignedProId}',
                        extra: job.assignedProId == null
                            ? null
                            : usersById[job.assignedProId!],
                      ),
                      child: const Text('View profile'),
                    ),
                  ),
                const SizedBox(height: 6),
                Text('${t.t('address')}: $visibleAddress'),
                if (!job.canRevealExactAddress(user.id))
                  Text(
                    t.t('exact_address_reveal_after_accept'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                Text('${t.t('posted')}: ${formatDateTime(job.createdAt)}'),
                if (canEditDetails) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _processing
                          ? null
                          : () => _showEditJobDialog(job, user),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Job Details'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (canChat && peerId != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(t.t('open_chat')),
              subtitle: Text(t.t('open_chat_subtitle')),
              onTap: () => context.push('/chat/${job.id}/$peerId'),
            ),
          ),
        _ActionsSection(
          job: job,
          user: user,
          bidsAsync: bidsAsync,
          bidController: _bidController,
          paymentMethod: _method,
          paymentPreview: paymentPreview,
          processing: _processing,
          isProLocked: financial?.isLocked ?? false,
          usersById: usersById,
          completedJobsByPro: completedJobsByPro,
          selectedBidSort: _bidSortOption,
          canSendMessage: canChat && peerId != null,
          showMessageLockedHint:
              user.role == UserRole.pro &&
              job.assignedProId != user.id &&
              (job.status == JobStatus.available ||
                  job.status == JobStatus.posted),
          startedAt: startedAt,
          stoppedAt: stoppedAt,
          onBidSortChanged: (value) => setState(() => _bidSortOption = value),
          onMethodChanged: (value) => setState(() => _method = value),
          onSubmitBid: () => _submitBid(job, user),
          onAcceptBid: (bidId) => ref
              .read(jobsControllerProvider)
              .acceptBid(jobId: job.id, bidId: bidId, customerId: user.id),
          onSendMessage: () {
            if (peerId == null || !canChat) {
              return;
            }
            context.push('/chat/${job.id}/$peerId');
          },
          onStartWork: () => _startWork(job, user),
          onRequestCompletion: () => _requestCompletion(job, user),
          onApproveCompletion: () => _approveCompletionRequest(job, user),
          onRejectCompletion: () => _rejectCompletionRequest(job, user),
          onPay: () => _pay(job, user),
        ),
        Card(
          child: ExpansionTile(
            title: Text(t.t('timeline_audit_trail')),
            subtitle: Text(t.t('timeline_subtitle')),
            children: job.timeline
                .map(
                  (event) => ListTile(
                    dense: true,
                    title: Text(event.type),
                    subtitle: Text(
                      '${formatDateTime(event.at)} | ${t.t('actor')}: ${usersById[event.actorId]?.fullName ?? event.actorId}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        Builder(
          builder: (context) {
            final canRaiseDispute =
                job.assignedProId != null &&
                (job.status == JobStatus.inProcess ||
                    job.status == JobStatus.completed ||
                    job.status == JobStatus.paidClosed) &&
                (user.role == UserRole.admin ||
                    user.id == job.customerId ||
                    user.id == job.assignedProId);
            final canCancel =
                user.role == UserRole.admin ||
                user.id == job.customerId ||
                (user.id == job.assignedProId &&
                    job.status == JobStatus.inProcess);
            return Card(
              child: ExpansionTile(
                title: Text(t.t('cancel_or_dispute')),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: <Widget>[
                        if (canCancel) ...<Widget>[
                          TextField(
                            controller: _cancelReasonController,
                            decoration: InputDecoration(
                              labelText: t.t('cancellation_reason'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await ref
                                        .read(jobsControllerProvider)
                                        .cancelJob(
                                          jobId: job.id,
                                          actorId: user.id,
                                          reason:
                                              _cancelReasonController.text
                                                  .trim()
                                                  .isEmpty
                                              ? t.t(
                                                  'user_requested_cancellation',
                                                )
                                              : _cancelReasonController.text
                                                    .trim(),
                                        );
                                    if (user.id == job.assignedProId) {
                                      await ref
                                          .read(
                                            localNotificationServiceProvider,
                                          )
                                          .cancelWorkTimerNotification(job.id);
                                    }
                                  },
                                  child: Text(t.t('cancel_job')),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextField(
                          controller: _disputeReasonController,
                          enabled: canRaiseDispute,
                          decoration: InputDecoration(
                            labelText: t.t('dispute_reason'),
                          ),
                        ),
                        if (!canRaiseDispute)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Dispute is available only after a pro is assigned.',
                              style: TextStyle(
                                color: Color(0xFFB3261E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: canRaiseDispute
                                    ? () => ref
                                          .read(jobsControllerProvider)
                                          .raiseDispute(
                                            jobId: job.id,
                                            actorId: user.id,
                                            reason:
                                                _disputeReasonController.text
                                                    .trim()
                                                    .isEmpty
                                                ? t.t('user_raised_dispute')
                                                : _disputeReasonController.text
                                                      .trim(),
                                          )
                                    : null,
                                child: Text(t.t('raise_dispute')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final jobAsync = ref.watch(jobByIdProvider(widget.jobId));
    final bidsAsync = ref.watch(bidsForJobProvider(widget.jobId));
    final usersById =
        ref.watch(usersByIdProvider).valueOrNull ?? <String, AppUser>{};
    final completedJobsByPro =
        ref.watch(completedJobsByProProvider).valueOrNull ?? <String, int>{};
    final financial = ref.watch(proFinancialStatusProvider);
    final fallbackJob = widget.initialJob;

    if (user == null) {
      return Scaffold(body: Center(child: Text(t.t('not_authenticated'))));
    }
    _syncBidEditor(user: user, bidsAsync: bidsAsync);

    return Scaffold(
      appBar: AppBar(title: Text(t.t('job_detail'))),
      body: jobAsync.when(
        loading: () {
          if (fallbackJob == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildJobContent(
            t: t,
            user: user,
            job: fallbackJob,
            bidsAsync: bidsAsync,
            financial: financial,
            usersById: usersById,
            completedJobsByPro: completedJobsByPro,
          );
        },
        error: (error, _) {
          if (fallbackJob == null) {
            return Center(child: Text(error.toString()));
          }
          return _buildJobContent(
            t: t,
            user: user,
            job: fallbackJob,
            bidsAsync: bidsAsync,
            financial: financial,
            usersById: usersById,
            completedJobsByPro: completedJobsByPro,
          );
        },
        data: (job) {
          final resolvedJob = job ?? fallbackJob;
          if (resolvedJob == null) {
            return Center(child: Text(t.t('job_not_found')));
          }
          return _buildJobContent(
            t: t,
            user: user,
            job: resolvedJob,
            bidsAsync: bidsAsync,
            financial: financial,
            usersById: usersById,
            completedJobsByPro: completedJobsByPro,
          );
        },
      ),
    );
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.job,
    required this.user,
    required this.bidsAsync,
    required this.bidController,
    required this.paymentMethod,
    required this.paymentPreview,
    required this.processing,
    required this.isProLocked,
    required this.usersById,
    required this.completedJobsByPro,
    required this.selectedBidSort,
    required this.canSendMessage,
    required this.showMessageLockedHint,
    required this.startedAt,
    required this.stoppedAt,
    required this.onBidSortChanged,
    required this.onMethodChanged,
    required this.onSubmitBid,
    required this.onAcceptBid,
    required this.onSendMessage,
    required this.onStartWork,
    required this.onRequestCompletion,
    required this.onApproveCompletion,
    required this.onRejectCompletion,
    required this.onPay,
  });

  final Job job;
  final AppUser user;
  final AsyncValue<List<Bid>> bidsAsync;
  final TextEditingController bidController;
  final PaymentMethod paymentMethod;
  final PaymentCalculation paymentPreview;
  final bool processing;
  final bool isProLocked;
  final Map<String, AppUser> usersById;
  final Map<String, int> completedJobsByPro;
  final _BidSortOption selectedBidSort;
  final bool canSendMessage;
  final bool showMessageLockedHint;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final ValueChanged<_BidSortOption> onBidSortChanged;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final VoidCallback onSubmitBid;
  final ValueChanged<String> onAcceptBid;
  final VoidCallback onSendMessage;
  final VoidCallback onStartWork;
  final VoidCallback onRequestCompletion;
  final VoidCallback onApproveCompletion;
  final VoidCallback onRejectCompletion;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isCustomer = user.id == job.customerId;
    final isAssignedPro = user.id == job.assignedProId;
    final isEligiblePro =
        user.role == UserRole.pro &&
        user.preferredCategories.contains(job.category);
    final canShowBidSection =
        user.role == UserRole.pro &&
        (job.status == JobStatus.available || job.status == JobStatus.posted);
    final canAcceptBid =
        isCustomer &&
        (job.status == JobStatus.available || job.status == JobStatus.posted);
    final canStartWork =
        isAssignedPro && job.status == JobStatus.inProcess && startedAt == null;
    final pendingCompletionRequest = hasPendingCompletionRequest(job);
    final canRequestCompletion =
        isAssignedPro &&
        job.status == JobStatus.inProcess &&
        !pendingCompletionRequest;
    final waitingCustomerApproval =
        isAssignedPro &&
        job.status == JobStatus.inProcess &&
        pendingCompletionRequest;
    final canRespondToCompletion =
        isCustomer &&
        job.status == JobStatus.inProcess &&
        pendingCompletionRequest;
    final canPay =
        isCustomer &&
        job.status == JobStatus.completed &&
        job.assignedProId != null;
    final myPendingBids =
        (bidsAsync.valueOrNull ?? <Bid>[])
            .where(
              (bid) => bid.proId == user.id && bid.status == BidStatus.pending,
            )
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final hasEditableBid = myPendingBids.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFD9E3F2)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.t('actions'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (canSendMessage) ...<Widget>[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: processing ? null : onSendMessage,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send Message'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (showMessageLockedHint && !canSendMessage)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Color(0xFFB3261E),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Messaging unlocks only after your bid is accepted.',
                        style: TextStyle(
                          color: Color(0xFFB3261E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (canShowBidSection) ...<Widget>[
              if (!isEligiblePro)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF2D7A2)),
                  ),
                  child: Text(
                    t.t('bid_category_restricted'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A4B05),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF5FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD2E2FF)),
                ),
                child: const Text(
                  'One active bid per pro. Re-submitting updates your bid.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F4F8A),
                  ),
                ),
              ),
              TextField(
                controller: bidController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: isEligiblePro,
                decoration: InputDecoration(
                  labelText: t.t('your_bid_amount'),
                  helperText: !isEligiblePro
                      ? t.t('bid_not_eligible')
                      : hasEditableBid
                      ? 'You already placed a bid. Edit amount and update it.'
                      : '${t.t('enter_to_accept')} ${formatPkr(job.fixedPrice)}',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: processing || isProLocked || !isEligiblePro
                      ? null
                      : onSubmitBid,
                  icon: Icon(
                    hasEditableBid
                        ? Icons.edit_note_rounded
                        : Icons.local_offer_outlined,
                  ),
                  label: Text(hasEditableBid ? 'Update Bid' : t.t('send_bid')),
                ),
              ),
              if (isProLocked)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
                    style: TextStyle(
                      color: Color(0xFFB3261E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (canAcceptBid)
              bidsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (error, _) => Text(error.toString()),
                data: (bids) {
                  if (bids.isEmpty) {
                    return Text(t.t('no_bids_received'));
                  }
                  final sorted = [...bids]
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  final latestByPro = <String, Bid>{};
                  for (final bid in sorted) {
                    latestByPro.putIfAbsent(bid.proId, () => bid);
                  }
                  final compactBids = latestByPro.values.toList(
                    growable: false,
                  );
                  int compareBids(Bid left, Bid right) {
                    switch (selectedBidSort) {
                      case _BidSortOption.priceLowToHigh:
                        final compare = left.amount.compareTo(right.amount);
                        if (compare != 0) {
                          return compare;
                        }
                        return right.createdAt.compareTo(left.createdAt);
                      case _BidSortOption.priceHighToLow:
                        final compare = right.amount.compareTo(left.amount);
                        if (compare != 0) {
                          return compare;
                        }
                        return right.createdAt.compareTo(left.createdAt);
                      case _BidSortOption.ratingHighToLow:
                        final leftRating = usersById[left.proId]?.rating ?? 0;
                        final rightRating = usersById[right.proId]?.rating ?? 0;
                        final compare = rightRating.compareTo(leftRating);
                        if (compare != 0) {
                          return compare;
                        }
                        return left.amount.compareTo(right.amount);
                      case _BidSortOption.worksDoneHighToLow:
                        final leftWorks = completedJobsByPro[left.proId] ?? 0;
                        final rightWorks = completedJobsByPro[right.proId] ?? 0;
                        final compare = rightWorks.compareTo(leftWorks);
                        if (compare != 0) {
                          return compare;
                        }
                        return left.amount.compareTo(right.amount);
                    }
                  }

                  compactBids.sort(compareBids);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Job Requests (${compactBids.length})',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          DropdownButton<_BidSortOption>(
                            value: selectedBidSort,
                            underline: const SizedBox.shrink(),
                            items: _BidSortOption.values
                                .map(
                                  (option) => DropdownMenuItem<_BidSortOption>(
                                    value: option,
                                    child: Text(option.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                onBidSortChanged(value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...compactBids.map((bid) {
                        final proUser = usersById[bid.proId];
                        final proName = proUser?.fullName ?? bid.proId;
                        final isPending = bid.status == BidStatus.pending;
                        final rating = proUser?.rating;
                        final worksDone =
                            completedJobsByPro[bid.proId] ??
                            proUser?.totalReviews ??
                            0;
                        final avatarProvider = resolveAvatarProvider(
                          proUser?.profileImageUrl,
                        );
                        final canOpenProfile =
                            proUser != null && proUser.role == UserRole.pro;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isPending
                                  ? const Color(0xFFC9DFFF)
                                  : const Color(0xFFDDE4EF),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: canOpenProfile
                                    ? () => context.push(
                                        '/pro/${proUser.id}',
                                        extra: proUser,
                                      )
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundImage: avatarProvider,
                                        child: avatarProvider == null
                                            ? Text(
                                                proName.isEmpty
                                                    ? '?'
                                                    : proName
                                                          .substring(0, 1)
                                                          .toUpperCase(),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          proName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F3FF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          t.bidStatusLabel(bid.status.value),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$proName requested for your job',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  if (rating != null)
                                    _BidMetaChip(
                                      icon: Icons.star_border_rounded,
                                      label:
                                          'Rating ${rating.toStringAsFixed(1)}',
                                    ),
                                  _BidMetaChip(
                                    icon: Icons.work_outline_rounded,
                                    label: 'Works Done $worksDone',
                                  ),
                                  _BidMetaChip(
                                    icon: Icons.payments_outlined,
                                    label: formatPkr(bid.amount),
                                    highlight: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatDateTime(bid.createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              if (isPending)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () => onAcceptBid(bid.id),
                                      child: Text(t.t('accept')),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            if (isAssignedPro && job.status == JobStatus.inProcess) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  WorkTimerBadge(startedAt: startedAt, stoppedAt: stoppedAt),
                  if (canStartWork)
                    ElevatedButton.icon(
                      onPressed: processing ? null : onStartWork,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start Work'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (canRequestCompletion)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: processing ? null : onRequestCompletion,
                  child: const Text('Job done / Request confirmation'),
                ),
              ),
            if (waitingCustomerApproval)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC8DFFF)),
                ),
                child: const Text(
                  'Completion requested. Waiting for customer confirmation.',
                  style: TextStyle(
                    color: Color(0xFF0C4A8A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (canRespondToCompletion)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD6E4FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Worker marked this job as done. Is the job completed?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton(
                            onPressed: processing ? null : onApproveCompletion,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Yes'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: processing ? null : onRejectCompletion,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('No'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (canPay) ...<Widget>[
              Text(
                t.t('payment_summary'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${t.t('gross')}: ${formatPkr(paymentPreview.gross)}'),
              Text('${t.t('platform_fee')}: ${formatPkr(paymentPreview.fee)}'),
              Text(
                '${t.t('pro_net_earning')}: ${formatPkr(paymentPreview.net)}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: PaymentMethod.values
                    .map(
                      (method) => ChoiceChip(
                        label: Text(t.paymentMethodLabel(method.value)),
                        selected: paymentMethod == method,
                        onSelected: (_) => onMethodChanged(method),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: processing ? null : onPay,
                  child: Text(
                    paymentMethod == PaymentMethod.cash
                        ? t.t('record_cash_payment')
                        : t.t('pay_online_instant_payout'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BidMetaChip extends StatelessWidget {
  const _BidMetaChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE8F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlight ? const Color(0xFFCDE2FF) : const Color(0xFFD8E3F1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: highlight ? const Color(0xFF1565C0) : Colors.black54,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: highlight ? const Color(0xFF0E2C53) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
