import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import 'products_api.dart';

final productsApiProvider = Provider<ProductsApi>((ref) => ProductsApi(ref.watch(apiClientProvider)));
