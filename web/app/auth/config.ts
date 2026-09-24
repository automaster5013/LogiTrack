import { createHash, randomBytes } from "node:crypto";

export const authCookie={state:"lt_oauth_state",verifier:"lt_pkce_verifier",nonce:"lt_oidc_nonce",access:"lt_access_token"} as const;
export function accessTokenConfig(){return {issuer:endpoint("COGNITO_ISSUER_URI"),clientId:required("COGNITO_CLIENT_ID")}}
export function authConfig(){
 const authBase=endpoint("COGNITO_AUTHORIZATION_BASE_URL");
 const {issuer,clientId}=accessTokenConfig();
 return {authBase,issuer,clientId,redirectUri:callback("OIDC_REDIRECT_URI"),postLogoutRedirectUri:callback("OIDC_POST_LOGOUT_REDIRECT_URI")};
}
export function randomUrlSafe(bytes=32){return randomBytes(bytes).toString("base64url")}
export function sha256UrlSafe(value:string){return createHash("sha256").update(value).digest("base64url")}
export function applicationOrigin(fallback:string){
 const configured=process.env.OIDC_REDIRECT_URI?.trim();
 if(!configured)return fallback;
 return new URL(callback("OIDC_REDIRECT_URI")).origin;
}
export function secureCookie(maxAge:number,path="/auth"){
 return {httpOnly:true,secure:process.env.NODE_ENV==="production",sameSite:"lax" as const,path,maxAge};
}
function required(name:string){const value=process.env[name]?.trim();if(!value)throw new Error(`${name} is required for operator authentication`);return value}
function endpoint(name:string){
 const url=validatedUrl(name);
 if(url.username||url.password||url.search||url.hash)throw new Error(`${name} must not contain credentials, query, or fragment`);
 return url.toString().replace(/\/$/,"");
}
function callback(name:string){
 const url=validatedUrl(name);
 if(url.username||url.password||url.search||url.hash)throw new Error(`${name} must not contain credentials, query, or fragment`);
 return url.toString();
}
function validatedUrl(name:string){
 const url=new URL(required(name));
 if(process.env.NODE_ENV==="production"&&url.protocol!=="https:")throw new Error(`${name} must use HTTPS in production`);
 if(url.protocol!=="https:"&&url.protocol!=="http:")throw new Error(`${name} must use HTTP or HTTPS`);
 return url;
}
