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
        var plan=service.prepare(new CreateDiscardPlanRequest(List.of(id,id)," invalid fixtures ")," operator ","request-1");
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
        var service=new DiscardPlanService(plans,events,replay,20);assertThrows(IllegalArgumentException.class,()->service.prepare(new CreateDiscardPlanRequest(List.of(UUID.randomUUID())," "),"operator","request"));
        assertThrows(IllegalArgumentException.class,()->service.execute(UUID.randomUUID(),"operator","APPROVE"));verifyNoInteractions(plans,events,replay);
    }

    @Test void repeatedExecutionReturnsStoredResultWithoutDiscardingEventsAgain(){
        var plans=mock(DiscardPlanRepository.class);var replay=mock(ReplayService.class);var service=new DiscardPlanService(plans,mock(DeadLetterEventRepository.class),replay,20);
        var plan=new DiscardPlan("operator","reason",List.of(UUID.randomUUID(),UUID.randomUUID()));plan.complete(1,1);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId()," operator ","DISCARD"));verifyNoInteractions(replay);
    }

    @Test void repeatedExecutionStillRequiresOriginalOperator(){
        var plans=mock(DiscardPlanRepository.class);var replay=mock(ReplayService.class);var service=new DiscardPlanService(plans,mock(DeadLetterEventRepository.class),replay,20);
        var plan=new DiscardPlan("operator","reason",List.of(UUID.randomUUID()));plan.complete(1,0);when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertThrows(IllegalArgumentException.class,()->service.execute(plan.getId(),"another-operator","DISCARD"));verifyNoInteractions(replay);
    }
    @Test void repeatedPreparationReturnsStoredPlanAndRejectsKeyReuse(){
        var plans=mock(DiscardPlanRepository.class);var events=mock(DeadLetterEventRepository.class);var service=new DiscardPlanService(plans,events,mock(ReplayService.class),20);
        var ids=List.of(UUID.randomUUID());var prior=new DiscardPlan("operator","request-2","reason",ids);when(plans.findByRequestKey("request-2")).thenReturn(Optional.of(prior));
        assertSame(prior,service.prepare(new CreateDiscardPlanRequest(ids," reason ")," operator ","request-2"));
        assertThrows(IllegalStateException.class,()->service.prepare(new CreateDiscardPlanRequest(ids,"different"),"operator","request-2"));
        verifyNoInteractions(events);verify(plans,never()).save(any());
    }
    @Test void executionKeyReturnsStoredResultAndRejectsReuse(){
        var plans=mock(DiscardPlanRepository.class);var replay=mock(ReplayService.class);var service=new DiscardPlanService(plans,mock(DeadLetterEventRepository.class),replay,20);
        var plan=new DiscardPlan("operator","reason",List.of(UUID.randomUUID()));when(plans.findByIdForUpdate(plan.getId())).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId(),"operator","DISCARD","execution-1"));assertEquals("execution-1",plan.getExecutionRequestKey());verify(replay).discard(plan.getEventIds().get(0),"operator","reason");
        when(plans.findByExecutionRequestKey("execution-1")).thenReturn(Optional.of(plan));
        assertSame(plan,service.execute(plan.getId()," operator ","DISCARD","execution-1"));verifyNoMoreInteractions(replay);
        assertThrows(IllegalStateException.class,()->service.execute(UUID.randomUUID(),"operator","DISCARD","execution-1"));
        assertThrows(IllegalStateException.class,()->service.execute(plan.getId(),"operator","DISCARD","execution-2"));
    }
}
