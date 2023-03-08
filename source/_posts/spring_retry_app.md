---
title: Spring Retry 在对接第三方API中的使用
date: 2021-10-07 15:57:01
tags: Spring
categories: 后端
---

-----

#### 一、Spring Retry 使用场景之调用第三方服务

在很多应用中，都需要对接第三方平台，如调用支付平台、调用外部企业平台等。出于对接口通信的安全性考虑，第三方服务往往都会下发一个 token 给调用方，调用方只有通过这个 token 才能完成业务处理。但这个 token 是存在有效期的，因此调用方也会把 token 缓存一定的时间，在有效期内直接读取缓存，缓存过期便再次请求第三方平台下发一个新的 token，缓存起来。这样既可以减少对第三方服务的调用次数，也可以缩短接口的处理时间。

这样就存在一个问题：如果这个 token 因为种种原因在第三方是已过期的状态，而调用方的缓存未过期，那么调用方的所有业务操作都会出错。从接口逻辑上来说，报错是正确的，也是有必要的，但在系统设计层面上来看，因为 token 过期导致的所有接口报错，是不合理的。好的设计应该是在接口层重新获取 token，继续完成业务逻辑，对顶层调用无感。

因此，spring retry 在对接第三方服务的场景中，可以有效提升接口的容错性。

#### 二、Spring Retry 在实际应用中的关注点

spring retry 本质上是代理逻辑的重复处理，每次处理的代码逻辑都是一样的，那么重复处理的意义何在？

我们以调用支付服务为例，当服务端告诉我们：“token 已过期，查询支付结果失败”，我们首先要做的事，就是把token已过期这个异常抛出去，让 spring retry 监听到这个异常，进行重试。重试的结果，必然还是“token 已过期，查询支付结果失败”，因为重试过程中使用的 token 还是已过期的 token。因此，不仅需要重试，还需要在重试之前清除 token 缓存。也就是说，spring retry 至少需要关注两点：

* 监听异常：对于指定的异常，按照配置的策略，开启重试；
* 清除缓存：对于指定的异常，清除缓存；

#### 三、代码实现

在底层方法上，使用 @Retryable 和 @TokenExpiredExceptionCatch 两个注解。前者的作用是发起业务重试，后者的作用是清除 token 缓存。

```java
@Retryable(value = {TokenExpiredException.class}, maxAttempts = 3, backoff = @Backoff(delay = 100L, multiplier = 1))
@TokenExpiredExceptionCatch
public Response invoke(Request request) {
    // 从缓存中获取 token 
    String token = cache.getToken();
    // 缓存不存在，则调用接口请求再次下发 token
    if (StringUtils.isEmpty(token)) {
        // 调用第三方平台，获取新的token，并缓存
        token = newToken;
    }
    // 调用第三方服务
    ResponseInfo responseInfo= Server.queryPayResult(token, request);
    if (responseInfo.getCode == 1002) {
        throw new TokenExpiredException(responseInfo.getMessage());
    }
    return responseInfo.getData();
}
```

自定义注解 @TokenExpiredExceptionCatch

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface TokenExpiredExceptionCatch {
}
```

切面监听注解 @TokenExpiredExceptionCatch

```java
@Around("@annotation(com.aspects.TokenExpiredExceptionCatch)")
public Object handler(ProceedingJoinPoint joinPoint) throws Throwable {
    try {
        return joinPoint.proceed();
    } catch (AbstractCustomException e) {
        // 解析异常码值
        ErrorCodeEnum ErrorCodeEnum = ErrorCodeEnum.getByCode(String.valueOf(e.getCode()));
        // --------------处理 token 已过期异常--------------
        if (ErrorCodeEnum.TOKEN_EXPIRED.equals(ErrorCodeEnum)) {
            // 清除缓存 token
        }
        throw e;
    }
}
```

#### 四、Spring Retry 注意事项

spring retry 是一个很好用的重试工具，配置简单，对 Spring 项目兼容良好，但也不可无脑使用，让所有接口都在底层无感重试。如果支付/退款业务发生重试，极有可能引来客诉或发生资损。因此，在引入重试机制的接口上，一定要判断接口的幂等性。