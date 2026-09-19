package io.logitrack.route;

import com.sun.net.httpserver.HttpServer;
import io.logitrack.delivery.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;
import java.net.InetSocketAddress;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;

class RouteAnalysisClientTest {
    @Test void rejectsDisabledTimeouts(){assertThrows(IllegalArgumentException.class,()->new RouteAnalysisClient(RestClient.builder(),"http://localhost",Duration.ZERO,Duration.ofSeconds(1),new SimpleMeterRegistry()));}
    @Test void fallsBackWithinConfiguredReadTimeout() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);
        server.createContext("/routes/analyze",exchange->{try{Thread.sleep(1000);}catch(InterruptedException ignored){}exchange.sendResponseHeaders(503,-1);exchange.close();});server.start();
        try{
            var metrics=new SimpleMeterRegistry();
            var client=new RouteAnalysisClient(RestClient.builder(),"http://localhost:"+server.getAddress().getPort(),Duration.ofMillis(100),Duration.ofMillis(100),metrics);
            var delivery=Delivery.create(new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5,127),new CreateDeliveryRequest.Location("Incheon",37.4,126.7)),"key");
            var started=System.nanoTime();var route=client.analyze(delivery);var elapsed=Duration.ofNanos(System.nanoTime()-started);
            assertEquals("spring-fallback",route.provider());assertTrue(elapsed.compareTo(Duration.ofSeconds(1))<0,"fallback took "+elapsed);
            assertEquals(1,metrics.get("logitrack.route.analysis").tag("outcome","fallback").counter().count());
            assertEquals(0,metrics.get("logitrack.route.analysis").tag("outcome","success").counter().count());
        }finally{server.stop(0);}
    }
    @Test void fallsBackWhenAnalyticsReturnsInvalidRoute() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);
        server.createContext("/routes/analyze",exchange->{var body=("{\"routeId\":\"%s\",\"provider\":\"bad\",\"algorithmVersion\":\"x\",\"coordinates\":[[999,999],[0,0]],\"distanceMeters\":-1,\"durationSeconds\":0,\"plannedEta\":\"2026-09-19T10:00:00Z\",\"geometryHash\":\"x\",\"generatedAt\":\"2026-09-19T09:00:00Z\"}").formatted(java.util.UUID.randomUUID());exchange.getResponseHeaders().add("Content-Type","application/json");exchange.sendResponseHeaders(200,body.getBytes().length);exchange.getResponseBody().write(body.getBytes());exchange.close();});server.start();
        try{
            var metrics=new SimpleMeterRegistry();var client=new RouteAnalysisClient(RestClient.builder(),"http://localhost:"+server.getAddress().getPort(),Duration.ofSeconds(1),Duration.ofSeconds(1),metrics);
            assertEquals("spring-fallback",client.analyze(delivery()).provider());
            assertEquals(1,metrics.get("logitrack.route.analysis").tag("outcome","fallback").counter().count());
        }finally{server.stop(0);}
    }
    private Delivery delivery(){return Delivery.create(new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5,127),new CreateDeliveryRequest.Location("Incheon",37.4,126.7)),"key");}
}
