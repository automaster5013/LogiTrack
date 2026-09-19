package io.logitrack.stream;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DeliveryStreamTest {
    private final StringRedisTemplate redis=mock(StringRedisTemplate.class);
    private final SimpleMeterRegistry metrics=new SimpleMeterRegistry();
    private final DeliveryStream stream=new DeliveryStream(redis,new ObjectMapper(),metrics,"logitrack.events","test-api");
    @Test void publishesDeliveryThroughRedis(){
        when(redis.convertAndSend(eq("logitrack.events"),anyString())).thenReturn(2L);
        stream.publish(java.util.Map.of("id","delivery-1"));
        verify(redis).convertAndSend(eq("logitrack.events"),contains("delivery-update"));
        assertEquals(1,metrics.counter("logitrack.sse.redis.published","event","delivery-update").count());
    }
    @Test void fallsBackLocallyWhenRedisFails(){
        stream.subscribe();when(redis.convertAndSend(anyString(),anyString())).thenThrow(new IllegalStateException("offline"));
        stream.publishAlert(java.util.Map.of("id","alert-1"));
        assertEquals(1,stream.clientCount());
        assertEquals(1,metrics.counter("logitrack.sse.fallback","reason","redis_error").count());
    }
    @Test void publishesTelemetryPointThroughRedis(){
        when(redis.convertAndSend(eq("logitrack.events"),anyString())).thenReturn(1L);
        stream.publishTelemetry(java.util.Map.of("eventId","event-1","deliveryId","delivery-1"));
        verify(redis).convertAndSend(eq("logitrack.events"),contains("telemetry-point"));
        assertEquals(1,metrics.counter("logitrack.sse.redis.published","event","telemetry-point").count());
    }
    @Test void keepsIdleSubscribersRegisteredAfterHeartbeat(){stream.subscribe();stream.heartbeat();assertEquals(1,stream.clientCount());}
}
