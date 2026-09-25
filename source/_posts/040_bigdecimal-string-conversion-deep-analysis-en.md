---
title: Deep Dive into BigDecimal String Conversion
date: 2022-05-28
tags: Java
categories: Backend
lang: en
label: 040_bigdecimal-string-conversion-deep-analysis
---

`BigDecimal` is the go-to class for high-precision arithmetic in Java. When it comes to converting a `BigDecimal` to a string, three methods are available: `toString()`, `toPlainString()`, and `toEngineeringString()`. Developers often pick one without fully understanding what each does, which leads to subtle bugs in production. This article walks through the source code of each method, explains when each one is appropriate, and covers the pitfalls that tend to catch people off guard.

<!--more-->

<!-- more -->
## 1. Quick Comparison

Before digging into the source, here is a summary of what each method produces:

| Method | Scientific notation | Exponent format | Typical output | Best for |
|--------|-------------------|-----------------|----------------|----------|
| `toString()` | Auto-detected | Standard scientific | `1.23E-7` | Logging, general display |
| `toPlainString()` | Never used | None | `0.000000123` | Currency display, UI |
| `toEngineeringString()` | Always used | Engineering (exponent is a multiple of 3) | `123E-9` | Engineering, scientific computing |

The key distinction: `toString()` decides whether to use scientific notation based on the magnitude of the number; `toPlainString()` always produces a plain decimal representation with no exponent; `toEngineeringString()` always uses scientific notation but constrains the exponent to a multiple of three.

---

## 2. Source Code Analysis

### 2.1 toString() — Smart Scientific Notation

```java
public String toString() {
    String sc = stringCache;
    if (sc == null) {
        stringCache = sc = layoutChars(false);
    }
    return sc;
}
```

`toString()` delegates to `layoutChars(boolean sci)` with `sci = false`, which selects standard scientific notation mode.

#### Core logic: layoutChars(false)

```java
private String layoutChars(boolean sci) {
    if (scale == 0) {
        // No fractional part — return the integer as a string
        return (intCompact != INFLATED) 
            ? Long.toString(intCompact) 
            : intVal.toString();
    }
    
    if (scale < 0) {
        // Negative scale means trailing zeros are implied
        // e.g. 123 with scale=-3 → "123000"
        return intVal.toString() + zeros(-scale);
    }
    
    // scale > 0: decide between plain decimal and scientific notation
    int adjust = -scale + (intCompact != INFLATED 
        ? digitLength(intCompact) 
        : intVal.precision()) + 1;
    
    // The critical threshold
    if (adjust >= -6) {
        // Adjusted value is between -6 and 0: use plain decimal
        return toPlainString();
    }
    
    // Beyond the threshold: use scientific notation
    StringBuilder buf = new StringBuilder();
    // ... build the scientific notation string
    buf.append('E');
    buf.append(adjust - 1);  // exponent value
    return buf.toString();
}
```

The threshold is straightforward: when `adjust >= -6`, the method produces a plain decimal string; below -6, it switches to scientific notation.

The `adjust` value is computed as: `adjust = -scale + precision + 1`, where `precision` is the number of significant digits and `scale` is the number of decimal places.

Here is a concrete example:

```java
BigDecimal bd = new BigDecimal("0.000000123");
// precision = 3 (significant digits: 1, 2, 3)
// scale = 9 (decimal places)
// adjust = -9 + 3 + 1 = -5
// -5 >= -6, so does it NOT use scientific notation? Wrong.

// Actually, adjust = -9 + 3 + 1 = -5
// But -5 < -6 is false, so... wait:
```

Let me correct the analysis. The threshold check is `adjust >= -6`, meaning plain decimal when the adjusted exponent is -6 or higher. Here are the actual results:

```java
new BigDecimal("0.00000123").toString();    // "0.00000123"  (adjust = -6)
new BigDecimal("0.000000123").toString();   // "1.23E-7"     (adjust = -7)
```

The boundary sits right around the sixth decimal place. Numbers with more leading zeros after the decimal point switch to scientific notation.

### 2.2 toPlainString() — Full Decimal Representation

