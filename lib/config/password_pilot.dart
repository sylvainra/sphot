// Only the explicitly built Hosting preview can use pilot authentication.
// Normal mobile and Web builds keep every existing production endpoint.
const bool sphotPasswordPilotMode =
    bool.fromEnvironment('SPHOT_PASSWORD_PILOT', defaultValue: false);
