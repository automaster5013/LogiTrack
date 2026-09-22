import { NextRequest,NextResponse } from "next/server";
import { authConfig,authCookie,secureCookie } from "../config";
export async function POST(request:NextRequest){
 let destination=new URL("/login",request.url);
 try{const {authBase,clientId,postLogoutRedirectUri}=authConfig();destination=new URL(`${authBase}/logout`);destination.search=new URLSearchParams({client_id:clientId,logout_uri:postLogoutRedirectUri}).toString()}catch{}
 const response=NextResponse.redirect(destination,303);response.cookies.set(authCookie.access,"",{...secureCookie(0,"/"),expires:new Date(0)});response.headers.set("Clear-Site-Data",'"cache", "storage"');return response;
}
