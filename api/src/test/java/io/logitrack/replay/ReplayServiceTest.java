package io.logitrack.replay;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.springframework.transaction.annotation.*;
import org.springframework.data.domain.*;
class ReplayServiceTest {
    @Test void pagesPendingEventsWithoutHidingOlderBacklog(){
        var events=mock(DeadLetterEventRepository.class);var service=new ReplayService(events,mock(ReplayAuditRepository.class),mock(KafkaTemplate.class),new SimpleMeterRegistry());
        var first=new DeadLetterEvent("vehicle.telemetry.v1","key","{}","trace","error","vehicle.telemetry.dlq.v1",0,1);
        when(events.findByStatus(eq(DeadLetterEvent.Status.PENDING),any(Pageable.class))).thenReturn(new PageImpl<>(List.of(first),PageRequest.of(1,100),201));
        var result=service.page(DeadLetterEvent.Status.PENDING,1,100);
        assertEquals(List.of(first),result.items());assertEquals(1,result.page());assertEquals(201,result.totalElements());assertTrue(result.hasMore());
        var pageable=org.mockito.ArgumentCaptor.forClass(Pageable.class);verify(events).findByStatus(eq(DeadLetterEvent.Status.PENDING),pageable.capture());assertEquals(1,pageable.getValue().getPageNumber());assertEquals(100,pageable.getValue().getPageSize());
    }
    @Test void isolatesEachReplayInANewTransaction() throws Exception {var annotation=ReplayService.class.getDeclaredMethod("replay",UUID.class,String.class).getAnnotation(Transactional.class);assertEquals(Propagation.REQUIRES_NEW,annotation.propagation());}
    @Test void countsSuccessfulAuditedReplay(){
        var events=mock(DeadLetterEventRepository.class);var audits=mock(ReplayAuditRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var service=new ReplayService(events,audits,kafka,metrics);
        var event=new DeadLetterEvent("vehicle.telemetry.v1","key","{}","trace","error","vehicle.telemetry.dlq.v1",0,1);when(events.lockById(event.getId())).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        service.replay(event.getId()," operator ");
        assertEquals(DeadLetterEvent.Status.REPLAYED,event.getStatus());verify(events).lockById(event.getId());verify(audits).save(any());assertEquals(1,metrics.get("logitrack.dlq.replays").counter().count());
    }
    @Test void hidesBrokerDetailsOnReplayFailure(){
        var events=mock(DeadLetterEventRepository.class);var kafka=mock(KafkaTemplate.class);var service=new ReplayService(events,mock(ReplayAuditRepository.class),kafka,new SimpleMeterRegistry());
        var event=new DeadLetterEvent("vehicle.telemetry.v1","key","{}","trace","error","vehicle.telemetry.dlq.v1",0,1);when(events.lockById(event.getId())).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.failedFuture(new IllegalStateException("secret broker-1.internal:9092")));
        var error=assertThrows(IllegalStateException.class,()->service.replay(event.getId(),"operator"));assertEquals("Could not publish replay event",error.getMessage());assertFalse(error.getMessage().contains("broker"));
    }
    @Test void discardsPendingEventWithAuditAndMetric(){
        var events=mock(DeadLetterEventRepository.class);var audits=mock(ReplayAuditRepository.class);var metrics=new SimpleMeterRegistry();var service=new ReplayService(events,audits,mock(KafkaTemplate.class),metrics);
        var event=new DeadLetterEvent("vehicle.telemetry.v1","key","{}","trace","error","vehicle.telemetry.dlq.v1",0,2);when(events.lockById(event.getId())).thenReturn(Optional.of(event));
        service.discard(event.getId()," operator "," invalid fixture ");
        assertEquals(DeadLetterEvent.Status.DISCARDED,event.getStatus());assertEquals("operator",event.getDiscardedBy());assertEquals("invalid fixture",event.getDiscardReason());
        var audit=org.mockito.ArgumentCaptor.forClass(ReplayAudit.class);verify(audits).save(audit.capture());assertEquals("DISCARD",audit.getValue().getAction());assertEquals("invalid fixture",audit.getValue().getReason());assertEquals(1,metrics.get("logitrack.dlq.discards").counter().count());
    }
    @Test void validatesDiscardReasonBeforeLocking(){
        var events=mock(DeadLetterEventRepository.class);var service=new ReplayService(events,mock(ReplayAuditRepository.class),mock(KafkaTemplate.class),new SimpleMeterRegistry());
        assertThrows(IllegalArgumentException.class,()->service.discard(UUID.randomUUID(),"operator","   "));verifyNoInteractions(events);
    }
}
