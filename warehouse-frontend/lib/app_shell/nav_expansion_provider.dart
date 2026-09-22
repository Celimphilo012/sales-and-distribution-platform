import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which nav groups are currently expanded in the sidebar / drawer, by
/// [NavGroup.id]. Lives in a provider (not widget state) so the choice
/// survives the drawer being rebuilt each time it opens and the shell
/// switching layouts on resize.
class NavExpansionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String groupId) {
    state = state.contains(groupId) ? ({...state}..remove(groupId)) : {...state, groupId};
  }

  /// Opens [groupId] without ever closing it — used to reveal the group that
  /// owns the current route.
  void open(String groupId) {
    if (state.contains(groupId)) return;
    state = {...state, groupId};
  }
}

final navExpansionProvider = NotifierProvider<NavExpansionNotifier, Set<String>>(NavExpansionNotifier.new);
