package io.logitrack.report;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Locale;

@Service
public class DailyKpiService {
    private static final int MAX_DAYS = 90;
    private final JdbcTemplate jdbc;

    public DailyKpiService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Scheduled(fixedDelayString = "${logitrack.reports.refresh-ms:60000}")
    @Transactional
    public void refreshScheduledProjection() {
        refresh(MAX_DAYS);
    }

    @Transactional(readOnly = true)
    public List<DailyDeliveryKpi> getDailyKpis(int requestedDays) {
        int days = boundedDays(requestedDays);
        return jdbc.query("""
            SELECT metric_date, total_deliveries, active_deliveries, delivered_deliveries,
                   delayed_deliveries, average_progress_percent, average_cycle_minutes,
                   on_time_rate_percent, projected_at
            FROM delivery_daily_kpis
            WHERE metric_date >= ((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date - (? - 1))
            ORDER BY metric_date
            """, (rs, row) -> new DailyDeliveryKpi(
                rs.getObject("metric_date", LocalDate.class),
                rs.getLong("total_deliveries"),
                rs.getLong("active_deliveries"),
                rs.getLong("delivered_deliveries"),
                rs.getLong("delayed_deliveries"),
                rs.getDouble("average_progress_percent"),
                rs.getDouble("average_cycle_minutes"),
                rs.getDouble("on_time_rate_percent"),
                rs.getObject("projected_at", Timestamp.class).toInstant()
            ), days);
    }

    byte[] toCsv(List<DailyDeliveryKpi> rows) {
        var csv = new StringBuilder("date,total,active,delivered,delayed,average_progress_percent,average_cycle_minutes,on_time_rate_percent,projected_at\r\n");
        rows.forEach(kpi -> csv.append(String.format(Locale.ROOT,
            "%s,%d,%d,%d,%d,%.2f,%.2f,%.2f,%s\r\n",
            kpi.metricDate(), kpi.totalDeliveries(), kpi.activeDeliveries(),
            kpi.deliveredDeliveries(), kpi.delayedDeliveries(),
            kpi.averageProgressPercent(), kpi.averageCycleMinutes(),
            kpi.onTimeRatePercent(), kpi.projectedAt())));
        return csv.toString().getBytes(StandardCharsets.UTF_8);
    }

    private void refresh(int days) {
        jdbc.update("""
            WITH calendar AS (
              SELECT generate_series(
                (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date - (? - 1),
                (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date,
                interval '1 day'
              )::date AS metric_date
            ), first_route AS (
              SELECT DISTINCT ON (delivery_id) delivery_id, planned_eta
              FROM route_snapshots
              ORDER BY delivery_id, generated_at ASC
            ), projection AS (
              SELECT c.metric_date,
                     COUNT(d.id)::bigint AS total_deliveries,
                     COUNT(d.id) FILTER (WHERE d.status <> 'DELIVERED')::bigint AS active_deliveries,
                     COUNT(d.id) FILTER (WHERE d.status = 'DELIVERED')::bigint AS delivered_deliveries,
                     COUNT(d.id) FILTER (WHERE d.status = 'DELAYED')::bigint AS delayed_deliveries,
                     COALESCE(AVG(d.progress) * 100, 0)::double precision AS average_progress_percent,
                     COALESCE(AVG(EXTRACT(EPOCH FROM (d.updated_at - d.created_at)) / 60)
                       FILTER (WHERE d.status = 'DELIVERED'), 0)::double precision AS average_cycle_minutes,
                     COALESCE(100.0 * COUNT(d.id) FILTER (
                       WHERE d.status = 'DELIVERED' AND r.planned_eta IS NOT NULL AND d.updated_at <= r.planned_eta
                     ) / NULLIF(COUNT(d.id) FILTER (WHERE d.status = 'DELIVERED' AND r.planned_eta IS NOT NULL), 0), 0)::double precision AS on_time_rate_percent
              FROM calendar c
              LEFT JOIN deliveries d ON (d.created_at AT TIME ZONE 'UTC')::date = c.metric_date
              LEFT JOIN first_route r ON r.delivery_id = d.id
              GROUP BY c.metric_date
            )
            INSERT INTO delivery_daily_kpis (
              metric_date, total_deliveries, active_deliveries, delivered_deliveries,
              delayed_deliveries, average_progress_percent, average_cycle_minutes,
              on_time_rate_percent, projected_at
            )
            SELECT metric_date, total_deliveries, active_deliveries, delivered_deliveries,
                   delayed_deliveries, average_progress_percent, average_cycle_minutes,
                   on_time_rate_percent, CURRENT_TIMESTAMP
            FROM projection
            ON CONFLICT (metric_date) DO UPDATE SET
              total_deliveries = EXCLUDED.total_deliveries,
              active_deliveries = EXCLUDED.active_deliveries,
              delivered_deliveries = EXCLUDED.delivered_deliveries,
              delayed_deliveries = EXCLUDED.delayed_deliveries,
              average_progress_percent = EXCLUDED.average_progress_percent,
              average_cycle_minutes = EXCLUDED.average_cycle_minutes,
              on_time_rate_percent = EXCLUDED.on_time_rate_percent,
              projected_at = EXCLUDED.projected_at
            """, days);
    }

    private static int boundedDays(int days) {
        if(days<1||days>MAX_DAYS)throw new IllegalArgumentException("days must be between 1 and 90");
        return days;
    }
}
