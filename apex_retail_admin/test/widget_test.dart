import 'package:flutter_test/flutter_test.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

void main() {
  test('UserRole wire mapping round-trips', () {
    expect(UserRoleX.fromWire('top_manager'), UserRole.topManager);
    expect(UserRole.manager.wire, 'manager');
  });
}
