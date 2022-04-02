---
title: MsOffice Word 文档格式-docx 研究
date: 2021-07-11 22:42:01
tags: Word
categories: MSOffice
---

-----

##### 一、`doc` 与 `docx` 简介

`doc` 全程为 `document`，是常见的文件扩展名，也是 `Word2003` 及之前版本的文本文档格式，其基于二进制形式存储；`docx` 是 `Word2007` 及之后版本的文本文档格式，其基于 `Office Open XML` 标准的压缩文件格式。

##### 二、`docx` 与 `doc` 的区别

既然 `docx` 基于 `ooxml` 的格式，那么本质上就是一个 `zip` 文件。以下是内容相同的文档，分别以 `doc` 和 `docx` 格式保存之后所占空间大小，可以看出 `docx` 文件明显比 `doc` 要小很多。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_0_30_compare_doc_docx_size.png)

-----------------

为了进一步了解 `ooxml` 结构，我们以一个含有页眉页脚、文本、图片的 `docx` 文件为例。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_4_13_export_word.png)

手动修改文件后缀为 `.zip` 后保存，然后解压得到文件结构：

* `rels`
  * `.rels`： 指定主要信息、扩展信息、文档内容的引用 `ID`
* `docProps`
  * `app.xml`: 扩展信息，包括字数、行数、段落数、页数等
  * `core.xml`：主要信息，包括创建人、修改人、创建时间、修改时间等
* `word`：文档信息
  * `_rels`：文档引用信息
    * `document.xml.rels`：指定文档中的页眉页脚、主题样式、图片音视频等的引用 `ID`
  * `media`：存放文档中使用的图片、音频、视频等媒体文件
    * `image1.jpg`：文档中引用的图片
  * `theme`：文档主题信息
    * `theme1.xml`
  * `document.xml`：文档内容
  * `endnotes.xml`
  * `fontTable.xml`
  * `footer1.xml`：页脚信息
  * `footnotes.xml`
  * `header1.xml`：页眉信息
  * `settings.xml`：文档配置信息
  * `styles.xml`：文档样式信息
  * `webSettings.xml`：网页样式配置信息
* `[Content_Types].xml`： 指定文件配置，包括图片类型、页眉页脚、主题样式、文档内容等

`docx` 的 `ooxml` 存储模式，将文档按照功能区划分为：配置信息、主题样式信息、页眉页脚信息、引用定义信息、媒体文件信息、文档内容信息等模块。这样便可将对应的信息抽离出来，存放在 `xml` 文件中。一方面，清晰的文档底层结构，方便查看内容细节，也方便进行二次开发；另一方面，文档信息分模块保存，好比把鸡蛋放在多个篮子里，可以增加容错性，使得文档修复更加方便。

-----------------

综上，与 `doc` 相比，`docx` 主要有以下特点：

* 压缩率高，存储相同内容所占空间更小；
* 将文档信息拆分保存，方便查看或二次开发；
* 多个 `xml` 文件打包，易于跨平台使用；
* 增加文档容错性，方便修复损坏文档。



> 参考：
>
> * [什么是 doc](https://baike.baidu.com/item/doc/364715?fr=aladdin)
> * [什么是 docx](https://baike.baidu.com/item/docx/6517348?fr=aladdin)
> * [docx 比 doc 好在哪里](https://www.zhihu.com/question/21547795)