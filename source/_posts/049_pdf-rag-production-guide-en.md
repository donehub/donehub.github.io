---
title: "Production-Grade PDF Processing for RAG Systems"
date: 2025-04-05
tags: [RAG, PDF]
categories: [AI]
lang: en
label: 049_pdf-rag-production-guide
---

I have been working on a RAG project recently and ran into plenty of pitfalls with PDF processing. Real-world PDFs come in many forms: contracts, financial reports, technical manuals, academic papers, and even scanned documents. The content is not just text — it includes tables of contents, tables, flowcharts, headers and footers, and multi-column layouts. Naively extracting raw text and feeding it into RAG will almost certainly produce broken, duplicated, context-free garbage chunks. Below is a four-layer architecture for PDF RAG, a methodology I developed through hands-on practice.

<!-- more -->

## Why "PDF to Text" Is a Demo-Level Answer

Consider a contract Q&A system. A user asks about the penalty clause amount, and the RAG system needs to find the answer in the contract PDF. If you just convert the PDF to plain text, the compensation standards in tables become garbled or broken characters, chapter relationships are completely lost (you have no idea whether a sentence belongs to Chapter 3 Section 2 or Chapter 5 Section 1), page number information disappears (so when a user references a clause on page 15, the system cannot locate it), and non-text content like signatures, stamps, and flowcharts is unhandleable. The Agent ends up answering with apparent confidence, but cannot trace back to the source or verify accuracy. PDF RAG is not a simple "convert to text then vectorize" problem. It's a layered engineering system.

## The Four-Layer Architecture

PDF RAG processing can be divided into four layers, each solving a core problem:

| Layer | Core Responsibility | Key Content |
|-------|---------------------|-------------|
| Layer 1: Parsing | PDF type identification and text extraction | Type detection, text extraction, OCR, visual understanding |
| Layer 2: Structure Restoration | Preserving document skeleton information | Heading hierarchy, chapter relationships, table structure, page mapping |
| Layer 3: Chunking & Indexing | Semantic chunking and index construction | Semantic chunks, metadata annotation, vector + keyword indexing |
| Layer 4: Agent Invocation | On-demand tool chain invocation | Tool design, retrieval on demand, multi-turn conversation |

### Parsing Layer — Identify First, Process Second

The first step in processing a PDF is not rushing to extract text — it is determining what type of PDF you are dealing with.

#### Three PDF Types

| Type | Characteristics | Processing Approach |
|------|----------------|---------------------|
| Native text PDF | Text is selectable and copyable | Direct text extraction |
| Scanned PDF | Essentially images, text not selectable | OCR recognition |
| Mixed content PDF | Text + tables + charts + flowcharts | Multimodal understanding |

You can use PyMuPDF or pdfplumber for a quick assessment: check whether the text layer exists in the PDF. If the amount of extractable text per page is very low, it's likely a scanned document.

#### Different Strategies for Different Types

Native text PDFs are the simplest case — extract text directly using libraries like PyMuPDF or pdfplumber. But be aware: even native text PDFs with complex layouts (multi-column, tables) may produce text in scrambled order.

Scanned PDFs need an OCR pipeline. Tesseract is the open-source option, but its Chinese recognition accuracy is mediocre. If budget allows, commercial APIs like Baidu OCR or Alibaba Cloud OCR deliver significantly better accuracy.

Mixed content PDFs are the most complex case. Tables need structured extraction, flowcharts need visual understanding, and screenshots need multimodal model analysis. Anthropic's Claude PDF Support follows this exact approach — it does not just read text, it also understands images, charts, and tables within the PDF.

```python
# Simple PDF type detection logic
def detect_pdf_type(pdf_path):
    doc = fitz.open(pdf_path)

    text_pages = 0
    image_pages = 0

    for page in doc:
        text = page.get_text()
        images = page.get_images()

        if len(text.strip()) > 50:  # Has sufficient text
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

### Structure Restoration — Preserving the Document Skeleton

After extracting text, the next step is restoring the PDF's structural information. Many people skip this step, but it directly determines the quality of downstream chunking.

#### Why Structure Matters

Extract 30,000 characters of plain text from a 50-page financial report. Without knowing which text belongs to which chapter or which table, this text is a pile of sand. When a user asks "What was the 2023 revenue?", the system might retrieve 2022 data because the text is similar, with no year-level structural information to distinguish them.

#### Structure Information to Preserve

1. Heading hierarchy: level-1, level-2, and level-3 headings forming a tree structure
2. Chapter relationships: which chapter each text segment belongs to
3. Page mapping: which page each text segment appears on
4. Table structure: table row/column relationships, headers, cells
5. Image captions: image titles, descriptions, and positions
6. Headers and footers: document metadata

#### Implementation Approach

For implementation, use pdfplumber to extract tables, use regex to identify heading hierarchies, then associate this structural information with the text content.

```python
# Structured extraction example
class DocumentStructure:
    def __init__(self):
        self.sections = []  # Section list
        self.tables = []    # Table list
        self.images = []    # Image list

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

### Chunking & Indexing — Semantic Chunking Is the Core

This step is the heart of PDF RAG. Chunking quality directly determines retrieval quality.

#### The Problem with Fixed-Size Chunking

Many beginner tutorials teach you to chunk every 500 characters. This approach basically does not work for PDFs. PDF content has structure — a chapter might be 2000 characters, and splitting it into 4 chunks means none of them are complete. A table might be only 100 characters, but mixing it with surrounding text dilutes the table information.

#### Principles of Semantic Chunking

