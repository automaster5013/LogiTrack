package io.logitrack.outbox;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class OutboxEventTest {
    @Test void schedulesExponentialRetryBackoff(){var event=new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"test","test-topic","key","{}");var before=java.time.Instant.now();event.failed(new RuntimeException("offline"));assertTrue(event.getNextAttemptAt().isAfter(before));var first=event.getNextAttemptAt();event.failed(new RuntimeException("offline"));assertTrue(event.getNextAttemptAt().isAfter(first));assertEquals(2,event.getAttempts());}
    @Test void failedEventCanBeResetForRetry(){
        var event=new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"test","test-topic","key","{}");
        for(int i=0;i<20;i++)event.failed(new RuntimeException("offline"));
        assertEquals(OutboxEvent.Status.FAILED,event.getStatus());assertEquals(20,event.getAttempts());
        event.retry();assertEquals(OutboxEvent.Status.PENDING,event.getStatus());assertEquals(0,event.getAttempts());assertNull(event.getLastError());
    }
    @Test void pendingEventCannotBeRetried(){
        var event=new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"test","test-topic","key","{}");
        assertThrows(IllegalStateException.class,event::retry);
    }
}
