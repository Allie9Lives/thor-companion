import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/app_updates.dart';
import 'package:thor_companion/telemetry.dart';

void main() {
  const url =
      'https://github.com/Allie9Lives/thor-companion/releases/tag/v0.17.1';
  test('only stable releases from this repository are update candidates', () {
    final release = parseRelease({'tag_name': 'v0.17.1', 'html_url': url});
    expect(release?.version, '0.17.1');
    expect(release?.url, url);
    expect(
      parseRelease({
        'tag_name': 'v0.18.0',
        'html_url': url,
        'prerelease': true,
      }),
      isNull,
    );
    expect(
      parseRelease({'tag_name': 'v0.18.0', 'html_url': url, 'draft': true}),
      isNull,
    );
    expect(
      parseRelease({'tag_name': 'v0.17.1-preview.1', 'html_url': url}),
      isNull,
    );
    expect(
      parseRelease({
        'tag_name': 'v0.17.1',
        'html_url': 'https://example.com/releases/tag/v0.17.1',
      }),
      isNull,
    );
  });

  test('versions compare on major.minor.patch only', () {
    expect(compareVersions('0.17.0', '0.17.0'), 0);
    expect(compareVersions('0.17.0-preview.12', '0.17.0'), 0);
    expect(compareVersions('0.17.0+45', 'v0.17.0'), 0);
    expect(compareVersions('0.17.1', '0.17.0'), greaterThan(0));
    expect(compareVersions('0.9.0', '0.10.0'), lessThan(0));
    expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
  });

  test('hardware reports the Thor Monitor version when the host sends it', () {
    expect(
      DeviceHardware.fromBytes(
        utf8.encode('{"model":"AYN Thor","host_version":"0.17.0"}'),
      ).hostVersion,
      '0.17.0',
    );
    expect(
      DeviceHardware.fromBytes(utf8.encode('{"model":"AYN Thor"}')).hostVersion,
      isNull,
    );
  });
}
