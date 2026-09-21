package io.logitrack.outbox;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class OutboxRecoveryControllerTest {
 @Test void rejectsInvalidPagesAndSizes(){var service=mock(OutboxRecoveryService.class);var controller=new OutboxRecoveryController(service);assertThrows(IllegalArgumentException.class,()->controller.failurePage(-1,100));assertThrows(IllegalArgumentException.class,()->controller.auditPage(0,101));verifyNoInteractions(service);}
}
