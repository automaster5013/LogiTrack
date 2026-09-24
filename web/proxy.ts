import { createRemoteJWKSet, jwtVerify } from "jose";
import { NextRequest,NextResponse } from "next/server";
import { accessTokenConfig, applicationOrigin, authCookie, secureCookie } from "./app/auth/config";

const jwksTimeoutMs=5_000;
const jwksByIssuer=new Map<string,ReturnType<typeof createRemoteJWKSet>>();

export async function proxy(request:NextRequest){
 if(request.nextUrl.pathname==="/")return NextResponse.next();
 if(process.env.AUTH_REQUIRED!=="true")return NextResponse.next();
 const token=request.cookies.get(authCookie.access)?.value;
 if(token&&await validAccessToken(token)){
  const response=NextResponse.next();response.headers.set("Cache-Control","no-store");return response;
 }
 const login=new URL("/login",applicationOrigin(request.nextUrl.origin));login.searchParams.set("returnTo",request.nextUrl.pathname);
 const response=NextResponse.redirect(login);response.headers.set("Cache-Control","no-store");
 if(token)response.cookies.set(authCookie.access,"",{...secureCookie(0,"/"),expires:new Date(0)});
 return response;
}

async function validAccessToken(token:string){
 try{
  const {issuer,clientId}=accessTokenConfig();
  let jwks=jwksByIssuer.get(issuer);
  if(!jwks){jwks=createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`),{timeoutDuration:jwksTimeoutMs});jwksByIssuer.set(issuer,jwks)}
  const {payload}=await jwtVerify(token,jwks,{issuer,requiredClaims:["exp","iat","token_use","client_id"]});
  return payload.token_use==="access"&&payload.client_id===clientId&&typeof payload.exp==="number"&&payload.exp>Date.now()/1000+30;
 }catch{return false}
}

export const config={matcher:["/((?!showcase|login|auth/|backend/|_next/|favicon.ico|api/runtime-version).*)"]};
