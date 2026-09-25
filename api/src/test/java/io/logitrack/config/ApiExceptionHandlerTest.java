package io.logitrack.config;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import org.springframework.http.HttpMethod;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import io.logitrack.stream.StreamCapacityExceededException;
import java.util.NoSuchElementException;
import static org.junit.jupiter.api.Assertions.*;
class ApiExceptionHandlerTest {
    private final ApiExceptionHandler handler=new ApiExceptionHandler();
    private MockHttpServletRequest request(){var request=new MockHttpServletRequest();request.addHeader(RequestTraceFilter.HEADER,"trace-123");return request;}
    @Test void returnsSafeConflictWithoutDatabaseDetails(){var response=handler.integrity(new DataIntegrityViolationException("secret SQL detail"),request());assertEquals(HttpStatus.CONFLICT,response.getStatusCode());assertEquals("Resource conflicts with existing data",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void returnsSafeConflictForConcurrentModification(){var response=handler.optimisticLock(new ObjectOptimisticLockingFailureException("Delivery","secret-id"),request());assertEquals(HttpStatus.CONFLICT,response.getStatusCode());assertEquals("Resource was modified by another request",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void fallsBackWhenNotFoundHasNoMessage(){var response=handler.missing(new NoSuchElementException(),request());assertEquals(HttpStatus.NOT_FOUND,response.getStatusCode());assertEquals("Resource not found",response.getBody().error());assertNotNull(response.getBody().timestamp());}
    @Test void hidesCausedValidationDetails(){var response=handler.bad(new IllegalArgumentException("safe-looking wrapper",new RuntimeException("secret parser detail")),request());assertEquals(HttpStatus.BAD_REQUEST,response.getStatusCode());assertEquals("Invalid request",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void hidesCausedConflictDetails(){var response=handler.conflict(new IllegalStateException("safe-looking wrapper",new RuntimeException("secret upstream detail")),request());assertEquals(HttpStatus.CONFLICT,response.getStatusCode());assertEquals("Request conflicts with current state",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void standardizesMissingRequestValues(){var response=handler.requestBoundary(new MissingServletRequestParameterException("limit","int"),request());assertEquals(HttpStatus.BAD_REQUEST,response.getStatusCode());assertEquals("Invalid or missing request value",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void standardizesUnsupportedMethods(){var response=handler.method(new HttpRequestMethodNotSupportedException("TRACE"),request());assertEquals(HttpStatus.METHOD_NOT_ALLOWED,response.getStatusCode());assertEquals("Request method is not supported",response.getBody().error());}
    @Test void hidesUnknownRouteDetails(){var response=handler.unknownRoute(new NoResourceFoundException(HttpMethod.GET,"private/path"),request());assertEquals(HttpStatus.NOT_FOUND,response.getStatusCode());assertEquals("Resource not found",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
    @Test void ignoresDisconnectedStreamingClients(){assertDoesNotThrow(()->handler.disconnectedClient(new AsyncRequestNotUsableException("client disconnected")));}
    @Test void reportsStreamCapacityAsTooManyRequests(){var response=handler.streamCapacity(new StreamCapacityExceededException(),request());assertEquals(HttpStatus.TOO_MANY_REQUESTS,response.getStatusCode());assertEquals("SSE connection capacity has been reached",response.getBody().error());}
    @Test void hidesUnexpectedExceptionDetails(){var response=handler.unexpected(new RuntimeException("secret internal detail"),request());assertEquals(HttpStatus.INTERNAL_SERVER_ERROR,response.getStatusCode());assertEquals("Internal server error",response.getBody().error());assertEquals("trace-123",response.getBody().traceId());}
}
