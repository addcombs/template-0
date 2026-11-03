package com.acombsdev.project0.lambda;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.*;

class FunctionUrlResponsesTest {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void movesMultiValueHeadersIntoHeaders() throws Exception {
        byte[] response = """
                {"statusCode":200,"body":"{}","isBase64Encoded":false,
                 "multiValueHeaders":{"Access-Control-Allow-Origin":["https://app.example"],
                                      "Vary":["Origin","Access-Control-Request-Method"]}}
                """.getBytes(StandardCharsets.UTF_8);
        JsonNode result = mapper.readTree(FunctionUrlResponses.withSingleValueHeaders(response, mapper));
        assertEquals("https://app.example", result.path("headers").path("Access-Control-Allow-Origin").asText());
        assertEquals("Origin, Access-Control-Request-Method", result.path("headers").path("Vary").asText());
        assertFalse(result.has("multiValueHeaders"));
        assertEquals(200, result.path("statusCode").asInt());
        assertEquals("{}", result.path("body").asText());
    }

    @Test
    void keepsExistingSingleValueHeadersAndOtherResponses() throws Exception {
        byte[] response = """
                {"statusCode":401,"headers":{"Content-Type":"text/plain"},
                 "multiValueHeaders":{"Content-Type":["application/json"],"WWW-Authenticate":["Bearer"]}}
                """.getBytes(StandardCharsets.UTF_8);
        JsonNode result = mapper.readTree(FunctionUrlResponses.withSingleValueHeaders(response, mapper));
        assertEquals("text/plain", result.path("headers").path("Content-Type").asText());
        assertEquals("Bearer", result.path("headers").path("WWW-Authenticate").asText());
        byte[] plain = "{\"statusCode\":204}".getBytes(StandardCharsets.UTF_8);
        assertSame(plain, FunctionUrlResponses.withSingleValueHeaders(plain, mapper));
    }
}
