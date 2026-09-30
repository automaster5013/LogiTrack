package io.logitrack.report;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Counter;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.concurrent.atomic.AtomicLong;

@Component
@ConditionalOnProperty(prefix = "logitrack.reports", name = "writer-enabled", havingValue = "true", matchIfMissing = true)
public class DailyKpiProjectionInitializer implements ApplicationRunner {
    private final DailyKpiService dailyKpiService;
    private final AtomicLong lastSuccessEpochSeconds = new AtomicLong();
    private final Counter lockSkipped;

    public DailyKpiProjectionInitializer(
        DailyKpiService dailyKpiService,
        MeterRegistry metrics,
        @Value("${logitrack.reports.refresh-ms:60000}") long refreshMs
    ) {
        this.dailyKpiService = dailyKpiService;
        Gauge.builder("logitrack.kpi.projection.last.success.timestamp.seconds", lastSuccessEpochSeconds, AtomicLong::doubleValue)
            .description("Unix timestamp of the last successful daily KPI projection refresh")
            .register(metrics);
        Gauge.builder("logitrack.kpi.projection.refresh.interval.seconds", () -> refreshMs / 1_000.0)
            .description("Configured daily KPI projection refresh interval")
            .register(metrics);
        lockSkipped = Counter.builder("logitrack.kpi.projection.refresh.skipped")
            .description("KPI projection refreshes skipped because another replica holds the database lock")
            .register(metrics);
    }

    @Override
    public void run(ApplicationArguments args) {
        refreshIfLeader();
    }

    @Scheduled(
        initialDelayString = "${logitrack.reports.refresh-ms:60000}",
        fixedDelayString = "${logitrack.reports.refresh-ms:60000}"
    )
    public void refreshScheduledProjection() {
        refreshIfLeader();
    }

    private void refreshIfLeader() {
        if (dailyKpiService.refreshProjection()) {
            recordSuccess();
        } else {
            lockSkipped.increment();
        }
    }

    private void recordSuccess() {
        lastSuccessEpochSeconds.set(Instant.now().getEpochSecond());
    }
}
