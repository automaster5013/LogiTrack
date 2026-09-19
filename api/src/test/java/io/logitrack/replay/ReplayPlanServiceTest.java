package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class ReplayPlanServiceTest {
    @Test void rejectsUnsafeBatchConfiguration(){
        var plans=mock(ReplayPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,0,5));
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,101,5));
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,20,0));
        assertThrows(IllegalArgumentException.class,()->new ReplayPlanService(plans,events,replay,20,1001));
    }
    @Test void rejectsNullEventIdentifiersBeforeRepositoryAccess(){
        var plans=mock(ReplayPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);
        var service=new ReplayPlanService(plans,events,replay,20,5);
        assertThrows(IllegalArgumentException.class,()->service.prepare(new CreateReplayPlanRequest(java.util.Arrays.asList((java.util.UUID)null)),"operator"));
        verifyNoInteractions(plans,events,replay);
    }
}
