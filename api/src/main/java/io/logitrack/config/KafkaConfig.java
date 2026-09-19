package io.logitrack.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import org.apache.kafka.common.TopicPartition;
import org.springframework.context.annotation.*;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.util.backoff.ExponentialBackOff;
import java.time.DateTimeException;
import java.util.NoSuchElementException;

@Configuration
public class KafkaConfig {
    @Bean DefaultErrorHandler errorHandler(KafkaTemplate<Object,Object> template){
        var recoverer=new DeadLetterPublishingRecoverer(template,(r,e)->new TopicPartition("vehicle.telemetry.dlq.v1",r.partition()));
        var backoff=new ExponentialBackOff(500,2); backoff.setMaxInterval(4000); backoff.setMaxElapsedTime(8000);
        var handler=new DefaultErrorHandler(recoverer,backoff);
        handler.addNotRetryableExceptions(IllegalArgumentException.class,DateTimeException.class,
            NoSuchElementException.class,JsonProcessingException.class);
        return handler;
    }
}
