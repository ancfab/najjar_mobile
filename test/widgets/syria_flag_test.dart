import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/syria_flag.dart';

void main() {
  testWidgets('SyriaFlag paints at a 3:2 width-to-height ratio derived from '
      'size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: SyriaFlag(size: 22))),
    );

    final renderedSize = tester.getSize(find.byType(SyriaFlag));
    expect(renderedSize.height, 22);
    expect(renderedSize.width, 33);
  });

  testWidgets('SyriaFlag renders without throwing for typical inline sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [SyriaFlag(size: 20), SyriaFlag(size: 22)],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SyriaFlag), findsNWidgets(2));
  });
}
