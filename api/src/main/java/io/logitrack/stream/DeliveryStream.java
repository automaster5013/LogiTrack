package io.logitrack.stream;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.*;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

@Component
public class DeliveryStream implements MessageListener {
    private static final Logger log=LoggerFactory.getLogger(DeliveryStream.class);
    private final CopyOnWriteArrayList<SseEmitter> clients=new CopyOnWriteArrayList<>();
    private final StringRedisTemplate redis; private final ObjectMapper mapper; private final MeterRegistry metrics;
    private final String channel; private final String instanceId;
    public DeliveryStream(StringRedisTemplate redis,ObjectMapper mapper,MeterRegistry metrics,
        @Value("${logitrack.stream.channel}") String channel,@Value("${logitrack.instance-id}") String instanceId){
        this.redis=redis;this.mapper=mapper;this.metrics=metrics;this.channel=channel;this.instanceId=instanceId;
        metrics.gauge("logitrack.sse.connections",clients,CopyOnWriteArrayList::size);
    }
    public SseEmitter subscribe(){
        var emitter=new SseEmitter(0L);clients.add(emitter);emitter.onCompletion(()->clients.remove(emitter));emitter.onTimeout(()->clients.remove(emitter));emitter.onError(error->clients.remove(emitter));
        try{emitter.send(SseEmitter.event().name("connected").data(Map.of("status","ok","instanceId",instanceId)));}
        catch(Exception error){clients.remove(emitter);}
        return emitter;
    }
    public void publish(Object value){publish("delivery-update",value);}
    public void publishAlert(Object value){publish("alert-update",value);}
    public void publishTelemetry(Object value){publish("telemetry-point",value);}
    @Scheduled(fixedDelayString="${logitrack.stream.heartbeat-ms:15000}")
    public void heartbeat(){
        for(var emitter:clients){try{emitter.send(SseEmitter.event().comment("keepalive"));}catch(Exception error){clients.remove(emitter);}}
    }
    private void publish(String name,Object value){
        try{
            var envelope=mapper.writeValueAsString(Map.of("name",name,"data",value));
            var subscribers=redis.convertAndSend(channel,envelope);
            if(subscribers==null||subscribers==0){broadcast(name,value);metrics.counter("logitrack.sse.fallback","reason","no_subscriber").increment();}
            else metrics.counter("logitrack.sse.redis.published","event",name).increment();
        }catch(Exception error){
            log.warn("Redis SSE fan-out unavailable; using local delivery: {}",error.toString());broadcast(name,value);
            metrics.counter("logitrack.sse.fallback","reason","redis_error").increment();
        }
    }
    @Override public void onMessage(Message message,byte[] pattern){
        try{
            var envelope=mapper.readTree(new String(message.getBody(),StandardCharsets.UTF_8));
            var name=envelope.required("name").asText();broadcast(name,envelope.required("data"));
            metrics.counter("logitrack.sse.redis.received","event",name).increment();
        }catch(Exception error){log.warn("Ignored invalid Redis stream event",error);metrics.counter("logitrack.sse.redis.invalid").increment();}
    }
    private void broadcast(String name,Object value){
        for(var emitter:clients){try{emitter.send(SseEmitter.event().name(name).data(value));}
            catch(Exception error){clients.remove(emitter);}}
    }
    int clientCount(){return clients.size();}
}
