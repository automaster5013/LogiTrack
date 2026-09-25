import { createRemoteJWKSet, jwtVerify } from "jose";
import { accessTokenConfig } from "./config";

const jwksTimeoutMs = 5_000;
const allowedClockSkewSeconds = 60;
const maxAccessTokenLifetimeSeconds = 3_660;
const maxSubjectCharacters = 120;
const jwksByIssuer = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

export function cognitoJwks(issuer: string) {
  let jwks = jwksByIssuer.get(issuer);
  if (!jwks) {
    jwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`), { timeoutDuration: jwksTimeoutMs });
    jwksByIssuer.set(issuer, jwks);
  }
  return jwks;
}

export async function verifyAccessToken(token: string) {
  const { issuer, clientId } = accessTokenConfig();
  const { payload } = await jwtVerify(token, cognitoJwks(issuer), {
    issuer,
    algorithms: ["RS256"],
    requiredClaims: ["exp", "iat", "sub", "token_use", "client_id"],
  });
  if (payload.token_use !== "access" || payload.client_id !== clientId) throw new Error("Invalid access token claims");
  if (typeof payload.sub !== "string" || payload.sub.length < 1 || payload.sub.length > maxSubjectCharacters || payload.sub.trim() !== payload.sub) {
    throw new Error("Access token subject is invalid");
  }
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.iat !== "number" || !Number.isInteger(payload.iat) || payload.iat > now + allowedClockSkewSeconds) {
    throw new Error("Access token issued-at time is invalid");
  }
  if (typeof payload.exp !== "number" || !Number.isInteger(payload.exp) || payload.exp <= now + 30) {
    throw new Error("Access token is expired or near expiry");
  }
  if (payload.exp <= payload.iat || payload.exp - payload.iat > maxAccessTokenLifetimeSeconds) {
    throw new Error("Access token lifetime is invalid");
  }
  return payload;
}
