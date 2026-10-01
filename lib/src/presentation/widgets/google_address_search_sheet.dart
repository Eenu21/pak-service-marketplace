import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/google_places_service.dart';

Future<GooglePlaceDetails?> showGoogleAddressSearchSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return showModalBottomSheet<GooglePlaceDetails>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => GoogleAddressSearchSheet(initialQuery: initialQuery),
  );
}

class GoogleAddressSearchSheet extends ConsumerStatefulWidget {
  const GoogleAddressSearchSheet({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<GoogleAddressSearchSheet> createState() =>
      _GoogleAddressSearchSheetState();
}

class _GoogleAddressSearchSheetState
    extends ConsumerState<GoogleAddressSearchSheet> {
  final _queryController = TextEditingController();
  final _uuid = const Uuid();
  Timer? _debounce;
  late String _sessionToken;
  List<GooglePlaceSuggestion> _results = const <GooglePlaceSuggestion>[];
  bool _loadingResults = false;
  bool _loadingSelection = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _sessionToken = _uuid.v4();
    _queryController.text = widget.initialQuery.trim();
    if (_queryController.text.length >= 3) {
      _search(_queryController.text);
    }
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _queryController.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final service = ref.read(googlePlacesServiceProvider);
    if (!service.isConfigured || query.length < 3) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const <GooglePlaceSuggestion>[];
        _loadingResults = false;
        _errorText = null;
      });
      return;
    }

    setState(() {
      _loadingResults = true;
      _errorText = null;
    });
    try {
      final results = await service.autocomplete(
        query,
        sessionToken: _sessionToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingResults = false;
        });
      }
    }
  }

  Future<void> _selectSuggestion(GooglePlaceSuggestion suggestion) async {
    final service = ref.read(googlePlacesServiceProvider);
    if (!service.isConfigured) {
      return;
    }
    setState(() {
      _loadingSelection = true;
      _errorText = null;
    });
    try {
      final details = await service.fetchPlaceDetails(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) {
        return;
      }
      if (details == null) {
        setState(() {
          _errorText = 'Address details unavailable for this place.';
        });
        return;
      }
      Navigator.of(context).pop(details);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingSelection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(googlePlacesServiceProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Search Address',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (!service.isConfigured)
            const Text(
              'Google address search is unavailable right now. You can still type your address manually in Profile or Post Job.',
            )
          else ...<Widget>[
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search with Google Maps',
                hintText: 'Type at least 3 characters',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingResults || _loadingSelection)
              const LinearProgressIndicator(),
            if (_errorText != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(color: Color(0xFFB3261E)),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: _results.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('No results yet. Start typing to search.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = _results[index];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(suggestion.description),
                          onTap: _loadingSelection
                              ? null
                              : () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}
