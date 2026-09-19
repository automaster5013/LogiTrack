package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class DeadLetterEventTest {
    @Test void replayIsSingleUse() {
        var event = new DeadLetterEvent("vehicle.telemetry.v1", "key", "{}", "trace", "failure", "vehicle.telemetry.dlq.v1", 0, 1);
        event.markReplayed("operator");
        assertThat(event.getStatus()).isEqualTo(DeadLetterEvent.Status.REPLAYED);
        assertThatThrownBy(() -> event.markReplayed("operator")).isInstanceOf(IllegalStateException.class);
    }
}

