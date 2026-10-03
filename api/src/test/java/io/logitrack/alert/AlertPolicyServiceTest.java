package io.logitrack.alert;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.springframework.data.domain.*;

class AlertPolicyServiceTest {
    private final AlertPolicyRepository policies=mock(AlertPolicyRepository.class);
    private final AlertPolicyAuditRepository audits=mock(AlertPolicyAuditRepository.class);
    private final AlertPolicyService service=new AlertPolicyService(policies,audits);
    private static UpsertAlertPolicyRequest request(String vehicle){return new UpsertAlertPolicyRequest(vehicle,500,300,1500,600,300,1800);}

    @Test void resolvesVehicleOverrideBeforeDefault() {
        var override=new AlertPolicy("TRUCK-01",700,400,1700,800,400,2000,"op");
        when(policies.findByVehicleIdAndActiveTrue("TRUCK-01")).thenReturn(Optional.of(override));
        assertSame(override,service.resolve("TRUCK-01"));verify(policies,never()).findByVehicleIdAndActiveTrue(AlertPolicy.DEFAULT_VEHICLE);
    }
    @Test void fallsBackToDefaultAndSignalsMissingDefault() {
        var fallback=new AlertPolicy(AlertPolicy.DEFAULT_VEHICLE,500,300,1500,600,300,1800,"system");
        when(policies.findByVehicleIdAndActiveTrue("TRUCK-02")).thenReturn(Optional.empty());
        when(policies.findByVehicleIdAndActiveTrue(AlertPolicy.DEFAULT_VEHICLE)).thenReturn(Optional.of(fallback));
        assertSame(fallback,service.resolve("TRUCK-02"));
        when(policies.findByVehicleIdAndActiveTrue(AlertPolicy.DEFAULT_VEHICLE)).thenReturn(Optional.empty());
        assertThrows(IllegalStateException.class,()->service.resolve("TRUCK-02"));
    }
    @Test void createsPolicyAndImmutableAuditSnapshot() {
        when(policies.findByVehicleId("TRUCK-03")).thenReturn(Optional.empty());when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var policy=service.upsert(request(" TRUCK-03 ")," operator-a ","request-1");
        assertEquals("TRUCK-03",policy.getVehicleId());assertEquals("operator-a",policy.getUpdatedBy());
        var audit=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(audit.capture());
        assertEquals(policy.getId(),audit.getValue().getPolicyId());assertEquals("operator-a",audit.getValue().getActor());assertEquals(AlertPolicyAudit.Action.UPSERT,audit.getValue().getAction());assertEquals("request-1",audit.getValue().getRequestKey());assertEquals(policy.getUpdatedAt(),audit.getValue().getPolicyUpdatedAt());
        verify(audits).lockRequestKey("request-1");
    }
    @Test void updatesExistingPolicyAndRejectsInvalidIdentity() {
        var policy=new AlertPolicy("TRUCK-04",500,300,1500,600,300,1800,"old");
        when(policies.findByVehicleId("TRUCK-04")).thenReturn(Optional.of(policy));when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        service.upsert(new UpsertAlertPolicyRequest("TRUCK-04",800,400,1800,900,400,2200),"new","request-2");
        assertEquals(800,policy.getDeviationOpenMeters());assertEquals("new",policy.getUpdatedBy());
        assertThrows(IllegalArgumentException.class,()->service.upsert(request(" "),"op","request-3"));
        assertThrows(IllegalArgumentException.class,()->service.upsert(request("TRUCK-05")," ","request-4"));
        assertThrows(IllegalArgumentException.class,()->service.upsert(request("TRUCK-05"),"op"," "));
    }
    @Test void rejectsNullPolicyRequestBeforeRepositoryAccess(){
        assertThrows(IllegalArgumentException.class,()->service.upsert(null,"operator","request"));
        verifyNoInteractions(policies,audits);
    }
    @Test void repeatedUpsertReturnsCurrentPolicyWithoutDuplicateAudit(){
        var current=new AlertPolicy("TRUCK-13",500,300,1500,600,300,1800,"operator");var prior=new AlertPolicyAudit(current,"operator","request-5");
        when(audits.findByRequestKey("request-5")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-13")).thenReturn(Optional.of(current));
        assertSame(current,service.upsert(request("TRUCK-13"),"operator","request-5"));verify(policies,never()).save(any());verify(audits,never()).save(any());
    }
    @Test void repeatedUpsertRejectsChangedPolicyOrDifferentRequest(){
        var current=new AlertPolicy("TRUCK-14",500,300,1500,600,300,1800,"operator");var prior=new AlertPolicyAudit(current,"operator","request-6");current.update(700,350,1700,800,400,2000,"another");
        when(audits.findByRequestKey("request-6")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-14")).thenReturn(Optional.of(current));
        assertThrows(IllegalStateException.class,()->service.upsert(request("TRUCK-14"),"operator","request-6"));
        assertThrows(IllegalStateException.class,()->service.upsert(new UpsertAlertPolicyRequest("TRUCK-14",600,300,1500,600,300,1800),"operator","request-6"));
        verify(policies,never()).save(any());verify(audits,never()).save(any());
    }
    @Test void resetsVehicleOverrideWithAuditedSnapshot() {
        var policy=new AlertPolicy("TRUCK-06",500,300,1500,600,300,1800,"old");
        when(policies.findByVehicleIdForUpdate("TRUCK-06")).thenReturn(Optional.of(policy));when(policies.save(policy)).thenReturn(policy);
        assertSame(policy,service.reset(" TRUCK-06 "," operator-r ","reset-key"));assertFalse(policy.isActive());assertEquals("operator-r",policy.getUpdatedBy());
        var audit=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(audit.capture());assertEquals(AlertPolicyAudit.Action.RESET,audit.getValue().getAction());assertEquals("reset-key",audit.getValue().getRequestKey());verify(audits).lockRequestKey("reset-key");
        assertThrows(IllegalArgumentException.class,()->service.reset(AlertPolicy.DEFAULT_VEHICLE,"operator"));
        assertThrows(NoSuchElementException.class,()->service.reset("TRUCK-MISSING","operator"));
    }
    @Test void repeatedResetBySameOperatorReturnsCurrentPolicyWithoutDuplicateAudit(){
        var policy=new AlertPolicy("TRUCK-09",500,300,1500,600,300,1800,"old");policy.deactivate("operator-r");
        when(policies.findByVehicleIdForUpdate("TRUCK-09")).thenReturn(Optional.of(policy));
        assertSame(policy,service.reset("TRUCK-09"," operator-r "));verify(policies,never()).save(any());verifyNoInteractions(audits);
    }
    @Test void resetByDifferentOperatorAfterCompletionRemainsRejected(){
        var policy=new AlertPolicy("TRUCK-10",500,300,1500,600,300,1800,"old");policy.deactivate("operator-r");
        when(policies.findByVehicleIdForUpdate("TRUCK-10")).thenReturn(Optional.of(policy));
        assertThrows(IllegalStateException.class,()->service.reset("TRUCK-10","another-operator"));verify(policies,never()).save(any());verifyNoInteractions(audits);
    }
    @Test void keyedResetReturnsOnlyTheMatchingUnchangedResult(){
        var policy=new AlertPolicy("TRUCK-15",500,300,1500,600,300,1800,"old");policy.deactivate("operator-r");
        var prior=new AlertPolicyAudit(policy,"operator-r",AlertPolicyAudit.Action.RESET,"reset-key");
        when(audits.findByRequestKey("reset-key")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-15")).thenReturn(Optional.of(policy));
        assertSame(policy,service.reset("TRUCK-15","operator-r","reset-key"));verify(policies,never()).save(any());verify(audits,never()).save(any());
        assertThrows(IllegalStateException.class,()->service.reset("TRUCK-OTHER","operator-r","reset-key"));
        assertThrows(IllegalStateException.class,()->service.reset("TRUCK-15","another","reset-key"));
        assertThrows(IllegalStateException.class,()->service.upsert(request("TRUCK-15"),"operator-r","reset-key"));
    }
    @Test void firstKeyedRetryClaimsALegacyResetAudit(){
        var policy=new AlertPolicy("TRUCK-RESET-LEGACY",700,350,1700,800,350,2100,"operator");policy.deactivate("operator");
        var prior=new AlertPolicyAudit(policy,"operator",AlertPolicyAudit.Action.RESET);
        when(audits.findByRequestKey("reset-key")).thenReturn(Optional.empty(),Optional.of(prior));when(policies.findByVehicleIdForUpdate(policy.getVehicleId())).thenReturn(Optional.of(policy));when(policies.findByVehicleId(policy.getVehicleId())).thenReturn(Optional.of(policy));
        when(audits.findFirstByVehicleIdAndActionAndActorAndPolicyUpdatedAtOrderByOccurredAtDesc(policy.getVehicleId(),AlertPolicyAudit.Action.RESET,"operator",policy.getUpdatedAt())).thenReturn(Optional.of(prior));
        assertSame(policy,service.reset(policy.getVehicleId(),"operator","reset-key"));assertEquals("reset-key",prior.getRequestKey());
        assertSame(policy,service.reset(policy.getVehicleId(),"operator","reset-key"));verify(audits,never()).save(any());
    }
    @Test void restoresPolicyFromImmutableAuditSnapshot() {
        var source=new AlertPolicy("TRUCK-07",200000,150000,250000,200000,150000,250000,"old");
        var snapshot=new AlertPolicyAudit(source,"original");
        var current=new AlertPolicy("TRUCK-07",500,300,1500,600,300,1800,"new");current.deactivate("new");
        when(audits.findByIdForUpdate(snapshot.getId())).thenReturn(Optional.of(snapshot));when(policies.findByVehicleId("TRUCK-07")).thenReturn(Optional.of(current));
        when(policies.save(current)).thenReturn(current);
        assertSame(current,service.restore(snapshot.getId()," operator-restore ","restore-key"));
        assertTrue(current.isActive());assertEquals(200000,current.getDeviationOpenMeters());assertEquals(200000,current.getDelayOpenSeconds());
        assertEquals("operator-restore",current.getUpdatedBy());
        var restored=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(restored.capture());
        assertEquals(AlertPolicyAudit.Action.RESTORE,restored.getValue().getAction());assertEquals("operator-restore",restored.getValue().getActor());assertEquals(snapshot.getId(),restored.getValue().getRestoredFromAuditId());assertEquals("restore-key",restored.getValue().getRequestKey());verify(audits).lockRequestKey("restore-key");
    }
    @Test void restoresMissingPolicyAndRejectsMissingSnapshotOrActor() {
        var source=new AlertPolicy("TRUCK-08",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        when(audits.findByIdForUpdate(snapshot.getId())).thenReturn(Optional.of(snapshot));when(policies.findByVehicleId("TRUCK-08")).thenReturn(Optional.empty());
        when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var created=service.restore(snapshot.getId(),"restorer");assertEquals("TRUCK-08",created.getVehicleId());assertEquals(800,created.getDeviationOpenMeters());
        var missing=UUID.randomUUID();when(audits.findByIdForUpdate(missing)).thenReturn(Optional.empty());
        assertThrows(NoSuchElementException.class,()->service.restore(missing,"restorer"));
        assertThrows(IllegalArgumentException.class,()->service.restore(snapshot.getId()," "));
    }
    @Test void repeatedRestoreReturnsCurrentPolicyWithoutDuplicateAudit(){
        var source=new AlertPolicy("TRUCK-11",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        var current=new AlertPolicy("TRUCK-11",800,400,1800,900,400,2200,"restorer");var prior=new AlertPolicyAudit(current,"restorer",snapshot.getId());
        when(audits.findByIdForUpdate(snapshot.getId())).thenReturn(Optional.of(snapshot));when(audits.findByRestoredFromAuditIdAndActor(snapshot.getId(),"restorer")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-11")).thenReturn(Optional.of(current));
        assertSame(current,service.restore(snapshot.getId()," restorer "));verify(policies,never()).save(any());verify(audits,never()).save(any());
    }
    @Test void firstKeyedRetryClaimsALegacyRestoreAudit(){
        var source=new AlertPolicy("TRUCK-LEGACY",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        var current=new AlertPolicy("TRUCK-LEGACY",800,400,1800,900,400,2200,"restorer");var prior=new AlertPolicyAudit(current,"restorer",snapshot.getId());
        when(audits.findByRequestKey("restore-key")).thenReturn(Optional.empty(),Optional.of(prior));when(audits.findByIdForUpdate(snapshot.getId())).thenReturn(Optional.of(snapshot));
        when(audits.findByRestoredFromAuditIdAndActor(snapshot.getId(),"restorer")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-LEGACY")).thenReturn(Optional.of(current));
        assertSame(current,service.restore(snapshot.getId(),"restorer","restore-key"));assertEquals("restore-key",prior.getRequestKey());
        assertSame(current,service.restore(snapshot.getId(),"restorer","restore-key"));verify(audits,never()).save(any());
        assertThrows(IllegalStateException.class,()->prior.bindRequestKey("different-key"));
    }
    @Test void repeatedRestoreRejectsAChangedPolicy(){
        var source=new AlertPolicy("TRUCK-12",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        var restored=new AlertPolicy("TRUCK-12",800,400,1800,900,400,2200,"restorer");var prior=new AlertPolicyAudit(restored,"restorer",snapshot.getId());restored.update(900,450,1900,1000,500,2300,"another-operator");
        when(audits.findByIdForUpdate(snapshot.getId())).thenReturn(Optional.of(snapshot));when(audits.findByRestoredFromAuditIdAndActor(snapshot.getId(),"restorer")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-12")).thenReturn(Optional.of(restored));
        assertThrows(IllegalStateException.class,()->service.restore(snapshot.getId(),"restorer"));verify(policies,never()).save(any());verify(audits,never()).save(any());
    }
    @Test void keyedRestoreReturnsOnlyTheMatchingUnchangedResult(){
        var source=new AlertPolicy("TRUCK-16",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        var current=new AlertPolicy("TRUCK-16",800,400,1800,900,400,2200,"restorer");var prior=new AlertPolicyAudit(current,"restorer",snapshot.getId(),"restore-key");
        when(audits.findByRequestKey("restore-key")).thenReturn(Optional.of(prior));when(policies.findByVehicleId("TRUCK-16")).thenReturn(Optional.of(current));
        assertSame(current,service.restore(snapshot.getId(),"restorer","restore-key"));verify(audits,never()).findByIdForUpdate(any());verify(audits,never()).save(any());
        assertThrows(IllegalStateException.class,()->service.restore(UUID.randomUUID(),"restorer","restore-key"));
        assertThrows(IllegalStateException.class,()->service.restore(snapshot.getId(),"another","restore-key"));
    }
    @Test void delegatesLists() {
        when(policies.findAllByActiveTrueOrderByVehicleIdAsc()).thenReturn(List.of());when(audits.findTop50ByOrderByOccurredAtDesc()).thenReturn(List.of());
        assertTrue(service.list().isEmpty());assertTrue(service.auditTrail().isEmpty());
    }
    @Test void pagesCompleteAuditHistoryWithStableNewestFirstOrdering(){
        when(audits.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(),PageRequest.of(2,25),76));
        var result=service.auditPage(2,25);assertEquals(76,result.totalElements());assertTrue(result.hasMore());
        var request=ArgumentCaptor.forClass(Pageable.class);verify(audits).findAll(request.capture());
        assertEquals(Sort.Direction.DESC,request.getValue().getSort().getOrderFor("occurredAt").getDirection());assertEquals(Sort.Direction.DESC,request.getValue().getSort().getOrderFor("id").getDirection());
    }
}
