package com.acombsdev.template0.lambda;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Lambda function URLs read response headers only from {@code headers}; the serverless adapter
 * writes them only to {@code multiValueHeaders}, so without this every header Spring sets
 * (CORS, WWW-Authenticate, Content-Type, ...) is dropped.
 */
public final class FunctionUrlResponses {
    private FunctionUrlResponses() {
    }

    public static byte[] withSingleValueHeaders(byte[] response, ObjectMapper mapper) throws IOException {
        JsonNode root = mapper.readTree(response);
        if (!(root instanceof ObjectNode node) || !(node.get("multiValueHeaders") instanceof ObjectNode multi)) {
            return response;
        }
        ObjectNode headers = node.get("headers") instanceof ObjectNode existing ? existing : node.putObject("headers");
        multi.properties().forEach(header -> {
            if (headers.has(header.getKey())) return;
            List<String> values = new ArrayList<>();
            header.getValue().forEach(value -> values.add(value.asText()));
            headers.put(header.getKey(), String.join(", ", values));
        });
        node.remove("multiValueHeaders");
        return mapper.writeValueAsBytes(node);
    }
}
