---
title: Spring ApplicationContext 容器的初始化 (上)
date: 2020-04-04 13:57:01
tags: Spring
categories: 后端
---

-----

<!-- more -->
#### 一、背景介绍

`Spring` 容器是 `Spring` 框架的核心。容器负责配置对象，注入对象，管理对象，并完成整个生命周期。`Spring` 容器依赖控制反转（`Inversion of Control`），也即依赖注入（`Dependency Injection`）来配置并注入对象。这样的对象被成为 `Bean`。具体过程可抽象为：`Spring` 读取程序中的 `Bean` 配置信息，并据此在容器中生成一份 `Bean` 配置注册表，然后再根据注册表实例化 `Bean` ，装配好待用。

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuIf8JCvEJ4zL22ueoinBVxfkvzEPAvvsp7swlFjfppI5QYu5803AvvKel6pjVRvtdK8qK0W2d58Jyo22J_OlVDQu7YvXgAVmTFwk9xlw529yVHIUBTZpT4__yraj4BNMS6L6C6NFDgzuiNmn5XN6S8Ey4iiI5T1Kn28v3k9mDCSf00r-sjRpOk4A3FK1_bx-nGZb43uMK-SzsGSA28HAX1ZO2Wmjp_TCVhfsnhED2z3SWf30j6NNbETJLZnVqVrqLpz861RIkdPGRrafl5Y_-sd_D90arEMwG4cOIy3Yi1105hT2LOBW0LKXt0DKjQGTw02G4eGeK0cAmwmKdkpT3r9Lo-MGcfS2J3e0)

