package io.logitrack.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.config.TopicConfig;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.KafkaAdmin;

import java.time.Duration;
import java.util.List;

@Configuration
public class KafkaTopicConfiguration {
    private static final long STANDARD_RETENTION_MS = Duration.ofDays(30).toMillis();
    private static final long DLQ_RETENTION_MS = Duration.ofDays(90).toMillis();
    private static final List<String> STANDARD_TOPICS = List.of(
        "delivery.created.v1", "vehicle.telemetry.v1", "inventory.received.v1",
        "warehouse.outbound.picked.v1", "warehouse.outbound.dispatched.v1",
        "delivery.alert.v1", "order.created.v1", "order.dispatched.v1", "order.fulfilled.v1"
    );

    private final int partitions;
    private final short replicationFactor;
    private final int minimumInSyncReplicas;

    public KafkaTopicConfiguration(
        @Value("${logitrack.kafka.topics.partitions:3}") int partitions,
        @Value("${logitrack.kafka.topics.replication-factor:1}") short replicationFactor,
        @Value("${logitrack.kafka.topics.minimum-in-sync-replicas:1}") int minimumInSyncReplicas
    ) {
        if (partitions < 1 || partitions > 100) {
            throw new IllegalArgumentException("Kafka topic partitions must be between 1 and 100");
        }
        if (replicationFactor < 1 || replicationFactor > 5) {
            throw new IllegalArgumentException("Kafka topic replication factor must be between 1 and 5");
        }
        if (minimumInSyncReplicas < 1 || minimumInSyncReplicas > replicationFactor) {
            throw new IllegalArgumentException("Kafka minimum in-sync replicas must be between 1 and the replication factor");
        }
        this.partitions = partitions;
        this.replicationFactor = replicationFactor;
        this.minimumInSyncReplicas = minimumInSyncReplicas;
    }

    @Bean
    KafkaAdmin.NewTopics logiTrackTopics() {
        return new KafkaAdmin.NewTopics(topicDefinitions().toArray(NewTopic[]::new));
    }

    @Bean
    static BeanPostProcessor reconcileTopicConfiguration() {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
                if (bean instanceof KafkaAdmin admin) {
                    admin.setModifyTopicConfigs(true);
                }
                return bean;
            }
        };
    }

    List<NewTopic> topicDefinitions() {
        var topics = STANDARD_TOPICS.stream()
            .map(name -> topic(name, STANDARD_RETENTION_MS))
            .collect(java.util.stream.Collectors.toCollection(java.util.ArrayList::new));
        topics.add(topic("vehicle.telemetry.dlq.v1", DLQ_RETENTION_MS));
        topics.add(topic("delivery.created.dlq.v1", DLQ_RETENTION_MS));
        return List.copyOf(topics);
    }

    private NewTopic topic(String name, long retentionMs) {
        return TopicBuilder.name(name)
            .partitions(partitions)
            .replicas(replicationFactor)
            .config(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, Integer.toString(minimumInSyncReplicas))
            .config(TopicConfig.UNCLEAN_LEADER_ELECTION_ENABLE_CONFIG, Boolean.FALSE.toString())
            .config(TopicConfig.RETENTION_MS_CONFIG, Long.toString(retentionMs))
            .build();
    }
}
