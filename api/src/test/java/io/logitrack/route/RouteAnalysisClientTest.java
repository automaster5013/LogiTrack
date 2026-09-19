package io.logitrack.route;

import com.sun.net.httpserver.HttpServer;
import io.logitrack.delivery.*;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;
import java.net.InetSocketAddress;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;

class RouteAnalysisClientTest {
    @Test void fallsBackWithinConfiguredReadTimeout() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);
        server.createContext("/routes/analyze",exchange->{try{Thread.sleep(1000);}catch(InterruptedException ignored){}exchange.sendResponseHeaders(503,-1);exchange.close();});server.start();
        try{
            var client=new RouteAnalysisClient(RestClient.builder(),"http://localhost:"+server.getAddress().getPort(),Duration.ofMillis(100),Duration.ofMillis(100));
            var delivery=Delivery.create(new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5,127),new CreateDeliveryRequest.Location("Incheon",37.4,126.7)),"key");
            var started=System.nanoTime();var route=client.analyze(delivery);var elapsed=Duration.ofNanos(System.nanoTime()-started);
            assertEquals("spring-fallback",route.provider());assertTrue(elapsed.compareTo(Duration.ofSeconds(1))<0,"fallback took "+elapsed);
        }finally{server.stop(0);}
    }
}
