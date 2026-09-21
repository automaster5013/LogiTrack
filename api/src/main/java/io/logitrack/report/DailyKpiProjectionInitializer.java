package io.logitrack.report;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class DailyKpiProjectionInitializer implements ApplicationRunner {
    private final DailyKpiService dailyKpiService;

    public DailyKpiProjectionInitializer(DailyKpiService dailyKpiService) {
        this.dailyKpiService = dailyKpiService;
    }

    @Override
    public void run(ApplicationArguments args) {
        dailyKpiService.refreshScheduledProjection();
    }
}
