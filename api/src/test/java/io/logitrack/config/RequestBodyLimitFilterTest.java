package io.logitrack.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import org.springframework.util.unit.DataSize;
import java.io.IOException;
import static org.junit.jupiter.api.Assertions.*;

class RequestBodyLimitFilterTest {
    @Test void stopsReadingPostBodyAtConfiguredLimit() throws Exception {
        var request=new MockHttpServletRequest("POST","/api/deliveries");request.setContent("12345".getBytes());var response=new MockHttpServletResponse();
        var filter=new RequestBodyLimitFilter(DataSize.ofBytes(4));
        assertThrows(IOException.class,()->filter.doFilter(request,response,(nextRequest,nextResponse)->nextRequest.getInputStream().readAllBytes()));
    }
    @Test void rejectsDisabledLimit(){assertThrows(IllegalArgumentException.class,()->new RequestBodyLimitFilter(DataSize.ofBytes(0)));}
}
