import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/avatar_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/jobs_controller.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalized(String value) {
    return value.trim().toLowerCase();
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.pro => 'Pro',
      UserRole.customer => 'Customer',
      UserRole.admin => 'Admin',
    };
  }

  List<Job> _buildRecentConversations(List<Job> jobs, AppUser user) {
    final list =
        jobs
            .where((job) {
              final assignedProId = job.assignedProId;
              if (assignedProId == null) {
                return false;
              }
              final participants = <String>{job.customerId, assignedProId};
              return participants.contains(user.id);
            })
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  bool _matchesUserQuery(AppUser user, String query) {
    final normalizedQuery = _normalized(query);
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final name = _normalized(user.fullName);
    final email = _normalized(user.email);
    final phone = _normalized(user.phone);
    final phoneDigits = _digitsOnly(phone);
    final queryDigits = _digitsOnly(normalizedQuery);

    if (name.contains(normalizedQuery) ||
        email.contains(normalizedQuery) ||
        phone.contains(normalizedQuery)) {
      return true;
    }
    if (queryDigits.length >= 3 && phoneDigits.contains(queryDigits)) {
      return true;
    }
    final parts = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (parts.isEmpty) {
      return false;
    }
    return parts.every(
      (part) =>
          name.contains(part) || email.contains(part) || phone.contains(part),
    );
  }

  int _userMatchScore(AppUser user, String query) {
    final normalizedQuery = _normalized(query);
    if (normalizedQuery.isEmpty) {
      return 0;
    }
    final name = _normalized(user.fullName);
    final email = _normalized(user.email);
    final phone = _normalized(user.phone);
    final phoneDigits = _digitsOnly(phone);
    final queryDigits = _digitsOnly(normalizedQuery);
    var score = 0;
    if (name.startsWith(normalizedQuery)) {
      score += 8;
    }
    if (email.startsWith(normalizedQuery)) {
      score += 6;
    }
    if (name.contains(normalizedQuery)) {
      score += 4;
    }
    if (email.contains(normalizedQuery)) {
      score += 3;
    }
    if (phone.contains(normalizedQuery)) {
      score += 5;
    }
    if (queryDigits.length >= 3 && phoneDigits.contains(queryDigits)) {
      score += 7;
    }
    return score;
  }

  List<AppUser> _searchUsers({
    required Iterable<AppUser> users,
    required AppUser currentUser,
    required String query,
  }) {
    final normalizedQuery = _normalized(query);
    if (normalizedQuery.isEmpty) {
      return const <AppUser>[];
    }
    final matched =
        users
            .where((candidate) {
              if (candidate.id == currentUser.id ||
                  candidate.role == UserRole.admin) {
                return false;
              }
              return _matchesUserQuery(candidate, normalizedQuery);
            })
            .toList(growable: false)
          ..sort((a, b) {
            final scoreA = _userMatchScore(a, normalizedQuery);
            final scoreB = _userMatchScore(b, normalizedQuery);
            if (scoreA != scoreB) {
              return scoreB.compareTo(scoreA);
            }
            return a.fullName.compareTo(b.fullName);
          });
    return matched;
  }

  List<Job> _filterConversations({
    required List<Job> jobs,
    required AppUser user,
    required Map<String, AppUser> usersById,
    required String query,
  }) {
    final normalizedQuery = _normalized(query);
    if (normalizedQuery.isEmpty) {
      return jobs;
    }
    return jobs
        .where((job) {
          final peerId = user.id == job.customerId
              ? job.assignedProId
              : job.customerId;
          final peer = peerId == null ? null : usersById[peerId];
          final haystack = <String>[
            job.title,
            peer?.fullName ?? '',
            peer?.email ?? '',
            peer?.phone ?? '',
          ].join(' ').toLowerCase();
          final queryDigits = _digitsOnly(normalizedQuery);
          final haystackDigits = _digitsOnly(haystack);
          return haystack.contains(normalizedQuery) ||
              (queryDigits.length >= 3 && haystackDigits.contains(queryDigits));
        })
        .toList(growable: false);
  }

  Job? _latestUnlockedThread({
    required List<Job> jobs,
    required String currentUserId,
    required String peerId,
  }) {
    final matching =
        jobs
            .where((job) {
              final assignedProId = job.assignedProId;
              if (assignedProId == null ||
                  job.status.index < JobStatus.inProcess.index) {
                return false;
              }
              final participants = <String>{job.customerId, assignedProId};
              return participants.contains(currentUserId) &&
                  participants.contains(peerId) &&
                  currentUserId != peerId;
            })
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matching.isEmpty ? null : matching.first;
  }

  void _openThreadForPeer({
    required AppUser peer,
    required AppUser currentUser,
    required List<Job> recentConversations,
  }) {
    final thread = _latestUnlockedThread(
      jobs: recentConversations,
      currentUserId: currentUser.id,
      peerId: peer.id,
    );
    if (thread == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No active chat thread found with ${peer.fullName}. Chat unlocks after bid acceptance.',
          ),
        ),
      );
      return;
    }
    context.push('/chat/${thread.id}/${peer.id}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            t.t('not_logged_in'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final jobsAsync = ref.watch(jobsForCurrentUserProvider);
    final notificationsAsync = ref.watch(notificationsProvider(user.id));
    final usersById =
        ref.watch(usersByIdProvider).valueOrNull ?? <String, AppUser>{};

    return Scaffold(
      backgroundColor: const Color(0xFF0A1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1118),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Inbox',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'Recent chats first',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CB0C8)),
            ),
          ],
        ),
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            error.toString(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        data: (jobs) {
          final recentConversations = _buildRecentConversations(jobs, user);
          final filteredConversations = _filterConversations(
            jobs: recentConversations,
            user: user,
            usersById: usersById,
            query: _searchQuery,
          );
          final userMatches = _searchUsers(
            users: usersById.values,
            currentUser: user,
            query: _searchQuery,
          );

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF8CA1BB),
                    ),
                    hintText: 'Search people, phone, email, or job title',
                    filled: true,
                    fillColor: const Color(0xFF131C27),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF263445)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF263445)),
                    ),
                    hintStyle: const TextStyle(color: Color(0xFF8CA1BB)),
                    suffixIcon: _searchQuery.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF8CA1BB),
                            ),
                          ),
                  ),
                ),
              ),
              if (_searchQuery.trim().isNotEmpty) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: Text(
                      'Accounts (${userMatches.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFC5D3E3),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: userMatches.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No user matched your search.',
                              style: TextStyle(color: Color(0xFF9CB0C8)),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: userMatches.length.clamp(0, 12),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final candidate = userMatches[index];
                            final avatar = resolveAvatarProvider(
                              candidate.profileImageUrl,
                            );
                            final initial = candidate.fullName.trim().isEmpty
                                ? '?'
                                : candidate.fullName
                                      .trim()
                                      .substring(0, 1)
                                      .toUpperCase();
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                  color: Color(0xFF293748),
                                ),
                              ),
                              color: const Color(0xFF121A24),
                              child: ListTile(
                                onTap: () => _openThreadForPeer(
                                  peer: candidate,
                                  currentUser: user,
                                  recentConversations: recentConversations,
                                ),
                                leading: CircleAvatar(
                                  backgroundImage: avatar,
                                  child: avatar == null ? Text(initial) : null,
                                ),
                                title: Text(
                                  candidate.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${candidate.email} | ${candidate.phone}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF9CB0C8),
                                  ),
                                ),
                                trailing: _RoleChip(
                                  label: _roleLabel(candidate.role),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    'Recent chats (${filteredConversations.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFC5D3E3),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filteredConversations.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No recent conversations yet. Once a job chat starts, it appears here.',
                            style: TextStyle(color: Color(0xFF9CB0C8)),
                          ),
                        ),
                      )
                    : notificationsAsync.when(
                        loading: () => _ConversationList(
                          jobs: filteredConversations,
                          user: user,
                          unreadByJobId: const <String, int>{},
                          usersById: usersById,
                        ),
                        error: (_, _) => _ConversationList(
                          jobs: filteredConversations,
                          user: user,
                          unreadByJobId: const <String, int>{},
                          usersById: usersById,
                        ),
                        data: (events) {
                          final unreadByJobId = <String, int>{};
                          for (final event in events) {
                            if (event.read || event.type != 'message') {
                              continue;
                            }
                            final jobId = event.metadata['job_id'] as String?;
                            if (jobId == null || jobId.isEmpty) {
                              continue;
                            }
                            unreadByJobId[jobId] =
                                (unreadByJobId[jobId] ?? 0) + 1;
                          }
                          return _ConversationList(
                            jobs: filteredConversations,
                            user: user,
                            unreadByJobId: unreadByJobId,
                            usersById: usersById,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.jobs,
    required this.user,
    required this.unreadByJobId,
    required this.usersById,
  });

  final List<Job> jobs;
  final AppUser user;
  final Map<String, int> unreadByJobId;
  final Map<String, AppUser> usersById;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No chats matched your search.',
            style: TextStyle(color: Color(0xFF9CB0C8)),
          ),
        ),
      );
    }
    final sortedJobs = <Job>[...jobs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      itemCount: sortedJobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final job = sortedJobs[index];
        final peerId = user.id == job.customerId
            ? job.assignedProId
            : job.customerId;
        if (peerId == null) {
          return const SizedBox.shrink();
        }
        final unread = unreadByJobId[job.id] ?? 0;
        final peer = usersById[peerId];
        return _ConversationTile(
          job: job,
          peer: peer,
          peerId: peerId,
          currentUserId: user.id,
          unreadCount: unread,
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.job,
    required this.peer,
    required this.peerId,
    required this.currentUserId,
    required this.unreadCount,
  });

  final Job job;
  final AppUser? peer;
  final String peerId;
  final String currentUserId;
  final int unreadCount;

  String _formatTrailingDate(DateTime value) {
    final now = DateTime.now();
    final sameDay =
        value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    if (sameDay) {
      return DateFormat('h:mm a').format(value);
    }
    return DateFormat('dd/MM/yyyy').format(value);
  }

  ChatMessage? _latestVisibleMessage(
    List<ChatMessage> messages,
    String userId,
  ) {
    for (final message in messages.reversed) {
      if (!message.isDeletedFor(userId)) {
        return message;
      }
    }
    return null;
  }

  String _previewText(ChatMessage? message) {
    if (message == null) {
      return 'No messages yet';
    }
    final body = message.isDeletedForEveryone
        ? 'This message was deleted'
        : message.text.trim();
    if (message.senderId == currentUserId) {
      return 'You: ${body.isEmpty ? '...' : body}';
    }
    return body.isEmpty ? '...' : body;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerPhone = peer?.phone.trim() ?? '';
    final rawName = (peer?.fullName ?? '').trim();
    final peerName = rawName.isNotEmpty
        ? rawName
        : (peerPhone.isNotEmpty ? peerPhone : 'User');
    final peerInitial = peerName.isEmpty
        ? '?'
        : peerName.substring(0, 1).toUpperCase();
    final avatar = resolveAvatarProvider(peer?.profileImageUrl);
    final messagesAsync = ref.watch(chatMessagesProvider(job.id));
    final messages = messagesAsync.valueOrNull ?? const <ChatMessage>[];
    final lastMessage = _latestVisibleMessage(messages, currentUserId);
    final preview = _previewText(lastMessage);
    final activityTime = lastMessage?.sentAt ?? job.updatedAt;
    final showOutgoingTicks =
        lastMessage != null && lastMessage.senderId == currentUserId;
    final isSeen = lastMessage?.seenAt != null;

    final tickColor = isSeen ? AppTheme.brandBlue : const Color(0xFF7E90A8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/chat/${job.id}/$peerId'),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF111922),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF273646)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF25234F),
                  backgroundImage: avatar,
                  child: avatar == null
                      ? Text(
                          peerInitial,
                          style: const TextStyle(
                            color: Color(0xFFC3C0FF),
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
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
                              peerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTrailingDate(activityTime),
                            style: const TextStyle(
                              color: Color(0xFFA9B9CD),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          if (showOutgoingTicks) ...<Widget>[
                            Icon(
                              isSeen
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 17,
                              color: tickColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unreadCount > 0
                                    ? const Color(0xFFE7F0FB)
                                    : const Color(0xFF9FB0C4),
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.brandTeal,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2F45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2D4868)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB9D4F8),
        ),
      ),
    );
  }
}
