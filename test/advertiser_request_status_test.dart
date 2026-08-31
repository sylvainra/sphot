import 'package:bathing_spots_app/web/advertiser/models/advertiser_request_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seule une demande approuvée ouvre le parcours validé', () {
    expect(isAdvertiserRequestApproved('draft'), isFalse);
    expect(isAdvertiserRequestApproved('pending'), isFalse);
    expect(isAdvertiserRequestApproved(' approved '), isTrue);
  });

  test('une demande en contrôle ou approuvée verrouille la candidature', () {
    expect(isAdvertiserApplicationLocked('draft'), isFalse);
    expect(isAdvertiserApplicationLocked('changes_requested'), isFalse);
    expect(isAdvertiserApplicationLocked('pending'), isTrue);
    expect(isAdvertiserApplicationLocked('APPROVED'), isTrue);
  });
}
