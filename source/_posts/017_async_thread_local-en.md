---
title: Propagating ThreadLocal Context in Async Threads and Thread Pools
date: 2020-12-14 01:45:12
tags: ThreadLocal
categories: Backend
lang: en
label: 017_async_thread_local
---

#### 1. Background

`ThreadLocal` provides thread-local variables. Because each thread has its own isolated copy, `ThreadLocal` is commonly used to store thread-specific information like logged-in user details or database connection config. But there's a catch most people miss: `ThreadLocal` only works in synchronous threads. It doesn't carry over to async threads or thread pools. This post explores how to propagate `ThreadLocal` context across async boundaries.

<!-- more -->
#### 2. The Problem

After a release, a production bug surfaced: "Failed to retrieve user info." To understand why, some context on the system architecture helps. When a user logs in, the backend fetches their profile using a user `key` and stores it in a `ThreadLocal` static object for later use. Here's a simplified version:

```java
/**
* Interceptor
*/
@Component
public class HandlerAccessInterceptor implements HandlerInterceptor {
    
    @Override
    public boolean preHandle(HttpServletRequest httpServletRequest,
                             HttpServletResponse httpServletResponse, Object o) throws Exception {
        // Add CORS headers
        httpServletResponse.setHeader("Access-Control-Allow-Origin", "*");
        httpServletResponse.setHeader("Access-Control-Allow-Headers", "Content-Type,Content-Length, Authorization, Accept,X-Requested-With");
        httpServletResponse.setHeader("Access-Control-Allow-Methods", "PUT,POST,GET,DELETE,OPTIONS");
        
        // Fetch and store user info
        if (httpServletRequest.getCookies() != null) {
            for (Cookie cookie : httpServletRequest.getCookies()) {
                if ("vkey".equals(cookie.getName())) {
                    UserContextUtil.setUser(cookie.getValue());
                }
            }
        }
        
        return true;
    }
    
    @Override
    public void postHandle(HttpServletRequest httpServletRequest, HttpServletResponse httpServletResponse, Object o, ModelAndView modelAndView) throws Exception {

    }
    
    // Clean up user info
    @Override
    public void afterCompletion(HttpServletRequest httpServletRequest, HttpServletResponse httpServletResponse, Object o, Exception e) throws Exception {
        UserContextUtil.remove();
    }
}

/**
* User context utility
*/
@Component
public class UserContextUtil {
    private static ThreadLocal<SyUser> threadLocal = new ThreadLocal<>();
    private static final String TOKEN_BEARER = "Bearer ";

    /**
     * Get current thread's user info
     *
     * @return Current thread's user info
     */
    public synchronized static SyUser getUser() {
        SyUser syUser = threadLocal.get();
        return syUser;
    }

    /**
    * Set user info directly
    */
    public synchronized static boolean setSyUser(SyUser syUser) {

        if (syUser == null) {
            return false;
        }

        threadLocal.set(syUser);

        return true;
    }

    /**
     * Parse login token from cookies and set current user
     *
     * @param cookies
     */
    public synchronized static boolean setUser(Cookie[] cookies) {
        if (cookies == null) {
            return false;
        }
        for (Cookie cookie : cookies) {
            String name = cookie.getName().toLowerCase();
            if ("vkey".equals(name)) {
                String value = cookie.getValue();
                if (StrUtil.isEmpty(value)) {
                    return false;
                }
                LoginUser loginUser = new LoginUser(value);
                if (loginUser.getId() == null) {
                    return false;
                }
                SyUser syUser = new SyUser();
                syUser.setId(loginUser.getId().intValue());
                syUser.setUserName(loginUser.getMobile());
                syUser.setTrueName(loginUser.getName());
                return setSyUser(syUser);
            }
        }
        return false;
    }

    /**
     * Parse login token from header and set current user
     *
     * @param headerValue Header vkey value
     */
    public synchronized static boolean setUser(String headerValue) {
        if (StrUtil.isEmpty(headerValue)) {
            return false;
        }
        if (headerValue.startsWith(TOKEN_BEARER)) {
            headerValue = headerValue.substring(TOKEN_BEARER.length());
        }
        LoginUser loginUser = new LoginUser(headerValue);
        if (loginUser.getId() == null) {
            return false;
        }
        SyUser syUser = new SyUser();
        syUser.setId(loginUser.getId().intValue());
        syUser.setUserName(loginUser.getMobile());
        syUser.setTrueName(loginUser.getName());
        syUser.setPhone(loginUser.getMobile());
        return setSyUser(syUser);
    }
    
    /**
     * Get logged-in user's name
     */
    public synchronized static String getUserName() {
        SyUser syUser = threadLocal.get();
        if (syUser == null) {
            return null;
        }
        return syUser.getTrueName();
    }

    /**
     * Remove user info from current thread
     */
    public synchronized static void remove() {
        threadLocal.remove();
    }
}
```

