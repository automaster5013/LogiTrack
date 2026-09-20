package io.logitrack.outbox;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.tracing.Tracer;
import io.micrometer.tracing.TraceContext;
import io.micrometer.tracing.Span;
import io.opentelemetry.api.trace.SpanContext;
import io.opentelemetry.api.trace.TraceFlags;
import io.opentelemetry.api.trace.TraceState;
import io.opentelemetry.context.Context;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OutboxPublishAttemptTest {
    @Test void publishesOneLockedEventAndCountsSuccess(){
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var event=event();
        when(repository.lockNextPending()).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        assertTrue(new OutboxPublishAttempt(repository,kafka,metrics,Tracer.NOOP).publishNext(5000));
        assertEquals(OutboxEvent.Status.PUBLISHED,event.getStatus());assertEquals(1,metrics.get("logitrack.outbox.published").counter().count());
    }
    @Test void stopsWhenNoDueEventExists(){var repository=mock(OutboxRepository.class);when(repository.lockNextPending()).thenReturn(Optional.empty());assertFalse(new OutboxPublishAttempt(repository,mock(KafkaTemplate.class),new SimpleMeterRegistry(),Tracer.NOOP).publishNext(5000));}
    @Test void recordsOneFailureWithoutThrowingIntoTheBatch(){
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var event=event();
        when(repository.lockNextPending()).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.failedFuture(new IllegalStateException("broker offline")));
        assertTrue(new OutboxPublishAttempt(repository,kafka,metrics,Tracer.NOOP).publishNext(5000));
        assertEquals(OutboxEvent.Status.PENDING,event.getStatus());assertEquals(1,event.getAttempts());assertEquals(1,metrics.get("logitrack.outbox.failures").counter().count());
    }
    @Test void restoresPersistedTraceAsProducerParent(){
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var tracer=mock(Tracer.class);
        var contextBuilder=mock(TraceContext.Builder.class);var parent=mock(TraceContext.class);var spanBuilder=mock(Span.Builder.class);var span=mock(Span.class);var scope=mock(Tracer.SpanInScope.class);
        var otel=SpanContext.create("0123456789abcdef0123456789abcdef","0123456789abcdef",TraceFlags.getSampled(),TraceState.getDefault());
        OutboxEvent event;try(var ignored=Context.root().with(io.opentelemetry.api.trace.Span.wrap(otel)).makeCurrent()){event=event();}
        when(repository.lockNextPending()).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        when(tracer.traceContextBuilder()).thenReturn(contextBuilder);when(contextBuilder.traceId(otel.getTraceId())).thenReturn(contextBuilder);when(contextBuilder.spanId(otel.getSpanId())).thenReturn(contextBuilder);when(contextBuilder.sampled(true)).thenReturn(contextBuilder);when(contextBuilder.build()).thenReturn(parent);
        when(tracer.spanBuilder()).thenReturn(spanBuilder);when(spanBuilder.setParent(parent)).thenReturn(spanBuilder);when(spanBuilder.name("outbox publish")).thenReturn(spanBuilder);when(spanBuilder.kind(Span.Kind.PRODUCER)).thenReturn(spanBuilder);when(spanBuilder.tag("messaging.destination.name","delivery.created.v1")).thenReturn(spanBuilder);when(spanBuilder.start()).thenReturn(span);when(tracer.withSpan(span)).thenReturn(scope);
        assertTrue(new OutboxPublishAttempt(repository,kafka,new SimpleMeterRegistry(),tracer).publishNext(5000));
        verify(tracer).withSpan(span);verify(span).end();verify(scope).close();
    }
    private OutboxEvent event(){return new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"delivery.created.v1","delivery.created.v1","key","{}");}
}