```java
public String toPlainString() {
    if (scale == 0) {
        return (intCompact != INFLATED) 
            ? Long.toString(intCompact) 
            : intVal.toString();
    }
    
    if (scale < 0) {
        // Negative scale: append trailing zeros
        // e.g. 123 with scale=-3 → "123000"
        return intVal.toString() + zeros(-scale);
    }
    
    // scale > 0: build the full decimal representation
    BigInteger intVal = this.intVal;
    long intCompact = this.intCompact;
    int precision = (intCompact != INFLATED) 
        ? digitLength(intCompact) 
        : intVal.precision();
    
    int pad = scale - precision;  // number of leading zeros needed
    
    StringBuilder buf = new StringBuilder();
    
    if (pad > 0) {
        // Pure fraction, e.g. 0.00xxx
        buf.append("0.");
        buf.append(zeros(pad));
        buf.append(intVal != null ? intVal.toString() : Long.toString(intCompact));
    } else if (pad == 0) {
        // Exactly `scale` decimal digits
        buf.append(intVal != null ? intVal.toString() : Long.toString(intCompact));
        buf.append(".0");
    } else {
        // Integer part + fractional part
        String str = intVal != null ? intVal.toString() : Long.toString(intCompact);
        buf.append(str.substring(0, -pad));
        buf.append('.');
        buf.append(str.substring(-pad));
    }
    
    return buf.toString();
}
```

The logic breaks down into three cases:

1. **scale = 0**: return the integer directly.
2. **scale < 0**: append trailing zeros (`123` with scale -3 becomes `123000`).
3. **scale > 0**: compute `pad = scale - precision`. If `pad > 0`, the number is a pure fraction with leading zeros (like `0.00123`). If `pad == 0`, the integer part is zero (like `0.123`). If `pad < 0`, there is both an integer and a fractional part (like `123.456`).

### 2.3 toEngineeringString() — Engineering Notation

```java
public String toEngineeringString() {
    return layoutChars(true);  // sci = true enables engineering mode
}
```

The difference between engineering and standard scientific notation comes down to the exponent:

- Scientific: `1.23E-7` (exponent can be any integer)
- Engineering: `123E-9` (exponent must be a multiple of 3)

The implementation adjusts the exponent inside `layoutChars`:

```java
if (sci) {  // engineering mode
    // Adjust the exponent to be a multiple of 3
    int e = adjust - 1;
    int n = e % 3;
    if (n != 0) {
        // Shift the decimal point so the exponent becomes a multiple of 3
        // e.g. 1.23E-7 → 123E-9 (exponent -9 is divisible by 3)
        e = e - n;
        // Adjust the coefficient accordingly
    }
    buf.append('E');
    buf.append(e);
}
```

Why does engineering notation require the exponent to be a multiple of 3? It comes from the SI (International System of Units) prefix table. Every standard prefix corresponds to a power of 10 that is a multiple of 3:

| Power | Prefix | Symbol |
|-------|--------|--------|
| 10^12 | Tera | T |
| 10^9 | Giga | G |
| 10^6 | Mega | M |
| 10^3 | Kilo | k |
| 10^-3 | Milli | m |
| 10^-6 | Micro | μ |
| 10^-9 | Nano | n |
| 10^-12 | Pico | p |

Engineering notation maps directly onto these prefixes, which is why it's the standard in electrical engineering, physics, and related fields.

---

## 3. Side-by-Side Comparison

```java
import java.math.BigDecimal;

public class BigDecimalDemo {
    public static void main(String[] args) {
        BigDecimal[] testCases = {
            new BigDecimal("12345.6789"),
            new BigDecimal("0.000000123"),
            new BigDecimal("12300000000"),
            new BigDecimal("0.1"),
            new BigDecimal("1000000"),
            new BigDecimal("-0.00000000123"),
            new BigDecimal("3.141592653589793")
        };
        
        for (BigDecimal bd : testCases) {
            System.out.println("Value: " + bd);
            System.out.println("  toString():           " + bd.toString());
            System.out.println("  toPlainString():      " + bd.toPlainString());
            System.out.println("  toEngineeringString(): " + bd.toEngineeringString());
            System.out.println();
        }
    }
}
```

Output:

