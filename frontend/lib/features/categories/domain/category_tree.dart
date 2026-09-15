import 'category.dart';

/// A [Category] plus its children, built client-side from the flat list
/// `GET /categories` returns — the backend endpoint is NOT a tree/recursive
/// response (unlike `/locations/:id/subtree`); it's a flat `findMany` you
/// can optionally filter to one level via `parentId`. See the F3 report.
class CategoryNode {
  const CategoryNode({required this.category, required this.children, required this.depth});

  final Category category;
  final List<CategoryNode> children;
  final int depth;
}

/// Groups a flat category list into a tree by `parentId`, sorted by name at
/// every level.
List<CategoryNode> buildCategoryTree(List<Category> categories) {
  final byParent = <String?, List<Category>>{};
  for (final category in categories) {
    byParent.putIfAbsent(category.parentId, () => []).add(category);
  }
  for (final siblings in byParent.values) {
    siblings.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<CategoryNode> build(String? parentId, int depth) {
    final children = byParent[parentId] ?? const [];
    return [
      for (final category in children)
        CategoryNode(category: category, children: build(category.id, depth + 1), depth: depth),
    ];
  }

  return build(null, 0);
}

/// Depth-first flatten — e.g. for a "pick a category" dropdown that shows
/// hierarchy via indentation off [CategoryNode.depth].
List<CategoryNode> flattenCategoryTree(List<CategoryNode> nodes) {
  final result = <CategoryNode>[];
  void visit(List<CategoryNode> level) {
    for (final node in level) {
      result.add(node);
      visit(node.children);
    }
  }

  visit(nodes);
  return result;
}

/// [categoryId] and every one of its descendants — used to stop a category
/// being reparented under itself or under its own subtree (the backend
/// rejects this too via `assertNoCycle`; this is the client-side mirror so
/// the picker doesn't even offer the invalid options).
Set<String> descendantIds(List<CategoryNode> tree, String categoryId) {
  final flat = flattenCategoryTree(tree);
  CategoryNode? root;
  for (final node in flat) {
    if (node.category.id == categoryId) {
      root = node;
      break;
    }
  }
  if (root == null) return {};

  final ids = <String>{categoryId};
  void collect(CategoryNode node) {
    for (final child in node.children) {
      ids.add(child.category.id);
      collect(child);
    }
  }

  collect(root);
  return ids;
}
