package io.logitrack.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import jakarta.servlet.FilterChain;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class SecurityHeadersFilterTest {
    @Test void addsBrowserSecurityHeaders() throws Exception {
        var filter=new SecurityHeadersFilter();var request=new MockHttpServletRequest();var response=new MockHttpServletResponse();var chain=mock(FilterChain.class);
        filter.doFilter(request,response,chain);
        assertEquals(SecurityHeadersFilter.CONTENT_SECURITY_POLICY,response.getHeader("Content-Security-Policy"));
        assertEquals("none",response.getHeader("X-Permitted-Cross-Domain-Policies"));
        assertEquals("nosniff",response.getHeader("X-Content-Type-Options"));
        assertEquals("DENY",response.getHeader("X-Frame-Options"));
        assertEquals("no-referrer",response.getHeader("Referrer-Policy"));
        assertEquals("camera=(), microphone=(), geolocation=()",response.getHeader("Permissions-Policy"));
        verify(chain).doFilter(request,response);
    }
    @Test void preventsApiResponsesFromBeingStored() throws Exception {
        var filter=new SecurityHeadersFilter();var request=new MockHttpServletRequest("GET","/api/deliveries");var response=new MockHttpServletResponse();
        filter.doFilter(request,response,mock(FilterChain.class));assertEquals("no-store",response.getHeader("Cache-Control"));
    }
    @Test void leavesNonApiCachePolicyToTheResourceHandler() throws Exception {
        var filter=new SecurityHeadersFilter();var request=new MockHttpServletRequest("GET","/actuator/prometheus");var response=new MockHttpServletResponse();
        filter.doFilter(request,response,mock(FilterChain.class));assertNull(response.getHeader("Cache-Control"));
    }
}
