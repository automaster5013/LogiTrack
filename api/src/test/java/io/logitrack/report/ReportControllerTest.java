package io.logitrack.report;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ReportControllerTest {
    @Test
    void returnsPdfAttachmentFromPostgresProjectionRows() {
        var service = mock(DailyKpiService.class);
        var client = mock(DailyKpiReportClient.class);
        var rows = List.<DailyDeliveryKpi>of();
        var pdf = "%PDF-1.7 test".getBytes();
        when(service.getDailyKpis(30)).thenReturn(rows);
        when(client.render(rows)).thenReturn(pdf);

        var response = new ReportController(service, client).dailyKpisPdf(30);

        assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
        assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PDF);
        assertThat(response.getHeaders().getContentDisposition().getFilename())
            .isEqualTo("logitrack-daily-kpi-report.pdf");
        assertThat(response.getBody()).isEqualTo(pdf);
    }
}
