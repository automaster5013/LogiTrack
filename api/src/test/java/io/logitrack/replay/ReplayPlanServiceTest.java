package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

class ReplayPlanServiceTest {
    @Test void rejectsUnsafeBatchConfiguration(){
        var plans=mock(ReplayPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,0,5));
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,20,0));
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,20,1001));
    }
}
