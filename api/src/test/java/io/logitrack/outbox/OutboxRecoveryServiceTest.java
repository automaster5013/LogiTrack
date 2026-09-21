package io.logitrack.outbox;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.springframework.data.domain.*;
class OutboxRecoveryServiceTest {
    private final OutboxRepository events=mock(OutboxRepository.class);private final OutboxRetryAuditRepository audits=mock(OutboxRetryAuditRepository.class);private final SimpleMeterRegistry metrics=new SimpleMeterRegistry();private final OutboxRecoveryService service=new OutboxRecoveryService(events,audits,metrics);
    @Test void retryRequiresOperator(){assertThrows(IllegalArgumentException.class,()->service.retry(UUID.randomUUID()," "));verifyNoInteractions(events,audits);}
    @Test void retryLocksEventAndWritesAudit(){
        var id=UUID.randomUUID();var event=new OutboxEvent(id,"DELIVERY",UUID.randomUUID(),"test","topic","key","{}");for(int i=0;i<20;i++)event.failed(new RuntimeException("offline"));when(events.lockById(id)).thenReturn(Optional.of(event));
        var result=service.retry(id," operator ");assertEquals(OutboxEvent.Status.PENDING,result.status());verify(audits).save(argThat(audit->audit.getOutboxEventId().equals(id)&&audit.getActor().equals("operator")));assertEquals(1,metrics.get("logitrack.outbox.retries").counter().count());
    }
    @Test void pagesFailuresAndAuditsWithStableNewestFirstOrdering(){
        var event=new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"test","topic","key","{}");
        when(events.findByStatus(eq(OutboxEvent.Status.FAILED),any(Pageable.class))).thenReturn(new PageImpl<>(List.of(event),PageRequest.of(1,20),41));
        when(audits.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(),PageRequest.of(2,20),61));
        assertEquals(41,service.failurePage(1,20).totalElements());assertEquals(61,service.auditPage(2,20).totalElements());
        var failureRequest=org.mockito.ArgumentCaptor.forClass(Pageable.class);var auditRequest=org.mockito.ArgumentCaptor.forClass(Pageable.class);
        verify(events).findByStatus(eq(OutboxEvent.Status.FAILED),failureRequest.capture());verify(audits).findAll(auditRequest.capture());
        assertNewestFirst(failureRequest.getValue(),"createdAt");assertNewestFirst(auditRequest.getValue(),"occurredAt");
    }
    private void assertNewestFirst(Pageable request,String timestamp){assertEquals(Sort.Direction.DESC,request.getSort().getOrderFor(timestamp).getDirection());assertEquals(Sort.Direction.DESC,request.getSort().getOrderFor("id").getDirection());}
}
