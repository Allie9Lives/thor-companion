Map<String, dynamic> validateRecordingStatus(Map<String, dynamic> source) {
  const states = ['idle', 'recording', 'ready', 'failed'];
  if (!states.contains(source['state'])) {
    throw const FormatException('Unsupported recording status');
  }
  if (source['state'] == 'idle') return {'state': 'idle'};
  final token = source['token'], mode = source['mode'], rows = source['tracks'];
  if (token is! String ||
      !RegExp(r'^[a-f0-9]{24}$').hasMatch(token) ||
      mode is! int ||
      mode < 0 ||
      mode > 2 ||
      rows is! List ||
      rows.length != (mode == 2 ? 2 : 1)) {
    throw const FormatException('Invalid recording tracks');
  }
  if (source.containsKey('quality') && ![0, 1].contains(source['quality']) ||
      source.containsKey('fps') && ![30, 60].contains(source['fps'])) {
    throw const FormatException('Invalid recording settings');
  }
  final screens = <int>{};
  for (final raw in rows) {
    if (raw is! Map) throw const FormatException('Invalid recording track');
    final screen = raw['screen'],
        bytes = raw['bytes'],
        offset = raw['offset_ms'];
    if (screen is! int ||
        ![0, 1].contains(screen) ||
        (mode != 2 && screen != mode) ||
        !screens.add(screen) ||
        bytes is! int ||
        bytes < 0 ||
        bytes > 512 * 1024 * 1024 ||
        offset is! num ||
        !offset.isFinite ||
        offset < 0 ||
        offset > 10000) {
      throw const FormatException('Invalid recording metadata');
    }
    if (source['state'] == 'ready') {
      final duration = raw['duration_ms'],
          width = raw['width'],
          height = raw['height'];
      if (bytes < 128 ||
          duration is! num ||
          !duration.isFinite ||
          duration <= 0 ||
          duration > 190000 ||
          width is! int ||
          width < 1 ||
          width > 4096 ||
          height is! int ||
          height < 1 ||
          height > 4096) {
        throw const FormatException('Recording was not finalized');
      }
    }
  }
  return Map<String, dynamic>.from(source);
}
