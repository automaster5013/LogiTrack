package io.logitrack.config;

import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaAdmin;

import java.time.Duration;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class KafkaTopicConfigurationTest {
    @Test
    void declaresTheCompleteProductionTopicSetWithDurableReplication() {
        var topics = new KafkaTopicConfiguration(6, (short) 3, 2).topicDefinitions();
        var byName = topics.stream().collect(Collectors.toMap(topic -> topic.name(), Function.identity()));

        assertThat(byName).containsOnlyKeys(
            "delivery.created.v1", "vehicle.telemetry.v1", "vehicle.telemetry.dlq.v1",
            "inventory.received.v1", "warehouse.outbound.picked.v1",
            "warehouse.outbound.dispatched.v1", "delivery.alert.v1",
            "order.created.v1", "order.dispatched.v1", "order.fulfilled.v1"
        );
        assertThat(topics).allSatisfy(topic -> {
            assertThat(topic.numPartitions()).isEqualTo(6);
            assertThat(topic.replicationFactor()).isEqualTo((short) 3);
            assertThat(topic.configs()).containsEntry("min.insync.replicas", "2")
                .containsEntry("unclean.leader.election.enable", "false");
        });
        assertThat(byName.get("vehicle.telemetry.v1").configs().get("retention.ms"))
            .isEqualTo(Long.toString(Duration.ofDays(30).toMillis()));
        assertThat(byName.get("vehicle.telemetry.dlq.v1").configs().get("retention.ms"))
            .isEqualTo(Long.toString(Duration.ofDays(90).toMillis()));
    }

    @Test
    void rejectsUnsafeTopicShapes() {
        assertThrows(IllegalArgumentException.class, () -> new KafkaTopicConfiguration(0, (short) 3, 2));
        assertThrows(IllegalArgumentException.class, () -> new KafkaTopicConfiguration(3, (short) 0, 1));
        assertThrows(IllegalArgumentException.class, () -> new KafkaTopicConfiguration(3, (short) 2, 3));
    }

    @Test
    void reconcilesManagedTopicConfigurationOnStartup() {
        var admin = mock(KafkaAdmin.class);

        KafkaTopicConfiguration.reconcileTopicConfiguration().postProcessBeforeInitialization(admin, "kafkaAdmin");

        verify(admin).setModifyTopicConfigs(true);
    }
}
