import type { DailyDeliveryKpi } from "../types";

type Props = { rows: DailyDeliveryKpi[]; csvUrl: string; pdfUrl: string };

const number = new Intl.NumberFormat("ko-KR", { maximumFractionDigits: 0 });

export default function DailyKpiPanel({ rows, csvUrl, pdfUrl }: Props) {
  const latest = rows.at(-1);
  const maxTotal = Math.max(1, ...rows.map((row) => row.totalDeliveries));

  return <section className="kpiBoard">
    <div className="kpiHeader">
      <div><p className="eyebrow">REPORTING / UTC DAILY COHORT</p><h2>Delivery performance</h2></div>
      <div className="kpiDownloads"><a href={pdfUrl} download>DOWNLOAD PDF ↓</a><a href={csvUrl} download>CSV</a></div>
    </div>
    <div className="kpiSummary">
      <div><span>TODAY&apos;S VOLUME</span><strong>{number.format(latest?.totalDeliveries ?? 0)}</strong><small>{latest?.activeDeliveries ?? 0} active</small></div>
      <div><span>DELIVERED</span><strong>{number.format(latest?.deliveredDeliveries ?? 0)}</strong><small>created today</small></div>
      <div><span>ON-TIME RATE</span><strong>{latest ? latest.onTimeRatePercent.toFixed(1) : "0.0"}%</strong><small>vs first planned ETA</small></div>
      <div><span>AVG. CYCLE</span><strong>{latest ? latest.averageCycleMinutes.toFixed(0) : "0"}<i>m</i></strong><small>completed deliveries</small></div>
    </div>
    <div className="kpiChart" role="img" aria-label="최근 14일 일별 배송량과 완료 배송량 차트. 작은 화면에서는 가로로 스크롤할 수 있습니다." tabIndex={0}>
      {rows.map((row) => {
        const totalHeight = row.totalDeliveries / maxTotal * 100;
        const deliveredHeight = row.totalDeliveries ? row.deliveredDeliveries / row.totalDeliveries * 100 : 0;
        const date = new Date(`${row.metricDate}T00:00:00Z`);
        const label = `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
        return <div className="kpiDay" key={row.metricDate} title={`${row.metricDate}: ${row.totalDeliveries} total, ${row.deliveredDeliveries} delivered, ${row.delayedDeliveries} delayed`}>
          <div className="kpiBarTrack">
            <div className="kpiTotal" style={{height: `${Math.max(totalHeight, row.totalDeliveries ? 4 : 0)}%`}}>
              <i style={{height: `${deliveredHeight}%`}} />
              {row.delayedDeliveries > 0 && <b aria-label={`${row.delayedDeliveries} delayed`} />}
            </div>
          </div>
          <span>{label}</span>
        </div>;
      })}
      {!rows.length && <p className="kpiEmpty">KPI projection을 준비하고 있습니다.</p>}
    </div>
    <div className="kpiLegend"><span><i className="total"/>TOTAL</span><span><i className="done"/>DELIVERED</span><span><i className="late"/>DELAYED</span><small>Projection refreshes every 60 seconds</small></div>
  </section>;
}
