---
title: RAG 对 PDF 的生产级处理方案
date: 2025-04-05
tags: [RAG, PDF]
categories: [AI]
---

## 背景

最近在做 RAG 相关的项目，踩了不少 PDF 处理的坑。真实业务里的 PDF，可能是合同、财报、技术手册、学术论文，甚至是扫描件。里面不只有文字，还有目录、表格、流程图、页眉页脚、多栏排版。如果你直接粗暴抽文本，最后 RAG 检索出来的大概率是一堆断裂、重复、缺上下文的垃圾片段。

今天聊聊 PDF RAG 的四层架构，这是我在实践中总结出来的一套方法论，希望能给出一些参考和启发。

<!-- more -->

## 为什么"PDF转文本"是 demo 级答案

先说个真实场景：你要做一个合同问答系统。用户问"违约金条款是多少"，你的 RAG 系统需要从合同 PDF 里找到答案。

如果你只是把 PDF 转成纯文本，会发生什么？

1. **表格信息丢失**：合同里的赔偿标准表格，转成文本后可能变成一堆乱码或者断裂的字符
2. **章节关系断裂**：你不知道这句话是第三章第二条还是第五章第一条
3. **页码信息消失**：用户说"第 15 页那个条款"，你的系统完全懵了
4. **图片内容丢失**：合同里的签名、盖章、流程图，纯文本根本处理不了

最后你的 Agent 回答问题时，看起来很自信，但你根本追不回来源，也没法验证答案的准确性。

所以，PDF RAG 不是一个简单的"转文本+向量化"的问题，而是一个需要分层处理的系统工程。

## 四层架构：从解析到调用

我把 PDF RAG 的处理分成四层，每一层解决一个核心问题：

```
┌─────────────────────────────────────────────┐
│  第4层：Agent 调用层                           │
│  工具链设计、按需检索、多轮对话                    │
├─────────────────────────────────────────────┤
│  第3层：切片和索引层                            │
│  语义切片、metadata 标注、向量+关键词索引           │
├─────────────────────────────────────────────┤
│  第2层：结构还原层                              │
│  标题层级、章节关系、表格结构、页码映射              │
├─────────────────────────────────────────────┤
│  第1层：解析层                                 │
│  PDF 类型识别、文本提取、OCR、视觉理解             │
└─────────────────────────────────────────────┘
```

下面逐层拆解。

### 第1层：解析层 —— 先识别，再处理

处理 PDF 的第一步，不是急着抽文本，而是先判断这个 PDF 是什么类型。

#### 三种 PDF 类型

| 类型 | 特点 | 处理方式 |
|------|------|----------|
| 原生文本 PDF | 文字可选中、可复制 | 直接提取文本 |
| 扫描件 PDF | 本质是图片，文字不可选中 | OCR 识别 |
| 图文混排 PDF | 文字+表格+图表+流程图 | 多模态理解 |

你可以用 PyMuPDF 或 pdfplumber 先做个简单判断：检查 PDF 里的文字层是否存在，如果每页提取的文字数量极少，大概率是扫描件。

#### 不同类型的不同策略

**原生文本 PDF**：这是最简单的情况，直接用 PyMuPDF、pdfplumber 这类库提取文本。但要注意，有些 PDF 虽然是原生文本，但排版复杂（多栏、表格），提取出来的文本顺序可能是乱的。

**扫描件 PDF**：需要走 OCR 流程。Tesseract 是开源方案，但中文识别准确率一般。如果预算充足，可以考虑百度 OCR、阿里云 OCR 这类商业 API，准确率高很多。

**图文混排 PDF**：这是最复杂的情况。表格需要结构化提取，流程图需要视觉理解，截图需要多模态模型分析。Anthropic 的 Claude PDF Support 就是这个思路，它不是只能读文字，还能理解 PDF 里的图片、图表和表格。

```python
# 简单的 PDF 类型判断逻辑
def detect_pdf_type(pdf_path):
    doc = fitz.open(pdf_path)

    text_pages = 0
    image_pages = 0

    for page in doc:
        text = page.get_text()
        images = page.get_images()

        if len(text.strip()) > 50:  # 有足够文字
            text_pages += 1
        if len(images) > 0:
            image_pages += 1

    if text_pages > len(doc) * 0.8:
        return "native_text"
    elif image_pages > len(doc) * 0.8:
        return "scanned"
    else:
        return "mixed"
```

### 第2层：结构还原 —— 保留文档骨架

