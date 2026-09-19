package io.logitrack.outbox;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class OutboxRecoveryServiceTest {
    private final OutboxRepository events=mock(OutboxRepository.class);private final OutboxRetryAuditRepository audits=mock(OutboxRetryAuditRepository.class);private final OutboxRecoveryService service=new OutboxRecoveryService(events,audits);
    @Test void retryRequiresOperator(){assertThrows(IllegalArgumentException.class,()->service.retry(UUID.randomUUID()," "));verifyNoInteractions(events,audits);}
    @Test void retryLocksEventAndWritesAudit(){
        var id=UUID.randomUUID();var event=new OutboxEvent(id,"DELIVERY",UUID.randomUUID(),"test","topic","key","{}");for(int i=0;i<20;i++)event.failed(new RuntimeException("offline"));when(events.lockById(id)).thenReturn(Optional.of(event));
        var result=service.retry(id," operator ");assertEquals(OutboxEvent.Status.PENDING,result.status());verify(audits).save(argThat(audit->audit.getOutboxEventId().equals(id)&&audit.getActor().equals("operator")));
    }
}
