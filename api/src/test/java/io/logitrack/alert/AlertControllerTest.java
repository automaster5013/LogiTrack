package io.logitrack.alert;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AlertControllerTest {
    @Test void pagesAlertsWithStableMostRecentlyObservedOrdering(){
        var repository=mock(DeliveryAlertRepository.class);
        var controller=new AlertController(repository,mock(AlertService.class));
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,DeliveryAlert.Severity.WARNING,"late",10,5);
        when(repository.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(alert),PageRequest.of(1,100),201));
        var result=controller.page(1,100);
        assertEquals(List.of(alert),result.items());assertEquals(201,result.totalElements());assertTrue(result.hasMore());
        var pageable=ArgumentCaptor.forClass(Pageable.class);verify(repository).findAll(pageable.capture());
        assertEquals(1,pageable.getValue().getPageNumber());assertEquals(100,pageable.getValue().getPageSize());
        assertEquals(Sort.Direction.DESC,pageable.getValue().getSort().getOrderFor("lastObservedAt").getDirection());
        assertEquals(Sort.Direction.DESC,pageable.getValue().getSort().getOrderFor("id").getDirection());
    }

    @Test void rejectsInvalidPageAndSize(){
        var repository=mock(DeliveryAlertRepository.class);
        var controller=new AlertController(repository,mock(AlertService.class));
        assertThrows(IllegalArgumentException.class,()->controller.page(-1,100));
        assertThrows(IllegalArgumentException.class,()->controller.page(0,0));
        verifyNoInteractions(repository);
    }
}
