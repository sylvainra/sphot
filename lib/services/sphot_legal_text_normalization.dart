/// Normalise uniquement les fins de ligne et les espaces périphériques.
///
/// Les fichiers Markdown embarqués par Flutter sur Windows peuvent utiliser
/// CRLF tandis que les articles JSON approuvés utilisent LF. Il s'agit du
/// même texte juridique : aucune différence de fond n'est masquée.
String normalizeSphotLegalText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
