---
title: Exporting Complex Word Documents with Freemarker
date: 2021-07-12 21:57:01
tags: freemarker
categories: Backend
lang: en
label: 024_export_word_by_freemark_1
---

-----

<!-- more -->
##### 1. Why This Approach

`Freemarker` is a template engine that can generate web pages, emails, documents, and more. For simple `Word` document exports, writing an `ftl` template by hand works fine. But for complex documents — ones with intricate styling, headers, footers, embedded images, and annotations — hand-coding templates quickly becomes impractical. Here's a solution that starts from the target document itself: convert the target `Word` template to an `xml` document, then convert the `xml` to an `ftl` file, and manually replace the variables in the template. This approach handles documents of any complexity.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_50_50_export_word_freemarker_flow.png)

##### 2. From Target Document to `ftl` Template

We'll use a house rental contract as the example. The template includes landlord info, tenant info, and property details.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_51_57_contract_template.png)

###### Step 1: Convert the Template to `xml`

In Word, click File → Save As, and choose `xml` format.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_52_36_convert_to_xml.png)

Open the `xml` file in `NotePad++` or `Sublime`. The raw output is a wall of text with no indentation, so you'll want to format it first.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_53_50_format_xml.png)

###### Step 2: Convert `xml` to `ftl`

After formatting, save the file as `ftl`. Now comes the manual part — replacing template variables.

**Text parameters:** Find each placeholder by its default value in the template and replace it directly.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_54_36_replace_txt_2.png)

**Image parameters:** Images are stored as `Base64`-encoded values in the template. The encoding step is handled by Java.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_55_36_replace_img_2.png)

##### 3. Exporting `Word` from the `ftl` Template with Java

Create a `freemarker_template` folder under `Resource` and place the `ftl` file inside.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_56_39_package_structure.png)

Image `Base64` encoding:

```java
import com.company.exception.ServiceException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import sun.misc.BASE64Encoder;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * @author zourongsheng
 * @version 1.0
 * @date 2021/07/11 22:48
 */
@Service
public class ImageServiceImpl implements ImageService {

    private static final Logger LOGGER = LoggerFactory.getLogger(ImageServiceImpl.class);

    /**
     * Encode image to Base64
     *
     * @param fileSrc Image file path: filePath + fileName
     * @return Base64 encoded image string
     */
    @Override
    public String getImgBase64Data(String fileSrc) {

        File img = new File(fileSrc);

        if (!img.exists()) {
            return null;
        }

        try (InputStream in = new FileInputStream(img)) {
            byte[] data = new byte[in.available()];
            in.read(data);
            BASE64Encoder encoder = new BASE64Encoder();
            return encoder.encode(data);
        } catch (IOException e) {
            LOGGER.error("invoke ImageService.getImgBase64Data error: {}", e.getMessage(), e);
            throw new ServiceException(e.getMessage(), e);
        }
    }
}
```

Template processing implementation:

```java
import com.company.exception.ServiceException;
import freemarker.template.Configuration;
import freemarker.template.Template;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.Assert;

import java.io.File;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * @author zourongsheng
 * @version 1.0
 * @date 2021/07/11 16:14
 */
@Service
public class TemplateServiceImpl implements TemplateService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TemplateServiceImpl.class);

    /**
     * Process template with data parameters
     *
     * @param templatePath Base directory for templates
     * @param templateName Template file name
     * @param params       Template parameters
     * @return Processed template content
     */
    @Override
    public String getTemplateContent(String templatePath, String templateName, Map<String, Object> params) {
        try {

            LOGGER.info("start building template content. path: 【{}】; name: 【{}】; params: 【{}】", templatePath, templateName, params);

            Assert.hasText(templatePath, "template path cannot be null or empty");

            Assert.hasText(templateName, "template name cannot be null or empty");

            // Get resource directory
            String resourcePath = TemplateServiceImpl.class.getResource(File.separator).getPath();

            // Template configuration
            Configuration configuration = new Configuration(Configuration.VERSION_2_3_28);
            configuration.setDefaultEncoding(StandardCharsets.UTF_8.name());
            String standardTemplatePath = templatePath.endsWith(File.separator) ? templatePath.concat(File.separator) : templatePath;
            configuration.setDirectoryForTemplateLoading(new File(resourcePath.concat(standardTemplatePath)));

            // Load template
            Template template = configuration.getTemplate(templateName);

            // Fill template parameters
            StringWriter writer = new StringWriter();
            template.process(params, writer);

            String content = writer.toString();

            LOGGER.info("finish building template content.");

            return content;
        } catch (Exception e) {
            LOGGER.error("invoke TemplateService.getStringFromVm error: {}", e.getMessage(), e);
            throw new ServiceException(e.getMessage(), e);
        }
    }
}
```

