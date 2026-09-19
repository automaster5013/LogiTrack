package io.logitrack.report;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/reports")
public class ReportController {
    private final DailyKpiService service;

    public ReportController(DailyKpiService service) {
        this.service = service;
    }

    @GetMapping("/daily-kpis")
    public List<DailyDeliveryKpi> dailyKpis(@RequestParam(defaultValue = "14") int days) {
        return service.getDailyKpis(days);
    }

    @GetMapping(value = "/daily-kpis.csv", produces = "text/csv")
    public ResponseEntity<byte[]> dailyKpisCsv(@RequestParam(defaultValue = "30") int days) {
        var body = service.toCsv(service.getDailyKpis(days));
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=logitrack-daily-kpis.csv")
            .contentType(new MediaType("text", "csv", java.nio.charset.StandardCharsets.UTF_8))
            .body(body);
    }
}

