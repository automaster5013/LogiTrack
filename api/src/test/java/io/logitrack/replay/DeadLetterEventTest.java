package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class DeadLetterEventTest {
    @Test void capturesOriginalKafkaPosition() {
        var event = new DeadLetterEvent("delivery.created.v1", 2, 41L, "key", "{}", "trace",
            "failure", "delivery.created.dlq.v1", 0, 1);
        assertThat(event.getOriginalPartition()).isEqualTo(2);
        assertThat(event.getOriginalOffset()).isEqualTo(41L);
    }

    @Test void replayIsSingleUse() {
        var event = new DeadLetterEvent("vehicle.telemetry.v1", "key", "{}", "trace", "failure", "vehicle.telemetry.dlq.v1", 0, 1);
        event.markReplayed("operator");
        assertThat(event.getStatus()).isEqualTo(DeadLetterEvent.Status.REPLAYED);
        assertThatThrownBy(() -> event.markReplayed("operator")).isInstanceOf(IllegalStateException.class);
    }

    @Test void discardIsTerminalAndCapturesDisposition() {
        var event = new DeadLetterEvent("vehicle.telemetry.v1", "key", "{}", "trace", "failure", "vehicle.telemetry.dlq.v1", 0, 2);
        event.discard("operator", "invalid historical fixture");
        assertThat(event.getStatus()).isEqualTo(DeadLetterEvent.Status.DISCARDED);
        assertThat(event.getDiscardedBy()).isEqualTo("operator");
        assertThat(event.getDiscardReason()).isEqualTo("invalid historical fixture");
        assertThat(event.getDiscardedAt()).isNotNull();
        assertThatThrownBy(() -> event.markReplayed("operator")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> event.discard("operator", "again")).isInstanceOf(IllegalStateException.class);
    }
}
