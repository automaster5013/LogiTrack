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
        when(policies.findByVehicleId("TRUCK-01")).thenReturn(Optional.of(override));
        assertSame(override,service.resolve("TRUCK-01"));verify(policies,never()).findByVehicleId(AlertPolicy.DEFAULT_VEHICLE);
    }
    @Test void fallsBackToDefaultAndSignalsMissingDefault() {
        var fallback=new AlertPolicy(AlertPolicy.DEFAULT_VEHICLE,500,300,1500,600,300,1800,"system");
        when(policies.findByVehicleId("TRUCK-02")).thenReturn(Optional.empty());
        when(policies.findByVehicleId(AlertPolicy.DEFAULT_VEHICLE)).thenReturn(Optional.of(fallback));
        assertSame(fallback,service.resolve("TRUCK-02"));
        when(policies.findByVehicleId(AlertPolicy.DEFAULT_VEHICLE)).thenReturn(Optional.empty());
        assertThrows(IllegalStateException.class,()->service.resolve("TRUCK-02"));
    }
    @Test void createsPolicyAndImmutableAuditSnapshot() {
        when(policies.findByVehicleId("TRUCK-03")).thenReturn(Optional.empty());when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var policy=service.upsert(request(" TRUCK-03 ")," operator-a ");
        assertEquals("TRUCK-03",policy.getVehicleId());assertEquals("operator-a",policy.getUpdatedBy());
        var audit=ArgumentCaptor.forClass(AlertPolicyAudit.class);verify(audits).save(audit.capture());
        assertEquals(policy.getId(),audit.getValue().getPolicyId());assertEquals("operator-a",audit.getValue().getActor());
    }
    @Test void updatesExistingPolicyAndRejectsInvalidIdentity() {
        var policy=new AlertPolicy("TRUCK-04",500,300,1500,600,300,1800,"old");
        when(policies.findByVehicleId("TRUCK-04")).thenReturn(Optional.of(policy));when(policies.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        service.upsert(new UpsertAlertPolicyRequest("TRUCK-04",800,400,1800,900,400,2200),"new");
        assertEquals(800,policy.getDeviationOpenMeters());assertEquals("new",policy.getUpdatedBy());
        assertThrows(IllegalArgumentException.class,()->service.upsert(request(" "),"op"));
        assertThrows(IllegalArgumentException.class,()->service.upsert(request("TRUCK-05")," "));
    }
    @Test void delegatesLists() {
        when(policies.findAllByOrderByVehicleIdAsc()).thenReturn(List.of());when(audits.findTop50ByOrderByOccurredAtDesc()).thenReturn(List.of());
        assertTrue(service.list().isEmpty());assertTrue(service.auditTrail().isEmpty());
    }
}
