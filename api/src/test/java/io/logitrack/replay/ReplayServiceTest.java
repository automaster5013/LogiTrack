package io.logitrack.replay;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.springframework.transaction.annotation.*;
class ReplayServiceTest {
    @Test void isolatesEachReplayInANewTransaction() throws Exception {var annotation=ReplayService.class.getDeclaredMethod("replay",UUID.class,String.class).getAnnotation(Transactional.class);assertEquals(Propagation.REQUIRES_NEW,annotation.propagation());}
    @Test void countsSuccessfulAuditedReplay(){
        var events=mock(DeadLetterEventRepository.class);var audits=mock(ReplayAuditRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var service=new ReplayService(events,audits,kafka,metrics);
        var event=new DeadLetterEvent("vehicle.telemetry.v1","key","{}","trace","error","vehicle.telemetry.dlq.v1",0,1);when(events.lockById(event.getId())).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        service.replay(event.getId()," operator ");
        assertEquals(DeadLetterEvent.Status.REPLAYED,event.getStatus());verify(events).lockById(event.getId());verify(audits).save(any());assertEquals(1,metrics.get("logitrack.dlq.replays").counter().count());
    }
}
