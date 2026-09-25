---
title: How the @Retention Meta-Annotation Works
date: 2020-10-11 21:27:58
lang: en
label: 014_@interface_retention
tags: Java
categories: Backend
---

-----

<!-- more -->
#### 1. What @Retention Does

`@Retention` is a meta-annotation — it annotates other annotations. It controls how long an annotation stays around, governed by the `RetentionPolicy` enum.

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

Here's the summary:

| Policy | Description | Use Case |
| :--- | :--- | :--- |
| `RetentionPolicy.SOURCE` | Retained only in source files; discarded during compilation | Compile-time checks, e.g. `@Override`, `@SuppressWarnings` |
| `RetentionPolicy.CLASS` | Recorded in the `.class` file but discarded when the JVM loads it | Compile-time preprocessing, e.g. generating metadata (`META-INF/services`) |
| `RetentionPolicy.RUNTIME` | Recorded in the `.class` file and retained after JVM loads it | Runtime reflection, e.g. `@Autowired`, `@Required` |



#### 2. Seeing @Retention in the Bytecode

##### Define three annotations, one per retention policy: SourcePolicy, ClassPolicy, RuntimePolicy

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

Apply them:

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

Run `javap -v RetentionPolicyTest` to inspect the bytecode:

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

The output is revealing:

* After compilation, `@SourcePolicy` has disappeared entirely — no trace in the bytecode.
* After compilation, `@ClassPolicy` is present under `RuntimeInvisibleAnnotations` — stored in the class file but not exposed at runtime.
* After compilation, `@RuntimePolicy` is present under `RuntimeVisibleAnnotations` — available for reflective access at runtime.
