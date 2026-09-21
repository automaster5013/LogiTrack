package io.logitrack.telemetry;

import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class TelemetryControllerTest {
    private final TelemetryPointRepository repository=mock(TelemetryPointRepository.class);
    private final TelemetryController controller=new TelemetryController(repository);
    @Test void scopesPointsToDistinctDeliveryIds(){
        var id=UUID.randomUUID();controller.list(List.of(id,id));
        verify(repository).findRecentWithLatestPerDelivery(new LinkedHashSet<>(List.of(id)));
        verify(repository,never()).findTop5000ByOrderByOccurredAtDescEventIdDesc();
    }
    @Test void preservesUnfilteredCompatibility(){
        controller.list(null);verify(repository).findTop5000ByOrderByOccurredAtDescEventIdDesc();
    }
    @Test void rejectsOversizedScopeWithoutQuerying(){
        var ids=new ArrayList<UUID>();for(int i=0;i<101;i++)ids.add(UUID.randomUUID());
        assertThrows(IllegalArgumentException.class,()->controller.list(ids));verifyNoInteractions(repository);
    }
    @Test void skipsQueryForEmptyScope(){
        assertTrue(controller.list(List.of()).isEmpty());verifyNoInteractions(repository);
    }
}
