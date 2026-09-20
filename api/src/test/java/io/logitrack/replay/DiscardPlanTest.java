package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class DiscardPlanTest {
    @Test void completesWithTerminalOutcome(){
        var plan=new DiscardPlan("operator","invalid fixtures",List.of(UUID.randomUUID(),UUID.randomUUID()));
        plan.complete(1,1);
        assertThat(plan.getStatus()).isEqualTo(DiscardPlan.Status.PARTIAL);
        assertThat(plan.getSucceededCount()).isEqualTo(1);
        assertThat(plan.getFailedCount()).isEqualTo(1);
        assertThat(plan.getExecutedAt()).isNotNull();
        plan.expire();
        assertThat(plan.getStatus()).isEqualTo(DiscardPlan.Status.PARTIAL);
        assertThatThrownBy(()->plan.complete(2,0)).isInstanceOf(IllegalStateException.class);
    }

    @Test void expiresOnlyPreparedPlan(){
        var plan=new DiscardPlan("operator","invalid fixtures",List.of(UUID.randomUUID()));
        plan.expire();
        assertThat(plan.getStatus()).isEqualTo(DiscardPlan.Status.EXPIRED);
        assertThat(plan.getExecutedAt()).isNull();
    }
}
