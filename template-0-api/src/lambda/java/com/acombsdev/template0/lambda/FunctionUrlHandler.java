package com.acombsdev.template0.lambda;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.spring.SpringDelegatingLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestStreamHandler;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Lambda handler: the adapter's SpringDelegatingLambdaContainerHandler, with its response headers
 * moved where function URLs read them (see FunctionUrlResponses). Built only by the lambda profile.
 */
public class FunctionUrlHandler implements RequestStreamHandler {
    private final SpringDelegatingLambdaContainerHandler delegate;
    private final ObjectMapper mapper = new ObjectMapper();

    public FunctionUrlHandler() throws ContainerInitializationException {
        delegate = new SpringDelegatingLambdaContainerHandler();
    }

    @Override
    public void handleRequest(InputStream input, OutputStream output, Context context) throws IOException {
        ByteArrayOutputStream response = new ByteArrayOutputStream();
        delegate.handleRequest(input, response, context);
        output.write(FunctionUrlResponses.withSingleValueHeaders(response.toByteArray(), mapper));
    }
}
