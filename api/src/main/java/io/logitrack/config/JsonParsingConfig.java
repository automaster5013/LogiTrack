package io.logitrack.config;

import com.fasterxml.jackson.core.StreamReadConstraints;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class JsonParsingConfig {
    private final int maxNestingDepth;

    public JsonParsingConfig(@Value("${logitrack.json.max-nesting-depth:100}") int maxNestingDepth) {
        if (maxNestingDepth < 1 || maxNestingDepth > 200) {
            throw new IllegalArgumentException("JSON nesting depth must be between 1 and 200");
        }
        this.maxNestingDepth = maxNestingDepth;
    }

    @Bean
    Jackson2ObjectMapperBuilderCustomizer jsonStreamReadConstraints() {
        return builder -> builder.postConfigurer(mapper -> mapper.getFactory().setStreamReadConstraints(
                StreamReadConstraints.builder().maxNestingDepth(maxNestingDepth).build()));
    }
}
