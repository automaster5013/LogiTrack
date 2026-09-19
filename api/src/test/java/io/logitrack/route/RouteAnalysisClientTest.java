package io.logitrack.route;

import com.sun.net.httpserver.HttpServer;
import io.logitrack.delivery.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;
import org.springframework.util.unit.DataSize;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.InetSocketAddress;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;

class RouteAnalysisClientTest {
    private RouteAnalysisClient client(String url,Duration connect,Duration read,SimpleMeterRegistry metrics){return new RouteAnalysisClient(RestClient.builder(),url,connect,read,DataSize.ofMegabytes(2),new ObjectMapper().findAndRegisterModules(),metrics);}
    @Test void rejectsDisabledTimeouts(){assertThrows(IllegalArgumentException.class,()->client("http://localhost",Duration.ZERO,Duration.ofSeconds(1),new SimpleMeterRegistry()));assertThrows(IllegalArgumentException.class,()->new RouteAnalysisClient(RestClient.builder(),"http://localhost",Duration.ofSeconds(1),Duration.ofSeconds(1),DataSize.ofBytes(100),new ObjectMapper(),new SimpleMeterRegistry()));}
    @Test void fallsBackWithinConfiguredReadTimeout() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);
        server.createContext("/routes/analyze",exchange->{try{Thread.sleep(1000);}catch(InterruptedException ignored){}exchange.sendResponseHeaders(503,-1);exchange.close();});server.start();
        try{
            var metrics=new SimpleMeterRegistry();
            var client=client("http://localhost:"+server.getAddress().getPort(),Duration.ofMillis(100),Duration.ofMillis(100),metrics);
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
            var metrics=new SimpleMeterRegistry();var client=client("http://localhost:"+server.getAddress().getPort(),Duration.ofSeconds(1),Duration.ofSeconds(1),metrics);
            assertEquals("spring-fallback",client.analyze(delivery()).provider());
            assertEquals(1,metrics.get("logitrack.route.analysis").tag("outcome","fallback").counter().count());
        }finally{server.stop(0);}
    }
    @Test void countsAnalyticsProviderFallbackAsDegraded() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);var now=Instant.now();
        server.createContext("/routes/analyze",exchange->{var body=("{\"routeId\":\"%s\",\"provider\":\"geodesic-fallback\",\"algorithmVersion\":\"route-v1\",\"coordinates\":[[127,37.5],[126.7,37.4]],\"distanceMeters\":1000,\"durationSeconds\":100,\"plannedEta\":\"%s\",\"geometryHash\":\"%s\",\"generatedAt\":\"%s\"}").formatted(java.util.UUID.randomUUID(),now.plusSeconds(100),"a".repeat(64),now);exchange.getResponseHeaders().add("Content-Type","application/json");exchange.sendResponseHeaders(200,body.getBytes().length);exchange.getResponseBody().write(body.getBytes());exchange.close();});server.start();
        try{var metrics=new SimpleMeterRegistry();var client=client("http://localhost:"+server.getAddress().getPort(),Duration.ofSeconds(1),Duration.ofSeconds(1),metrics);assertEquals("geodesic-fallback",client.analyze(delivery()).provider());assertEquals(1,metrics.get("logitrack.route.analysis").tag("outcome","fallback").counter().count());}finally{server.stop(0);}
    }
    @Test void colocatedFallbackHasPersistableDistance(){
        var client=client("http://127.0.0.1:1",Duration.ofMillis(50),Duration.ofMillis(50),new SimpleMeterRegistry());
        var same=new CreateDeliveryRequest.Location("Same place",37.5,127.0);var delivery=Delivery.create(new CreateDeliveryRequest("ORD-SAME","TRUCK-1",same,same),"key");
        var route=client.analyze(delivery);assertEquals("spring-fallback",route.provider());assertEquals(1,route.distanceMeters());assertTrue(route.durationSeconds()>0);
    }
    @Test void oversizedAnalyticsResponseFallsBackWithoutBufferingItAll() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);var body=new byte[2048];server.createContext("/routes/analyze",exchange->{exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);exchange.close();});server.start();
        try{var metrics=new SimpleMeterRegistry();var client=new RouteAnalysisClient(RestClient.builder(),"http://localhost:"+server.getAddress().getPort(),Duration.ofSeconds(1),Duration.ofSeconds(1),DataSize.ofKilobytes(1),new ObjectMapper().findAndRegisterModules(),metrics);assertEquals("spring-fallback",client.analyze(delivery()).provider());assertEquals(1,metrics.get("logitrack.route.analysis").tag("outcome","fallback").counter().count());}finally{server.stop(0);}
    }
    private Delivery delivery(){return Delivery.create(new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5,127),new CreateDeliveryRequest.Location("Incheon",37.4,126.7)),"key");}
}
