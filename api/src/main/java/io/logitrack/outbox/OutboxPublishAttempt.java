package io.logitrack.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import java.util.concurrent.TimeUnit;

@Component
public class OutboxPublishAttempt {
    private final OutboxRepository repository;
    private final KafkaTemplate<Object,Object> kafka;
    private final MeterRegistry metrics;

    public OutboxPublishAttempt(OutboxRepository repository,KafkaTemplate<Object,Object> kafka,MeterRegistry metrics){
        this.repository=repository;this.kafka=kafka;this.metrics=metrics;
    }

    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public boolean publishNext(long timeoutMillis){
        var candidate=repository.lockNextPending();
        if(candidate.isEmpty())return false;
        var event=candidate.get();
        try{
            kafka.send(event.getTopic(),event.getEventKey(),event.getPayload()).get(timeoutMillis,TimeUnit.MILLISECONDS);
            event.published();metrics.counter("logitrack.outbox.published","event_type",event.getTopic()).increment();
        }catch(Exception error){
            if(error instanceof InterruptedException)Thread.currentThread().interrupt();
            event.failed(error);metrics.counter("logitrack.outbox.failures","event_type",event.getTopic()).increment();
        }
        return true;
    }
}
