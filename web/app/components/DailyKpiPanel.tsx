import type { DailyDeliveryKpi } from "../types";

type Props = { rows: DailyDeliveryKpi[]; csvUrl: string; pdfUrl: string };

const number = new Intl.NumberFormat("ko-KR", { maximumFractionDigits: 0 });

export default function DailyKpiPanel({ rows, csvUrl, pdfUrl }: Props) {
  const latest = rows.at(-1);
  const maxTotal = Math.max(1, ...rows.map((row) => row.totalDeliveries));
  const reportDate = latest ? latest.metricDate.replaceAll("-", ".") : "집계 대기";

  return <section className="kpiBoard">
    <div className="kpiHeader">
      <div><p className="eyebrow">{reportDate} / UTC 기준</p><h2>배송 성과</h2></div>
      <div className="kpiDownloads"><a href={pdfUrl} download aria-label="배송 성과 PDF 내려받기">PDF 내려받기 ↓</a><a href={csvUrl} download aria-label="배송 성과 CSV 내려받기">CSV</a></div>
    </div>
    <div className="kpiSummary">
      <div><span>오늘 접수</span><strong>{number.format(latest?.totalDeliveries ?? 0)}</strong><small>오늘 접수분 중 진행 {latest?.activeDeliveries ?? 0}건</small></div>
      <div><span>배송 완료</span><strong>{number.format(latest?.deliveredDeliveries ?? 0)}</strong><small>오늘 접수분 기준</small></div>
      <div><span>정시 배송률</span><strong>{latest ? latest.onTimeRatePercent.toFixed(1) : "0.0"}%</strong><small>최초 예정 시각 기준</small></div>
      <div><span>평균 소요 시간</span><strong>{latest ? latest.averageCycleMinutes.toFixed(0) : "0"}<i>분</i></strong><small>완료 배송 기준</small></div>
    </div>
    <div className="kpiChart" role="img" aria-label="최근 14일 일별 배송량과 완료 배송량 차트. 작은 화면에서는 가로로 스크롤할 수 있습니다." tabIndex={0}>
      {rows.map((row) => {
        const totalHeight = row.totalDeliveries / maxTotal * 100;
        const deliveredHeight = row.totalDeliveries ? row.deliveredDeliveries / row.totalDeliveries * 100 : 0;
        const date = new Date(`${row.metricDate}T00:00:00Z`);
        const label = `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
        return <div className="kpiDay" key={row.metricDate} title={`${row.metricDate}: 전체 ${row.totalDeliveries}건, 완료 ${row.deliveredDeliveries}건, 지연 ${row.delayedDeliveries}건`}>
          <div className="kpiBarTrack">
            <div className="kpiTotal" style={{height: `${Math.max(totalHeight, row.totalDeliveries ? 4 : 0)}%`}}>
              <i style={{height: `${deliveredHeight}%`}} />
              {row.delayedDeliveries > 0 && <b aria-label={`지연 ${row.delayedDeliveries}건`} />}
            </div>
          </div>
          <span>{label}</span>
        </div>;
      })}
      {!rows.length && <p className="kpiEmpty">배송 성과 집계를 준비하고 있습니다.</p>}
    </div>
    <div className="kpiLegend"><span><i className="total"/>전체</span><span><i className="done"/>완료</span><span><i className="late"/>지연</span><small>60초마다 갱신</small></div>
  </section>;
}
