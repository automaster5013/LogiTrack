package io.logitrack.config;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class RequestTraceFilterTest {
    private final RequestTraceFilter filter=new RequestTraceFilter();
    @Test void createsAndPropagatesTraceId() throws Exception {
        var request=new MockHttpServletRequest();var response=new MockHttpServletResponse();var chain=mock(FilterChain.class);filter.doFilter(request,response,chain);
        var trace=response.getHeader(RequestTraceFilter.HEADER);assertNotNull(trace);assertDoesNotThrow(()->java.util.UUID.fromString(trace));
        verify(chain).doFilter(argThat(next->trace.equals(((jakarta.servlet.http.HttpServletRequest)next).getHeader(RequestTraceFilter.HEADER))),eq(response));assertNull(MDC.get("requestId"));
    }
    @Test void preservesSafeCallerTraceId() throws Exception {
        var request=new MockHttpServletRequest();request.addHeader(RequestTraceFilter.HEADER,"support-case:123");var response=new MockHttpServletResponse();var chain=mock(FilterChain.class);filter.doFilter(request,response,chain);
        assertEquals("support-case:123",response.getHeader(RequestTraceFilter.HEADER));verify(chain).doFilter(any(),eq(response));
    }
    @Test void rejectsUnsafeTraceId() throws Exception {
        var request=new MockHttpServletRequest();request.addHeader(RequestTraceFilter.HEADER,"bad trace id");var response=new MockHttpServletResponse();var chain=mock(FilterChain.class);filter.doFilter(request,response,chain);
        var body=new com.fasterxml.jackson.databind.ObjectMapper().readTree(response.getContentAsString());assertEquals(400,response.getStatus());assertTrue(body.get("error").asText().contains("1-128"));assertEquals(response.getHeader(RequestTraceFilter.HEADER),body.get("traceId").asText());assertNotNull(body.get("timestamp"));verifyNoInteractions(chain);
    }
}
