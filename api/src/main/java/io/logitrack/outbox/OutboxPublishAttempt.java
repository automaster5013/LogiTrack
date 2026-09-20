package io.logitrack.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.tracing.Span;
import io.micrometer.tracing.Tracer;
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
    private final Tracer tracer;

    public OutboxPublishAttempt(OutboxRepository repository,KafkaTemplate<Object,Object> kafka,MeterRegistry metrics,Tracer tracer){
        this.repository=repository;this.kafka=kafka;this.metrics=metrics;this.tracer=tracer;
    }

    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public boolean publishNext(long timeoutMillis){
        var candidate=repository.lockNextPending();
        if(candidate.isEmpty())return false;
        var event=candidate.get();
        Span publishSpan=null;
        try{
            if(event.hasOriginTraceContext()){
                var parent=tracer.traceContextBuilder().traceId(event.getOriginTraceId()).spanId(event.getOriginSpanId())
                    .sampled(event.getOriginTraceSampled()).build();
                publishSpan=tracer.spanBuilder().setParent(parent).name("outbox publish").kind(Span.Kind.PRODUCER)
                    .tag("messaging.destination.name",event.getTopic()).start();
            }
            if(publishSpan==null)send(event,timeoutMillis);
            else try(var ignored=tracer.withSpan(publishSpan)){send(event,timeoutMillis);}
            event.published();metrics.counter("logitrack.outbox.published","event_type",event.getTopic()).increment();
        }catch(Exception error){
            if(error instanceof InterruptedException)Thread.currentThread().interrupt();
            if(publishSpan!=null)publishSpan.error(error);
            event.failed(error);metrics.counter("logitrack.outbox.failures","event_type",event.getTopic()).increment();
        }finally{if(publishSpan!=null)publishSpan.end();}
        return true;
    }
    private void send(OutboxEvent event,long timeoutMillis)throws Exception{
        kafka.send(event.getTopic(),event.getEventKey(),event.getPayload()).get(timeoutMillis,TimeUnit.MILLISECONDS);
    }
}
