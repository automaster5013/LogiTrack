import { NextRequest,NextResponse } from "next/server";
import { verifyAccessToken } from "./app/auth/access-token";
import { applicationOrigin, authCookie, secureCookie } from "./app/auth/config";

export async function proxy(request:NextRequest){
 if(request.nextUrl.pathname==="/")return NextResponse.next();
 if(process.env.AUTH_REQUIRED!=="true")return NextResponse.next();
 const currentToken=request.cookies.get(authCookie.access)?.value;
 const legacyToken=request.cookies.get(authCookie.legacyAccess)?.value;
 const token=currentToken||legacyToken;
 const payload=token?await validAccessToken(token):undefined;
 if(token&&payload){
  const response=NextResponse.next();response.headers.set("Cache-Control","no-store");
  if(!currentToken&&legacyToken){response.cookies.set(authCookie.access,legacyToken,secureCookie(Math.min(payload.exp!-Math.floor(Date.now()/1000),3600),"/"));response.cookies.set(authCookie.legacyAccess,"",{...secureCookie(0,"/"),expires:new Date(0)})}
  return response;
 }
 const login=new URL("/login",applicationOrigin(request.nextUrl.origin));login.searchParams.set("returnTo",request.nextUrl.pathname);
 const response=NextResponse.redirect(login);response.headers.set("Cache-Control","no-store");
 if(token)for(const name of [authCookie.access,authCookie.legacyAccess])response.cookies.set(name,"",{...secureCookie(0,"/"),expires:new Date(0)});
 return response;
}

async function validAccessToken(token:string){
 try{return await verifyAccessToken(token)}catch{return undefined}
}

export const config={matcher:["/((?!showcase|login|auth/|backend/|_next/|favicon.ico|api/runtime-version).*)"]};
