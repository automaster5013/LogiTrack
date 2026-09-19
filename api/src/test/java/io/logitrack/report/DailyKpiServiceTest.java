package io.logitrack.report;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;

class DailyKpiServiceTest {
    @Test void rejectsOutOfRangeProjectionConfiguration(){var jdbc=mock(org.springframework.jdbc.core.JdbcTemplate.class);assertThrows(IllegalArgumentException.class,()->new DailyKpiService(jdbc,0));assertThrows(IllegalArgumentException.class,()->new DailyKpiService(jdbc,91));}

    @Test void rejectsOutOfRangeReportRequest(){var service=new DailyKpiService(mock(org.springframework.jdbc.core.JdbcTemplate.class),30);assertThrows(IllegalArgumentException.class,()->service.getDailyKpis(0));assertThrows(IllegalArgumentException.class,()->service.getDailyKpis(91));}
    @Test
    void rendersStableUtf8CsvReport() {
        var service = new DailyKpiService(mock(org.springframework.jdbc.core.JdbcTemplate.class), 30);
        var kpi = new DailyDeliveryKpi(LocalDate.of(2026, 9, 19), 12, 5, 7, 1,
            72.5, 48.25, 85.71, Instant.parse("2026-09-19T01:00:00Z"));

        var csv = new String(service.toCsv(List.of(kpi)), StandardCharsets.UTF_8);

        assertThat(csv).startsWith("date,total,active,delivered,delayed");
        assertThat(csv).contains("2026-09-19,12,5,7,1,72.50,48.25,85.71,2026-09-19T01:00:00Z");
    }
}
