---
title: 在异步线程或线程池中传输 ThreadLocal 上下文
date: 2020-12-14 01:45:12
tags: ThreadLocal
categories: 后端
---

#### 一、背景介绍

`ThreadLocal`是线程提供的本地变量，因其线程特殊属性，被经常用于存储与线程相关的信息，如保存登录用户信息、数据库连接配置等。但我们忽略了一个关键点：`ThreadLocal` 只能用在同步线程中，而在异步线程或线程池中则不起作用。因此，本博文主要探讨如何在异步线程和线程池中传递 `ThreadLocal` 上下文。

<!-- more -->
#### 二、问题描述

发版之后，爆出线上问题：“用户信息获取失败”。为了更好地解释这个问题，先介绍下公司的系统架构：用户登录时，后台系统通过用户 `key` 获取个人信息并保存在 `ThreadLocal` 静态对象中，以供后续使用。简要实现如下：

```java
/**
* 拦截器
*/
@Component
public class HandlerAccessInterceptor implements HandlerInterceptor {
    
    @Override
    public boolean preHandle(HttpServletRequest httpServletRequest,
                             HttpServletResponse httpServletResponse, Object o) throws Exception {
        // 增加允许跨域的返回信息
        httpServletResponse.setHeader("Access-Control-Allow-Origin", "*");
        httpServletResponse.setHeader("Access-Control-Allow-Headers", "Content-Type,Content-Length, Authorization, Accept,X-Requested-With");
        httpServletResponse.setHeader("Access-Control-Allow-Methods", "PUT,POST,GET,DELETE,OPTIONS");
        
        // 获取并保存用户信息
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
    
    // 清除用户信息
    @Override
    public void afterCompletion(HttpServletRequest httpServletRequest, HttpServletResponse httpServletResponse, Object o, Exception e) throws Exception {
        UserContextUtil.remove();
    }
}

/**
* 用户信息工具
*/
@Component
public class UserContextUtil {
    private static ThreadLocal<SyUser> threadLocal = new ThreadLocal<>();
    private static final String TOKEN_BEARER = "Bearer ";

    /**
     * 获取当前线程用户信息
     *
     * @return 前线程用户信息
     */
    public synchronized static SyUser getUser() {
        SyUser syUser = threadLocal.get();
        return syUser;
    }

    /**
    * 直接保存用户信息
    */
    public synchronized static boolean setSyUser(SyUser syUser) {

        if (syUser == null) {
            return false;
        }

        threadLocal.set(syUser);

        return true;
    }

    /**
     * 转换登录用户信息为当期系统用户信息
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
     * 转换登录用户信息为当期系统用户信息
     *
     * @param headerValue 头部 vkey 值
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
     * 获取登录用户姓名
     */
    public synchronized static String getUserName() {
        SyUser syUser = threadLocal.get();
        if (syUser == null) {
            return null;
        }
        return syUser.getTrueName();
    }

    /**
     * 移除线程中用户信息
     */
    public synchronized static void remove() {
        threadLocal.remove();
    }
}
```

问题代码定位：

```java
@RestController
@RequestMapping("/web/file")
@Slf4j
public class ManageFileController {
    
    @Resource
    private ManageFileService manageFileService;
    
	/**
     * 【加载文件】
     * 下载文件的数据准备阶段可能非常长, 前台操作人员无法得知进度, 且无法做其他操作
     * 故将数据准备与文件下载解耦, 解决交互上不舒服的问题
     *
     * @param loadFileReqDTO 加载文件请求
     * @return 调用是否成功
     */
    @PostMapping("/loadFile")
    public RespDTO<String> loadFile(@Valid @RequestBody LoadFileReqDTO loadFileReqDTO) {

        // 初始化加载文件信息
        AsyncLoadFile asyncLoadFile = manageFileService.initLoadFileInfo(loadFileReqDTO);

        // 执行文件加载
        manageFileService manageFileService.loadFile(loadFileReqDTO, inheritedSyUser);

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
     * 【加载文件】
     *
     * @param loadFileReqDTO 加载文件请求
     * @param asyncLoadFile  初始化加载文件信息
     * @param syUser         用户信息
     */
    @Async(TASK_EXECUTOR)
    public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {

        try {

            log.info("异步加载文件开始; userName: {}", UserContextUtil.getUserName());

            // 路由加载服务
            LoadFileService loadFileService = manageFileHelper.router(loadFileReqDTO.getLoadFileType());

            // 开启文件加载过程
            LoadFileReqBO loadFileReqBO = new LoadFileReqBO();
            BeanUtils.copyProperties(loadFileReqDTO, loadFileReqBO);

            LoadFileRespBO loadFileRespBO = loadFileService.executeLoadFile(loadFileReqBO);

            // 备份文件至影像件系统
            String fileKey = FileUtil.uploadFile(loadFileRespBO.getFilePathUrl(), FileTypeEnum.XLSX, STORE_FILE_KEY);

            CuiShouAssert.notEmpty(fileKey, "调用影像件系统异常!");

            asyncLoadFile.setFileName(loadFileRespBO.getFileName());
            asyncLoadFile.setFileKey(fileKey);
            asyncLoadFile.setLoadStatus(LoadStatusEnum.SUCCESS.name());
        } catch (Exception e) {
            log.info("加载文件异常; errMsg: {}", e.getMessage(), e);
            asyncLoadFile.setLoadStatus(LoadStatusEnum.FAILURE.name());
            asyncLoadFile.setRemark(e.getMessage());
        }

        asyncLoadFileMapper.update(asyncLoadFile);
        
        log.info("异步加载文件结束; userName: {}", UserContextUtil.getUserName());
    }
}
```

