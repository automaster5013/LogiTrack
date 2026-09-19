package io.logitrack.config;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import java.util.NoSuchElementException;
import static org.junit.jupiter.api.Assertions.*;
class ApiExceptionHandlerTest {
    private final ApiExceptionHandler handler=new ApiExceptionHandler();
    private MockHttpServletRequest request(){var request=new MockHttpServletRequest();request.addHeader(RequestTraceFilter.HEADER,"trace-123");return request;}
    @Test void returnsSafeConflictWithoutDatabaseDetails(){var response=handler.integrity(new DataIntegrityViolationException("secret SQL detail"),request());assertEquals(HttpStatus.CONFLICT,response.getStatusCode());assertEquals("Resource conflicts with existing data",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void returnsSafeConflictForConcurrentModification(){var response=handler.optimisticLock(new ObjectOptimisticLockingFailureException("Delivery","secret-id"),request());assertEquals(HttpStatus.CONFLICT,response.getStatusCode());assertEquals("Resource was modified by another request",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void fallsBackWhenNotFoundHasNoMessage(){var response=handler.missing(new NoSuchElementException(),request());assertEquals(HttpStatus.NOT_FOUND,response.getStatusCode());assertEquals("Resource not found",response.getBody().error());assertNotNull(response.getBody().timestamp());}
}
