import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('Obx que devuelve Positioned dentro de Stack', (tester) async {
    final show = false.obs;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Obx(() {
                if (!show.value) return const SizedBox.shrink();
                return const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 100,
                  child: ColoredBox(color: Colors.black),
                );
              }),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    show.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    show.value = false;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GestureDetector opaco sin hijo dentro de Positioned.fill',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // Regresión del "pantalla gris": el patrón de _buildAndroidContent tiene un
  // `Positioned.fill(video)` y un `Obx` que devuelve `SizedBox.shrink()` (0x0)
  // cuando el menú está cerrado. Sin `SizedBox.expand`, ese hijo no posicionado
  // hace que el `Stack` se encoja a 0x0 y el video quede invisible. Este test
  // fija que con el envoltorio el área del video ocupa toda la pantalla.
  testWidgets('el area del video no colapsa con el menu cerrado',
      (tester) async {
    final showSidebar = false.obs;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    key: const Key('video'),
                    color: Colors.red,
                  ),
                ),
                Obx(() {
                  if (!showSidebar.value) return const SizedBox.shrink();
                  return const Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 200,
                    child: ColoredBox(color: Colors.black),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(const Key('video')));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));

    // Con el menú abierto el video debe seguir ocupando toda la pantalla
    // (el panel se superpone, no lo encoge).
    showSidebar.value = true;
    await tester.pump();
    final sizeOpen = tester.getSize(find.byKey(const Key('video')));
    expect(sizeOpen, size);
  });
}
