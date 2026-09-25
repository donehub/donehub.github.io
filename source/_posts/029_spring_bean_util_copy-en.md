---
title: How Spring's Bean Copying Actually Works
date: 2021-11-11 13:57:01
tags: Spring
categories: Backend
lang: en
label: 029_spring_bean_util_copy
---

-----

<!-- more -->
#### 1. The Mechanics of Spring Bean Copying

Spring's object copying mechanism is built on reflection and introspection. It reads field values from a source object and writes them into a target object. The process breaks down into two steps:

* Use introspection to obtain property descriptors for both the source and target objects;
* Use reflection to read values from source properties and write them into the corresponding target properties;

```java
/**
 * Core Spring bean copy method
 *
 * @param source           source object
 * @param target           target object
 * @param editable         constrains the target Class
 * @param ignoreProperties properties to skip during copy
 */
private static void copyProperties(Object source, Object target, Class<?> editable,
                                   String... ignoreProperties) throws BeansException {
    
    Assert.notNull(source, "Source must not be null");
    Assert.notNull(target, "Target must not be null");
    
    Class<?> actualEditable = target.getClass();
    if (editable != null) {
        // If target is not an instance of editable, abort the copy
        if (!editable.isInstance(target)) {
            throw new IllegalArgumentException("Target class [" + target.getClass().getName() +"] not assignable to Editable class [" + editable.getName() + "]");
        }
        actualEditable = editable;
    }
    // Introspect the target object to get its property descriptors
    PropertyDescriptor[] targetPds = getPropertyDescriptors(actualEditable);
    // Parse the list of properties to ignore
    List<String> ignoreList = (ignoreProperties != null ? Arrays.asList(ignoreProperties) : null);
    // Iterate over target property descriptors and copy values one by one
    for (PropertyDescriptor targetPd : targetPds) {
        // Get the write method for this target property
        Method writeMethod = targetPd.getWriteMethod();
        // If the property is writable and not in the ignore list,
        // introspect the source object for the matching property descriptor,
        // read the value, and write it to the target
        if (writeMethod != null && (ignoreList == null || !ignoreList.contains(targetPd.getName()))) {
            // Introspect the source object, look up the matching property descriptor by name
            PropertyDescriptor sourcePd = getPropertyDescriptor(source.getClass(), targetPd.getName());
            if (sourcePd != null) {
                // Get the read method for the source property
                Method readMethod = sourcePd.getReadMethod();
                if (readMethod != null
                    && ClassUtils.isAssignable(writeMethod.getParameterTypes()[0],
                                              readMethod.getReturnType())) {
                    
                    try {
                        if (!Modifier.isPublic(readMethod.getDeclaringClass().getModifiers())) {
                            readMethod.setAccessible(true);
                        }
                        // Read the source property value
                        Object value = readMethod.invoke(source);
                        if (!Modifier.isPublic(writeMethod.getDeclaringClass().getModifiers())) {
                            writeMethod.setAccessible(true);
                        }
                        // Write the value to the target property
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



#### 2. How BeanUtils.copyProperties Works

Based on the analysis above, here's the full picture of how Spring's bean copying works:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_39_5_introspector.jpg)

The introspection mechanism decomposes a Bean into individual property descriptors, which are cached in a Map keyed by property name. Each property descriptor contains three things: the property name, the getter method, and the setter method. During copying, the process first finds the target property's setter, then locates the corresponding source property's getter, and finally uses reflection to transfer the value.

#### 3. JavaBean Introspection

JavaBean introspection is built on top of reflection. It parses a Bean's property descriptors to provide a higher-level API for accessing properties and methods. While raw reflection gives you access to all fields and methods of a class, introspection specifically works with property descriptors and only operates on classes that follow the JavaBean convention.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_37_1_refect_instropection.png)

Here's the core introspection logic in `java.beans.Introspector`:

```java
// Get all public methods
Method methodList[] = getPublicDeclaredMethods(beanClass);
// Iterate over each public method. For clarity, we'll use the first method as an example...

Method method = methodList[0];
if (method == null) {
    continue;
}
// Skip static methods
int mods = method.getModifiers();
if (Modifier.isStatic(mods)) {
    continue;
}
// Get the method name, e.g., setAge, getAge
String name = method.getName();
// Get parameter types and return type
Class<?>[] argTypes = method.getParameterTypes();
Class<?> resultType = method.getReturnType();
// Get the number of parameters
int argCount = argTypes.length;
PropertyDescriptor pd = null;

if (argCount == 0) {
    // 1. No parameters: this is a getter
    if (name.startsWith(GET_PREFIX)) {
        // 1.1 Method starts with "get", e.g., getAge
        pd = new PropertyDescriptor(this.beanClass, name.substring(3), method, null);
    } else if (resultType == boolean.class && name.startsWith(IS_PREFIX)) {
        // 1.2 Method starts with "is", e.g., isMale — only for primitive boolean
        pd = new PropertyDescriptor(this.beanClass, name.substring(2), method, null);
    }
} else if (argCount == 1) {
    // 2. One parameter
    if (int.class.equals(argTypes[0]) && name.startsWith(GET_PREFIX)) {
        // 2.1 Indexed getter, e.g., getChild(Integer index) — wrap as indexed property
        pd = new IndexedPropertyDescriptor(this.beanClass, name.substring(3), null, null, method, null);
    } else if (void.class.equals(resultType) && name.startsWith(SET_PREFIX)) {
        // 2.2 Setter method
        pd = new PropertyDescriptor(this.beanClass, name.substring(3), null, method);
        if (throwsException(method, PropertyVetoException.class)) {
            pd.setConstrained(true);
        }
    }
} else if (argCount == 2) {
    // 3. Two parameters
    if (void.class.equals(resultType) && int.class.equals(argTypes[0]) && name.startsWith(SET_PREFIX)) {
        // 3.1 Indexed setter, e.g., setChild(Integer index, Child child) — wrap as indexed property
        pd = new IndexedPropertyDescriptor(this.beanClass, name.substring(3), null, null, null, method);
        if (throwsException(method, PropertyVetoException.class)) {
            pd.setConstrained(true);
        }
    }
}

return PropertyDescriptor;
```

The introspection mechanism relies on three key factors: method name, parameter count, and return type. The rules can be summarized as:

* Only public non-static methods are introspectable;
* Standard setters are recognized, e.g., `void setAge(Integer age)`;
* Standard getters are recognized, e.g., `ResultType getAge()`;
* Indexed setters are recognized, e.g., `setChild(Integer index, Child child)`;
* Indexed getters are recognized, e.g., `getChild(Integer index)`;
* Boolean getters with the `is` prefix are recognized for primitive boolean only, e.g., `boolean isMale()`;

#### 4. The JavaBean Convention Trap

Spring's bean copying requires both source and target objects to follow the JavaBean convention. This is where things can silently break. Consider a boxed Boolean property: the getter for `Boolean isMale` doesn't match the JavaBean standard (which expects `getMale()` for non-primitive types, or `isMale()` returning primitive `boolean`). As a result, introspection won't find a matching property descriptor, and the target field will remain null — no exception, no warning, just a silent data loss.

This is a common gotcha when using `BeanUtils.copyProperties` in projects that don't strictly enforce JavaBean naming conventions. The copy appears to work, but certain fields are silently skipped. If you're seeing mysteriously null fields after a bean copy, check whether the getter/setter naming follows the JavaBean spec.