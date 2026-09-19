package io.logitrack.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SchedulingLimits {
    public SchedulingLimits(
        @Value("${logitrack.outbox.poll-delay-ms:250}") long outboxPollMs,
        @Value("${logitrack.metrics.recovery-refresh-ms:10000}") long recoveryRefreshMs,
        @Value("${logitrack.reports.refresh-ms:60000}") long reportRefreshMs,
        @Value("${logitrack.retention.initial-delay-ms:60000}") long retentionInitialDelayMs,
        @Value("${logitrack.retention.poll-delay-ms:300000}") long retentionPollMs){
        range(outboxPollMs,50,60_000,"Outbox poll delay");
        range(recoveryRefreshMs,1_000,300_000,"Recovery metric refresh");
        range(reportRefreshMs,1_000,3_600_000,"Report refresh");
        range(retentionInitialDelayMs,0,86_400_000,"Retention initial delay");
        range(retentionPollMs,1_000,86_400_000,"Retention poll delay");
    }
    private static void range(long value,long min,long max,String name){if(value<min||value>max)throw new IllegalArgumentException(name+" must be between "+min+" and "+max+" milliseconds");}
}
