// Pilot authentication is enabled only by an explicit Flutter dart-define
// (local Chrome run or Hosting preview). Normal builds retain production URLs.
const bool sphotPasswordPilotMode =
    bool.fromEnvironment('SPHOT_PASSWORD_PILOT', defaultValue: false);

/// Disposable login to which direct Firestore writes must be limited when
/// testing Sauveteur creation, assignments and deletion from Flutter.
const String sphotPilotTestSauveteurLogin = String.fromEnvironment(
  'SPHOT_PASSWORD_PILOT_TEST_SAUVETEUR_LOGIN',
  defaultValue: '',
);

bool sphotPilotAllowsSauveteur(String login) =>
    !sphotPasswordPilotMode ||
    (sphotPilotTestSauveteurLogin.isNotEmpty &&
        login.trim().toLowerCase() ==
            sphotPilotTestSauveteurLogin.trim().toLowerCase());

/// Route only the four Sauveteur management operations to isolated pilot
/// Functions. A normal application build keeps its existing endpoints.
String sphotSauveteurManagementEndpoint(String endpoint) {
  if (!sphotPasswordPilotMode) return endpoint;
  return switch (endpoint) {
    'upsertSauveteurAccount' => 'upsertSauveteurAccountPilot',
    'sendSauveteurCredentialsEmail' => 'sendSauveteurCredentialsEmailPilot',
    'deleteSauveteurAccount' => 'deleteSauveteurAccountPilot',
    'changeSauveteurPassword' => 'changeSauveteurPasswordPilot',
    _ => throw StateError('Fonction pilote non autorisée : $endpoint'),
  };
}
