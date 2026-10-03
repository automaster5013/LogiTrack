package io.logitrack.replay;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.annotation.KafkaListener;

import static org.assertj.core.api.Assertions.assertThat;

class DeadLetterCatalogTest {
    @Test
    void catalogsTelemetryAndSimulatorDeadLetterTopics() throws Exception {
        var method = DeadLetterCatalog.class.getDeclaredMethod("capture", ConsumerRecord.class);
        var listener = method.getAnnotation(KafkaListener.class);

        assertThat(listener.topics()).containsExactlyInAnyOrder(
            "vehicle.telemetry.dlq.v1", "delivery.created.dlq.v1"
        );
    }
}
