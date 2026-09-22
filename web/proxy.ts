import { NextRequest,NextResponse } from "next/server";

export function proxy(request:NextRequest){
 if(process.env.AUTH_REQUIRED!=="true")return NextResponse.next();
 const token=request.cookies.get("lt_access_token")?.value;
 if(token&&notExpired(token))return NextResponse.next();
 const login=new URL("/login",request.url);login.searchParams.set("returnTo",request.nextUrl.pathname);
 return NextResponse.redirect(login);
}

function notExpired(token:string){
 try{const part=token.split(".")[1].replace(/-/g,"+").replace(/_/g,"/");const payload=JSON.parse(atob(part)) as {exp?:number};return typeof payload.exp==="number"&&payload.exp>Date.now()/1000+30}catch{return false}
}

export const config={matcher:["/((?!showcase|login|auth/|_next/|favicon.ico|api/runtime-version).*)"]};
