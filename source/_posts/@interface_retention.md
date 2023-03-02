---
title: 元注解 @Retention 的作用机制
date: 2020-10-11 21:27:58
tags: Java
categories: 后端
---

-----

#### 一、@Retention 简介

@Retention 是用来定义注解的注解，这类注解也叫 元注解。@Retention 定义了注解的生命周期，生命周期的长短取决于 `RetentionPolicy` 属性值。

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.ANNOTATION_TYPE)
public @interface Retention {
    /**
     * Returns the retention policy.
     * @return the retention policy
     */
    RetentionPolicy value();
}
```

```java
public enum RetentionPolicy {
    /**
     * Annotations are to be discarded by the compiler.
     */
    SOURCE,

    /**
     * Annotations are to be recorded in the class file by the compiler
     * but need not be retained by the VM at run time.  This is the default
     * behavior.
     */
    CLASS,

    /**
     * Annotations are to be recorded in the class file by the compiler and
     * retained by the VM at run time, so they may be read reflectively.
     *
     * @see java.lang.reflect.AnnotatedElement
     */
    RUNTIME
}
```

归纳如下：

|         属性值          |                            描述                             |                           使用场景                           |
| :---------------------: | :---------------------------------------------------------: | :----------------------------------------------------------: |
| RetentionPolicy.SOURCE  |    注解只保留在源文件，当被编译成class文件，注解就会消失    |          代码预检，如 @Override、@SuppressWarnings           |
|  RetentionPolicy.CLASS  |     注解被保留到class文件，但当jvm加载class文件时被遗弃     | 编译时进行一些预处理操作，如生成辅助信息（META-INF/services） |
| RetentionPolicy.RUNTIME | 注解不仅被保存到class文件中，jvm加载class文件之后，仍然存在 |       运行时动态获取注解信息，如 @Autowired、@Required       |



#### 二、通过字节码认识 @Retention

##### 定义三种生命周期的注解：SourcePolicy、ClassPolicy、RuntimePolicy

```java
@Retention(RetentionPolicy.SOURCE)
@Target(ElementType.METHOD)
public @interface SourcePolicy {
}

@Retention(RetentionPolicy.CLASS)
@Target(ElementType.METHOD)
public @interface ClassPolicy {
}

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface RuntimePolicy {
}
```

使用以上注解：

```java
public class RetentionPolicyTest {
    @SourcePolicy
    public void sourcePolicy() {
    }

    @ClassPolicy
    public void classPolicy() {
    }

    @RuntimePolicy
    public void runtimePolicy() {
    }
}
```

`javap -v RetentionPolicyTest` 查看字节码：

```java
{
  public RetentionPolicyTest();
    flags: ACC_PUBLIC
    Code:
      stack=1, locals=1, args_size=1
         0: aload_0
         1: invokespecial #1                  // Method java/lang/Object."<init>":()V
         4: return
      LineNumberTable:
        line 3: 0

  public void sourcePolicy();
    flags: ACC_PUBLIC
    Code:
      stack=0, locals=1, args_size=1
         0: return
      LineNumberTable:
        line 7: 0

  public void classPolicy();
    flags: ACC_PUBLIC
    Code:
      stack=0, locals=1, args_size=1
         0: return
      LineNumberTable:
        line 11: 0
    RuntimeInvisibleAnnotations:
      0: #11()

  public void runtimePolicy();
    flags: ACC_PUBLIC
    Code:
      stack=0, locals=1, args_size=1
         0: return
      LineNumberTable:
        line 15: 0
    RuntimeVisibleAnnotations:
      0: #14()
}
```

可以看到：

* 编译之后，@SourcePolicy 信息不存在；
* 编译之后，@ClassPolicy 具有属性：RuntimeInvisibleAnnotations；
* 编译之后，@RuntimePolicy 具有属性：RuntimeVisibleAnnotations；

