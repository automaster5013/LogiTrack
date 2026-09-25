package io.logitrack.stream;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.security.Principal;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class StreamControllerTest {
    @Test void keysAuthenticatedStreamsByPrincipal(){
        var stream=mock(DeliveryStream.class);var emitter=new SseEmitter();when(stream.subscribe("subject:operator-a")).thenReturn(emitter);
        var request=new MockHttpServletRequest();request.setRemoteAddr("10.0.0.1");
        assertSame(emitter,new StreamController(stream).deliveries(()->"operator-a",request));verify(stream).subscribe("subject:operator-a");
    }

    @Test void localStreamsUseDirectAddressAndIgnoreForwardedHeader(){
        var stream=mock(DeliveryStream.class);var emitter=new SseEmitter();when(stream.subscribe("address:10.0.0.1")).thenReturn(emitter);
        var request=new MockHttpServletRequest();request.setRemoteAddr("10.0.0.1");request.addHeader("X-Forwarded-For","203.0.113.99");
        assertSame(emitter,new StreamController(stream).deliveries((Principal)null,request));verify(stream).subscribe("address:10.0.0.1");
    }
}