1. Chunk by structure: keep paragraphs under the same heading together, do not split a chapter into multiple chunks
2. Handle tables separately: tables are structured data and should not be mixed with plain text
3. Handle images separately: images need summary generation and should not be silently dropped
4. Split long tables by rows/columns: if a table is too long, convert it to structured text by row/column fields

#### Metadata Annotation

Every chunk needs metadata — this is the foundation for traceability:

```python
chunk_metadata = {
    "doc_id": "contract_2024_001",      # Document ID
    "page": 15,                          # Page number
    "section": "Chapter 3 Breach Liability",  # Section heading
    "section_level": 2,                  # Section level
    "table_id": "table_3_1",            # Table ID (if applicable)
    "image_desc": "Flowchart: breach handling process",  # Image description (if applicable)
    "version": "2024-01-15",            # Document version
    "chunk_type": "text"                # Chunk type: text/table/image
}
```

#### Contextual Retrieval: Enriching Chunks with Context

Anthropic proposed a practical method called Contextual Retrieval. The core idea is prepending each chunk with a context description so the model knows where the fragment sits in the original document.

For example, the raw chunk is:

> The breaching party shall pay 20% of the total contract value as a penalty.

After adding context:

> This document is the "2024 Service Contract," Chapter 3 Breach Liability, Section 3.2 Penalty Calculation Method. Specific content: The breaching party shall pay 20% of the total contract value as a penalty.

The benefit is that even if only this chunk is retrieved, the model can still understand its context rather than seeing the tree without the forest.

```python
# Contextual Retrieval example
def add_context(chunk, document_context):
    """Add context description to a chunk"""
    context_prompt = f"""
    Document: {document_context['doc_title']}
    Section: {document_context['section']}
    Location: Page {document_context['page']}

    Summarize in one sentence where this fragment sits in the original document and what its topic is.
    """

    context = llm.generate(context_prompt)
    return f"{context}\n\n{chunk}"
```

#### Indexing Strategy

After chunking, you need to build two types of indexes:

1. Vector index: for semantic similarity search
2. Keyword index: for exact matching (e.g., clause numbers, table IDs)

Using both together produces better retrieval results. A Hybrid Search approach fuses vector search and keyword search results.

### Agent Invocation — On-Demand Tool Chain

The final layer is the Agent invocation strategy. The core idea is encapsulating PDF capabilities as tools rather than stuffing the entire PDF into context.

#### Tool Design

```python
# PDF RAG tool chain
tools = [
    {
        "name": "search_pdf",
        "description": "Search for relevant fragments in the PDF",
        "parameters": {
            "query": "Search keywords",
            "doc_id": "Document ID (optional)",
            "section": "Section filter (optional)"
        }
    },
    {
        "name": "read_page",
        "description": "Read content from a specific page of the PDF",
        "parameters": {
            "doc_id": "Document ID",
            "page_num": "Page number"
        }
    },
    {
        "name": "extract_table",
        "description": "Extract table data from the PDF",
        "parameters": {
            "doc_id": "Document ID",
            "table_id": "Table ID"
        }
    },
    {
        "name": "analyze_chart",
        "description": "Analyze charts in the PDF",
        "parameters": {
            "doc_id": "Document ID",
            "image_id": "Image ID"
        }
    },
    {
        "name": "quote_source",
        "description": "Return original text citation and page number",
        "parameters": {
            "chunk_id": "Fragment ID"
        }
    }
]
```

#### Invocation Strategy

Different types of user questions follow different invocation paths:

1. Simple factual questions (e.g., "What is the penalty amount?") → direct vector retrieval
2. Complex comparison questions (e.g., "Penalty clause differences between Contract A and Contract B") → retrieve multiple sections first, then let the Agent plan the reading
3. Table questions (e.g., "Quarterly revenue for 2023") → call extract_table
4. Chart questions (e.g., "What does this flowchart show?") → call analyze_chart

This design lets the Agent dynamically decide which tools to invoke based on question complexity rather than stuffing all information into context at once.

## Production Details: Traceable Citations and Evaluation

Two aspects that cannot be skipped when taking a PDF RAG system to production: traceable citations and an evaluation framework.

### Traceable Citations

When the Agent answers questions, it must include source information: which page the answer came from, which section it belongs to, and what the original text says. This lets users verify accuracy and trace the root of issues. Anthropic's Citation documentation also mentions that PDFs can cite by extracted text and return page ranges — a practice worth adopting.

```python
# Answer with citation example
def answer_with_citation(question, doc_id):
    # Retrieve relevant fragments
    chunks = search_pdf(question, doc_id)

    # Generate answer
    answer = generate_answer(question, chunks)

    # Build citations
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

### Evaluation Framework

Evaluation cannot just look at whether the final answer is correct — you need to assess quality across the entire pipeline:

| Evaluation Dimension | What to Evaluate |
|---------------------|------------------|
| Retrieval quality | Did retrieved fragments hit the mark? Is ranking reasonable? |
| Page accuracy | Are returned page numbers correct? |
| Table parsing | Were tables extracted correctly? Is structure complete? |
| OCR quality | Are there missing or incorrect characters? |
| Chart understanding | Was chart information correctly interpreted? |
| Answer accuracy | Is the final answer correct? |

Building an evaluation dataset covering different PDF types and question types, running regular evaluations, monitoring system quality, and closing the loop with traceable citations — that is how a system genuinely moves from demo to production.

**References**:

- [Anthropic Claude PDF Support](https://docs.anthropic.com/en/docs/build-with-claude/pdf-support)
- [Anthropic Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)
- [Anthropic Citation](https://docs.anthropic.com/en/docs/build-with-claude/citation)
- [pdfplumber documentation](https://github.com/jsvine/pdfplumber)
- [PyMuPDF documentation](https://pymupdf.readthedocs.io/)