The problematic code:

```java
@RestController
@RequestMapping("/web/file")
@Slf4j
public class ManageFileController {
    
    @Resource
    private ManageFileService manageFileService;
    
	/**
     * [Load file]
     * The data preparation phase for file download can be very long.
     * The frontend operator can't see progress or do anything else.
     * So we decouple data preparation from file download to improve UX.
     *
     * @param loadFileReqDTO Load file request
     * @return Whether the call succeeded
     */
    @PostMapping("/loadFile")
    public RespDTO<String> loadFile(@Valid @RequestBody LoadFileReqDTO loadFileReqDTO) {

        // Initialize file load info
        AsyncLoadFile asyncLoadFile = manageFileService.initLoadFileInfo(loadFileReqDTO);

        // Execute file load
        manageFileService.loadFile(loadFileReqDTO, asyncLoadFile, inheritedSyUser);

        return RespDTO.success();
    }
}

/**
 * @author zourongsheng
 * @version 1.0
 * @date 2020/10/21 13:55
 */
@Service
@Slf4j
public class ManageFileService {
    
    @Resource
    private ManageFileHelper manageFileHelper;
    
    @Resource
    private AsyncLoadFileMapper asyncLoadFileMapper;
    
    /**
     * [Load file]
     *
     * @param loadFileReqDTO Load file request
     * @param asyncLoadFile  Initialized file load info
     * @param syUser         User info
     */
    @Async(TASK_EXECUTOR)
    public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {

        try {

            log.info("Async file load started; userName: {}", UserContextUtil.getUserName());

            // Route to the appropriate load service
            LoadFileService loadFileService = manageFileHelper.router(loadFileReqDTO.getLoadFileType());

            // Start the file loading process
            LoadFileReqBO loadFileReqBO = new LoadFileReqBO();
            BeanUtils.copyProperties(loadFileReqDTO, loadFileReqBO);

            LoadFileRespBO loadFileRespBO = loadFileService.executeLoadFile(loadFileReqBO);

            // Upload file to the imaging system
            String fileKey = FileUtil.uploadFile(loadFileRespBO.getFilePathUrl(), FileTypeEnum.XLSX, STORE_FILE_KEY);

            CuiShouAssert.notEmpty(fileKey, "Imaging system call failed!");

            asyncLoadFile.setFileName(loadFileRespBO.getFileName());
            asyncLoadFile.setFileKey(fileKey);
            asyncLoadFile.setLoadStatus(LoadStatusEnum.SUCCESS.name());
        } catch (Exception e) {
            log.info("File load error; errMsg: {}", e.getMessage(), e);
            asyncLoadFile.setLoadStatus(LoadStatusEnum.FAILURE.name());
            asyncLoadFile.setRemark(e.getMessage());
        }

        asyncLoadFileMapper.update(asyncLoadFile);
        
        log.info("Async file load finished; userName: {}", UserContextUtil.getUserName());
    }
}
```

```java
Output...
2020-12-14 17:51:15.235  INFO [-,d11235d6f6eda8d0,8c023b1e45855f97,false] 19444 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : Async file load started; userName: null
```

The issue is straightforward. When `@Async` spawns a child thread in the thread pool, the parent thread's `ThreadLocal` variables don't carry over.

