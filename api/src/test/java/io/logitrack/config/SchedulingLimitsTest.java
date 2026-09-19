package io.logitrack.config;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class SchedulingLimitsTest {
    @Test void acceptsDefaultSchedule(){assertDoesNotThrow(()->new SchedulingLimits(250,10_000,60_000,60_000,300_000));}
    @Test void rejectsBusyLoopsAndExtremeDelays(){
        assertThrows(IllegalArgumentException.class,()->new SchedulingLimits(1,10_000,60_000,60_000,300_000));
        assertThrows(IllegalArgumentException.class,()->new SchedulingLimits(250,999,60_000,60_000,300_000));
        assertThrows(IllegalArgumentException.class,()->new SchedulingLimits(250,10_000,60_000,-1,300_000));
        assertThrows(IllegalArgumentException.class,()->new SchedulingLimits(250,10_000,60_000,60_000,86_400_001));
    }
}
