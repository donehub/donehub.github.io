---
title: Spring ApplicationContext Initialization (Part 1)
date: 2020-04-04 13:57:01
lang: en
label: 004_spring_container
tags: Spring
categories: Backend
---

-----

<!-- more -->
#### 1. Background

The `Spring` container is the heart of the Spring framework. It handles object creation, dependency injection, lifecycle management — basically everything. The container uses Inversion of Control (IoC), also called Dependency Injection (DI), to connect objects. These managed objects are called `Bean`s. The process is straightforward: Spring reads the bean configuration, builds a registry, then instantiates and wires up the beans.

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuIf8JCvEJ4zL22ueoinBVxfkvzEPAvvsp7swlFjfppI5QYu5803AvvKel6pjVRvtdK8qK0W2d58Jyo22J_OlVDQu7YvXgAVmTFwk9xlw529yVHIUBTZpT4__yraj4BNMS6L6C6NFDgzuiNmn5XN6S8Ey4iiI5T1Kn28v3k9mDCSf00r-sjRpOk4A3FK1_bx-nGZb43uMK-SzsGSA28HAX1ZO2Wmjp_TCVhfsnhED2z3SWf30j6NNbETJLZnVqVrqLpz861RIkdPGRrafl5Y_-sd_D90arEMwG4cOIy3Yi1105hT2LOBW0LKXt0DKjQGTw02G4eGeK0cAmwmKdkpT3r9Lo-MGcfS2J3e0)

