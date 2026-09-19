package io.logitrack.route;

import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageRequest;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RouteControllerTest {
    private final RouteSnapshotRepository repository=mock(RouteSnapshotRepository.class);
    private final RouteController controller=new RouteController(repository);
    @Test void scopesRoutesToDistinctDeliveryIds(){
        var id=UUID.randomUUID();controller.list(List.of(id,id),200);
        verify(repository).findLatestByDeliveryIdIn(new LinkedHashSet<>(List.of(id)));
        verify(repository,never()).findAllByOrderByGeneratedAtDesc(any());
    }
    @Test void rejectsMoreThanOneHundredDeliveryIds(){
        var ids=new ArrayList<UUID>();for(int i=0;i<101;i++)ids.add(UUID.randomUUID());
        assertThrows(IllegalArgumentException.class,()->controller.list(ids,200));
        verifyNoInteractions(repository);
    }
    @Test void boundsUnscopedRouteHistory(){
        controller.list(null,25);
        verify(repository).findAllByOrderByGeneratedAtDesc(PageRequest.of(0,25));
        assertThrows(IllegalArgumentException.class,()->controller.list(null,501));
    }
}
