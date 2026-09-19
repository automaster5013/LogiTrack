package io.logitrack.report;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.util.unit.DataSize;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.List;

@Component
public class DailyKpiReportClient {
    private final RestClient client;
    private final long maxResponseBytes;

    public DailyKpiReportClient(RestClient.Builder builder,
                                @Value("${logitrack.analytics.url}") String analyticsUrl,
                                @Value("${logitrack.analytics.report-connect-timeout:1s}") Duration connectTimeout,
                                @Value("${logitrack.analytics.report-read-timeout:15s}") Duration readTimeout,
                                @Value("${logitrack.analytics.report-max-response-size:10MB}") DataSize maxResponseSize) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(connectTimeout);
        requestFactory.setReadTimeout(readTimeout);
        this.client = builder.baseUrl(analyticsUrl).requestFactory(requestFactory).build();
        this.maxResponseBytes = maxResponseSize.toBytes();
    }

    public byte[] render(List<DailyDeliveryKpi> rows) {
        var body = client.post()
            .uri("/reports/daily-kpis.pdf")
            .body(rows)
            .retrieve()
            .body(byte[].class);
        if (body == null || body.length < 5 || body.length > maxResponseBytes || body[0] != '%' || body[1] != 'P' || body[2] != 'D' || body[3] != 'F') {
            throw new IllegalStateException("Analytics service returned an invalid KPI PDF");
        }
        return body;
    }
}
