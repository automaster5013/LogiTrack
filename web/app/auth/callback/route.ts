import { NextRequest,NextResponse } from "next/server";
import { createRemoteJWKSet,jwtVerify } from "jose";
import { authConfig,authCookie,secureCookie } from "../config";

export async function GET(request:NextRequest){
 const code=request.nextUrl.searchParams.get("code"),state=request.nextUrl.searchParams.get("state");
 const expectedState=request.cookies.get(authCookie.state)?.value,expectedNonce=request.cookies.get(authCookie.nonce)?.value,verifier=request.cookies.get(authCookie.verifier)?.value;
 if(!code||!state||!expectedState||!expectedNonce||!verifier||state!==expectedState)return finish("invalid_oauth_response");
 try{
  const {authBase,issuer,clientId,redirectUri}=authConfig();
  const tokenResponse=await fetch(`${authBase}/oauth2/token`,{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"authorization_code",client_id:clientId,redirect_uri:redirectUri,code_verifier:verifier,code}),cache:"no-store"});
  if(!tokenResponse.ok)return finish("token_exchange_failed");
  const token=await tokenResponse.json() as {access_token?:string;id_token?:string;expires_in?:number;token_type?:string};
  if(!token.access_token||!token.id_token||token.token_type?.toLowerCase()!=="bearer")return finish("invalid_token_response");
  await jwtVerify(token.id_token,createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`)),{issuer,audience:clientId,requiredClaims:["nonce"],maxTokenAge:"5 minutes"}).then(({payload})=>{if(payload.nonce!==expectedNonce)throw new Error("OIDC nonce mismatch")});
  const response=NextResponse.redirect(new URL("/",request.url));
  response.cookies.set(authCookie.access,token.access_token,secureCookie(Math.min(Math.max(token.expires_in??900,60),3600),"/"));
  clearTransient(response);response.headers.set("Cache-Control","no-store");return response;
 }catch{return finish("authentication_unavailable")}
 function finish(reason:string){const response=NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(reason)}`,request.url));clearTransient(response);response.headers.set("Cache-Control","no-store");return response}
}
function clearTransient(response:NextResponse){for(const name of [authCookie.state,authCookie.nonce,authCookie.verifier])response.cookies.set(name,"",{...secureCookie(0),expires:new Date(0)})}
