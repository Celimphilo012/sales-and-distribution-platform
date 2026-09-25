import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { MulterError } from 'multer';

interface StructuredError {
  statusCode: number;
  error: string;
  message: string | string[];
  path: string;
  timestamp: string;
}

/**
 * Normalises every thrown error (HttpException or otherwise) into one
 * response shape so API consumers never have to branch on error format.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let error = 'Internal Server Error';
    let message: string | string[] = 'An unexpected error occurred';

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'string') {
        message = body;
        error = exception.name;
      } else {
        const asObject = body as Record<string, unknown>;
        message = (asObject.message as string | string[]) ?? exception.message;
        error = (asObject.error as string) ?? exception.name;
      }
    } else if (exception instanceof MulterError) {
      // Not an HttpException (multer throws its own error class from inside
      // an interceptor, before the route handler runs) — without this it
      // falls through to the generic 500 branch below, same class of bug as
      // the ledger's raw CHECK-constraint leak (see InventoryService).
      // Every upload in this app (product import, adjustment photos) goes
      // through this one filter, so this fixes both at once.
      status = HttpStatus.BAD_REQUEST;
      error = 'Bad Request';
      message =
        exception.code === 'LIMIT_FILE_SIZE'
          ? 'File is too large.'
          : `Upload rejected: ${exception.message}`;
    } else if (exception instanceof Error) {
      this.logger.error(exception.message, exception.stack);
      message = exception.message;
      error = exception.name;
    } else {
      this.logger.error('Unknown exception thrown', String(exception));
    }

    const structured: StructuredError = {
      statusCode: status,
      error,
      message,
      path: request.url,
      timestamp: new Date().toISOString(),
    };

    response.status(status).json(structured);
  }
}