#### 3. Solutions

* Pass user info as a method parameter to the async method, then re-set it in the `ThreadLocal` inside that method.
* Use `InheritableThreadLocal` to propagate context to child threads.

```java
/**
 * [Load file - Approach 1]
 * The data preparation phase for file download can be very long.
 * The frontend operator can't see progress or do anything else.
 * So we decouple data preparation from file download to improve UX.
 *
 * @param loadFileReqDTO Load file request
 * @return Whether the call succeeded
 */
@PostMapping("/loadFile")
public RespDTO<String> loadFile(@Valid @RequestBody LoadFileReqDTO loadFileReqDTO) {

    // Initialize file load info
    AsyncLoadFile asyncLoadFile = manageFileService.initLoadFileInfo(loadFileReqDTO);
    
    // #loadFile is async; pass user info to the child thread explicitly
    SyUser syUser = UserContextUtil.getUser();

    SyUser inheritedSyUser = new SyUser();

    BeanUtils.copyProperties(syUser, inheritedSyUser);

    // Execute file load
    manageFileService.loadFile(loadFileReqDTO, asyncLoadFile, inheritedSyUser);

    return RespDTO.success();
}

/**
* [Load file]
* The data preparation phase for file download can be very long.
* The frontend operator can't see progress or do anything else.
* So we decouple data preparation from file download to improve UX.
*
* @param loadFileReqDTO Load file request
* @param asyncLoadFile  Initialized file load info
* @param syUser         User info
*/
@Async(TASK_EXECUTOR)
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("Async file load started; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("Async file load finished; UserName: {}", UserContextUtil.getRealName());
}
```

```java
Approach 1 output...
2020-12-14 18:03:34.947  INFO [-,480f9c55e785ec6f,c8de532979871193,false] 19444 --- [common-async-executor-2] c.v.c.o.service.file.ManageFileService   : Async file load started; UserName: Rongsheng Zou
2020-12-14 18:03:35.235  INFO [-,480f9c55e785ec6f,c8de532979871193,false] 19444 --- [common-async-executor-2] c.v.c.o.service.file.ManageFileService   : Async file load finished; UserName: null
```

Approach 1 is a brute-force workaround. It fixes the symptom, not the cause, and the next developer who isn't aware of the pattern will fall into the same trap. Here's approach 2:

```java
private static ThreadLocal<SyUser> threadLocal = new InheritableThreadLocal<>();

/**
* [Load file - async thread]
* The data preparation phase for file download can be very long.
* The frontend operator can't see progress or do anything else.
* So we decouple data preparation from file download to improve UX.
*
* @param loadFileReqDTO Load file request
* @param asyncLoadFile  Initialized file load info
* @param syUser         User info
*/
@Async
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("Async file load started; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("Async file load finished; UserName: {}", UserContextUtil.getRealName());
}

/**
* [Load file - async thread pool]
* The data preparation phase for file download can be very long.
* The frontend operator can't see progress or do anything else.
* So we decouple data preparation from file download to improve UX.
*
* @param loadFileReqDTO Load file request
* @param asyncLoadFile  Initialized file load info
* @param syUser         User info
*/
@Async(TASK_EXECUTOR)
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("Async file load started; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("Async file load finished; UserName: {}", UserContextUtil.getRealName());
}
```

Results for both async thread and async thread pool:

```java
Output...
2020-12-14 18:36:41.560  INFO [-,8658c694de3e9b7a,ccc7a782204c91b0,false] 19876 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : Async file load started; UserName: Rongsheng Zou

2020-12-14 18:41:17.735  INFO [-,67b4725bcaacfc64,36ee2acec232be32,false] 21600 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : Async file load started; UserName: Rongsheng Zou
```

#### 4. Summary

`ThreadLocal`'s thread-isolation property is convenient, but in high-concurrency systems, relying on raw static thread-local objects without understanding their limitations is a recipe for subtle bugs. Like any tool — whether it's `Redis` or `MQ` — deeply understanding the characteristics of the utilities you rely on daily is a prerequisite for solid system design.
