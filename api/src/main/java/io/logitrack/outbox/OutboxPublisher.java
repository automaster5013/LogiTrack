package io.logitrack.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.util.concurrent.TimeUnit;

@Component
public class OutboxPublisher {
    private final OutboxRepository repository; private final KafkaTemplate<Object,Object> kafka; private final MeterRegistry metrics;
    public OutboxPublisher(OutboxRepository repository,KafkaTemplate<Object,Object> kafka,MeterRegistry metrics){this.repository=repository;this.kafka=kafka;this.metrics=metrics;}

    @Scheduled(fixedDelayString="${logitrack.outbox.poll-delay-ms:250}")
    @Transactional
    public void publishPending(){
        for(var event:repository.lockPendingBatch()){
            try{
                kafka.send(event.getTopic(),event.getEventKey(),event.getPayload()).get(10, TimeUnit.SECONDS);
                event.published(); metrics.counter("logitrack.outbox.published","event_type",event.getTopic()).increment();
            }catch(Exception error){
                event.failed(error); metrics.counter("logitrack.outbox.failures","event_type",event.getTopic()).increment();
            }
        }
    }
}

