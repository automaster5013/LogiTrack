package io.logitrack.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Value;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicBoolean;

@Component
public class OutboxPublisher {
    private static final Logger log=LoggerFactory.getLogger(OutboxPublisher.class);
    private final OutboxPublishAttempt attempt;
    private final MeterRegistry metrics;
    private final int batchSize;private final long publishTimeoutMillis;
    private final AtomicBoolean publisherHealthy=new AtomicBoolean(true);
    public OutboxPublisher(OutboxPublishAttempt attempt,MeterRegistry metrics,
        @Value("${logitrack.outbox.batch-size:20}") int batchSize,@Value("${logitrack.outbox.publish-timeout:5s}") Duration publishTimeout){if(batchSize<1||batchSize>100)throw new IllegalArgumentException("Outbox batch size must be between 1 and 100");if(publishTimeout.isZero()||publishTimeout.isNegative()||publishTimeout.compareTo(Duration.ofSeconds(30))>0)throw new IllegalArgumentException("Outbox publish timeout must be positive and at most 30 seconds");this.attempt=attempt;this.metrics=metrics;this.batchSize=batchSize;this.publishTimeoutMillis=publishTimeout.toMillis();metrics.counter("logitrack.outbox.publish.failures");}

    @Scheduled(fixedDelayString="${logitrack.outbox.poll-delay-ms:250}")
    public void publishPending(){
        try {
            for(var index=0;index<batchSize;index++)if(!attempt.publishNext(publishTimeoutMillis))break;
            if(!publisherHealthy.getAndSet(true))log.info("Outbox publisher recovered");
        } catch(RuntimeException error){
            metrics.counter("logitrack.outbox.publish.failures").increment();
            if(publisherHealthy.getAndSet(false))log.warn("Outbox publisher failed; scheduled retries will continue: {}",error.toString());
        }
    }
}
