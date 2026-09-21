package io.logitrack.replay;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class ReplayControllerTest {
 @Test void rejectsInvalidAuditPages(){var service=mock(ReplayService.class);var controller=new ReplayController(service,mock(ReplayPlanService.class),mock(DiscardPlanService.class));assertThrows(IllegalArgumentException.class,()->controller.auditPage(-1,100));assertThrows(IllegalArgumentException.class,()->controller.auditPage(0,0));verifyNoInteractions(service);}
}
