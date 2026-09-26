import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  test('IconData encodes its FontManifest family key', () {
    expect(const NativeIcon.icon(Icons.add).encode(), {
      'type': 'glyph',
      'codePoint': Icons.add.codePoint,
      'family': 'MaterialIcons',
    });
    // Package fonts are registered as packages/<package>/<family>.
    expect(const NativeIcon.icon(CupertinoIcons.gauge).encode()['family'], 'packages/cupertino_icons/CupertinoIcons');
  });

  test('SVG sources encode asset, package and tint', () {
    expect(const NativeIcon.svgAsset('assets/a.svg', package: 'pkg', tinted: false).encode(), {
      'type': 'svgAsset',
      'asset': 'assets/a.svg',
      'package': 'pkg',
      'tinted': false,
    });
    expect(const NativeIcon.svg('<svg/>').encode(), {'type': 'svg', 'data': '<svg/>', 'tinted': true});
  });

  test('icons compare by value so rebuilds do not resend them', () {
    expect(const NativeIcon.icon(Icons.add), const NativeIcon.icon(Icons.add));
    expect(NativeIcon.symbol('a'.padRight(1)), const NativeIcon.symbol('a'));
    expect(const NativeIcon.icon(Icons.add), isNot(const NativeIcon.icon(Icons.remove)));
    expect(const NativeIcon.svgAsset('a.svg'), isNot(const NativeIcon.svgAsset('a.svg', tinted: false)));
  });
}
