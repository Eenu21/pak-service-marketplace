String deriveMaskedAddress(String exactAddress) {
  final parts = exactAddress
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '';
  }
  if (parts.length == 1) {
    return parts.first;
  }
  if (parts.length == 2) {
    return '${parts[0]}, ${parts[1]}';
  }
  return '${parts[parts.length - 2]}, ${parts.last}';
}
