/**
 * Vercel / Next.js Edge Middleware: HTTP Basic Authentication
 *
 * IMPORTANT:
 * - This runs BEFORE any page/static response is served (link-level protection).
 * - Credentials are read ONLY from server-side environment variables.
 * - No credentials are shipped to the client.
 *
 * Env vars required (set in Vercel Project Settings):
 * - BASIC_AUTH_USER
 * - BASIC_AUTH_PASSWORD
 */
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

function unauthorizedResponse() {
  return new NextResponse('Authentication required.', {
    status: 401,
    headers: {
      // Triggers the browser's built-in username/password prompt
      'WWW-Authenticate': 'Basic realm="Protected", charset="UTF-8"',
      // Prevent caching of the 401 response
      'Cache-Control': 'no-store',
    },
  });
}

export function middleware(req: NextRequest) {
  const expectedUser = process.env.BASIC_AUTH_USER;
  const expectedPass = process.env.BASIC_AUTH_PASSWORD;

  // Fail closed if env vars are missing (safer than accidentally going public).
  if (!expectedUser || !expectedPass) {
    return new NextResponse(
      'Server misconfigured: BASIC_AUTH_USER/BASIC_AUTH_PASSWORD not set.',
      { status: 500, headers: { 'Cache-Control': 'no-store' } },
    );
  }

  const auth = req.headers.get('authorization');
  if (!auth || !auth.startsWith('Basic ')) {
    return unauthorizedResponse();
  }

  // Decode "Basic base64(user:pass)"
  const base64 = auth.slice('Basic '.length).trim();
  let decoded = '';
  try {
    decoded = atob(base64);
  } catch (_) {
    return unauthorizedResponse();
  }

  const sep = decoded.indexOf(':');
  if (sep === -1) {
    return unauthorizedResponse();
  }

  const user = decoded.slice(0, sep);
  const pass = decoded.slice(sep + 1);

  if (user !== expectedUser || pass !== expectedPass) {
    return unauthorizedResponse();
  }

  // Auth OK → allow request to continue.
  return NextResponse.next();
}

/**
 * Apply to all routes, but skip Next internals and common static files.
 *
 * Adjust exclusions if your Flutter build serves assets from different paths.
 */
export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|favicon.png|manifest.json|robots.txt).*)',
  ],
};

