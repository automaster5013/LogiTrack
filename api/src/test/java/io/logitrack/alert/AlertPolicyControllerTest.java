package io.logitrack.alert;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class AlertPolicyControllerTest {
 @Test void rejectsInvalidAuditPages(){var service=mock(AlertPolicyService.class);var controller=new AlertPolicyController(service);assertThrows(IllegalArgumentException.class,()->controller.auditPage(-1,100));assertThrows(IllegalArgumentException.class,()->controller.auditPage(0,101));verifyNoInteractions(service);}
}