Spring provides two container types: `BeanFactory` and `ApplicationContext`. `BeanFactory` is the low-level foundation for IoC, but `ApplicationContext` builds on top of it with enterprise-level features. The [official docs](https://docs.spring.io/spring/docs/5.2.5.RELEASE/spring-framework-reference/core.html#context-introduction-ctx-vs-beanfactory) lay out the differences:

| Feature | BeanFactory | ApplicationContext |
| :--- | :---: | :---: |
| Bean instantiation / wiring | Yes | Yes |
| Lifecycle management | No | Yes |
| `BeanPostProcessor` auto-registration | No | Yes |
| `BeanFactoryPostProcessor` auto-registration | No | Yes |
| i18n via `MessageSource` | No | Yes |
| Event publishing via `ApplicationEvent` | No | Yes |

This post focuses on `ApplicationContext`. The Spring source version referenced here is [5.2.5.RELEASE](https://docs.spring.io/spring/docs/5.2.5.RELEASE/spring-framework-reference/index.html).

#### 2. Class Relationships

`ApplicationContext` has many implementations. For this analysis, I'll use a Java EE web application (built with Spring) as the example. To understand the initialization process, it helps to look at the class diagram for `XmlWebApplicationContext`:

![](http://www.plantuml.com/plantuml/png/hLNHhjCm37tlL_G7jY_WOMCCWJJGD93WrStSDLAQJ8ax6EBZMTHLiZgtIT7DMzjpJe_jsDu40azTQmfb88JoPsj-OBMzNerMGDhPdRE4lwc0Af07HMMFspuVJrXx30rK1cLU1l41hVL5u6fBw6jGMFQGpel_6M6_DzZYDzTvXJb_dzLwZs2_GelRN-2HlVziDMam-e-sbuXXdvYzP2WByZMhEROt2pxe6jLT6UIcZ0iO7HNFU_01Q-WCdJ34HEB1mHbzTXGCkBStxPrjqT8EhX7EhUX0yLLCuKTGvFoTVVsaqODNZLPWPCGN304kGx75-FStj7JiAgD3Wpo28RGZ4A6tyT7Sq7ELZXnBp8WgPOMxB79Rf7oSTtzNg-dUMz0plL9sToRxgXnEzBXUvokpBYmJPw6ob8vq8jBJXlSwfhpcouv7nHl99ghLdpu9wU4vtyrfCRa-2ueYo0Xbu4P6erbopT6YrHGhDUM6IIhOpA4Fi-K_wOKueva6p_NYehCRATDV1_jh109D6Favj8bTaABn1S7yfMYJ-sEUDh5Iad_ZUqOsoHSq2t_uFBagHtSZrbHUxQ8ghvMisEEcLka6xRbhpJy0)

#### 3. Container Initialization

When a Java EE web app starts, `ContextLoaderListener` fires and initializes the root `WebApplicationContext`. Here's the implementation:

```java
/**
* Triggered by <context>contextLoaderListener</context> in web.xml.
* Initializes the root container.
*
* @param servletContext The application context; only one per application
* @return The root container
*/
public WebApplicationContext initWebApplicationContext(ServletContext servletContext) {
    // The root container is mounted on ServletContext — there can only be one
    if (servletContext
            .getAttribute(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE)
        != null) {
        throw new IllegalStateException("...");
    }
    servletContext.log("Initializing Spring root WebApplicationContext");
    Log logger = LogFactory.getLog(ContextLoader.class);
    if (logger.isInfoEnabled()) {
        logger.info("Root WebApplicationContext: initialization started");
    }
    long startTime = System.currentTimeMillis();
    try {
        if (this.context == null) {
            // Default root container is XmlWebApplicationContext
            this.context = createWebApplicationContext(servletContext);
        }
        if (this.context instanceof ConfigurableWebApplicationContext) {
            ConfigurableWebApplicationContext cwac
                = (ConfigurableWebApplicationContext) this.context;
            // Container hasn't been refreshed yet
            if (!cwac.isActive()) {
                // Set parent context
                if (cwac.getParent() == null) {
                    // For web apps, parent context defaults to null
                    ApplicationContext parent = loadParentContext(servletContext);
                    cwac.setParent(parent);
                }
                // Configure and refresh
                configureAndRefreshWebApplicationContext(cwac, servletContext);
            }
        }
        // Mount the root container on ServletContext with a well-known attribute name
        servletContext
            .setAttribute(WebApplicationContext
                          .ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, this.context);
        // Get the current thread's class loader
        ClassLoader ccl = Thread.currentThread().getContextClassLoader();
        if (ccl == ContextLoader.class.getClassLoader()) {
            currentContext = this.context;
        } else if (ccl != null) {
            // If the class loader isn't ContextLoader's, store it in the thread-local map
            currentContextPerThread.put(ccl, this.context);
        }
        if (logger.isInfoEnabled()) {
            long elapsedTime = System.currentTimeMillis() - startTime;
            logger.info("Root WebApplicationContext initialized in "
                        + elapsedTime + " ms");
        }
        return this.context;
    } catch (RuntimeException | Error ex) {
        logger.error("Context initialization failed", ex);
        // On failure, mount the exception on ServletContext — no further initialization
        servletContext
            .setAttribute(WebApplicationContext
                          .ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, ex);
        throw ex;
    }
}

/**
* Create the root WebApplicationContext
*
* @param sc ServletContext; one per application
* @return The root WebApplicationContext
*/
WebApplicationContext createWebApplicationContext(ServletContext sc) {
    // Determine the implementation class
    Class<?> contextClass = determineContextClass(sc);
    if (!ConfigurableWebApplicationContext.class.isAssignableFrom(contextClass)) {
        throw new ApplicationContextException("...");
    }
    // Instantiate the root container
    return (ConfigurableWebApplicationContext) BeanUtils.instantiateClass(contextClass);
}

/**
* Determine the root container implementation class
*
* @param servletContext Application context; one per application
* @return Implementation class; defaults to XmlWebApplicationContext
*/
Class<?> determineContextClass(ServletContext servletContext) {
    // Read <context-param>contextClass</context-param> from web.xml
    String contextClassName = servletContext.getInitParameter(CONTEXT_CLASS_PARAM);
    if (contextClassName != null) {
        try {
            return ClassUtils.forName(contextClassName,
                                      ClassUtils.getDefaultClassLoader());
        } catch (ClassNotFoundException ex) {
            throw new ApplicationContextException(
                "Failed to load custom context class [" + contextClassName + "]", ex);
        }
    } else {
        // If not configured, use the default: XmlWebApplicationContext
        contextClassName =
            defaultStrategies.getProperty(WebApplicationContext.class.getName());
        try {
            return ClassUtils.forName(contextClassName,
                                      ContextLoader.class.getClassLoader());
        } catch (ClassNotFoundException ex) {
            throw new ApplicationContextException(
                "Failed to load default context class [" + contextClassName + "]", ex);
        }
    }
}
```

Key takeaways from the code:

* A web app gets exactly one root container
* The implementation class is configurable; `XmlWebApplicationContext` is the default
* A parent context is supported but defaults to `null` — this is a placeholder for parent-child container hierarchies
* The root `WebApplicationContext` is mounted on `ServletContext` under the attribute name `WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE`

Now let's look at the configuration and refresh phase:

```java
/**
* Configure and refresh the root WebApplicationContext
*
* @param wac Configurable root container
* @param sc  ServletContext; one per application
*/
void configureAndRefreshWebApplicationContext(ConfigurableWebApplicationContext wac,
                                              ServletContext sc) {
    // 1. Assign an ID to the root container (used later to load Spring MVC config)
    if (ObjectUtils.identityToString(wac).equals(wac.getId())) {
        String idParam = sc.getInitParameter(CONTEXT_ID_PARAM);
        if (idParam != null) {
            wac.setId(idParam);
        } else {
            // Generate a default ID
            wac.setId(ConfigurableWebApplicationContext.APPLICATION_CONTEXT_ID_PREFIX +
                      ObjectUtils.getDisplayString(sc.getContextPath()));
        }
    }
    // 2. Attach the application context
    wac.setServletContext(sc);
    // 3. Set the config location
    // Reads <context-param>configLocation</context-param> from web.xml
    String configLocationParam = sc.getInitParameter(CONFIG_LOCATION_PARAM);
    if (configLocationParam != null) {
        wac.setConfigLocation(configLocationParam);
    }
    // 4. Initialize environment properties
    ConfigurableEnvironment env = wac.getEnvironment();
    if (env instanceof ConfigurableWebEnvironment) {
        ((ConfigurableWebEnvironment) env).initPropertySources(sc, null);
    }
    // 5. Run custom context initializers
    customizeContext(sc, wac);
    // 6. Refresh the root container
    wac.refresh();
}

/**
* Run custom context initializers
*
* @param sc  ServletContext; one per application
* @param wac Configurable root container
*/
void customizeContext(ServletContext sc, ConfigurableWebApplicationContext wac) {
    List<Class<ApplicationContextInitializer<ConfigurableApplicationContext>>>
        initializerClasses =
        determineContextInitializerClasses(sc);
    for (Class<ApplicationContextInitializer<ConfigurableApplicationContext>>
         initializerClass : initializerClasses) {
        Class<?> initializerContextClass =
            GenericTypeResolver.resolveTypeArgument(initializerClass,
                                                    ApplicationContextInitializer.class);
        if (initializerContextClass != null
            && !initializerContextClass.isInstance(wac)) {
            throw new ApplicationContextException(String.format("..."));
        }
        // Instantiate the initializer and add to the list
        this.contextInitializers.add(BeanUtils.instantiateClass(initializerClass));
        AnnotationAwareOrderComparator.sort(this.contextInitializers);
        for (ApplicationContextInitializer<ConfigurableApplicationContext>
             initializer : this.contextInitializers) {
            // Execute each initializer in order
            initializer.initialize(wac);
        }
    }
}
```

What we see here:

* Config location comes from `<context-param>configLocation</context-param>` in web.xml
* Environment properties are initialized early because `initPropertySources` is called during every refresh — this ensures Servlet properties are available to post-processors and other early lifecycle components
* Custom initializers run after configuration is loaded but before the container refreshes. They're loaded from `ServletContext`'s `contextInitializerClasses` and `globalInitializerClasses` settings, then executed in order
* After customization, `wac.refresh()` triggers the full container refresh — that's the subject of the next post
