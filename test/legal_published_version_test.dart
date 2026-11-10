import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/services/legal_published_version.dart';

void main() {
  test('les textes communs conservent leur version propre', () {
    final versions = LegalPublishedVersion.acceptedSnapshot(
      cgu: {'version': '1.1', 'revision': 0},
      privacyPolicy: {'version': '1.0'},
      rgpdNotice: {'version': '1.2', 'revision': 1},
      fallback: '1.2',
    );

    expect(versions['cgu'], '1.1:r0');
    expect(versions['privacyPolicy'], '1.0:historique');
    expect(versions['rgpdNotice'], '1.2:r1');
    expect(
      LegalPublishedVersion.matchesRecordedSnapshot(versions, versions),
      isTrue,
    );
    expect(
      LegalPublishedVersion.matchesRecordedSnapshot(
        {...versions, 'rgpdNotice': '1.0:historique'},
        versions,
      ),
      isFalse,
    );
  });

  test('les acceptations historiques restent compatibles', () {
    expect(
      LegalPublishedVersion.matchesRecordedSnapshot(
        null,
        {'rgpdNotice': '1.0:historique'},
      ),
      isTrue,
    );
  });
}
