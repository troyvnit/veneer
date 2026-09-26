import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  test('IconData encodes its FontManifest family key', () {
    final add = const NativeIcon.icon(Icons.add).encode();
    expect(add['type'], 'glyph');
    expect(add['codePoint'], Icons.add.codePoint);
    expect(add['family'], 'MaterialIcons');
    // Package fonts are registered as packages/<package>/<family>.
    expect(const NativeIcon.icon(CupertinoIcons.gauge).encode()['family'], 'packages/cupertino_icons/CupertinoIcons');
  });

  test('IconData carries fallbacks, text direction and variable-font axes', () {
    const data = IconData(
      0xe000,
      fontFamily: 'MaterialSymbolsRounded',
      fontPackage: 'symbols',
      fontFamilyFallback: ['Backup'],
      matchTextDirection: true,
    );
    final encoded = const NativeIcon.icon(data, fill: 1, weight: 600).encode();
    expect(encoded['family'], 'packages/symbols/MaterialSymbolsRounded');
    expect(encoded['fallback'], ['packages/symbols/Backup'], reason: 'fallbacks resolve in the same package');
    expect(encoded['mirror'], isTrue);
    expect(encoded['axes'], {'FILL': 1.0, 'wght': 600.0}, reason: 'unset axes are omitted');
    expect(const NativeIcon.icon(Icons.add).encode()['axes'], isEmpty);
  });

  test('SVG sources encode asset, package and tint', () {
    expect(const NativeIcon.svgAsset('assets/a.svg', package: 'pkg', tinted: false).encode(), {
      'type': 'svgAsset',
      'asset': 'assets/a.svg',
      'package': 'pkg',
      'tinted': false,
    });
    expect(const NativeIcon.svg('<svg/>').encode(), {'type': 'svg', 'data': '<svg/>', 'tinted': true});
    expect(const NativeIcon.svgFile('/tmp/a.svg').encode(), {'type': 'svgFile', 'path': '/tmp/a.svg', 'tinted': true});
  });

  test('icons compare by value so rebuilds do not resend them', () {
    expect(const NativeIcon.icon(Icons.add), const NativeIcon.icon(Icons.add));
    expect(NativeIcon.symbol('a'.padRight(1)), const NativeIcon.symbol('a'));
    expect(const NativeIcon.icon(Icons.add), isNot(const NativeIcon.icon(Icons.remove)));
    expect(const NativeIcon.svgAsset('a.svg'), isNot(const NativeIcon.svgAsset('a.svg', tinted: false)));
    expect(const NativeIcon.icon(Icons.add, weight: 700), isNot(const NativeIcon.icon(Icons.add)));
  });
}
