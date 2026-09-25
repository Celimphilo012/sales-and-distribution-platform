import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/core/theme/app_theme.dart';
import 'package:warehouse_frontend/features/stock_adjustments/data/stock_adjustments_providers.dart';
import 'package:warehouse_frontend/features/stock_adjustments/domain/stock_adjustment.dart';
import 'package:warehouse_frontend/features/stock_adjustments/presentation/widgets/adjustment_summary_tile.dart';

final _now = DateTime(2026, 1, 1);

/// A real, minimal 1x1-pixel JPEG — `Image.memory` actually decodes this
/// (unlike arbitrary garbage bytes, which throw asynchronously mid-test).
final _tinyJpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=',
);

StockAdjustment _adjustment({String? photoPath}) => StockAdjustment(
  id: 'a1',
  productId: 'p1',
  locationId: 'l1',
  bucket: AdjustmentBucket.damaged,
  delta: 3,
  direction: AdjustmentDirection.increase,
  reason: 'Damaged carton found',
  status: AdjustmentStatus.pending,
  requestedBy: 'u1',
  requestedAt: _now,
  photoPath: photoPath,
  product: const AdjustmentProductRef(id: 'p1', sku: 'SOP-1', name: 'Soap'),
  location: const AdjustmentLocationRef(id: 'l1', name: 'Bin A', code: 'BINA'),
  requestedByUser: const AdjustmentUserRef(id: 'u1', fullName: 'Warehouse Staff', email: 'staff@example.com'),
);

void main() {
  testWidgets('an adjustment with no photo shows no thumbnail and never fetches one', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AdjustmentSummaryTile(adjustment: _adjustment())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Photo attached'), findsNothing);
  });

  testWidgets('an adjustment with a photo shows a thumbnail, tappable to view full-size', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adjustmentPhotoProvider('a1').overrideWith((ref) async => _tinyJpegBytes)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AdjustmentSummaryTile(adjustment: _adjustment(photoPath: 'abc123.jpg'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('Soap — evidence photo'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2)); // thumbnail (now behind the dialog) + full-size in the dialog

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Soap — evidence photo'), findsNothing);
  });

  testWidgets('a photo that fails to load shows a plain error note, not a broken layout', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adjustmentPhotoProvider('a1').overrideWith((ref) async => throw Exception('network error'))],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AdjustmentSummaryTile(adjustment: _adjustment(photoPath: 'abc123.jpg'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Photo attached, but could not be loaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
