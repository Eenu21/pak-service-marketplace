import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceContext {
  const DeviceContext({required this.deviceInfo, required this.ipAddress});

  final String deviceInfo;
  final String ipAddress;
}

class DeviceContextService {
  String describeDevice() => _platformDescription();

  Future<DeviceContext> resolve() async {
    final platformInfo = describeDevice();
    final ip = await _detectIpAddress();
    return DeviceContext(deviceInfo: platformInfo, ipAddress: ip);
  }

  String _platformDescription() {
    if (kIsWeb) {
      return 'web';
    }
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
        .trim();
  }

  Future<String> _detectIpAddress() async {
    if (kIsWeb) {
      return 'unavailable';
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.any,
      ).timeout(const Duration(milliseconds: 350));
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (_) {
      return 'unavailable';
    }
    return 'unavailable';
  }
}

final deviceContextServiceProvider = Provider<DeviceContextService>(
  (_) => DeviceContextService(),
);
