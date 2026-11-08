import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bathing_spots_app/services/public_legal_acceptance_service.dart';

void main() {
  const service = PublicLegalAcceptanceService();
  const original = PublicLegalVersions(
    cgu: '1.0:r1',
    privacyPolicy: '1.0:r1',
    rgpdNotice: '1.0:r1',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une première ouverture demande une acceptation explicite', () async {
    expect(
      await service.accessDecision(original),
      PublicLegalAccessDecision.acceptCgu,
    );

    await service.accept(original);

    expect(
      await service.accessDecision(original),
      PublicLegalAccessDecision.allowAccess,
    );
  });

  test('une nouvelle révision des CGU demande une réacceptation', () async {
    await service.accept(original);

    const revisedCgu = PublicLegalVersions(
      cgu: '1.0:r2',
      privacyPolicy: '1.0:r1',
      rgpdNotice: '1.0:r1',
    );

    expect(
      await service.accessDecision(revisedCgu),
      PublicLegalAccessDecision.acceptCgu,
    );
  });

  test('une évolution RGPD informe sans demander une nouvelle CGU', () async {
    await service.accept(original);

    const revisedNotice = PublicLegalVersions(
      cgu: '1.0:r1',
      privacyPolicy: '1.0:r2',
      rgpdNotice: '1.0:r3',
    );

    expect(
      await service.accessDecision(revisedNotice),
      PublicLegalAccessDecision.acknowledgeInformationUpdate,
    );

    await service.acknowledgeInformationUpdate(revisedNotice);

    expect(
      await service.accessDecision(revisedNotice),
      PublicLegalAccessDecision.allowAccess,
    );
  });
}
