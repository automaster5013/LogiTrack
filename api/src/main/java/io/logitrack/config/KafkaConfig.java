package io.logitrack.config;

import org.apache.kafka.common.TopicPartition;
import org.springframework.context.annotation.*;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.util.backoff.ExponentialBackOff;

@Configuration
public class KafkaConfig {
    @Bean DefaultErrorHandler errorHandler(KafkaTemplate<Object,Object> template){
        var recoverer=new DeadLetterPublishingRecoverer(template,(r,e)->new TopicPartition("vehicle.telemetry.dlq.v1",r.partition()));
        var backoff=new ExponentialBackOff(500,2); backoff.setMaxInterval(4000); backoff.setMaxElapsedTime(8000);
        return new DefaultErrorHandler(recoverer,backoff);
    }
}