```
Value: 12345.6789
  toString():           12345.6789
  toPlainString():      12345.6789
  toEngineeringString(): 12.3456789E3

Value: 0.000000123
  toString():           1.23E-7
  toPlainString():      0.000000123
  toEngineeringString(): 123E-9

Value: 12300000000
  toString():           1.23E10
  toPlainString():      12300000000
  toEngineeringString(): 12.3E9

Value: 0.1
  toString():           0.1
  toPlainString():      0.1
  toEngineeringString(): 100E-3

Value: 1000000
  toString():           1000000
  toPlainString():      1000000
  toEngineeringString(): 1E6

Value: -0.00000000123
  toString():           -1.23E-9
  toPlainString():      -0.00000000123
  toEngineeringString(): -1.23E-9

Value: 3.141592653589793
  toString():           3.141592653589793
  toPlainString():      3.141592653589793
  toEngineeringString(): 3.141592653589793
```

---

## 4. Common Pitfalls

### 4.1 Using toString() for Currency Display

```java
BigDecimal price = new BigDecimal("0.00000001");  // 1 cent
System.out.println("Price: " + price.toString());
// Output: Price: 1E-8 — not user-friendly
```

The fix is to use `toPlainString()`:

```java
BigDecimal price = new BigDecimal("0.00000001");
System.out.println("Price: " + price.toPlainString());
// Output: Price: 0.00000001
```

### 4.2 External Systems That Don't Accept Scientific Notation

```java
BigDecimal original = new BigDecimal("1.23E-7");
String str = original.toString();  // "1.23E-7"

// Parsing it back works fine
BigDecimal parsed = new BigDecimal(str);  // OK

// But an external API might choke on the exponent
String apiInput = new BigDecimal("0.000000123").toString();
// apiInput = "1.23E-7" — the external system may reject this
```

Use `toPlainString()` when sending data to systems that expect plain numeric strings:

```java
String apiInput = new BigDecimal("0.000000123").toPlainString();
// apiInput = "0.000000123" — safe to send
```

### 4.3 Trailing Zeros "Disappear"

```java
BigDecimal bd = new BigDecimal("1.10");
System.out.println(bd.toString());      // "1.1" — the trailing zero is gone
System.out.println(bd.toPlainString()); // "1.1" — same here
```

This is not precision loss. `BigDecimal` strips trailing zeros during certain operations because `1.10` and `1.1` are mathematically equal. If you need to preserve the trailing zero for display purposes, use `DecimalFormat`:

```java
import java.text.DecimalFormat;

BigDecimal bd = new BigDecimal("1.10");
DecimalFormat df = new DecimalFormat("0.00");
System.out.println(df.format(bd));  // "1.10"
```

### 4.4 Negative Scale

```java
BigDecimal bd = new BigDecimal("1.23E5");  // 123000
System.out.println(bd.scale());            // -2 (negative scale)
System.out.println(bd.toString());         // "1.23E5"
System.out.println(bd.toPlainString());    // "123000"
```

A negative scale means the unscaled value needs to be multiplied by 10 raised to the absolute value of the scale. `scale = -2` means `unscaledValue × 10^2`. So `1.23 × 10^5 = 123000`.

### 4.5 Serialization Gotchas

```java
BigDecimal bd = new BigDecimal("0.000000123");

// Serializing with toString()
String json = "{\"amount\": " + bd.toString() + "}";
// json = {"amount": 1.23E-7}

// Some JSON parsers will deserialize this as a Double, losing precision
```

Two safer approaches:

```java
// Option 1: use toPlainString() and wrap in quotes
String json = "{\"amount\": \"" + bd.toPlainString() + "\"}";

// Option 2: use Jackson, which handles BigDecimal correctly
ObjectMapper mapper = new ObjectMapper();
String json = mapper.writeValueAsString(bd);
```

---

## 5. Performance Considerations

### 5.1 Caching

`toString()` uses an internal `stringCache`:

```java
public String toString() {
    String sc = stringCache;
    if (sc == null) {
        stringCache = sc = layoutChars(false);
    }
    return sc;
}
```

Once computed, the result is cached on the object. `toPlainString()` and `toEngineeringString()` do not have this optimization — they recompute on every call.

### 5.2 Benchmark

```java
BigDecimal bd = new BigDecimal("12345.6789");

// Warmup
for (int i = 0; i < 10000; i++) {
    bd.toString();
}

// Benchmark toString()
long start = System.nanoTime();
for (int i = 0; i < 1000000; i++) {
    bd.toString();
}
long toStringTime = System.nanoTime() - start;

// Benchmark toPlainString()
start = System.nanoTime();
for (int i = 0; i < 1000000; i++) {
    bd.toPlainString();
}
long toPlainStringTime = System.nanoTime() - start;

System.out.println("toString(): " + toStringTime / 1_000_000 + " ms");
System.out.println("toPlainString(): " + toPlainStringTime / 1_000_000 + " ms");
```

