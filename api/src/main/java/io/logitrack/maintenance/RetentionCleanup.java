package io.logitrack.maintenance;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.time.Duration;
import java.time.Instant;

@Component
public class RetentionCleanup {
    private static final Duration MIN_RETENTION=Duration.ofDays(1);
    private final RetentionCleanupAttempt attempt;
    private final MeterRegistry metrics;
    private final Duration processedRetention;
    private final Duration outboxRetention;
    private final Duration telemetryRetention;
    private final int batchSize;

    public RetentionCleanup(RetentionCleanupAttempt attempt,MeterRegistry metrics,
        @Value("${logitrack.retention.processed-events:30d}") Duration processedRetention,
        @Value("${logitrack.retention.published-outbox:7d}") Duration outboxRetention,
        @Value("${logitrack.retention.telemetry:30d}") Duration telemetryRetention,
        @Value("${logitrack.retention.batch-size:1000}") int batchSize){
        validate(processedRetention,"Processed-event");validate(outboxRetention,"Published-outbox");validate(telemetryRetention,"Telemetry");
        if(batchSize<1||batchSize>10_000)throw new IllegalArgumentException("Retention batch size must be between 1 and 10000");
        this.attempt=attempt;this.metrics=metrics;this.processedRetention=processedRetention;this.outboxRetention=outboxRetention;this.telemetryRetention=telemetryRetention;this.batchSize=batchSize;
        for(var table:new String[]{"processed_events","outbox_events","telemetry_points"})metrics.counter("logitrack.retention.deleted","table",table);
        metrics.counter("logitrack.retention.failures");
    }

    @Scheduled(initialDelayString="${logitrack.retention.initial-delay-ms:60000}",fixedDelayString="${logitrack.retention.poll-delay-ms:300000}")
    public void cleanup(){
        var now=Instant.now();
        try {
            var result=attempt.cleanup(now.minus(processedRetention),now.minus(outboxRetention),now.minus(telemetryRetention),batchSize);
            record("processed_events",result.processedEvents());
            record("outbox_events",result.outboxEvents());
            record("telemetry_points",result.telemetryPoints());
        } catch(RuntimeException error){metrics.counter("logitrack.retention.failures").increment();throw error;}
    }
    private void record(String table,int count){metrics.counter("logitrack.retention.deleted","table",table).increment(count);}
    private static void validate(Duration value,String name){if(value.compareTo(MIN_RETENTION)<0)throw new IllegalArgumentException(name+" retention must be at least one day");}
}