Unit test:

```java
import ImageService;
import TemplateService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.commons.io.IOUtils;
import org.junit.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Resource;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.runner.RunWith;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;

/**
 * @author zourongsheng
 * @version 1.0
 * @date 2021/07/11 16:44
 */
@RunWith(SpringRunner.class)
@SpringBootTest
public class TemplateTest {
    
    private static final Logger LOGGER = LoggerFactory.getLogger(TemplateTest.class);

    @Resource
    private TemplateService templateService;

    @Resource
    private ImageService imageService;

    @Test
    public void generateWordFromTemplate() {

        String templatePath = "freemarker_template/";
        String templateName = "contract.ftl";

        ContractInfo contractInfo = new ContractInfo();
        contractInfo.setLandlordName("地头蛇");
        contractInfo.setLandlordIdNo("100011232132112");
        contractInfo.setLandlordAddress("上海市青浦区");
        contractInfo.setLandlordPhoneNo("13032389090");
        contractInfo.setTenantName("打工人");
        contractInfo.setTenantIdNo("340323199901013217");
        contractInfo.setTenantAddress("安徽省蚌埠市");
        contractInfo.setTenantPhoneNo("15656997878");
        contractInfo.setYear("2020");
        contractInfo.setMonth("01");
        contractInfo.setDay("01");
        // Image Base64 encoding
        String imgBase64Data = imageService.getImgBase64Data("C:\\house.jpg");
        contractInfo.setImgBase64Data(imgBase64Data);

        ObjectMapper objectMapper = new ObjectMapper();
        Map<String, Object> params = objectMapper.convertValue(contractInfo, Map.class);

        String content = templateService.getTemplateContent(templatePath, templateName, params);

        File file = new File("Rental Contract.doc");

        try (InputStream in = IOUtils.toInputStream(content, StandardCharsets.UTF_8);
             OutputStream out = new FileOutputStream(file)) {

            byte[] data = new byte[1024];

            int len;
            while (-1 != (len = in.read(data, 0, data.length))) {
                out.write(data, 0, len);
            }
            out.flush();
        } catch (Exception e) {
            LOGGER.error("Failed to export rental contract; errMsg: {}", e.getMessage(), e);
        }
    }
}
```

**Important note:** Documents exported this way are essentially `xml` documents under the hood, so you must use the `.doc` extension. See [Inside the docx format](https://donehub.github.io/my-blog/2021/07/11/difference_btw_doc_docx/) for details.

Run the test and the file `Rental Contract.doc` gets generated.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_57_34_export_word.png)

##### 4. Takeaways

Converting a target template to `ftl` and then processing it can theoretically handle documents of any complexity. But this approach has a real downside: `ftl` files end up packed with inline styles and complex tags, making them nearly unreadable. When the template changes, manually replacing a large number of parameters becomes a nightmare.



> References:
>
> * [Java: Export Word documents with freemarker (text, tables, images)](https://blog.csdn.net/weixin_42142057/article/details/82495417)
> * [Java: Export Word documents with freemarker (text, images)](https://blog.csdn.net/u014231523/article/details/86586721)
> * [Advantages of docx over doc](https://www.zhihu.com/question/21547795/answer/18577889)