```java
运行结果...
2020-12-14 17:51:15.235  INFO [-,d11235d6f6eda8d0,8c023b1e45855f97,false] 19444 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : 异步加载文件开始; userName: null
```

问题很好定位，`@Async` 异步线程池开启子线程处理任务后，父线程提供的本地线程变量就销毁了。

#### 三、解决方法

* 将用户信息当作参数传入异步方法，再在异步方法中重新设置本地变量；
* 采用 `InheritedThreadLocal` 实现子线程上下文的传递。

```java
/**
 * 【加载文件-方法一】
 * 下载文件的数据准备阶段可能非常长, 前台操作人员无法得知进度, 且无法做其他操作
 * 故将数据准备与文件下载解耦, 解决交互上不舒服的问题
 *
 * @param loadFileReqDTO 加载文件请求
 * @return 调用是否成功
 */
@PostMapping("/loadFile")
public RespDTO<String> loadFile(@Valid @RequestBody LoadFileReqDTO loadFileReqDTO) {

    // 初始化加载文件信息
    AsyncLoadFile asyncLoadFile = manageFileService.initLoadFileInfo(loadFileReqDTO);
    
    // #loadFile 为异步方法, 这里将操作人信息继承到子线程中
    SyUser syUser = UserContextUtil.getUser();

    SyUser inheritedSyUser = new SyUser();

    BeanUtils.copyProperties(syUser, inheritedSyUser);

    // 执行文件加载
    manageFileService manageFileService.loadFile(loadFileReqDTO, inheritedSyUser);

    return RespDTO.success();
}

/**
* 【加载文件】
* 下载文件的数据准备阶段可能非常长, 前台操作人员无法得知进度, 且无法做其他操作
* 故将数据准备与文件下载解耦, 解决交互上不舒服的问题
*
* @param loadFileReqDTO 加载文件请求
* @param asyncLoadFile  初始化加载文件信息
* @param syUser         用户信息
*/
@Async(TASK_EXECUTOR)
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("异步加载文件开始; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("异步加载文件结束; UserName: {}", UserContextUtil.getRealName());
}
```

```java
方法一运行结果...
2020-12-14 18:03:34.947  INFO [-,480f9c55e785ec6f,c8de532979871193,false] 19444 --- [common-async-executor-2] c.v.c.o.service.file.ManageFileService   : 异步加载文件开始; UserName: 邹荣升
2020-12-14 18:03:35.235  INFO [-,480f9c55e785ec6f,c8de532979871193,false] 19444 --- [common-async-executor-2] c.v.c.o.service.file.ManageFileService   : 异步加载文件结束; UserName: null
```

方法一可以说是傻瓜操作，治标不治本，后来的同事稍不注意还会掉进坑里。我们来实现方法二：

```java
private static ThreadLocal<SyUser> threadLocal = new InheritableThreadLocal<>();

/**
* 【加载文件-异步线程】
* 下载文件的数据准备阶段可能非常长, 前台操作人员无法得知进度, 且无法做其他操作
* 故将数据准备与文件下载解耦, 解决交互上不舒服的问题
*
* @param loadFileReqDTO 加载文件请求
* @param asyncLoadFile  初始化加载文件信息
* @param syUser         用户信息
*/
@Async
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("异步加载文件开始; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("异步加载文件结束; UserName: {}", UserContextUtil.getRealName());
}

/**
* 【加载文件-异步线程池】
* 下载文件的数据准备阶段可能非常长, 前台操作人员无法得知进度, 且无法做其他操作
* 故将数据准备与文件下载解耦, 解决交互上不舒服的问题
*
* @param loadFileReqDTO 加载文件请求
* @param asyncLoadFile  初始化加载文件信息
* @param syUser         用户信息
*/
@Async(TASK_EXECUTOR)
public void loadFile(LoadFileReqDTO loadFileReqDTO, AsyncLoadFile asyncLoadFile, SyUser syUser) {
    
    UserContextUtil.setSyUser(syUser);
    log.info("异步加载文件开始; UserName: {}", UserContextUtil.getRealName());
    UserContextUtil.remove();
    log.info("异步加载文件结束; UserName: {}", UserContextUtil.getRealName());
}
```

异步线程和异步线程池两种情况下的运行结果：

```java
运行结果...
2020-12-14 18:36:41.560  INFO [-,8658c694de3e9b7a,ccc7a782204c91b0,false] 19876 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : 异步加载文件开始; UserName: 邹荣升

2020-12-14 18:41:17.735  INFO [-,67b4725bcaacfc64,36ee2acec232be32,false] 21600 --- [common-async-executor-1] c.v.c.o.service.file.ManageFileService   : 异步加载文件开始; UserName: 邹荣升
```

#### 三、总结

虽然 `ThreadLocal` 的线程相关属性提供了很多便利性，但在高并发系统中，直接使用原生静态对象并不合适。因此，如使用 `Redis`、`MQ` 一样，深入了解常用工具的特性，是系统设计的必备要素。