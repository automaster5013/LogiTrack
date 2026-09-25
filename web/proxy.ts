import { NextRequest,NextResponse } from "next/server";
import { verifyAccessToken } from "./app/auth/access-token";
import { applicationOrigin, authCookie, secureCookie } from "./app/auth/config";
import { contentSecurityPolicy } from "./csp";
import { Buffer } from "node:buffer";

export async function proxy(request:NextRequest){
 const nonce=Buffer.from(crypto.randomUUID()).toString("base64");
 const csp=contentSecurityPolicy(nonce);
 const next=()=>{
  const headers=new Headers(request.headers);headers.set("x-nonce",nonce);headers.set("Content-Security-Policy",csp);
  const response=NextResponse.next({request:{headers}});response.headers.set("Content-Security-Policy",csp);return response;
 };
 const publicPage=["/","/showcase","/login"].includes(request.nextUrl.pathname);
 if(publicPage||process.env.AUTH_REQUIRED!=="true")return next();
 const currentToken=request.cookies.get(authCookie.access)?.value;
 const legacyToken=request.cookies.get(authCookie.legacyAccess)?.value;
 const token=currentToken||legacyToken;
 const payload=token?await validAccessToken(token):undefined;
 if(token&&payload){
  const response=next();response.headers.set("Cache-Control","no-store");
  if(!currentToken&&legacyToken){response.cookies.set(authCookie.access,legacyToken,secureCookie(Math.min(payload.exp!-Math.floor(Date.now()/1000),3600),"/"));response.cookies.set(authCookie.legacyAccess,"",{...secureCookie(0,"/"),expires:new Date(0)})}
  return response;
 }
 const login=new URL("/login",applicationOrigin(request.nextUrl.origin));login.searchParams.set("returnTo",request.nextUrl.pathname);
 const response=NextResponse.redirect(login);response.headers.set("Cache-Control","no-store");response.headers.set("Content-Security-Policy",csp);
 if(token)for(const name of [authCookie.access,authCookie.legacyAccess])response.cookies.set(name,"",{...secureCookie(0,"/"),expires:new Date(0)});
 return response;
}

async function validAccessToken(token:string){
 try{return await verifyAccessToken(token)}catch{return undefined}
}

export const config={matcher:["/((?!auth/|backend/|_next/|favicon.ico|api/runtime-version).*)"]};
