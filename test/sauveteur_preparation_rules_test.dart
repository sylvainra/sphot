import 'package:flutter_test/flutter_test.dart';

import 'package:sphot/models/flag_state.dart';

void main() {
  Map<String, dynamic> spot({
    Map<String, dynamic>? liveFlag,
    Map<String, dynamic>? preparation,
    bool realtimeAvailable = true,
  }) {
    return {
      'typeSphot': 'POSTE DE SECOURS',
      'realtimeAvailable': realtimeAvailable,
      'realtimeStatus': 'available',
      if (liveFlag != null) 'liveFlag': liveFlag,
      if (preparation != null) 'preparedFlag': preparation,
    };
  }

  test('premier jour : drapeau par défaut affalé, non surveillé', () {
    final state = SpotFlagState.fromFirestore(
      'LONGE09',
      spot(),
    );

    expect(state.flagPosition, FlagPosition.affale);
    expect(state.flagColor, FlagColor.green);
    expect(state.hasValidFlag, isFalse);
  });

  test('préparation non publiée : la carte conserve le drapeau précédent', () {
    final state = SpotFlagState.fromFirestore(
      'LONGE09',
      spot(
        liveFlag: {
          'flagColor': 'green',
          'flagPosition': 'affale',
          'purpleFlagActive': false,
          'windsockActive': false,
        },
        preparation: {
          'pending': true,
          'flagColor': 'red',
          'flagPosition': 'affale',
          'purpleFlagActive': true,
          'windsockActive': true,
        },
      ),
    );

    expect(state.flagColor, FlagColor.green);
    expect(state.flagPosition, FlagPosition.affale);
    expect(state.liveFlag?['purpleFlagActive'], isFalse);
    expect(state.liveFlag?['windsockActive'], isFalse);
    expect(state.hasValidFlag, isFalse);
  });

  test('à ouverture : préparé affiché mais toujours non hissé', () {
    final state = SpotFlagState.fromFirestore(
      'LONGE09',
      spot(liveFlag: {
        'flagColor': 'yellow',
        'flagPosition': 'affale',
        'purpleFlagActive': true,
        'windsockActive': true,
      }),
    );
    expect(state.flagColor, FlagColor.yellow);
    expect(state.flagPosition, FlagPosition.affale);
    expect(state.hasValidFlag, isFalse);
  });

  test('sans accès temps réel : aucune position supposée publiée', () {
    final state = SpotFlagState.fromFirestore(
      'LONGE09',
      spot(realtimeAvailable: false),
    );
    expect(state.flagPosition, FlagPosition.none);
    expect(state.flagColor, FlagColor.none);
  });
}
