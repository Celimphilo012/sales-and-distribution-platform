import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import 'product_import_api.dart';

final productImportApiProvider = Provider<ProductImportApi>(
  (ref) => ProductImportApi(ref.watch(apiClientProvider)),
);
