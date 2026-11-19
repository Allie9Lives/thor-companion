import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

const releasesUrl = 'https://github.com/Allie9Lives/thor-companion/releases';

class AppRelease {
  const AppRelease(this.version, this.url);
  final String version, url;
}

/// Same rules as Thor Monitor's own check: stable releases from this repository only.
AppRelease? parseRelease(Map<String, dynamic> j) {
  if (j['draft'] == true || j['prerelease'] == true) return null;
  final tag = RegExp(r'^v?(\d+\.\d+\.\d+)$').firstMatch('${j['tag_name']}');
  final url = j['html_url'];
  if (tag == null || url is! String || !url.startsWith('$releasesUrl/tag/')) {
    return null;
  }
  return AppRelease(tag[1]!, url);
}

/// Compares major.minor.patch; build and preview suffixes are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final s in v.replaceFirst('v', '').split(RegExp(r'[.+-]')).take(3))
      int.tryParse(s) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final n = i < x.length ? x[i] : 0, m = i < y.length ? y[i] : 0;
    if (n != m) return n.compareTo(m);
  }
  return 0;
}

/// Latest stable release, checked at most every 6 hours. Null when unknown.
Future<AppRelease?> latestRelease({String? userAgent}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final store = SharedPreferencesAsync();
    final now = DateTime.now().millisecondsSinceEpoch;
    final checked = await store.getInt('update_checked_ms') ?? 0;
    final cachedVersion = await store.getString('update_version');
    final cachedUrl = await store.getString('update_url');
    if (now - checked < const Duration(hours: 6).inMilliseconds &&
        cachedVersion != null &&
        cachedUrl != null) {
      return AppRelease(cachedVersion, cachedUrl);
    }
    final request = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/Allie9Lives/thor-companion/releases/latest',
      ),
    );
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, userAgent ?? 'Thor-Companion');
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 12));
    if (body.length > 512 * 1024) return null;
    final release = parseRelease(jsonDecode(body) as Map<String, dynamic>);
    if (release == null) return null;
    await store.setInt('update_checked_ms', now);
    await store.setString('update_version', release.version);
    await store.setString('update_url', release.url);
    return release;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
