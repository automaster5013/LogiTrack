package io.logitrack.route;

import io.logitrack.delivery.Delivery;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

@Component
public class RouteAnalysisClient {
    private final RestClient client;
    public RouteAnalysisClient(RestClient.Builder builder, @Value("${logitrack.analytics.url}") String url,
        @Value("${logitrack.analytics.route-connect-timeout:1s}") Duration connectTimeout,
        @Value("${logitrack.analytics.route-read-timeout:4s}") Duration readTimeout) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(connectTimeout);
        requestFactory.setReadTimeout(readTimeout);
        client = builder.baseUrl(url).requestFactory(requestFactory).build();
    }
    public RoutePlan analyze(Delivery delivery) {
        try {
            var request=Map.of(
                "origin",Map.of("lat",delivery.getOriginLat(),"lon",delivery.getOriginLon()),
                "destination",Map.of("lat",delivery.getDestinationLat(),"lon",delivery.getDestinationLon()));
            var result=client.post().uri("/routes/analyze").body(request).retrieve().body(RoutePlan.class);
            if(result==null||result.coordinates()==null||result.coordinates().size()<2) throw new IllegalStateException("Invalid route response");
            return result;
        } catch(Exception ignored) {
            return fallback(delivery);
        }
    }
    private RoutePlan fallback(Delivery d) {
        var points=new ArrayList<List<Double>>();
        for(int i=0;i<=24;i++) points.add(List.of(
            d.getOriginLon()+(d.getDestinationLon()-d.getOriginLon())*i/24,
            d.getOriginLat()+(d.getDestinationLat()-d.getOriginLat())*i/24));
        var distance=Math.round(haversine(d.getOriginLat(),d.getOriginLon(),d.getDestinationLat(),d.getDestinationLon())*1.18);
        var duration=Math.max(60,Math.round(distance/(42_000d/3_600d))); var now=Instant.now();
        return new RoutePlan(UUID.randomUUID(),"spring-fallback","route-v1",points,distance,duration,now.plusSeconds(duration),hash(points),now);
    }
    private long haversine(double lat1,double lon1,double lat2,double lon2) {
        var r=6_371_000d; var dLat=Math.toRadians(lat2-lat1); var dLon=Math.toRadians(lon2-lon1);
        var h=Math.pow(Math.sin(dLat/2),2)+Math.cos(Math.toRadians(lat1))*Math.cos(Math.toRadians(lat2))*Math.pow(Math.sin(dLon/2),2);
        return Math.round(2*r*Math.asin(Math.sqrt(h)));
    }
    private String hash(List<List<Double>> points) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(points.toString().getBytes(StandardCharsets.UTF_8))); }
        catch(Exception e) { throw new IllegalStateException(e); }
    }
}
