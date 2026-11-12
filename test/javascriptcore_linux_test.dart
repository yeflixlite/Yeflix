@TestOn('linux')
library;

import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/utils/javascriptcore_linux.dart';

void main() {
  test('JavaScriptCore se carga aunque solo exista la 4.1', () {
    expect(
      JavascriptCoreLoader.ensureInitialized(),
      isTrue,
      reason: 'sin JavaScriptCore no se pueden instalar extensiones',
    );
    expect(JavascriptCoreLoader.loadedFrom, isNotNull);
  });

  test('el runtime evalúa JavaScript y JSON con la librería cargada', () {
    JavascriptCoreLoader.ensureInitialized();
    final runtime = JavascriptCoreRuntime();
    final result = runtime.evaluate(
      "JSON.stringify({sum: 40 + 2, txt: 'hola', arr: [1, 2, 3]})",
    );
    expect(result.isError, isFalse, reason: result.stringResult);
    expect(result.stringResult, '{"sum":42,"txt":"hola","arr":[1,2,3]}');
  });
}
