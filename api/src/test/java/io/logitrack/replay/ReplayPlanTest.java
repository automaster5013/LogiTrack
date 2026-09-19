package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class ReplayPlanTest {
    @Test void completesOnlyOnce() {
        var plan=new ReplayPlan("operator", List.of(UUID.randomUUID(),UUID.randomUUID()));
        plan.complete(2,0);
        assertThat(plan.getStatus()).isEqualTo(ReplayPlan.Status.EXECUTED);
        assertThat(plan.getSucceededCount()).isEqualTo(2);
        assertThatThrownBy(()->plan.complete(2,0)).isInstanceOf(IllegalStateException.class);
    }

    @Test void recordsPartialCompletion() {
        var plan=new ReplayPlan("operator", List.of(UUID.randomUUID(),UUID.randomUUID()));
        plan.complete(1,1);
        assertThat(plan.getStatus()).isEqualTo(ReplayPlan.Status.PARTIAL);
    }

    @Test void expirationIsTerminalAndIdempotent() {
        var plan=new ReplayPlan("operator",List.of(UUID.randomUUID()));
        plan.expire();
        plan.expire();
        assertThat(plan.getStatus()).isEqualTo(ReplayPlan.Status.EXPIRED);
        assertThatThrownBy(()->plan.complete(1,0)).isInstanceOf(IllegalStateException.class);
    }
}
