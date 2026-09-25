---
title: Using Spring Retry for Third-Party API Integration
date: 2021-10-07 15:57:01
tags: Spring
categories: Backend
lang: en
label: 027_spring_retry_app
---

-----

<!-- more -->
#### 1. The Token Expiry Problem in Third-Party Integrations

Many applications need to integrate with external platforms — payment gateways, enterprise service providers, and so on. For security, these third-party services typically issue a token to the caller, and all business operations require a valid token. Tokens have an expiration window, so the caller caches the token and refreshes it only when the cache expires. This approach reduces the number of calls to the third-party service and keeps response times low.

This setup introduces a subtle failure mode: the token may expire on the third-party side while the caller's cache still considers it valid. Every subsequent API call fails with a token-expired error. From the API's perspective, rejecting requests with an expired token is correct behavior. But from a system design perspective, letting token expiry cascade into blanket API failures is poor engineering. A robust design should transparently refresh the token at the integration layer and retry the operation, so the caller never notices the interruption.

This is exactly where Spring Retry proves useful — it turns a hard failure into a self-healing flow.

#### 2. What to Watch Out For

Spring Retry works by wrapping the target method in a proxy and re-invoking it when a specified exception is thrown. The key question is what makes a retry succeed when the first attempt failed.

Consider a payment service integration. When the server responds with "token expired, query failed", simply retrying with the same stale token will produce the same error. The retry logic needs to do two things:

* **Listen for the right exception**: Catch the token-expired exception and trigger a retry according to the configured policy;
* **Clear the stale cache**: Evict the expired token from cache before the retry executes, so the next attempt fetches a fresh token;

Both pieces are necessary. Retry without cache eviction is pointless — you'd just be hammering the third-party service with the same bad token.

#### 3. Implementation

The business method uses two annotations: `@Retryable` to drive the retry loop, and a custom `@TokenExpiredExceptionCatch` to handle cache eviction.

```java
@Retryable(value = {TokenExpiredException.class}, maxAttempts = 3, backoff = @Backoff(delay = 100L, multiplier = 1))
@TokenExpiredExceptionCatch
public Response invoke(Request request) {
    // Get token from cache
    String token = cache.getToken();
    // If cache is empty, call the third-party API to fetch a new token
    if (StringUtils.isEmpty(token)) {
        // Call the third-party platform, get a new token, and cache it
        token = newToken;
    }
    // Call the third-party service
    ResponseInfo responseInfo = Server.queryPayResult(token, request);
    if (responseInfo.getCode == 1002) {
        throw new TokenExpiredException(responseInfo.getMessage());
    }
    return responseInfo.getData();
}
```

Custom annotation definition:

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface TokenExpiredExceptionCatch {
}
```

AOP aspect to intercept the custom annotation and evict the stale token:

```java
@Around("@annotation(com.aspects.TokenExpiredExceptionCatch)")
public Object handler(ProceedingJoinPoint joinPoint) throws Throwable {
    try {
        return joinPoint.proceed();
    } catch (AbstractCustomException e) {
        // Parse the error code
        ErrorCodeEnum errorCodeEnum = ErrorCodeEnum.getByCode(String.valueOf(e.getCode()));
        // --------------Handle token expired exception--------------
        if (ErrorCodeEnum.TOKEN_EXPIRED.equals(errorCodeEnum)) {
            // Evict the cached token
        }
        throw e;
    }
}
```

The flow works like this: the business method throws `TokenExpiredException`, the AOP aspect catches it, clears the stale token from cache, and re-throws the exception. Spring Retry catches the exception, waits for the backoff period, and re-invokes the method. This time, the cache is empty, so a fresh token is fetched from the third-party service, and the operation succeeds.

#### 4. Caveats

Spring Retry is easy to set up and integrates cleanly with Spring projects, but it shouldn't be applied blindly across all interfaces. Payment and refund operations are particularly sensitive — retrying a payment without verifying idempotency can trigger duplicate charges and customer complaints. Any interface that uses retry must be checked for idempotency first. If the third-party API doesn't guarantee idempotent behavior, retry is not a safe option.