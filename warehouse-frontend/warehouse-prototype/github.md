repo: Celimphilo012/sales-and-distribution-platform
branch: main
path: warehouse-frontend

## Last sync
date: 2026-09-29T18:44:06Z

### Updated in this project
- Warehouse Console v2: every catalogue, warehousing, stock and admin screen with table/list/grid views, stats and advanced filters
- Add/edit dialogs for all entities, warehouse structure map, light/dark theme
- Reports screen with PDF and Excel export carrying the logo

## Screen map
| Project screen | Repo files |
| --- | --- |
| Current UI.dc.html | lib/app_shell/responsive_app_shell.dart, nav_panel.dart, shell_top_bar.dart, lib/core/theme/app_theme.dart, app_semantic_colors.dart, lib/features/dashboard/presentation/dashboard_screen.dart, lib/shared/widgets/app_card.dart, status_badge.dart |
| Warehouse Console.dc.html — shell | lib/app_shell/*.dart, lib/routing/nav_items.dart, lib/core/responsive/breakpoints.dart |
| Warehouse Console — Dashboard | lib/features/dashboard/presentation/dashboard_screen.dart, domain/dashboard_summary.dart |
| Warehouse Console — Products / detail | lib/features/products/presentation/products_list_screen.dart, product_detail_screen.dart |
| Warehouse Console — Inventory | lib/features/inventory/presentation/inventory_screen.dart, where_is_this_product_view.dart |
| Warehouse Console — Receiving / Transfers | lib/features/receiving/presentation/receiving_form_screen.dart, lib/features/transfers/presentation/transfer_form_screen.dart |
| Warehouse Console — Stock counts | lib/features/stock_counts/presentation/stock_counts_screen.dart |
| Warehouse Console — Stock adjustments | lib/features/stock_adjustments/presentation/stock_adjustments_screen.dart |
| Warehouse Console — Warehouse structure | lib/features/locations/presentation/warehouse_structure_screen.dart |
| Warehouse Console — Users / Roles | lib/features/users/presentation/users_screen.dart, lib/features/roles/presentation/roles_screen.dart |
| Warehouse Console — Audit log | lib/features/audit/presentation/audit_log_screen.dart |
| Warehouse Console v2 — Workstreams / Categories / Attribute types / Warehouses / Packing | lib/features/workstreams, categories, attribute_types, warehouses, packing (domain + presentation) |
| Warehouse Console v2 — theme | lib/core/theme/theme_mode_provider.dart |
| Warehouse Console — Settings | lib/features/settings/presentation/settings_screen.dart |