`Spring` 提供了两种容器：`BeanFactory` 与 `ApplicationContext`。`BeanFactory` 为  `Spring Ioc` 功能提供了底层的实现基础，但为了实现框架化，`Spring` 新增了`ApplicationContext` 接口。 `ApplicationContext` 继承于 `BeanFactory`，并涵盖其所有功能。[官方](<https://docs.spring.io/spring/docs/5.2.5.RELEASE/spring-framework-reference/core.html#context-introduction-ctx-vs-beanfactory>)对两个容器做出比较：

| 特征                                | BeanFactory | ApplicationContext |
| :---------------------------------- | :---------: | :----------------: |
| Bean 实例化 / 连接                  |     是      |         是         |
| 集成生命周期管理                    |     否      |         是         |
| `BeanPostProcessor` 自动注册        |     否      |         是         |
| `BeanFactoryPostProcessor` 自动注册 |     否      |         是         |
| 利用 `MessageSource` 进行国际化     |     否      |         是         |
| 嵌入式 `ApplicationEvent` 发布机制  |     否      |         是         |

本文分析 `ApplicationContext` 容器。Spring 源码参考版本 [5.2.5.RELEASE](<https://docs.spring.io/spring/docs/5.2.5.RELEASE/spring-framework-reference/index.html>)。

#### 二、`ApplicationContext` 容器涉及的类关系图

`ApplicationContext` 有很多实现类，这里我们以 `Java EE web ` （采用 `Spring` 框架）应用的启动过程为例。为了更直观地描述初始化过程，我们有必要认识  `XmlWebApplicationContext` 的关联类图:

![](http://www.plantuml.com/plantuml/png/hLNHhjCm37tlL_G7jY_WOMCCWJJGD93WrStSDLAQJ8ax6EBZMTHLiZgtIT7DMzjpJe_jsDu40azTQmfb88JoPsj-OBMzNerMGDhPdRE4lwc0Af07HMMFspuVJrXx30rK1cLU1l41hVL5u6fBw6jGMFQGpel_6M6_DzZYDzTvXJb_dzLwZs2_GelRN-2HlVziDMam-e-sbuXXdvYzP2WByZMhEROt2pxe6jLT6UIcZ0iO7HNFU_01Q-WCdJ34HEB1mHbzTXGCkBStxPrjqT8EhX7EhUX0yLLCuKTGvFoTVVsaqODNZLPWPCGN304kGx75-FStj7JiAgD3Wpo28RGZ4A6tyT7Sq7ELZXnBp8WgPOMxB79Rf7oSTtzNg-dUMz0plL9sToRxgXnEzBXUvokpBYmJPw6ob8vq8jBJXlSwfhpcouv7nHl99ghLdpu9wU4vtyrfCRa-2ueYo0Xbu4P6erbopT6YrHGhDUM6IIhOpA4Fi-K_wOKueva6p_NYehCRATDV1_jh109D6Favj8bTaABn1S7yfMYJ-sEUDh5Iad_ZUqOsoHSq2t_uFBagHtSZrbHUxQ8ghvMisEEcLka6xRbhpJy0)

 #### 三、`ApplicationContext` 容器初始化

`Java EE Web` 项目启动，会触发 `ContextLoaderListener` 监听器，完成 `WebApplicationContext` -根容器的初始化。具体实现方法如下:

```java
/**
* web.xml 中 <context>contextLoaderListener</context> 触发根容器初始化
*
* @param servletContext 整个应用的上下文; 一个应用只有一个 ServletContext
* @return 根容器
*/
public WebApplicationContext initWebApplicationContext(ServletContext servletContext) {
    // 根容器挂载在 ServletContext 下，有且仅有一个根容器
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
            // 默认生成的根容器为 XmlWebApplicationContext
            this.context = createWebApplicationContext(servletContext);
        }
        if (this.context instanceof ConfigurableWebApplicationContext) {
            ConfigurableWebApplicationContext cwac
                = (ConfigurableWebApplicationContext) this.context;
            // 根容器还没有被刷新
            if (!cwac.isActive()) {
                // 添加父容器
                if (cwac.getParent() == null) {
                    // 对于 web 应用， 父容器默认为空
                    ApplicationContext parent = loadParentContext(servletContext);
                    cwac.setParent(parent);
                }
                // 配置并刷新容器
                configureAndRefreshWebApplicationContext(cwac, servletContext);
            }
        }
        // 将根容器挂载在 ServletContext 下，指定属性 name 值，方便在应用内部随时使用
        servletContext
            .setAttribute(WebApplicationContext
                          .ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, this.context);
        // 获取当前线程的上下文加载器
        ClassLoader ccl = Thread.currentThread().getContextClassLoader();
        if (ccl == ContextLoader.class.getClassLoader()) {
            currentContext = this.context;
        } else if (ccl != null) {
            // 若上下文加载器不是 ContextLoader 加载器，则存至 currentContextPerThread 静态域
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
        // 若发生异常，则将异常挂载到 ServletContext 上下文中，此后不再初始化
        servletContext
            .setAttribute(WebApplicationContext
                          .ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, ex);
        throw ex;
    }
}

/**
* 创建根容器 WebApplicationContext
*
* @param sc ServletContext 应用上下文; 一个应用只有一个应用上下文
* @return WebApplicationContext 根容器
*/
WebApplicationContext createWebApplicationContext(ServletContext sc) {
    // 判断根容器的实现类
    Class<?> contextClass = determineContextClass(sc);
    if (!ConfigurableWebApplicationContext.class.isAssignableFrom(contextClass)) {
        throw new ApplicationContextException("...");
    }
    // 实例化根容器
    return (ConfigurableWebApplicationContext) BeanUtils.instantiateClass(contextClass);
}

/**
* 判断根容器的实现类
*
* @param servletContext 应用上下文; 一个应用只有一个应用上下文
* @return 根容器的实现类; 默认为 XmlWebApplicationContext
*/
Class<?> determineContextClass(ServletContext servletContext) {
    // 读取web.xml中的配置 <context-param>contextClass</context-param>
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
        // 若未配置, 则创建默认的根容器 XmlWebApplicationContext
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

从代码实现可以得出：

* 一个 `Web` 应用，根容器只能创建一次；

* 根容器的实现类可配置，默认为 `XmlWebApplicationContext`；

* 需要为根容器指定父容器，旨在实现父容器-子容器的继承架构。目前持保留实现，默认为 `null`；

* 根容器 `WebApplicationContext` 是挂载在应用上下文 `ServletContext` 下的，并指定属性名  `WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE`。

  

  下面介绍根容器的配置与刷新:

```java
/**
* WebApplicationContext 根容器的配置与刷新
*
* @param wac WebApplicationContext 根容器的可配置继承
* @param sc  ServletContext 应用上下文; 一个应用只有一个应用上下文
*/
void configureAndRefreshWebApplicationContext(ConfigurableWebApplicationContext wac,
                                              ServletContext sc) {
    // 1. 为根容器配置 ID，用于后面加载Spring-MVC的配置文件
    if (ObjectUtils.identityToString(wac).equals(wac.getId())) {
        String idParam = sc.getInitParameter(CONTEXT_ID_PARAM);
        if (idParam != null) {
            wac.setId(idParam);
        } else {
            // 生成默认的 ID
            wac.setId(ConfigurableWebApplicationContext.APPLICATION_CONTEXT_ID_PREFIX +
                      ObjectUtils.getDisplayString(sc.getContextPath()));
        }
    }
    // 2. 为根容器配置应用上下文
    wac.setServletContext(sc);
    // 3. 为根容器添加配置参数地址
    // 读取web.xml中的配置 <context-param>configLocation</context-param>
    String configLocationParam = sc.getInitParameter(CONFIG_LOCATION_PARAM);
    if (configLocationParam != null) {
        wac.setConfigLocation(configLocationParam);
    }
    // 4. 初始化环境属性
    ConfigurableEnvironment env = wac.getEnvironment();
    if (env instanceof ConfigurableWebEnvironment) {
        ((ConfigurableWebEnvironment) env).initPropertySources(sc, null);
    }
    // 5. 自定义上下文
    customizeContext(sc, wac);
    // 6. 刷新根容器
    wac.refresh();
}

/**
* 自定义上下文
*
* @param sc  ServletContext 应用上下文; 一个应用只有一个应用上下文
* @param wac WebApplicationContext 根容器的可配置继承
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
        // 创建 Initializer 实例，并添加到 contextInitializers
        this.contextInitializers.add(BeanUtils.instantiateClass(initializerClass));
        AnnotationAwareOrderComparator.sort(this.contextInitializers);
        for (ApplicationContextInitializer<ConfigurableApplicationContext>
             initializer : this.contextInitializers) {
            // 依次执行初始化程序
            initializer.initialize(wac);
        }
    }
}
```

从代码实现可以得出：

* 通过 `<context-parm>configLocation</context-param>` 为根容器添加配置信息；
* 因为只要刷新上下文，就要调用环境的 `initPropertySources` 方法，所以需要提前初始化环境属性，以保证根容器刷新之前的一些操作，如后置处理或初始化过程，都可以直接获取到 `Servlet` 属性；
* 在根容器添加配置后，刷新前，执行自定义操作。根据 `ServletContext` 的 `contextInitializerClasses` 和 `globalInitializerClasses`  配置加载所有的上下文初始化程序，并依次执行；
* 自定义根容器后，执行根容器的刷新。放在下一个专栏分解。













  