package io.logitrack.config;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class WebConfigTest {
    @Test void defaultsToBothPublishedLocalConsoleOrigins(){
        assertArrayEquals(new String[]{"http://localhost:3000","http://127.0.0.1:3000"},
            WebConfig.parseAllowedOrigins(WebConfig.DEFAULT_ALLOWED_ORIGINS));
    }

    @Test void trimsDeduplicatesAndAcceptsExactHttpOrigins(){
        assertArrayEquals(new String[]{"https://console.example.com","http://localhost:3000"},
            WebConfig.parseAllowedOrigins(" https://console.example.com, http://localhost:3000,https://console.example.com "));
    }

    @Test void rejectsOriginsThatWouldBroadenOrMisstateTheCorsBoundary(){
        for(var value:new String[]{"*","https://*.example.com","ftp://console.example.com","https://user@example.com","https://example.com/path","https://example.com?debug=true","https://example.com#fragment","not an origin"})
            assertThrows(IllegalArgumentException.class,()->WebConfig.parseAllowedOrigins(value),value);
    }

    @Test void rejectsAnEmptyOriginList(){
        assertThrows(IllegalArgumentException.class,()->new WebConfig(" , "));
    }
}
