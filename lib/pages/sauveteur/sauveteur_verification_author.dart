/// Restitue l'auteur d'une vérification depuis la trace conservée
/// par le serveur. Le nom courant n'est qu'une aide à la lecture :
/// l'identifiant historique enregistré reste toujours visible.
String sauveteurVerificationAuthor(
  Map<String, dynamic> entry, {
  Iterable<Map<String, dynamic>> personnel = const [],
}) {
  final rawAuthor = entry['createdBy'];
  final author = rawAuthor is Map
      ? Map<String, dynamic>.from(rawAuthor)
      : <String, dynamic>{};

  final login = (author['login'] ?? '').toString().trim();
  final displayName = (author['displayName'] ?? '').toString().trim();
  final firstName = (author['prenom'] ?? '').toString().trim();
  final lastName = (author['nom'] ?? '').toString().trim();
  final recordedName = displayName.isNotEmpty
      ? displayName
      : [firstName, lastName]
          .where((value) => value.isNotEmpty)
          .join(' ');

  if (login.isNotEmpty) {
    final loginNormalized = login.toLowerCase();
    for (final person in personnel) {
      final personLogin = (person['login'] ?? '').toString().trim().toLowerCase();
      if (personLogin != loginNormalized) continue;
      final name = (person['label'] ?? '').toString().trim();
      if (name.isNotEmpty && name.toLowerCase() != loginNormalized) {
        return '$name ($login)';
      }
      break;
    }

    if (recordedName.isNotEmpty &&
        recordedName.toLowerCase() != loginNormalized) {
      return '$recordedName ($login)';
    }
    return login;
  }

  if (recordedName.isNotEmpty) return recordedName;

  final sauveteurId = (author['sauveteurId'] ?? '').toString().trim();
  if (sauveteurId.isNotEmpty) {
    return 'Référence sauveteur : $sauveteurId';
  }
  return 'Non renseigné';
}
