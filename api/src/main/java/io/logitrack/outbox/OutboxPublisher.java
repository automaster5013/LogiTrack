package io.logitrack.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.beans.factory.annotation.Value;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Component
public class OutboxPublisher {
    private final OutboxRepository repository; private final KafkaTemplate<Object,Object> kafka; private final MeterRegistry metrics;
    private final int batchSize;private final long publishTimeoutMillis;
    public OutboxPublisher(OutboxRepository repository,KafkaTemplate<Object,Object> kafka,MeterRegistry metrics,
        @Value("${logitrack.outbox.batch-size:20}") int batchSize,@Value("${logitrack.outbox.publish-timeout:5s}") Duration publishTimeout){if(batchSize<1||batchSize>100)throw new IllegalArgumentException("Outbox batch size must be between 1 and 100");if(publishTimeout.isZero()||publishTimeout.isNegative()||publishTimeout.compareTo(Duration.ofSeconds(30))>0)throw new IllegalArgumentException("Outbox publish timeout must be positive and at most 30 seconds");this.repository=repository;this.kafka=kafka;this.metrics=metrics;this.batchSize=batchSize;this.publishTimeoutMillis=publishTimeout.toMillis();}

    @Scheduled(fixedDelayString="${logitrack.outbox.poll-delay-ms:250}")
    @Transactional
    public void publishPending(){
        for(var event:repository.lockPendingBatch(batchSize)){
            try{
                kafka.send(event.getTopic(),event.getEventKey(),event.getPayload()).get(publishTimeoutMillis,TimeUnit.MILLISECONDS);
                event.published(); metrics.counter("logitrack.outbox.published","event_type",event.getTopic()).increment();
            }catch(Exception error){
                event.failed(error); metrics.counter("logitrack.outbox.failures","event_type",event.getTopic()).increment();
            }
        }
    }
}
