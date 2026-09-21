package io.logitrack.report;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class DailyKpiProjectionInitializerTest {
    @Test
    void refreshesTheProjectionBeforeStartupCompletes() throws Exception {
        var service = mock(DailyKpiService.class);
        var initializer = new DailyKpiProjectionInitializer(service);

        initializer.run(mock(ApplicationArguments.class));

        verify(service).refreshScheduledProjection();
    }
}
