import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());

  const defaultCorsOrigins = 'http://localhost:5173,http://localhost:8080,http://localhost:3001';
  const corsOrigins = (process.env.CORS_ORIGINS ?? defaultCorsOrigins)
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  app.enableCors({
    origin: corsOrigins,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );
  app.useGlobalFilters(new AllExceptionsFilter());

  // When the app is mounted under a sub-path (cPanel/Passenger serves it at
  // e.g. https://host/api and passes the FULL path through), set API_BASE_PATH
  // to that segment. Unset locally, so nothing changes in dev.
  const basePath = process.env.API_BASE_PATH?.trim().replace(/^\/+|\/+$/g, '');
  if (basePath) {
    app.setGlobalPrefix(basePath);
  }

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Warehouse System API')
    .setDescription(
      'Standalone Warehouse System — Step 1: Authentication, Users, Roles and Permissions. ' +
        'Independent of the back-office backend, own database (warehouse_db).',
    )
    .setVersion('0.1')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

  const port = process.env.PORT ?? 3100;
  await app.listen(port);
  // eslint-disable-next-line no-console
  console.log(`Warehouse API listening on http://localhost:${port}`);
  // eslint-disable-next-line no-console
  console.log(`Swagger docs on http://localhost:${port}/docs`);
}

bootstrap();
