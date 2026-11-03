package com.acombsdev.project0.web;

import org.junit.jupiter.api.Test;
import org.springframework.context.support.GenericApplicationContext;
import org.springframework.mock.web.MockServletContext;
import org.springframework.web.context.WebApplicationContext;
import org.springframework.web.context.support.GenericWebApplicationContext;

import static org.junit.jupiter.api.Assertions.*;

class RootWebApplicationContextRegistrarTest {
    private static final String ROOT = WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE;

    @Test
    void registersTheWebContextWhenTheServletContextHasNone() {
        var servletContext = new MockServletContext();
        var webContext = new GenericWebApplicationContext(servletContext);
        new RootWebApplicationContextRegistrar(webContext).setServletContext(servletContext);
        assertSame(webContext, servletContext.getAttribute(ROOT));
    }

    @Test
    void keepsAnExistingRootContext() {
        var servletContext = new MockServletContext();
        var existing = new GenericWebApplicationContext(servletContext);
        servletContext.setAttribute(ROOT, existing);
        new RootWebApplicationContextRegistrar(new GenericWebApplicationContext(servletContext)).setServletContext(servletContext);
        assertSame(existing, servletContext.getAttribute(ROOT));
    }

    @Test
    void ignoresContextsThatAreNotWebContexts() {
        var servletContext = new MockServletContext();
        new RootWebApplicationContextRegistrar(new GenericApplicationContext()).setServletContext(servletContext);
        assertNull(servletContext.getAttribute(ROOT));
    }
}
