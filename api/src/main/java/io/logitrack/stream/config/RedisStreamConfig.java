package io.logitrack.stream.config;

import io.logitrack.stream.DeliveryStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.listener.*;

@Configuration
public class RedisStreamConfig {
    @Bean RedisMessageListenerContainer deliveryStreamListener(RedisConnectionFactory connectionFactory,DeliveryStream stream,
        @Value("${logitrack.stream.channel}") String channel){
        var container=new RedisMessageListenerContainer();container.setConnectionFactory(connectionFactory);
        container.addMessageListener(stream,new ChannelTopic(channel));return container;
    }
}
