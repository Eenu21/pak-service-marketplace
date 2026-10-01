import 'dart:convert';

import 'package:flutter/material.dart';

ImageProvider<Object>? resolveAvatarProvider(String? avatarValue) {
  final value = avatarValue?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.startsWith('data:image')) {
    final commaIndex = value.indexOf(',');
    if (commaIndex < 0 || commaIndex + 1 >= value.length) {
      return null;
    }
    try {
      final bytes = base64Decode(value.substring(commaIndex + 1));
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(value);
  }
  return null;
}

