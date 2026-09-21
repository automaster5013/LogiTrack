"use client";

import { useEffect, useState } from "react";
import type { DailyDeliveryKpi } from "../types";

type Props = { rows: DailyDeliveryKpi[]; csvUrl: string; pdfUrl: string };

const number = new Intl.NumberFormat("ko-KR", { maximumFractionDigits: 0 });

export default function DailyKpiPanel({ rows, csvUrl, pdfUrl }: Props) {
  const latest = rows.at(-1);
  const [selectedDate, setSelectedDate] = useState<string>();
  useEffect(() => {
    if (rows.length && !rows.some((row) => row.metricDate === selectedDate)) setSelectedDate(rows.at(-1)?.metricDate);
  }, [rows, selectedDate]);
  const selected = rows.find((row) => row.metricDate === selectedDate) ?? latest;
  const maxTotal = Math.max(1, ...rows.map((row) => row.totalDeliveries));
  const reportDate = latest ? latest.metricDate.replaceAll("-", ".") : "집계 대기";

  return <section className="kpiBoard">
    <div className="kpiHeader">
      <div><p className="eyebrow">{reportDate} / UTC 기준</p><h2>배송 성과</h2></div>
      <div className="kpiDownloads"><a href={pdfUrl} download aria-label="배송 성과 PDF 내려받기">PDF 내려받기 ↓</a><a href={csvUrl} download aria-label="배송 성과 CSV 내려받기">CSV</a></div>
    </div>
    <div className="kpiSummary">
      <div><span>당일 접수</span><strong>{number.format(latest?.totalDeliveries ?? 0)}</strong><small>당일 접수분 중 진행 {latest?.activeDeliveries ?? 0}건</small></div>
      <div><span>배송 완료</span><strong>{number.format(latest?.deliveredDeliveries ?? 0)}</strong><small>당일 접수분 기준</small></div>
      <div><span>정시 배송률</span><strong>{latest ? latest.onTimeRatePercent.toFixed(1) : "0.0"}%</strong><small>최초 예정 시각 기준</small></div>
      <div><span>평균 소요 시간</span><strong>{latest ? latest.averageCycleMinutes.toFixed(0) : "0"}<i>분</i></strong><small>완료 배송 기준</small></div>
    </div>
    <div className="kpiChart" role="group" aria-label="최근 14일 일별 배송량과 완료 배송량 차트. 날짜를 선택하면 상세 수치를 확인할 수 있습니다.">
      {rows.map((row) => {
        const totalHeight = row.totalDeliveries / maxTotal * 100;
        const deliveredHeight = row.totalDeliveries ? row.deliveredDeliveries / row.totalDeliveries * 100 : 0;
        const date = new Date(`${row.metricDate}T00:00:00Z`);
        const label = `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
        const detail = `${row.metricDate}: 전체 ${row.totalDeliveries}건, 완료 ${row.deliveredDeliveries}건, 진행 ${row.activeDeliveries}건, 지연 ${row.delayedDeliveries}건, 정시 배송률 ${row.onTimeRatePercent.toFixed(1)}%`;
        return <button type="button" className="kpiDay" key={row.metricDate} title={detail} aria-pressed={selected?.metricDate===row.metricDate} aria-label={detail} onClick={()=>setSelectedDate(row.metricDate)}>
          <span className="kpiBarTrack">
            <div className="kpiTotal" style={{height: `${Math.max(totalHeight, row.totalDeliveries ? 4 : 0)}%`}}>
              <i style={{height: `${deliveredHeight}%`}} />
              {row.delayedDeliveries > 0 && <b aria-label={`지연 ${row.delayedDeliveries}건`} />}
            </div>
          </span>
          <span>{label}</span>
        </button>;
      })}
      {!rows.length && <p className="kpiEmpty">배송 성과 집계를 준비하고 있습니다.</p>}
    </div>
    {selected&&<div className="kpiDetail" aria-live="polite"><strong>{selected.metricDate.replaceAll("-", ".")}</strong><span>전체 {number.format(selected.totalDeliveries)}건</span><span>완료 {number.format(selected.deliveredDeliveries)}건</span><span>진행 {number.format(selected.activeDeliveries)}건</span><span>지연 {number.format(selected.delayedDeliveries)}건</span><span>정시 {selected.onTimeRatePercent.toFixed(1)}%</span></div>}
    <div className="kpiLegend"><span><i className="total"/>전체</span><span><i className="done"/>완료</span><span><i className="late"/>지연</span><small>{latest?<><time dateTime={latest.projectedAt}>집계 {new Date(latest.projectedAt).toLocaleString("ko-KR")}</time> · 60초마다 갱신</>:"집계 대기"}</small></div>
  </section>;
}
