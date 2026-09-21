package io.logitrack.report;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import org.mockito.ArgumentCaptor;

class DailyKpiServiceTest {
    @Test void rejectsOutOfRangeReportRequest(){var service=new DailyKpiService(mock(org.springframework.jdbc.core.JdbcTemplate.class));assertThrows(IllegalArgumentException.class,()->service.getDailyKpis(0));assertThrows(IllegalArgumentException.class,()->service.getDailyKpis(91));}
    @Test void readsReportsWithoutRefreshingProjection(){
        var jdbc=mock(org.springframework.jdbc.core.JdbcTemplate.class);var service=new DailyKpiService(jdbc);
        service.getDailyKpis(14);
        verify(jdbc).query(anyString(),any(org.springframework.jdbc.core.RowMapper.class),eq(14));
        verify(jdbc,never()).update(anyString(),any(Object[].class));
    }
    @Test void scheduledRefreshCoversTheFullPublicReportRange(){
        var jdbc=mock(org.springframework.jdbc.core.JdbcTemplate.class);var service=new DailyKpiService(jdbc);
        service.refreshProjection();
        var sql=ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(),eq(90),eq(90));
        assertThat(sql.getValue()).contains("d.created_at >=", "LEFT JOIN LATERAL", "WHERE delivery_id = d.id");
        assertThat(sql.getValue()).doesNotContain("DISTINCT ON (delivery_id)");
    }
    @Test
    void rendersStableUtf8CsvReport() {
        var service = new DailyKpiService(mock(org.springframework.jdbc.core.JdbcTemplate.class));
        var kpi = new DailyDeliveryKpi(LocalDate.of(2026, 9, 19), 12, 5, 7, 1,
            72.5, 48.25, 85.71, Instant.parse("2026-09-19T01:00:00Z"));

        var csv = new String(service.toCsv(List.of(kpi)), StandardCharsets.UTF_8);

        assertThat(csv).startsWith("date,total,active,delivered,delayed");
        assertThat(csv).contains("2026-09-19,12,5,7,1,72.50,48.25,85.71,2026-09-19T01:00:00Z");
    }
}
