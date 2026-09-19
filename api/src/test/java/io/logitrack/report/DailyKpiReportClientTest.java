package io.logitrack.report;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.springframework.util.unit.DataSize;
import org.springframework.web.client.RestClient;
import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;

class DailyKpiReportClientTest {
    @Test void rejectsPdfLargerThanConfiguredResponseLimit() throws Exception {
        var server=HttpServer.create(new InetSocketAddress(0),0);var body="%PDF-oversized".getBytes();
        server.createContext("/reports/daily-kpis.pdf",exchange->{exchange.getResponseHeaders().add("Content-Type","application/pdf");exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);exchange.close();});server.start();
        try{
            var client=new DailyKpiReportClient(RestClient.builder(),"http://localhost:"+server.getAddress().getPort(),Duration.ofSeconds(1),Duration.ofSeconds(1),DataSize.ofBytes(8));
            assertThrows(IllegalStateException.class,()->client.render(List.of()));
        }finally{server.stop(0);}
    }
}
