import { NextResponse } from "next/server";
import { authConfig,authCookie,randomUrlSafe,secureCookie,sha256UrlSafe } from "../config";

export async function GET(){
 try{
  const {authBase,clientId,redirectUri}=authConfig();
  const state=randomUrlSafe(),nonce=randomUrlSafe(),verifier=randomUrlSafe(64);
  const url=new URL(`${authBase}/oauth2/authorize`);
  url.search=new URLSearchParams({response_type:"code",client_id:clientId,redirect_uri:redirectUri,scope:"openid profile",state,nonce,prompt:"login",code_challenge:sha256UrlSafe(verifier),code_challenge_method:"S256"}).toString();
  const response=NextResponse.redirect(url);
  response.cookies.set(authCookie.state,state,secureCookie(300));
  response.cookies.set(authCookie.nonce,nonce,secureCookie(300));
  response.cookies.set(authCookie.verifier,verifier,secureCookie(300));
  response.headers.set("Cache-Control","no-store");
  return response;
 }catch{return NextResponse.json({error:"Operator authentication is not configured"},{status:503,headers:{"Cache-Control":"no-store"}})}
}
