/**
 * Custom error classes for the API.
 *
 * Rules (CLAUDE.md §5.2):
 *   - Never throw raw strings — always use a typed Error subclass.
 *   - All errors carry a `code` field for classification.
 *   - Never expose stack traces to API clients.
 */

// ---------------------------------------------------------------------------
// Error codes
// ---------------------------------------------------------------------------

export type ErrorCode =
  | 'INTERNAL_ERROR'
  | 'NOT_FOUND'
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'CONFLICT'
  | 'BAD_REQUEST'
  | 'SERVICE_UNAVAILABLE'
  | 'AUTH_FAILED'
  | 'KYC_REQUIRED'
  | 'KYC_REJECTED'
  | 'CHAIN_ERROR'
  | 'RATE_LIMITED'
  | 'WEBHOOK_INVALID_SIGNATURE';

// HTTP status codes the API actually returns (all "contentful" per Hono) — keeps
// AppError.statusCode sound so the error handler needs no unchecked cast.
export type HttpStatusCode = 400 | 401 | 403 | 404 | 409 | 429 | 500 | 502 | 503;

// ---------------------------------------------------------------------------
// Base class
// ---------------------------------------------------------------------------

export class AppError extends Error {
  public readonly code: ErrorCode;
  public readonly statusCode: HttpStatusCode;
  public readonly details?: unknown;

  constructor(message: string, code: ErrorCode, statusCode: HttpStatusCode, details?: unknown) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
    Error.captureStackTrace?.(this, new.target);
  }
}

// ---------------------------------------------------------------------------
// Concrete error types
// ---------------------------------------------------------------------------

export class NotFoundError extends AppError {
  constructor(message = 'Resource not found', details?: unknown) {
    super(message, 'NOT_FOUND', 404, details);
    this.name = 'NotFoundError';
  }
}

export class ValidationError extends AppError {
  constructor(message = 'Validation failed', details?: unknown) {
    super(message, 'VALIDATION_ERROR', 400, details);
    this.name = 'ValidationError';
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required', details?: unknown) {
    super(message, 'UNAUTHORIZED', 401, details);
    this.name = 'UnauthorizedError';
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Insufficient permissions', details?: unknown) {
    super(message, 'FORBIDDEN', 403, details);
    this.name = 'ForbiddenError';
  }
}

export class ConflictError extends AppError {
  constructor(message = 'Resource conflict', details?: unknown) {
    super(message, 'CONFLICT', 409, details);
    this.name = 'ConflictError';
  }
}

export class ServiceUnavailableError extends AppError {
  constructor(message = 'Service temporarily unavailable', details?: unknown) {
    super(message, 'SERVICE_UNAVAILABLE', 503, details);
    this.name = 'ServiceUnavailableError';
  }
}

export class ChainError extends AppError {
  constructor(message = 'Blockchain interaction failed', details?: unknown) {
    super(message, 'CHAIN_ERROR', 502, details);
    this.name = 'ChainError';
  }
}

export class KycRequiredError extends AppError {
  constructor(message = 'KYC verification required to perform this action') {
    super(message, 'KYC_REQUIRED', 403);
    this.name = 'KycRequiredError';
  }
}

export class RateLimitError extends AppError {
  constructor(message = 'Too many requests', details?: unknown) {
    super(message, 'RATE_LIMITED', 429, details);
    this.name = 'RateLimitError';
  }
}
