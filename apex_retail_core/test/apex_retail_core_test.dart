import 'package:flutter_test/flutter_test.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

void main() {
  test('Product JSON round-trips', () {
    final p = Product(
      id: 'P001',
      name: 'Rice',
      sku: 'R-1',
      category: 'Grains',
      buyingPrice: 100,
      sellingPrice: 150,
      currentStock: 10,
      minStockLevel: 2,
      expirationDate: null,
      createdAt: '2026-01-01T00:00:00Z',
    );
    final back = Product.fromJson(p.toJson());
    expect(back.name, 'Rice');
    expect(back.sellingPrice, 150);
  });
}
