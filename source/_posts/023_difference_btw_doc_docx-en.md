---
title: Inside the docx Format — How Word Documents Actually Work
date: 2021-07-11 22:42:01
tags: Word
categories: MSOffice
lang: en
label: 023_difference_btw_doc_docx
---

-----

<!-- more -->
##### 1. `doc` vs `docx` — A Quick Overview

`doc` (short for `document`) is a common file extension and the document format used by Word 2003 and earlier, based on binary storage. `docx` is the format introduced in Word 2007, built on the `Office Open XML` standard — essentially a compressed file format.

##### 2. What Makes `docx` Different from `doc`

Since `docx` is based on the `ooxml` format, it's fundamentally a `zip` file. Here's a comparison of file sizes for documents with identical content saved in each format — `docx` is clearly much smaller.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_0_30_compare_doc_docx_size.png)

-----------------

To understand the `ooxml` structure, let's look at a `docx` file containing headers, footers, text, and images.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_4_13_export_word.png)

Rename the file extension to `.zip` and extract it. Here's the internal structure:

* `rels`
  * `.rels`: References to core properties, extended properties, and document content by `ID`
* `docProps`
  * `app.xml`: Extended properties — word count, line count, paragraph count, page count, etc.
  * `core.xml`: Core properties — author, last modifier, creation time, modification time, etc.
* `word`: Document content
  * `_rels`: Document reference information
    * `document.xml.rels`: References to headers, footers, theme styles, images, audio/video, etc. by `ID`
  * `media`: Media files used in the document — images, audio, video
    * `image1.jpg`: An image referenced in the document
  * `theme`: Document theme information
    * `theme1.xml`
  * `document.xml`: The actual document content
  * `endnotes.xml`
  * `fontTable.xml`
  * `footer1.xml`: Footer content
  * `footnotes.xml`
  * `header1.xml`: Header content
  * `settings.xml`: Document configuration settings
  * `styles.xml`: Document style definitions
  * `webSettings.xml`: Web view configuration
* `[Content_Types].xml`: Content type declarations — image types, headers/footers, theme styles, document content, etc.

The `ooxml` storage model partitions the document by functional area: configuration, theme styles, headers/footers, relationship definitions, media files, and document content. Each piece lives in its own `xml` file. This has two practical benefits. First, the clean internal structure makes it easy to inspect document internals and build tooling on top of it. Second, splitting document data across multiple files adds fault tolerance — if one file gets corrupted, the others may still be recoverable, much like spreading eggs across multiple baskets.

-----------------

To sum up, `docx` has several advantages over `doc`:

* Higher compression ratio — takes up less space for the same content;
* Modular internal structure — easy to inspect and extend;
* Packaged as multiple `xml` files — portable across platforms;
* Better fault tolerance — damaged documents are easier to repair.



> References:
>
> * [What is doc](https://baike.baidu.com/item/doc/364715?fr=aladdin)
> * [What is docx](https://baike.baidu.com/item/docx/6517348?fr=aladdin)
> * [Why docx is better than doc](https://www.zhihu.com/question/21547795)
