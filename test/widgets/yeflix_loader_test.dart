import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/views/widgets/yeflix_loader.dart';

void main() {
  testWidgets('muestra el mensaje y el fondo negro de carga inicial',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: YeflixLoader()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cargando video...'), findsOneWidget);
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(box.color, Colors.black);
  });

  testWidgets('el buffering usa un fondo semitransparente', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: YeflixLoader(opaque: false)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(box.color, Colors.black.withOpacity(0.62));
  });

  testWidgets('se adapta a tablet sin desbordar', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: YeflixLoader()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Cargando video...'), findsOneWidget);
  });
}
