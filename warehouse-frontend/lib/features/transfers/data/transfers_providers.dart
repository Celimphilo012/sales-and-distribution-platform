import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import 'transfers_api.dart';

final transfersApiProvider = Provider<TransfersApi>((ref) => TransfersApi(ref.watch(apiClientProvider)));
