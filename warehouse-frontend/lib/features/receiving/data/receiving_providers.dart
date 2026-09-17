import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import 'receiving_api.dart';

final receivingApiProvider = Provider<ReceivingApi>((ref) => ReceivingApi(ref.watch(apiClientProvider)));