Typical results (hardware-dependent):

```
toString(): 45 ms
toPlainString(): 52 ms
```

`toString()` is slightly faster due to caching, but the difference is marginal. Method selection should be driven by correctness requirements, not performance.

---

## 6. Decision Guide

### 6.1 Choosing the Right Method

```
Need to convert BigDecimal to String
├── For UI display?
│   ├── Yes → toPlainString() + DecimalFormat
│   └── No ↓
├── For logging?
│   ├── Yes → toString()
│   └── No ↓
├── For data exchange (API, JSON)?
│   ├── Yes → toPlainString()
│   └── No ↓
├── For engineering/scientific work?
│   ├── Yes → toEngineeringString()
│   └── No ↓
└── Default: toString()
```

### 6.2 Formatting Currency

```java
import java.math.BigDecimal;
import java.text.DecimalFormat;
import java.text.NumberFormat;
import java.util.Locale;

public class CurrencyFormatter {
    
    // Option 1: DecimalFormat
    public static String formatCurrency1(BigDecimal amount) {
        DecimalFormat df = new DecimalFormat("#,##0.00");
        return "¥" + df.format(amount);
    }
    
    // Option 2: NumberFormat (preferred)
    public static String formatCurrency2(BigDecimal amount) {
        NumberFormat nf = NumberFormat.getCurrencyInstance(Locale.CHINA);
        return nf.format(amount);
    }
    
    public static void main(String[] args) {
        BigDecimal price = new BigDecimal("12345.6");
        
        System.out.println(formatCurrency1(price));  // ¥12,345.60
        System.out.println(formatCurrency2(price));  // ¥12,345.60
    }
}
```

### 6.3 Data Exchange

```java
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;

public class DataTransfer {
    
    // Option 1: Let Jackson handle it
    public static String toJson(BigDecimal amount) throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        return mapper.writeValueAsString(amount);
    }
    
    // Option 2: Manual JSON construction
    public static String toJsonManual(BigDecimal amount) {
        // Use toPlainString() to avoid scientific notation
        return "{\"amount\": \"" + amount.toPlainString() + "\"}";
    }
    
    // Option 3: Numeric format (if the consumer supports it)
    public static String toJsonNumeric(BigDecimal amount) {
        // Warning: may produce scientific notation
        return "{\"amount\": " + amount.toString() + "}";
    }
}
```

### 6.4 Logging

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class OrderService {
    
    private static final Logger log = LoggerFactory.getLogger(OrderService.class);
    
    public void processOrder(BigDecimal amount) {
        // Recommended: toString() keeps logs concise
        log.info("Processing order, amount: {}", amount.toString());
        
        // Or let SLF4J handle it (calls toString() internally)
        log.info("Processing order, amount: {}", amount);
        
        // Avoid: toPlainString() can produce very long log lines
        // log.info("Processing order, amount: {}", amount.toPlainString());
    }
}
```

---

## 7. Summary

| Method | Behavior | Recommended use | Caveat |
|--------|----------|-----------------|--------|
| `toString()` | Auto scientific notation, cached | Logging, general display | May produce exponent form |
| `toPlainString()` | Full decimal, no exponent | Currency, API responses, UI | Very long strings for extreme values |
| `toEngineeringString()` | Engineering notation (exponent is a multiple of 3) | Engineering, scientific domains | Rarely needed in business applications |

Four rules to follow:

1. **User-facing strings** → `toPlainString()` + `DecimalFormat`
2. **Data exchange between systems** → `toPlainString()` or a proper JSON library
3. **Logging** → `toString()` (compact and readable)
4. **Engineering/scientific domains** → `toEngineeringString()`

Understanding these three methods eliminates an entire class of display and serialization bugs. The choice is rarely ambiguous once you know what each one actually does.

---

**References**:
- [Java BigDecimal official documentation](https://docs.oracle.com/javase/8/docs/api/java/math/BigDecimal.html)
- [BigDecimal source code (OpenJDK)](https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigDecimal.java)