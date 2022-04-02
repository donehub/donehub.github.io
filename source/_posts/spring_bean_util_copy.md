---
title: Spring 对象拷贝机制
date: 2021-11-11 13:57:01
tags: Spring
categories: 后端
---

-----

#### 一、 `Spring` 对象拷贝的具体实现

`Spring` 对象拷贝，基于反射和内省，将源对象字段值装填到目标对象字段上。主要分以下两步：

* 通过内省，获取源对象和目标对象的属性描述器；
* 通过反射，解析源属性值，赋值到目标属性中；

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
    // 内省目标对象, 获取其属性描述器列表
    PropertyDescriptor[] targetPds = getPropertyDescriptors(actualEditable);
    // 解析需要忽略拷贝的字段
    List<String> ignoreList = (ignoreProperties != null ? Arrays.asList(ignoreProperties) : null);
    // 遍历目标对象的属性描述器, 依次进行属性值的拷贝
    for (PropertyDescriptor targetPd : targetPds) {
        // 解析目标属性描述器的写入方法
        Method writeMethod = targetPd.getWriteMethod();
        // 如果目标属性可以写入且需要拷贝, 则内省源对象, 获取对应的属性描述器, 读取属性值并拷贝到目标属性中
        if (writeMethod != null && (ignoreList == null || !ignoreList.contains(targetPd.getName()))) {
            // 内省源对象, 缓存属性描述器, 并根据目标属性名称取出对应的源属性的描述器
            PropertyDescriptor sourcePd = getPropertyDescriptor(source.getClass(), targetPd.getName());
            if (sourcePd != null) {
                // 解析源属性值的读取方法
                Method readMethod = sourcePd.getReadMethod();
                if (readMethod != null
                    && ClassUtils.isAssignable(writeMethod.getParameterTypes()[0],
                                              readMethod.getReturnType())) {
                    
                    try {
                        if (!Modifier.isPublic(readMethod.getDeclaringClass().getModifiers())) {
                            readMethod.setAccessible(true);
                        }
                        // 读取源属性值
                        Object value = readMethod.invoke(source);
                        if (!Modifier.isPublic(writeMethod.getDeclaringClass().getModifiers())) {
                            writeMethod.setAccessible(true);
                        }
                        // 写入目标属性
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

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_39_5_introspector.jpg)

通过内省机制，对 `Bean` 进行拆分，得到每个属性的描述器，缓存在 `Map` 中，`Key`为变量名，`Value`为属性描述器。属性描述器主要包括：属性名称、读取属性值的方法、设置属性值的方法。拷贝过程中，先获取目标属性的写入方法，再获取对应源属性的读取方法，最后通过反射拷贝属性值。

#### 三、`JavaBean`内省机制

`JavaBean` 内省，是建立在反射基础上的，通过解析 `Bean`各个属性的描述器，以便通过属性描述器来操作 `Bean` 的一种机制。反射是将 `Java` 类中的各种成分映射成相应的 `Java` 类，可以获取所有属性以及调用任何方法。与反射不同的是，内省是通过属性描述器来暴露一个 `Bean` 的属性、方法和时间的，而且只有符合 `JavaBean` 规则的类的成员才可以调用内生 `API` 进行操作。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_37_1_refect_instropection.png)

内省在 `java.beans.Introspector`中的具体实现：

```java
// 获取所有的 public 方法
Method methodList[] = getPublicDeclaredMethods(beanClass);
// 循环遍历处理每一个 public 方法, 为方便讲解, 此处我们以第一个方法为例...

Method method = methodList[0];
if (method == null) {
    continue;
}
// 跳过 static 方法
int mods = method.getModifiers();
if (Modifier.isStatic(mods)) {
    continue;
}
// 获取该方法的名称, 如setAge、getAge
String name = method.getName();
// 获取该方法的入参和返参
Class<?>[] argTypes = method.getParameterTypes();
Class<?> resultType = method.getReturnType();
// 获取该方法的入参个数
int argCount = argTypes.length;
PropertyDescriptor pd = null;

if (argCount == 0) {
    // 1. 没有入参: 说明是获取属性值的方法
    if (name.startsWith(GET_PREFIX)) {
        // 1.1 该方法名称以 get 开头, 如 getAge
        pd = new PropertyDescriptor(this.beanClass, name.substring(3), method, null);
    } else if (resultType == boolean.class && name.startsWith(IS_PREFIX)) {
        // 1.2 该方法名称以 is 开头, 如 isMale, 只处理基本类型的布尔值
        pd = new PropertyDescriptor(this.beanClass, name.substring(2), method, null);
    }
} else if (argCount == 1) {
    // 2. 有一个入参
    if (int.class.equals(argTypes[0]) && name.startsWith(GET_PREFIX)) {
        // 2.1 获取属性值的方法, 如 getChild(Integer index), 则封装成索引属性器
        pd = new IndexedPropertyDescriptor(this.beanClass, name.substring(3), null, null, method, null);
    } else if (void.class.equals(resultType) && name.startsWith(SET_PREFIX)) {
        // 2.2 设置属性值的方法
        pd = new PropertyDescriptor(this.beanClass, name.substring(3), null, method);
        if (throwsException(method, PropertyVetoException.class)) {
            pd.setConstrained(true);
        }
    }
} else if (argCount == 2) {
    // 3. 有两个入参
    if (void.class.equals(resultType) && int.class.equals(argTypes[0]) && name.startsWith(SET_PREFIX)) {
        // 3.1 只处理设置属性值的方法, 如 setChild(Integer index, Child child), 则封装成索引属性器
        pd = new IndexedPropertyDescriptor(this.beanClass, name.substring(3), null, null, null, method);
        if (throwsException(method, PropertyVetoException.class)) {
            pd.setConstrained(true);
        }
    }
}

return PropertyDescriptor;
```

由此可以看出，一个类的方法名称、入参个数、反参类型是`JavaBean` 内省的主要要素，可以总结为：

* 只能内省一个类暴露的 `public` 非静态方法；
* 可以内省标准化的 `set` 方法，如  `void setAge(Integer age)`；
* 可以内省标准化的 `get` 方法，如  `ResultType getAge()`；
* 可以内省设置索引属性的方法，如 `setChild(Integer index, Child child)`；
* 可以内省获取索引属性的方法，如 `getChild(Integer index)`；
* 可以内省获取基本类型布尔值的且以 `is` 开头的方法，如 `boolean isMale()`；

#### 五、总结

`Spring` 对象拷贝，基于反射和内省机制，通过属性描述器，将源属性值写入目标属性。如今 `Spring` 架构已被广泛使用，旗下各种好用的工具也是顺手拈来，但无端的滥用也潜藏着一些问题。比如 `Spring` 对象拷贝，要求操作的对象必须符合 `JavaBean` 规范，否则将无法拷贝。如拷贝包装类型的布尔值，其读取方法为 `Boolean isMale` ，不符合 `JavaBean` 规范，对应的目标属性值一定是 `null`。