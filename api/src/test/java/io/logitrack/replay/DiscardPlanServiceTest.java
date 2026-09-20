package io.logitrack.replay;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DiscardPlanServiceTest {
    @Test void preparesDeduplicatedPendingPlan(){
        var plans=mock(DiscardPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);
        var service=new DiscardPlanService(plans,events,replay,20);var id=UUID.randomUUID();
        var event=new DeadLetterEvent("topic","key","{}","trace","error","dlq",0,1);when(events.findAllById(List.of(id))).thenReturn(List.of(event));when(plans.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var plan=service.prepare(new CreateDiscardPlanRequest(List.of(id,id)," invalid fixtures ")," operator ");
        assertEquals(List.of(id),plan.getEventIds());assertEquals("operator",plan.getActor());assertEquals("invalid fixtures",plan.getReason());assertEquals(DiscardPlan.Status.PREPARED,plan.getStatus());
    }

    @Test void executesApprovedPlanAndUsesSharedReason(){
        var plans=mock(DiscardPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);var service=new DiscardPlanService(plans,events,replay,20);
        var ids=List.of(UUID.randomUUID(),UUID.randomUUID());var plan=new DiscardPlan("operator","invalid fixtures",ids);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        var result=service.execute(plan.getId(),"operator","DISCARD");
        assertEquals(DiscardPlan.Status.EXECUTED,result.getStatus());assertEquals(2,result.getSucceededCount());verify(replay).discard(ids.get(0),"operator","invalid fixtures");verify(replay).discard(ids.get(1),"operator","invalid fixtures");
    }

    @Test void recordsPartialOutcomeWithoutAbortingRemainingEvents(){
        var plans=mock(DiscardPlanRepository.class);var replay=mock(ReplayService.class);var service=new DiscardPlanService(plans,mock(DeadLetterEventRepository.class),replay,20);
        var ids=List.of(UUID.randomUUID(),UUID.randomUUID());var plan=new DiscardPlan("operator","reason",ids);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));doThrow(new IllegalStateException("not pending")).when(replay).discard(ids.get(0),"operator","reason");
        var result=service.execute(plan.getId(),"operator","DISCARD");
        assertEquals(DiscardPlan.Status.PARTIAL,result.getStatus());assertEquals(1,result.getSucceededCount());assertEquals(1,result.getFailedCount());verify(replay).discard(ids.get(1),"operator","reason");
    }

    @Test void rejectsUnsafeInputsBeforeMutation(){
        var plans=mock(DiscardPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var replay=mock(ReplayService.class);
        assertThrows(IllegalArgumentException.class,()->new DiscardPlanService(plans,events,replay,0));
        var service=new DiscardPlanService(plans,events,replay,20);assertThrows(IllegalArgumentException.class,()->service.prepare(new CreateDiscardPlanRequest(List.of(UUID.randomUUID())," "),"operator"));
        assertThrows(IllegalArgumentException.class,()->service.execute(UUID.randomUUID(),"operator","APPROVE"));verifyNoInteractions(plans,events,replay);
    }
}
