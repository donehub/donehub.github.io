---
title: Spring 对象拷贝机制
date: 2021-11-11 13:57:01
tags: Spring
categories: 后端
---

-----

#### 一、 `Spring` 对象拷贝的具体实现

`Spring` 对象拷贝，基于反射和内省，将源对象字段值装填到目标对象字段上。主要分以下两步：

* 获取源对象和目标对象的变量的属性信息；
* 对于需要拷贝的目标变量，解析源变量的属性信息，并赋值；

```java
/**
 * Spring 对象拷贝基础方法
 *
 * @param source           源对象
 * @param target           目标对象
 * @param editable         限制目标 Class
 * @param ignoreProperties 需要忽略的拷贝字段
 */
private static void copyProperties(Object source, Object target, Class<?> editable,
                                   String... ignoreProperties) throws BeansException {
    
    Assert.notNull(source, "Source must not be null");
    Assert.notNull(target, "Target must not be null");
    
    Class<?> actualEditable = target.getClass();
    if (editable != null) {
        // 如果 target 不是 editable 的实例, 则中断拷贝
        if (!editable.isInstance(target)) {
            throw new IllegalArgumentException("Target class [" + target.getClass().getName() +"] not assignable to Editable class [" + editable.getName() + "]");
        }
        actualEditable = editable;
    }
    // 内省目标 Bean, 得到对应变量的属性信息列表
    PropertyDescriptor[] targetPds = getPropertyDescriptors(actualEditable);
    // 解析需要忽略拷贝的字段
    List<String> ignoreList = (ignoreProperties != null ? Arrays.asList(ignoreProperties) : null);
    // 遍历目标对象的变量属性信息, 依次进行变量值的拷贝
    for (PropertyDescriptor targetPd : targetPds) {
        // 解析目标变量值的写入方法
        Method writeMethod = targetPd.getWriteMethod();
        // 如果目标变量可以写入且需要拷贝, 则读取源变量的属性信息, 读取对应的值并拷贝到目标变量中
        if (writeMethod != null && (ignoreList == null || !ignoreList.contains(targetPd.getName()))) {
            // 内省源 Bean, 缓存所有变量的属性信息, 并根据目标变量名称取出对应的源变量的属性信息
            PropertyDescriptor sourcePd = getPropertyDescriptor(source.getClass(), targetPd.getName());
            if (sourcePd != null) {
                // 解析源变量值的读取方法
                Method readMethod = sourcePd.getReadMethod();
                if (readMethod != null
                    && ClassUtils.isAssignable(writeMethod.getParameterTypes()[0],
                                              readMethod.getReturnType())) {
                    
                    try {
                        if (!Modifier.isPublic(readMethod.getDeclaringClass().getModifiers())) {
                            readMethod.setAccessible(true);
                        }
                        // 读取源变量值
                        Object value = readMethod.invoke(source);
                        if (!Modifier.isPublic(writeMethod.getDeclaringClass().getModifiers())) {
                            writeMethod.setAccessible(true);
                        }
                        // 将源变量值写入目标变量
                        writeMethod.invoke(target, value);
                    } catch (Throwable ex) {
                        throw new FatalBeanException("Could not copy property '" + targetPd.getName() + "' from source to target", ex);
                    }
                }
            }
        }
    }
}
```



#### 二、 `BeanUtils.copyProperties`实现原理

根据以上分析，整合出 `Spring` 对象拷贝的实现原理：

![](http://assets.processon.com/chart_image/618cc3a7e0b34d73f7f1b7cd.png?_=1636618716955)

通过内省机制，对 `Bean` 进行拆分，得到每个变量的属性信息，缓存在 `Map` 中，`Key`为变量名，`Value`为属性信息。属性信息主要包括：变量名称、读取变量值的方法、设置变量值的方法。拷贝过程中，先获取目标变量的写入方法，再获取对应源变量的读取方法，最后完成变量值的拷贝。