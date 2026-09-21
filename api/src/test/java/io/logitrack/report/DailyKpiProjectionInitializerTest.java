package io.logitrack.report;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import static org.assertj.core.api.Assertions.assertThat;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class DailyKpiProjectionInitializerTest {
    @Test
    void refreshesTheProjectionBeforeStartupCompletes() throws Exception {
        var service = mock(DailyKpiService.class);
        var metrics = new SimpleMeterRegistry();
        var initializer = new DailyKpiProjectionInitializer(service, metrics, 60_000);

        initializer.run(mock(ApplicationArguments.class));

        verify(service).refreshProjection();
        assertThat(metrics.get("logitrack.kpi.projection.last.success.timestamp.seconds").gauge().value()).isPositive();
        assertThat(metrics.get("logitrack.kpi.projection.refresh.interval.seconds").gauge().value()).isEqualTo(60);
    }

    @Test
    void refreshesPeriodicallyOnlyAfterOneFullInterval() throws Exception {
        var service = mock(DailyKpiService.class);
        var initializer = new DailyKpiProjectionInitializer(service, new SimpleMeterRegistry(), 60_000);

        initializer.refreshScheduledProjection();

        verify(service).refreshProjection();
        var scheduled = DailyKpiProjectionInitializer.class
            .getDeclaredMethod("refreshScheduledProjection").getAnnotation(Scheduled.class);
        assertThat(scheduled.initialDelayString()).isEqualTo("${logitrack.reports.refresh-ms:60000}");
        assertThat(scheduled.fixedDelayString()).isEqualTo("${logitrack.reports.refresh-ms:60000}");
    }

    @Test
    void isDisabledWhenThisApiInstanceIsNotTheProjectionWriter() {
        var condition = DailyKpiProjectionInitializer.class.getAnnotation(ConditionalOnProperty.class);

        assertThat(condition.prefix()).isEqualTo("logitrack.reports");
        assertThat(condition.name()).containsExactly("writer-enabled");
        assertThat(condition.havingValue()).isEqualTo("true");
        assertThat(condition.matchIfMissing()).isTrue();
    }
}
