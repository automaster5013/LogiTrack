import { NextRequest,NextResponse } from "next/server";
import { verifyAccessToken } from "./app/auth/access-token";
import { applicationOrigin, authCookie, secureCookie } from "./app/auth/config";

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
 try{await verifyAccessToken(token);return true}catch{return false}
}

export const config={matcher:["/((?!showcase|login|auth/|backend/|_next/|favicon.ico|api/runtime-version).*)"]};
