import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { ApiKeyGuard } from '../common/guards/api-key.guard';
import { RequireScopes } from '../common/decorators/require-scopes.decorator';
import { ProductsService } from '../products/products.service';
import { CategoriesService } from '../categories/categories.service';
import { ListProductsQueryDto } from '../products/dto/list-products-query.dto';

/**
 * System-to-system catalogue read — authenticated by API key (`ApiKeyGuard`),
 * never a user JWT. Reuses the same `ProductsService`/`CategoriesService`
 * the internal `/products` and `/categories` routes use; this is purely a
 * read view for external consumers, no new business logic.
 */
@ApiTags('external-catalogue')
@UseGuards(ApiKeyGuard)
@RequireScopes('catalogue:read')
@Controller('api/v1/catalogue')
export class ExternalCatalogueController {
  constructor(
    private readonly productsService: ProductsService,
    private readonly categoriesService: CategoriesService,
  ) {}

  @Get()
  async getCatalogue(@Query() query: ListProductsQueryDto) {
    const [products, categories] = await Promise.all([
      this.productsService.findAll(query),
      this.categoriesService.findAll({}),
    ]);
    return { categories, products };
  }
}
