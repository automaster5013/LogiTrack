package io.logitrack.config;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import static org.junit.jupiter.api.Assertions.*;

class ApiRateLimitFilterTest {
    private final Clock clock=Clock.fixed(Instant.ofEpochSecond(120),ZoneOffset.UTC);
    @AfterEach void clearContext(){SecurityContextHolder.clearContext();}

    @Test void rejectsRequestsBeyondLimitAndProvidesRetryHeaders()throws Exception{
        var filter=new ApiRateLimitFilter(2,60,10,clock);var calls=new AtomicInteger();
        var first=invoke(filter,"10.0.0.1",calls);var second=invoke(filter,"10.0.0.1",calls);var rejected=invoke(filter,"10.0.0.1",calls);
        assertEquals(200,first.getStatus());assertEquals("1",first.getHeader(ApiRateLimitFilter.REMAINING_HEADER));
        assertEquals("0",second.getHeader(ApiRateLimitFilter.REMAINING_HEADER));
        assertEquals(429,rejected.getStatus());assertEquals("60",rejected.getHeader("Retry-After"));assertEquals(2,calls.get());
    }

    @Test void isolatesAuthenticatedSubjectsInsteadOfTrustingForwardedAddress()throws Exception{
        var filter=new ApiRateLimitFilter(1,60,10,clock);var calls=new AtomicInteger();
        SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken("operator-a","", "ROLE_VIEWER"));
        assertEquals(200,invoke(filter,"10.0.0.1",calls).getStatus());
        SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken("operator-b","", "ROLE_VIEWER"));
        assertEquals(200,invoke(filter,"10.0.0.1",calls).getStatus());
        assertEquals(2,calls.get());
    }

    @Test void ignoresNonApiRoutesAndRejectsInvalidConfiguration()throws Exception{
        var filter=new ApiRateLimitFilter(1,60,10,clock);var request=new MockHttpServletRequest("GET","/actuator/health/readiness");var response=new MockHttpServletResponse();
        filter.doFilter(request,response,(nextRequest,nextResponse)->nextResponse.getWriter().write("ok"));
        assertEquals("ok",response.getContentAsString());assertNull(response.getHeader(ApiRateLimitFilter.LIMIT_HEADER));
        assertThrows(IllegalArgumentException.class,()->new ApiRateLimitFilter(0,60,10));
    }

    private static MockHttpServletResponse invoke(ApiRateLimitFilter filter,String address,AtomicInteger calls)throws Exception{
        var request=new MockHttpServletRequest("GET","/api/deliveries");request.setRemoteAddr(address);request.addHeader("X-Forwarded-For","203.0.113.10");
        var response=new MockHttpServletResponse();filter.doFilter(request,response,(nextRequest,nextResponse)->calls.incrementAndGet());return response;
    }
}
