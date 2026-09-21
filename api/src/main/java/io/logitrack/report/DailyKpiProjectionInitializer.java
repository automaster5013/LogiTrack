package io.logitrack.report;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "logitrack.reports", name = "writer-enabled", havingValue = "true", matchIfMissing = true)
public class DailyKpiProjectionInitializer implements ApplicationRunner {
    private final DailyKpiService dailyKpiService;

    public DailyKpiProjectionInitializer(DailyKpiService dailyKpiService) {
        this.dailyKpiService = dailyKpiService;
    }

    @Override
    public void run(ApplicationArguments args) {
        dailyKpiService.refreshProjection();
    }

    @Scheduled(
        initialDelayString = "${logitrack.reports.refresh-ms:60000}",
        fixedDelayString = "${logitrack.reports.refresh-ms:60000}"
    )
    public void refreshScheduledProjection() {
        dailyKpiService.refreshProjection();
    }
}
