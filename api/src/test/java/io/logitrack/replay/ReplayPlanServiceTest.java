package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

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
        assertThrows(IllegalArgumentException.class,()->service.prepare(new CreateReplayPlanRequest(java.util.Arrays.asList((java.util.UUID)null)),"operator","request"));
        verifyNoInteractions(plans,events,replay);
    }
    @Test void repeatedExecutionReturnsStoredResultWithoutReplayingEvents(){
        var plans=mock(ReplayPlanRepository.class);var replay=mock(ReplayService.class);var service=new ReplayPlanService(plans,mock(DeadLetterEventRepository.class),replay,20,1000);
        var ids=List.of(UUID.randomUUID(),UUID.randomUUID());var plan=new ReplayPlan("operator",ids);plan.complete(1,1);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId()," operator ","APPROVE"));verifyNoInteractions(replay);
    }
    @Test void repeatedExecutionStillRequiresOriginalOperator(){
        var plans=mock(ReplayPlanRepository.class);var replay=mock(ReplayService.class);var service=new ReplayPlanService(plans,mock(DeadLetterEventRepository.class),replay,20,1000);
        var plan=new ReplayPlan("operator",List.of(UUID.randomUUID()));plan.complete(1,0);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertThrows(IllegalArgumentException.class,()->service.execute(plan.getId(),"another-operator","APPROVE"));verifyNoInteractions(replay);
    }
    @Test void repeatedPreparationReturnsStoredPlanAndRejectsKeyReuse(){
        var plans=mock(ReplayPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var service=new ReplayPlanService(plans,events,mock(ReplayService.class),20,1000);
        var ids=List.of(UUID.randomUUID());var prior=new ReplayPlan("operator","request-3",ids);when(plans.findByRequestKey("request-3")).thenReturn(Optional.of(prior));
        assertSame(prior,service.prepare(new CreateReplayPlanRequest(ids)," operator ","request-3"));
        assertThrows(IllegalStateException.class,()->service.prepare(new CreateReplayPlanRequest(List.of(UUID.randomUUID())),"operator","request-3"));
        verifyNoInteractions(events);verify(plans,never()).save(any());
    }
    @Test void executionKeyReturnsStoredResultAndRejectsReuse(){
        var plans=mock(ReplayPlanRepository.class);var replay=mock(ReplayService.class);var service=new ReplayPlanService(plans,mock(DeadLetterEventRepository.class),replay,20,1000);
        var plan=new ReplayPlan("operator",List.of(UUID.randomUUID()));when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId(),"operator","APPROVE","execution-1"));assertEquals("execution-1",plan.getExecutionRequestKey());verify(replay).replay(plan.getEventIds().get(0),"operator");
        when(plans.findByExecutionRequestKey("execution-1")).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId()," operator ","APPROVE","execution-1"));verifyNoMoreInteractions(replay);
        assertThrows(IllegalStateException.class,()->service.execute(UUID.randomUUID(),"operator","APPROVE","execution-1"));
        assertThrows(IllegalStateException.class,()->service.execute(plan.getId(),"operator","APPROVE","execution-2"));
    }
}
