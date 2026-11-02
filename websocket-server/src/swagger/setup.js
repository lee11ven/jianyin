import swaggerUi from 'swagger-ui-express';
import { openApiDocument } from './openapi.js';

/**
 * 挂载 OpenAPI JSON 与 Swagger UI。
 * - GET /openapi.json
 * - GET /docs （及静态资源）
 * @param {import('express').Express} app
 */
export function mountSwagger(app) {
  app.get('/openapi.json', (_req, res) => {
    res.json(openApiDocument);
  });

  app.use(
    '/docs',
    swaggerUi.serve,
    swaggerUi.setup(openApiDocument, {
      customSiteTitle: '见音网关 API',
      swaggerOptions: {
        persistAuthorization: true,
        displayRequestDuration: true,
        docExpansion: 'list',
        filter: true,
      },
    }),
  );
}
