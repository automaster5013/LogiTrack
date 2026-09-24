import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";
import { cognitoJwks, verifyAccessToken } from "../access-token";
import { applicationOrigin, authConfig, authCookie, secureCookie } from "../config";

const tokenExchangeTimeoutMs = 10_000;
const maxTokenResponseBytes = 64 * 1024;
const maxAccessTokenCharacters = 32 * 1024;
const maxIdTokenCharacters = 16 * 1024;
const maxAuthorizationCodeCharacters = 4096;
const maxStateCharacters = 256;

type TokenResponse = {
  access_token: string;
  id_token: string;
  expires_in?: number;
  token_type: string;
};

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const state = request.nextUrl.searchParams.get("state");
  const expectedState = request.cookies.get(authCookie.state)?.value;
  const expectedNonce = request.cookies.get(authCookie.nonce)?.value;
  const verifier = request.cookies.get(authCookie.verifier)?.value;
  if (!code || !state || !expectedState || !expectedNonce || !verifier || !validCallbackInput(code, state, expectedState)) return finish("invalid_oauth_response");

  try {
    const { authBase, issuer, clientId, redirectUri } = authConfig();
    const tokenResponse = await fetch(`${authBase}/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "authorization_code", client_id: clientId, redirect_uri: redirectUri, code_verifier: verifier, code }),
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(tokenExchangeTimeoutMs),
    });
    if (!tokenResponse.ok) return finish("token_exchange_failed");
    const token = await readBoundedTokenResponse(tokenResponse);
    if (!token) return finish("invalid_token_response");

    const [{ payload: idPayload }, accessPayload] = await Promise.all([
      jwtVerify(token.id_token, cognitoJwks(issuer), {
        issuer,
        audience: clientId,
        algorithms: ["RS256"],
        requiredClaims: ["exp", "iat", "sub", "nonce", "token_use"],
        maxTokenAge: "5 minutes",
      }),
      verifyAccessToken(token.access_token),
    ]);
    if (idPayload.token_use !== "id") throw new Error("Invalid ID token purpose");
    if (idPayload.nonce !== expectedNonce) throw new Error("OIDC nonce mismatch");
    if (idPayload.sub !== accessPayload.sub) throw new Error("OIDC subject mismatch");
    const accessTokenSecondsRemaining = Math.floor(accessPayload.exp! - Date.now() / 1000);
    const sessionMaxAge = Math.min(token.expires_in ?? accessTokenSecondsRemaining, accessTokenSecondsRemaining, 3600);

    const response = NextResponse.redirect(new URL("/console", applicationOrigin(request.nextUrl.origin)));
    response.cookies.set(authCookie.access, token.access_token, secureCookie(sessionMaxAge, "/"));
    clearTransient(response);
    response.headers.set("Cache-Control", "no-store");
    return response;
  } catch {
    return finish("authentication_unavailable");
  }

  function finish(reason: string) {
    const response = NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(reason)}`, applicationOrigin(request.nextUrl.origin)));
    clearTransient(response);
    response.headers.set("Cache-Control", "no-store");
    return response;
  }
}

function validCallbackInput(code: string, state: string, expectedState: string) {
  if (code.length > maxAuthorizationCodeCharacters || state.length > maxStateCharacters) return false;
  const supplied = Buffer.from(state);
  const expected = Buffer.from(expectedState);
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}

async function readBoundedTokenResponse(response: Response): Promise<TokenResponse | null> {
  const mediaType = response.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (mediaType !== "application/json") return null;
  const declaredLength = response.headers.get("content-length");
  if (declaredLength && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > maxTokenResponseBytes)) return null;
  if (!response.body) return null;

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxTokenResponseBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const parsed: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
    return isTokenResponse(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function isTokenResponse(value: unknown): value is TokenResponse {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const token = value as Record<string, unknown>;
  if (typeof token.access_token !== "string" || token.access_token.length < 1 || token.access_token.length > maxAccessTokenCharacters) return false;
  if (typeof token.id_token !== "string" || token.id_token.length < 1 || token.id_token.length > maxIdTokenCharacters) return false;
  if (typeof token.token_type !== "string" || token.token_type.toLowerCase() !== "bearer") return false;
  return token.expires_in === undefined || (typeof token.expires_in === "number" && Number.isInteger(token.expires_in) && token.expires_in > 0);
}

function clearTransient(response: NextResponse) {
  for (const name of [authCookie.state, authCookie.nonce, authCookie.verifier]) response.cookies.set(name, "", { ...secureCookie(0), expires: new Date(0) });
}
