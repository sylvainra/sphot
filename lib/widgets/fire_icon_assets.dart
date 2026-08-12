/// Canonical Fire icon assets.
///
/// Every color variant uses the same symmetric geometry as the validated red
/// Fire. New SPHOT screens must reference these SVG constants instead of the
/// legacy PNG files.
abstract final class FireIconAssets {
  static const String black = 'data/icons/fire_black_icon.svg';
  static const String blue = 'data/icons/fire_blue_icon.svg';
  static const String cyan = 'data/icons/fire_cyan_icon.svg';
  static const String green = 'data/icons/fire_green_icon.svg';
  static const String orange = 'data/icons/fire_orange_icon.svg';
  static const String orangeAlternative = 'data/icons/fire_orange1_icon.svg';
  static const String orangeWithoutWhite = 'data/icons/fire_orange2_icon.svg';
  static const String red = 'data/icons/fire_red_icon.svg';
  static const String skin = 'data/icons/fire_skin_icon.svg';
  static const String yellow = 'data/icons/fire_yellow_icon.svg';

  static const Set<String> all = {
    black,
    blue,
    cyan,
    green,
    orange,
    orangeAlternative,
    orangeWithoutWhite,
    red,
    skin,
    yellow,
  };
}
