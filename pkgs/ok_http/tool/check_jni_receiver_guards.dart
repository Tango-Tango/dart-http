// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

const _bindingsPath = 'lib/src/jni/bindings.dart';

void main() {
  final bindings = File(_bindingsPath).readAsStringSync();
  final errors = <String>[
    if (bindings.contains('reference.pointer'))
      'Unretained reference.pointer call found.',
    ..._guardErrors(bindings, 'self'),
    ..._guardErrors(bindings, 'class'),
  ];
  if (errors.isEmpty) {
    stdout.writeln('JNI receiver lifetime guards verified.');
    return;
  }
  stderr.writeln(errors.join('\n'));
  exitCode = 1;
}

Iterable<String> _guardErrors(String bindings, String kind) sync* {
  final receiver = kind == 'self' ? 'reference' : '_class.reference';
  final declaration = 'final _\$\$${kind}Ref = $receiver;';
  final use = '_\$\$${kind}Ref.pointer';
  final declarationCount = declaration.allMatches(bindings).length;
  final useCount = use.allMatches(bindings).length;
  if (declarationCount == 0) {
    yield 'No _\$\$${kind}Ref guards found.';
  } else if (declarationCount != useCount) {
    yield '_\$\$${kind}Ref guards: $declarationCount declarations, '
        '$useCount uses.';
  }
}
