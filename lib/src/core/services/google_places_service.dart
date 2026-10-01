import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class AddressLookupException implements Exception {
  const AddressLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GooglePlaceSuggestion {
  const GooglePlaceSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

class GooglePlaceDetails {
  const GooglePlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String formattedAddress;
  final double latitude;
  final double longitude;
}

class GooglePlacesService {
  const GooglePlacesService({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;
  static const String _fallbackUserAgent =
      'ServiceMenApp/1.0 (manual-address-geocoding)';
  static const Duration _requestTimeout = Duration(seconds: 6);

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<List<GooglePlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) async {
    final query = input.trim();
    if (!isConfigured || query.length < 3) {
      return const <GooglePlaceSuggestion>[];
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': query,
        'types': 'address',
        'key': _apiKey,
        'sessiontoken': sessionToken,
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw AddressLookupException(
        'Google address search is unavailable right now.',
      );
    }

    final payload = _decodeMap(response.body);
    final status = payload['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status == 'ZERO_RESULTS') {
      return const <GooglePlaceSuggestion>[];
    }
    if (status != 'OK') {
      final message = payload['error_message'] as String?;
      throw AddressLookupException(
        message ?? 'Google address search is unavailable right now.',
      );
    }

    final predictions = payload['predictions'] as List<dynamic>? ?? <dynamic>[];
    return predictions
        .map((prediction) {
          final data = Map<String, dynamic>.from(prediction as Map);
          return GooglePlaceSuggestion(
            placeId: data['place_id'] as String? ?? '',
            description: data['description'] as String? ?? '',
          );
        })
        .where((value) => value.placeId.isNotEmpty)
        .toList(growable: false);
  }

  Future<GooglePlaceDetails?> fetchPlaceDetails(
    String placeId, {
    required String sessionToken,
  }) async {
    if (!isConfigured || placeId.trim().isEmpty) {
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId.trim(),
        'fields': 'formatted_address,geometry/location,place_id',
        'key': _apiKey,
        'sessiontoken': sessionToken,
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw const AddressLookupException(
        'Address details are unavailable right now.',
      );
    }

    final payload = _decodeMap(response.body);
    final status = payload['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status != 'OK') {
      final message = payload['error_message'] as String?;
      throw AddressLookupException(
        message ?? 'Address details are unavailable right now.',
      );
    }

    final result = Map<String, dynamic>.from(
      payload['result'] as Map? ?? <String, dynamic>{},
    );
    final geometry = Map<String, dynamic>.from(
      result['geometry'] as Map? ?? <String, dynamic>{},
    );
    final location = Map<String, dynamic>.from(
      geometry['location'] as Map? ?? <String, dynamic>{},
    );
    final latitude = (location['lat'] as num?)?.toDouble();
    final longitude = (location['lng'] as num?)?.toDouble();
    final address = result['formatted_address'] as String? ?? '';
    final resolvedPlaceId = result['place_id'] as String? ?? placeId;
    if (latitude == null || longitude == null || address.trim().isEmpty) {
      return null;
    }
    return GooglePlaceDetails(
      placeId: resolvedPlaceId,
      formattedAddress: address.trim(),
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<GooglePlaceDetails?> geocodeAddress(String address) async {
    final query = address.trim();
    if (query.isEmpty) {
      return null;
    }

    if (isConfigured) {
      try {
        final resolved = await _geocodeWithGoogle(query);
        if (resolved != null) {
          return resolved;
        }
      } catch (_) {
        // Fall back to manual geocoding when Google Maps is not linked
        // correctly on the current build.
      }
    }

    return _geocodeWithOpenStreetMap(query);
  }

  Future<GooglePlaceDetails?> _geocodeWithGoogle(String query) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      <String, String>{'address': query, 'key': _apiKey},
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw const AddressLookupException(
        'Address lookup is unavailable right now.',
      );
    }

    final payload = _decodeMap(response.body);
    final status = payload['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status == 'ZERO_RESULTS') {
      return null;
    }
    if (status != 'OK') {
      final message = payload['error_message'] as String?;
      throw AddressLookupException(
        message ?? 'Address lookup is unavailable right now.',
      );
    }

    final results = payload['results'] as List<dynamic>? ?? <dynamic>[];
    if (results.isEmpty) {
      return null;
    }

    final result = Map<String, dynamic>.from(results.first as Map);
    final geometry = Map<String, dynamic>.from(
      result['geometry'] as Map? ?? <String, dynamic>{},
    );
    final location = Map<String, dynamic>.from(
      geometry['location'] as Map? ?? <String, dynamic>{},
    );
    final latitude = (location['lat'] as num?)?.toDouble();
    final longitude = (location['lng'] as num?)?.toDouble();
    final formattedAddress = result['formatted_address'] as String? ?? query;
    final placeId = result['place_id'] as String? ?? query;
    if (latitude == null || longitude == null) {
      return null;
    }
    return GooglePlaceDetails(
      placeId: placeId,
      formattedAddress: formattedAddress.trim(),
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<GooglePlaceDetails?> _geocodeWithOpenStreetMap(String query) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      <String, String>{
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
        'addressdetails': '0',
      },
    );
    final response = await _get(
      uri,
      headers: const <String, String>{
        'User-Agent': _fallbackUserAgent,
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      throw const AddressLookupException(
        'Address lookup is unavailable right now. Please try again.',
      );
    }

    final payload = _decodeList(response.body);
    if (payload.isEmpty) {
      return null;
    }

    final result = Map<String, dynamic>.from(payload.first as Map);
    final latitude = double.tryParse(result['lat'] as String? ?? '');
    final longitude = double.tryParse(result['lon'] as String? ?? '');
    final formattedAddress = result['display_name'] as String? ?? query;
    final placeId = '${result['place_id'] ?? query}';
    if (latitude == null || longitude == null) {
      return null;
    }

    return GooglePlaceDetails(
      placeId: placeId,
      formattedAddress: formattedAddress.trim(),
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      return await http
          .get(uri, headers: headers)
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AddressLookupException(
        'Address lookup timed out. Please try again.',
      );
    } catch (error) {
      if (error is AddressLookupException) {
        rethrow;
      }
      throw const AddressLookupException(
        'Address lookup is unavailable right now. Please try again.',
      );
    }
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      throw const AddressLookupException(
        'Address lookup returned an invalid response. Please try again.',
      );
    }
  }

  List<dynamic> _decodeList(String body) {
    try {
      return jsonDecode(body) as List<dynamic>? ?? <dynamic>[];
    } catch (_) {
      throw const AddressLookupException(
        'Address lookup returned an invalid response. Please try again.',
      );
    }
  }
}

final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  final apiKey = ref.watch(appConfigProvider).googleMapsApiKey;
  return GooglePlacesService(apiKey: apiKey);
});
