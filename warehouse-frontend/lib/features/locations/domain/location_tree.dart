import 'location.dart';

/// A [Location] plus its children — built client-side from a flat list of
/// locations (one warehouse's worth, concatenated from a
/// `GET /locations/:id/subtree` call per root — see `locations_providers.dart`
/// for why: a warehouse can have MORE THAN ONE root/top-level location, and
/// there is no single "whole warehouse" subtree endpoint, only a per-location
/// one). [depth] here is recomputed while building the tree (0 = a warehouse
/// root), independent of the `Location.depth` a subtree response carries —
/// they agree in practice but this tree is deliberately the source of truth
/// for rendering, not a re-trust of server-reported depth.
class LocationNode {
  const LocationNode({required this.location, required this.children, required this.depth});

  final Location location;
  final List<LocationNode> children;
  final int depth;
}

/// Groups a flat location list into a forest by `parentId` (null = a
/// warehouse-level root — a warehouse can have several), sorted by name at
/// every level. No assumption about depth anywhere (CLAUDE.md rule 5).
List<LocationNode> buildLocationTree(List<Location> locations) {
  final byParent = <String?, List<Location>>{};
  for (final location in locations) {
    byParent.putIfAbsent(location.parentId, () => []).add(location);
  }
  for (final siblings in byParent.values) {
    siblings.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<LocationNode> build(String? parentId, int depth) {
    final children = byParent[parentId] ?? const [];
    return [
      for (final location in children)
        LocationNode(location: location, children: build(location.id, depth + 1), depth: depth),
    ];
  }

  return build(null, 0);
}

/// Depth-first flatten — used for the parent picker in the move dialog.
List<LocationNode> flattenLocationTree(List<LocationNode> nodes) {
  final result = <LocationNode>[];
  void visit(List<LocationNode> level) {
    for (final node in level) {
      result.add(node);
      visit(node.children);
    }
  }

  visit(nodes);
  return result;
}

/// [locationId] and every one of its descendants — the client-side mirror of
/// the backend's `assertNoCycle` (§G move endpoint), so the move dialog's
/// target picker doesn't even offer the invalid options, and so the UI can
/// give an immediate, clear rejection instead of waiting on a round trip for
/// the common case.
Set<String> locationDescendantIds(List<LocationNode> tree, String locationId) {
  final flat = flattenLocationTree(tree);
  LocationNode? root;
  for (final node in flat) {
    if (node.location.id == locationId) {
      root = node;
      break;
    }
  }
  if (root == null) return {};

  final ids = <String>{locationId};
  void collect(LocationNode node) {
    for (final child in node.children) {
      ids.add(child.location.id);
      collect(child);
    }
  }

  collect(root);
  return ids;
}

/// Returns a PRUNED copy of [tree] containing only nodes whose name or code
/// matches [query] (case-insensitive), every ANCESTOR of a match (so a hit
/// is shown in its real position in the hierarchy, not floating with no
/// context), and — once a node itself matches — its FULL original subtree
/// (finding "Rack A1" shows everything under it, not just the rack).
List<LocationNode> filterLocationTree(List<LocationNode> tree, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return tree;

  List<LocationNode> prune(List<LocationNode> nodes) {
    final kept = <LocationNode>[];
    for (final node in nodes) {
      final selfMatches =
          node.location.name.toLowerCase().contains(trimmed) ||
          node.location.code.toLowerCase().contains(trimmed);
      if (selfMatches) {
        kept.add(node);
        continue;
      }
      final prunedChildren = prune(node.children);
      if (prunedChildren.isNotEmpty) {
        kept.add(LocationNode(location: node.location, children: prunedChildren, depth: node.depth));
      }
    }
    return kept;
  }

  return prune(tree);
}
