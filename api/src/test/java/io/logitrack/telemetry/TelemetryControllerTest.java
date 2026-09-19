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
        verify(repository).findTop5000ByDeliveryIdInOrderByOccurredAtDesc(new LinkedHashSet<>(List.of(id)));
        verify(repository,never()).findTop5000ByOrderByOccurredAtDesc();
    }
    @Test void preservesUnfilteredCompatibility(){
        controller.list(null);verify(repository).findTop5000ByOrderByOccurredAtDesc();
    }
}