抽完文本之后，下一步是还原 PDF 的结构信息。这一步很多人忽略了，但它直接决定了后续切片的质量。

#### 为什么要还原结构

想象一下，你从一份 50 页的财报里抽出了 3 万字的纯文本。如果你不知道哪段文字属于哪个章节、哪张表格，那这些文本就是一盘散沙。

用户问"2023 年营收是多少"，你的系统可能检索到 2022 年的数据，因为它们在文本上很相似，但你没有年份的结构信息来区分。

#### 需要保留的结构信息

1. **标题层级**：一级标题、二级标题、三级标题，形成树状结构
2. **章节关系**：每段文字属于哪个章节
3. **页码映射**：每段文字在第几页
4. **表格结构**：表格的行列关系、表头、单元格
5. **图片说明**：图片的标题、描述、所在位置
6. **页眉页脚**：文档的元信息

#### 实现思路

可以用 pdfplumber 提取表格，用正则表达式识别标题层级，然后把这些结构信息和文本内容关联起来。

```python
# 结构化提取示例
class DocumentStructure:
    def __init__(self):
        self.sections = []  # 章节列表
        self.tables = []    # 表格列表
        self.images = []    # 图片列表

    def add_section(self, title, level, page_num, content):
        self.sections.append({
            "title": title,
            "level": level,
            "page": page_num,
            "content": content
        })

    def add_table(self, table_id, page_num, headers, rows):
        self.tables.append({
            "id": table_id,
            "page": page_num,
            "headers": headers,
            "rows": rows
        })
```

### 第3层：切片和索引 —— 语义切片是核心

这一步是整个 PDF RAG 的核心。切片质量直接决定了检索质量。

#### 固定字数切片的问题

很多入门教程会教你"每 500 字切一个 chunk"，这种方法在 PDF 场景下基本不可用。

为什么？因为 PDF 的内容是有结构的。一个章节可能有 2000 字，你切成 4 个 chunk，每个 chunk 都不完整。一个表格可能只有 100 字，但你把它和前后文混在一起，表格信息就被稀释了。

#### 语义切片的原则

1. **按结构切**：标题下面的段落放一起，不要把一个章节切成多个 chunk
2. **表格单独处理**：表格是结构化数据，不能和纯文本混在一起
3. **图片单独处理**：图片需要生成摘要，不能直接丢弃
4. **长表格按行列拆分**：如果表格太长，可以按行列字段转成结构化文本

#### metadata 标注

每个 chunk 都要带 metadata，这是后续追溯的基础：

```python
chunk_metadata = {
    "doc_id": "contract_2024_001",      # 文档 ID
    "page": 15,                          # 页码
    "section": "第三章 违约责任",         # 章节标题
    "section_level": 2,                  # 章节层级
    "table_id": "table_3_1",            # 表格编号（如果有）
    "image_desc": "流程图：违约处理流程",  # 图片描述（如果有）
    "version": "2024-01-15",            # 文档版本
    "chunk_type": "text"                # chunk 类型：text/table/image
}
```

#### Contextual Retrieval：给 chunk 补上下文

Anthropic 提出了一个很实用的方法：Contextual Retrieval。核心思路是，给每个 chunk 补一段上下文说明，让模型知道这个片段在原文中属于哪一部分。

举个例子，原始 chunk 是：

> 违约方应支付合同总金额的 20% 作为违约金。

补完上下文后：

> 本文档是《2024年服务合同》，属于第三章"违约责任"中的第3.2条"违约金计算方式"。具体内容：违约方应支付合同总金额的 20% 作为违约金。

这样做的好处是，即使检索时只召回了这个 chunk，模型也能理解它的上下文，不会"只见树木，不见森林"。

```python
# Contextual Retrieval 示例
def add_context(chunk, document_context):
    """给 chunk 添加上下文说明"""
    context_prompt = f"""
    文档：{document_context['doc_title']}
    章节：{document_context['section']}
    位置：第{document_context['page']}页

    请用一句话概括这个片段在原文中的位置和主题。
    """

    context = llm.generate(context_prompt)
    return f"{context}\n\n{chunk}"
```

#### 索引策略

切完片之后，需要建立两种索引：

1. **向量索引**：用于语义相似度检索
2. **关键词索引**：用于精确匹配（如条款编号、表格编号）

两者结合使用，检索效果会更好。可以用 Hybrid Search 的方式，把向量检索和关键词检索的结果融合。

