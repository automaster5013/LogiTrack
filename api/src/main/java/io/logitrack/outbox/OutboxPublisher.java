package io.logitrack.outbox;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Value;
import java.time.Duration;

@Component
public class OutboxPublisher {
    private final OutboxPublishAttempt attempt;
    private final int batchSize;private final long publishTimeoutMillis;
    public OutboxPublisher(OutboxPublishAttempt attempt,
        @Value("${logitrack.outbox.batch-size:20}") int batchSize,@Value("${logitrack.outbox.publish-timeout:5s}") Duration publishTimeout){if(batchSize<1||batchSize>100)throw new IllegalArgumentException("Outbox batch size must be between 1 and 100");if(publishTimeout.isZero()||publishTimeout.isNegative()||publishTimeout.compareTo(Duration.ofSeconds(30))>0)throw new IllegalArgumentException("Outbox publish timeout must be positive and at most 30 seconds");this.attempt=attempt;this.batchSize=batchSize;this.publishTimeoutMillis=publishTimeout.toMillis();}

    @Scheduled(fixedDelayString="${logitrack.outbox.poll-delay-ms:250}")
    public void publishPending(){
        for(var index=0;index<batchSize;index++)if(!attempt.publishNext(publishTimeoutMillis))break;
    }
}
