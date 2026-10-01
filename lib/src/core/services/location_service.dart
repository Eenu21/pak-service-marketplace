import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

enum LocationFailure { permissionDenied, serviceDisabled, timeout, unknown }

class LocationResult {
  const LocationResult._({this.position, this.failure});

  final Position? position;
  final LocationFailure? failure;

  bool get hasPosition => position != null;

  factory LocationResult.success(Position position) =>
      LocationResult._(position: position);

  factory LocationResult.failure(LocationFailure failure) =>
      LocationResult._(failure: failure);
}

class LocationService {
  static const Duration _cacheTtlNormal = Duration(minutes: 3);
  static const Duration _cacheTtlAggressive = Duration(minutes: 10);
  static const Duration _lastKnownMaxAgeNormal = Duration(minutes: 10);
  static const Duration _lastKnownMaxAgeAggressive = Duration(minutes: 30);
  static const Duration _freshFixTimeoutNormal = Duration(seconds: 3);
  static const Duration _freshFixTimeoutAggressive = Duration(seconds: 2);

  Position? _cachedPosition;
  DateTime? _cachedAt;
  Position? _cachedAggressivePosition;
  DateTime? _cachedAggressiveAt;

  Future<bool> ensurePermission({bool requestIfDenied = true}) async {
    var permission = await Geolocator.checkPermission();
    if (requestIfDenied && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<LocationResult> getCurrentPosition({
    bool aggressive = false,
    bool requestPermissionIfNeeded = true,
  }) async {
    final now = DateTime.now();
    final cacheTtl = aggressive ? _cacheTtlAggressive : _cacheTtlNormal;
    final cached = aggressive ? _cachedAggressivePosition : _cachedPosition;
    final cachedAt = aggressive ? _cachedAggressiveAt : _cachedAt;

    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) <= cacheTtl) {
      return LocationResult.success(cached);
    }

    final hasPermission = await ensurePermission(
      requestIfDenied: requestPermissionIfNeeded,
    );
    if (!hasPermission) {
      return LocationResult.failure(LocationFailure.permissionDenied);
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult.failure(LocationFailure.serviceDisabled);
    }

    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {
      lastKnown = null;
    }

    final maxAge = aggressive
        ? _lastKnownMaxAgeAggressive
        : _lastKnownMaxAgeNormal;
    if (lastKnown != null) {
      final timestamp = lastKnown.timestamp;
      if (timestamp == null || now.difference(timestamp) <= maxAge) {
        _cachePosition(lastKnown, aggressive: aggressive);
        return LocationResult.success(lastKnown);
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: aggressive
            ? _freshFixTimeoutAggressive
            : _freshFixTimeoutNormal,
      );
      _cachePosition(position, aggressive: aggressive);
      return LocationResult.success(position);
    } on TimeoutException {
      if (lastKnown != null) {
        _cachePosition(lastKnown, aggressive: aggressive);
        return LocationResult.success(lastKnown);
      }
      return LocationResult.failure(LocationFailure.timeout);
    } catch (_) {
      if (lastKnown != null) {
        _cachePosition(lastKnown, aggressive: aggressive);
        return LocationResult.success(lastKnown);
      }
      return LocationResult.failure(LocationFailure.unknown);
    }
  }

  void _cachePosition(Position position, {required bool aggressive}) {
    if (aggressive) {
      _cachedAggressivePosition = position;
      _cachedAggressiveAt = DateTime.now();
    } else {
      _cachedPosition = position;
      _cachedAt = DateTime.now();
    }
  }

  double distanceKm({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    final meters = Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
    return meters / 1000;
  }
}

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);
