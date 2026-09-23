import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/config/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Khanya POS runtime icon is bundled into the Flutter asset bundle', () async {
    final data = await rootBundle.load(KhanyaBrand.appIconAsset);

    expect(data.lengthInBytes, greaterThan(1024));
  });

  test('production client points at the public Khanya API', () {
    expect(
      AppConfig.productionApiBaseUrl,
      'https://api.khanya.ithute.co.ls/api/v1',
    );
  });
}
