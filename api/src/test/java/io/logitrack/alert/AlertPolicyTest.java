package io.logitrack.alert;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class AlertPolicyTest {
    @Test void createsAndUpdatesOrderedThresholds() {
        var policy=new AlertPolicy("TRUCK-01",500,300,1500,600,300,1800,"operator-a");
        assertNotNull(policy.getId());assertEquals("TRUCK-01",policy.getVehicleId());assertEquals(500,policy.getDeviationOpenMeters());
        assertEquals(300,policy.getDeviationCloseMeters());assertEquals(1500,policy.getCriticalDeviationMeters());
        assertEquals(600,policy.getDelayOpenSeconds());assertEquals(300,policy.getDelayCloseSeconds());assertEquals(1800,policy.getCriticalDelaySeconds());
        var firstUpdate=policy.getUpdatedAt();policy.update(700,400,1700,900,450,2100,"operator-b");
        assertEquals(700,policy.getDeviationOpenMeters());assertEquals("operator-b",policy.getUpdatedBy());assertFalse(policy.getUpdatedAt().isBefore(firstUpdate));
    }
    @Test void rejectsInvalidDeviationThresholds() {
        assertThrows(IllegalArgumentException.class,()->new AlertPolicy("V",300,300,1000,600,300,1800,"op"));
        assertThrows(IllegalArgumentException.class,()->new AlertPolicy("V",Double.NaN,100,1000,600,300,1800,"op"));
        assertThrows(IllegalArgumentException.class,()->new AlertPolicy("V",1200,300,1000,600,300,1800,"op"));
    }
    @Test void rejectsInvalidDelayThresholds() {
        assertThrows(IllegalArgumentException.class,()->new AlertPolicy("V",500,300,1500,300,300,1800,"op"));
        assertThrows(IllegalArgumentException.class,()->new AlertPolicy("V",500,300,1500,1900,300,1800,"op"));
    }
}
