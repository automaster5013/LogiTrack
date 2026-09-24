import Link from "next/link";
import "./login.css";

export const metadata={title:"운영자 로그인 | LogiTrack",description:"패스키와 교차 기기 QR 인증을 사용하는 LogiTrack 운영자 로그인"};

const authenticationErrors:Record<string,string>={
 invalid_oauth_response:"로그인 응답을 확인할 수 없습니다. 새 로그인을 시작해 주세요.",
 token_exchange_failed:"인증 서버가 로그인을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.",
 invalid_token_response:"인증 서버의 응답 형식이 올바르지 않습니다. 잠시 후 다시 시도해 주세요.",
 authentication_unavailable:"현재 운영자 인증을 완료할 수 없습니다. 잠시 후 다시 시도해 주세요.",
};

export default async function Login({searchParams}:{searchParams:Promise<{error?:string|string[]}>}){
 const errorParam=(await searchParams).error;
 const errorCode=Array.isArray(errorParam)?errorParam[0]:errorParam;
 const errorMessage=errorCode?authenticationErrors[errorCode]:undefined;
 return <main className="loginPage"><section className="loginCard"><Link className="loginBrand" href="/"><span>LT</span><b>LOGITRACK</b></Link><p className="loginEyebrow">SECURE OPERATOR ACCESS</p><h1>운영자 로그인</h1><p className="loginLead">패스키로 비밀번호 없이 안전하게 접속합니다. 다른 기기의 패스키를 선택하면 브라우저가 일회성 QR 코드를 표시합니다.</p>{errorMessage&&<div className="loginError" role="alert"><b>로그인을 완료하지 못했습니다</b><p>{errorMessage}</p></div>}<a className="passkeyButton" href="/auth/login"><i aria-hidden="true">⌁</i><span><b>{errorMessage?"다시 로그인하기":"패스키 · QR로 계속"}</b><small>휴대폰 생체인증 또는 보안키</small></span><em>→</em></a><ol><li><b>1</b><span>로그인을 시작하고 <strong>다른 기기 사용</strong>을 선택합니다.</span></li><li><b>2</b><span>휴대폰 카메라로 화면의 일회성 QR을 스캔합니다.</span></li><li><b>3</b><span>휴대폰에서 얼굴·지문 인증 후 접속을 승인합니다.</span></li></ol><div className="securityNote"><b>피싱 방지 설계</b><p>QR에는 비밀번호나 재사용 토큰이 없습니다. 패스키 개인키는 휴대폰 밖으로 나오지 않으며, 사용자 확인이 완료된 서명만 Cognito가 검증합니다.</p></div><Link className="backShowcase" href="/">← 프로젝트 소개로 돌아가기</Link></section><aside className="loginVisual"><div className="qrFrame" aria-hidden="true"><div className="qrMock"><i/><i/><i/><span/></div><div className="phone"><span/><b>✓</b><small>본인 확인</small></div></div><p>PASSKEY / WEBAUTHN</p><h2>복제할 수 없는<br/>운영자 신원 증명</h2></aside></main>;
}