### 第4层：Agent 调用 —— 工具链按需调用

最后一层是 Agent 的调用策略。核心思路是：不要把整个 PDF 塞进上下文，而是把 PDF 能力封装成工具。

#### 工具设计

```python
# PDF RAG 工具链
tools = [
    {
        "name": "search_pdf",
        "description": "检索 PDF 中的相关片段",
        "parameters": {
            "query": "检索关键词",
            "doc_id": "文档 ID（可选）",
            "section": "章节筛选（可选）"
        }
    },
    {
        "name": "read_page",
        "description": "读取 PDF 指定页的内容",
        "parameters": {
            "doc_id": "文档 ID",
            "page_num": "页码"
        }
    },
    {
        "name": "extract_table",
        "description": "提取 PDF 中的表格数据",
        "parameters": {
            "doc_id": "文档 ID",
            "table_id": "表格编号"
        }
    },
    {
        "name": "analyze_chart",
        "description": "分析 PDF 中的图表",
        "parameters": {
            "doc_id": "文档 ID",
            "image_id": "图片编号"
        }
    },
    {
        "name": "quote_source",
        "description": "返回原文引用和页码",
        "parameters": {
            "chunk_id": "片段 ID"
        }
    }
]
```

#### 调用策略

不同类型的用户问题，走不同的调用路径：

1. **简单事实问题**（如"违约金是多少"）→ 直接向量召回
2. **复杂对比问题**（如"A 合同和 B 合同的违约金差异"）→ 先检索多个章节，再让 Agent 规划阅读
3. **表格问题**（如"2023 年各季度营收"）→ 调用 extract_table
4. **图表问题**（如"这个流程图说明了什么"）→ 调用 analyze_chart

这种设计的好处是，Agent 可以根据问题的复杂度，动态决定调用哪些工具，而不是一次性把所有信息都塞进上下文。

## 生产级细节：可追溯引用和评测

如果你的 PDF RAG 系统要上生产，有两个东西是必须要做的：可追溯引用和评测。

### 可追溯引用

Agent 回答问题时，必须带上来源信息：

- 页码：答案来自第几页
- 章节：答案属于哪个章节
- 原文片段：原始文本是什么

这样做的好处是，用户可以验证答案的准确性，你也可以追溯问题的根源。

Anthropic 的 Citation 文档里也提到，PDF 可以按提取出的文本做引用，并返回页码范围。这是一个很好的实践。

```python
# 带引用的回答示例
def answer_with_citation(question, doc_id):
    # 检索相关片段
    chunks = search_pdf(question, doc_id)

    # 生成回答
    answer = generate_answer(question, chunks)

    # 构建引用
    citations = []
    for chunk in chunks:
        citations.append({
            "page": chunk.metadata["page"],
            "section": chunk.metadata["section"],
            "text": chunk.content[:200] + "..."
        })

    return {
        "answer": answer,
        "citations": citations
    }
```

### 评测体系

评测不能只看最终答案对不对，还要看整个链路的质量：

| 评测维度 | 评测内容 |
|----------|----------|
| 检索质量 | 检索片段是否命中、排序是否合理 |
| 页码准确性 | 返回的页码是否正确 |
| 表格解析 | 表格是否正确提取、结构是否完整 |
| OCR 质量 | 是否漏字、错字 |
| 图表理解 | 图表信息是否被正确理解 |
| 答案准确性 | 最终答案是否正确 |

建议搭建一个评测数据集，包含不同类型的 PDF 和对应的问题，定期跑评测，监控系统质量。

## 总结

PDF RAG 不是一个简单的"转文本+向量化"的问题。生产级的 PDF RAG 需要四层架构：

1. **解析层**：识别 PDF 类型，采用不同处理策略
2. **结构还原层**：保留文档的骨架信息
3. **切片和索引层**：语义切片 + metadata 标注 + 上下文补充
4. **Agent 调用层**：工具链按需调用

最后，一定要做可追溯引用和评测闭环。这样你的系统才能真正用起来，而不是停留在 demo 阶段。

---

**参考资源**：
- [Anthropic Claude PDF Support](https://docs.anthropic.com/en/docs/build-with-claude/pdf-support)
- [Anthropic Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)
- [Anthropic Citation](https://docs.anthropic.com/en/docs/build-with-claude/citation)
- [pdfplumber 文档](https://github.com/jsvine/pdfplumber)
- [PyMuPDF 文档](https://pymupdf.readthedocs.io/)
