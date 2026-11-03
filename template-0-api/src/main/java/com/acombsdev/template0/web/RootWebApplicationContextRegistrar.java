package com.acombsdev.template0.web;

import jakarta.servlet.ServletContext;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Component;
import org.springframework.web.context.ServletContextAware;
import org.springframework.web.context.WebApplicationContext;

/**
 * Registers the application context as the servlet context's root web application context
 * when nothing else has.
 *
 * <p>Embedded Tomcat registers it automatically, so locally this does nothing. On AWS Lambda the
 * serverless adapter supplies a servlet context without it, and Spring Boot's actuator endpoints
 * (such as {@code /actuator/health}) then fail with "No WebApplicationContext found".
 */
@Component
class RootWebApplicationContextRegistrar implements ServletContextAware {
    private final ApplicationContext applicationContext;

    RootWebApplicationContextRegistrar(ApplicationContext applicationContext) {
        this.applicationContext = applicationContext;
    }

    @Override
    public void setServletContext(ServletContext servletContext) {
        if (servletContext.getAttribute(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE) == null
                && applicationContext instanceof WebApplicationContext webContext) {
            servletContext.setAttribute(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, webContext);
        }
    }
}
