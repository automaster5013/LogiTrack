package io.logitrack.alert;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

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
        var policy=service.upsert(request(" TRUCK-03 ")," operator-a ");
        assertEquals("TRUCK-03",policy.getVehicleId());assertEquals("operator-a",policy.getUpdatedBy());
        var audit=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(audit.capture());
        assertEquals(policy.getId(),audit.getValue().getPolicyId());assertEquals("operator-a",audit.getValue().getActor());assertEquals(AlertPolicyAudit.Action.UPSERT,audit.getValue().getAction());
    }
    @Test void updatesExistingPolicyAndRejectsInvalidIdentity() {
        var policy=new AlertPolicy("TRUCK-04",500,300,1500,600,300,1800,"old");
        when(policies.findByVehicleId("TRUCK-04")).thenReturn(Optional.of(policy));when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        service.upsert(new UpsertAlertPolicyRequest("TRUCK-04",800,400,1800,900,400,2200),"new");
        assertEquals(800,policy.getDeviationOpenMeters());assertEquals("new",policy.getUpdatedBy());
        assertThrows(IllegalArgumentException.class,()->service.upsert(request(" "),"op"));
        assertThrows(IllegalArgumentException.class,()->service.upsert(request("TRUCK-05")," "));
    }
    @Test void rejectsNullPolicyRequestBeforeRepositoryAccess(){
        assertThrows(IllegalArgumentException.class,()->service.upsert(null,"operator"));
        verifyNoInteractions(policies,audits);
    }
    @Test void resetsVehicleOverrideWithAuditedSnapshot() {
        var policy=new AlertPolicy("TRUCK-06",500,300,1500,600,300,1800,"old");
        when(policies.findByVehicleIdAndActiveTrue("TRUCK-06")).thenReturn(Optional.of(policy));when(policies.save(policy)).thenReturn(policy);
        assertSame(policy,service.reset(" TRUCK-06 "," operator-r "));assertFalse(policy.isActive());assertEquals("operator-r",policy.getUpdatedBy());
        var audit=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(audit.capture());assertEquals(AlertPolicyAudit.Action.RESET,audit.getValue().getAction());
        assertThrows(IllegalArgumentException.class,()->service.reset(AlertPolicy.DEFAULT_VEHICLE,"operator"));
        assertThrows(NoSuchElementException.class,()->service.reset("TRUCK-MISSING","operator"));
    }
    @Test void restoresPolicyFromImmutableAuditSnapshot() {
        var source=new AlertPolicy("TRUCK-07",200000,150000,250000,200000,150000,250000,"old");
        var snapshot=new AlertPolicyAudit(source,"original");
        var current=new AlertPolicy("TRUCK-07",500,300,1500,600,300,1800,"new");current.deactivate("new");
        when(audits.findById(snapshot.getId())).thenReturn(Optional.of(snapshot));when(policies.findByVehicleId("TRUCK-07")).thenReturn(Optional.of(current));
        when(policies.save(current)).thenReturn(current);
        assertSame(current,service.restore(snapshot.getId()," operator-restore "));
        assertTrue(current.isActive());assertEquals(200000,current.getDeviationOpenMeters());assertEquals(200000,current.getDelayOpenSeconds());
        assertEquals("operator-restore",current.getUpdatedBy());
        var restored=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(restored.capture());
        assertEquals(AlertPolicyAudit.Action.RESTORE,restored.getValue().getAction());assertEquals("operator-restore",restored.getValue().getActor());
    }
    @Test void restoresMissingPolicyAndRejectsMissingSnapshotOrActor() {
        var source=new AlertPolicy("TRUCK-08",800,400,1800,900,400,2200,"old");var snapshot=new AlertPolicyAudit(source,"original");
        when(audits.findById(snapshot.getId())).thenReturn(Optional.of(snapshot));when(policies.findByVehicleId("TRUCK-08")).thenReturn(Optional.empty());
        when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var created=service.restore(snapshot.getId(),"restorer");assertEquals("TRUCK-08",created.getVehicleId());assertEquals(800,created.getDeviationOpenMeters());
        var missing=UUID.randomUUID();when(audits.findById(missing)).thenReturn(Optional.empty());
        assertThrows(NoSuchElementException.class,()->service.restore(missing,"restorer"));
        assertThrows(IllegalArgumentException.class,()->service.restore(snapshot.getId()," "));
    }
    @Test void delegatesLists() {
        when(policies.findAllByActiveTrueOrderByVehicleIdAsc()).thenReturn(List.of());when(audits.findTop50ByOrderByOccurredAtDesc()).thenReturn(List.of());
        assertTrue(service.list().isEmpty());assertTrue(service.auditTrail().isEmpty());
    }
}
