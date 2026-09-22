import Link from "next/link";
import "./showcase.css";

export const metadata={title:"LogiTrack | 실시간 물류 운영 플랫폼",description:"주문·창고·배차·실시간 운송·이상 복구를 하나의 흐름으로 연결하는 이벤트 기반 물류 관제 플랫폼"};

const vehicles=[
  {id:"LT-204",state:"정시",progress:"78%",x:70,y:31,delay:"0분"},
  {id:"LT-118",state:"주의",progress:"54%",x:48,y:53,delay:"7분"},
  {id:"LT-071",state:"정시",progress:"91%",x:27,y:69,delay:"0분"},
];

export default function Showcase(){
 return <main className="showcase">
  <nav className="showcaseNav" aria-label="쇼케이스 메뉴">
   <Link className="showcaseBrand" href="/showcase" aria-label="LogiTrack 쇼케이스"><span>LT</span><b>LOGITRACK</b></Link>
   <div><a href="#system">SYSTEM</a><a href="#flow">FLOW</a><Link className="consoleLink" href="/">운영 콘솔 열기 ↗</Link></div>
  </nav>
  <section className="showcaseHero" aria-labelledby="showcase-title">
   <div className="heroCopy">
    <p className="showcaseEyebrow"><i/> LIVE LOGISTICS INTELLIGENCE</p>
    <h1 id="showcase-title"><span>물류의 모든 순간을</span><br/><em>하나의 흐름</em>으로.</h1>
    <p className="heroLead">주문부터 창고, 배차, 실시간 운송, 이상 감지와 복구까지.<br/>LogiTrack은 흩어진 운영 신호를 실행 가능한 한 화면으로 연결합니다.</p>
    <div className="heroActions"><Link href="/">실시간 관제 체험하기 <span>→</span></Link><a href="#system">시스템 살펴보기</a></div>
    <dl className="heroMetrics"><div><dt>99.9<small>%</small></dt><dd>목표 가용성</dd></div><div><dt>&lt; 3<small>s</small></dt><dd>이벤트 가시화</dd></div><div><dt>360<small>°</small></dt><dd>운영 추적성</dd></div></dl>
   </div>
   <div className="simulator" aria-label="가상 물류 관제 시뮬레이터">
    <div className="simHeader"><div><i/><span>SEOUL CONTROL TOWER</span></div><time>LIVE · 14:32:08</time></div>
    <div className="simMap">
     <svg viewBox="0 0 760 510" role="img" aria-label="서울과 인천 사이의 세 배송 차량 운행 경로">
      <defs><pattern id="grid" width="38" height="38" patternUnits="userSpaceOnUse"><path d="M38 0H0V38" fill="none" stroke="currentColor" strokeOpacity=".08"/></pattern><filter id="glow"><feGaussianBlur stdDeviation="4" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
      <rect width="760" height="510" fill="url(#grid)"/>
      <path className="mapRoad faint" d="M18 98C184 54 255 128 376 100S590 28 742 90M8 352c118-54 230 30 342-19s202-91 402-52M125 8c23 116-12 203 53 304s124 131 138 198M578 0c-68 124 16 225-55 330s-28 139-9 180"/>
      <path className="mapRoad" d="M92 410C201 346 196 255 313 239s174-110 349-132"/>
      <path className="mapRoad active" d="M92 410C201 346 196 255 313 239s174-110 349-132"/>
      <circle className="hub" cx="92" cy="410" r="10"/><circle className="hub" cx="662" cy="107" r="10"/>
      <text x="70" y="448">INCHEON DC</text><text x="622" y="82">SEOUL HUB</text>
      {vehicles.map(v=><g key={v.id} className={`vehicle ${v.state==="주의"?"warn":""}`} transform={`translate(${v.x*7.6} ${v.y*5.1})`}><circle r="19"/><path d="M-8-5h11v9H-8zm11 3h6l4 5v6H3z"/><circle cx="-3" cy="10" r="3"/><circle cx="9" cy="10" r="3"/><text x="-25" y="-29">{v.id}</text></g>)}
     </svg>
     <div className="scanLine"/>
     <div className="mapPulse"><span>3</span>대 운송 중</div>
    </div>
    <div className="simRows">{vehicles.map(v=><div key={v.id}><span className={v.state==="주의"?"warn":""}><i/>{v.state}</span><b>{v.id}</b><div className="miniTrack"><i style={{width:v.progress}}/></div><strong>{v.progress}</strong><small>지연 {v.delay}</small></div>)}</div>
   </div>
  </section>
  <section className="systemStrip" id="system" aria-label="LogiTrack 핵심 기능">
   <article><span>01</span><div><b>ORDER → DELIVERY</b><h2>주문과 운송의 연결</h2><p>멱등 주문 접수와 배차를 하나의 추적 가능한 흐름으로 관리합니다.</p></div></article>
   <article><span>02</span><div><b>WAREHOUSE → ROAD</b><h2>재고와 현장의 동기화</h2><p>입출고 원장과 차량 위치를 실시간 이벤트로 일관되게 연결합니다.</p></div></article>
   <article><span>03</span><div><b>DETECT → RECOVER</b><h2>문제를 놓치지 않는 운영</h2><p>지연·경로 이탈을 감지하고 감사 가능한 복구 절차까지 제공합니다.</p></div></article>
  </section>
  <section className="flowSection" id="flow"><p>ONE EVENT STREAM · ONE OPERATIONAL TRUTH</p><div><span>주문</span><i>→</i><span>창고</span><i>→</i><span>배차</span><i>→</i><span>운송</span><i>→</i><span>분석</span><i>→</i><span>복구</span></div></section>
 </main>
}
