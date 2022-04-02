---
title: 用 freemarker 导出复杂的 word 文档
date: 2021-07-12 21:57:01
tags: freemarker
categories: 后端
---

-----

##### 一、学习背景

`Freemarker` 是一款强大的模板引擎，可以用来生成网页、邮件、文档等。对于简单的 `Word` 文档导出，只需要手动编写 `ftl` 文件即可。但如果要导出复杂的文档，比如带有复杂样式、页眉页脚、内嵌图片、批注等，手动编写模板就行不通了。现在提出一个从目标文档出发的解决方案：先将目标 `Word` 模板文档转换为 `xml` 文档，然后将 `xml` 文档转换为 `ftl` 文档，手动替换模板中的变量之后即可导出复杂 `Word` 。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_50_50_export_word_freemarker_flow.png)

##### 二、根据目标文档获取 `ftl` 文档

我们以导出房屋租赁合同文档为例，模板中有房东、租客信息、房屋信息等。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_51_57_contract_template.png)

###### 1. 将目标模板转换为 `xml` 文档

操作 `Word` 文档，点击【文件】，另存为 `xml` 文档。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_52_36_convert_to_xml.png)

用 `NotePad++` 或 `Sublime` 打开 `xml` 文档，内容缺乏层次感，这里需要格式化一下。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_53_50_format_xml.png)

###### 2. 将 `xml` 文档转换为 `ftl` 文档

格式化之后的 `xml` 文档，选择【文件】，另存为 `ftl` 文档。接下来需要手动替换模板参数。

**文本参数：**根据模板中的默认值，找到其所在位置，直接替换。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_54_36_replace_txt_2.png)

**图片参数：**图片参数是对图片进行 `Base64` 加密之后的值，加密操作可以由 `Java` 来完成。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_55_36_replace_img_2.png)

##### 三、使用 `Java` 根据 `ftl` 模板导出 `Word` 文档

在 `Resource` 目录下新建文件夹 `freemarker_template`，将 `ftl` 文档粘贴进去。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_56_39_package_structure.png)

图片 `Base64` 位编码：

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
     * 【对图片进行 Base64 编码】
     *
     * @param fileSrc 图片的存储地址: filePath + fileName
     * @return 图片 Base64 编码
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

解析模板内容实现：

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
     * 【组装数据模板信息】
     *
     * @param templatePath 模板存放的根目录
     * @param templateName 模板名称
     * @param params       模板内容参数
     * @return 数据模板信息
     */
    @Override
    public String getTemplateContent(String templatePath, String templateName, Map<String, Object> params) {
        try {

            LOGGER.info("start building template content. path: 【{}】; name: 【{}】; params: 【{}】", templatePath, templateName, params);

            Assert.hasText(templatePath, "template path cannot be null or empty");

            Assert.hasText(templateName, "template name cannot be null or empty");

            // 获取资源目录
            String resourcePath = TemplateServiceImpl.class.getResource(File.separator).getPath();

            // 模板配置信息
            Configuration configuration = new Configuration(Configuration.VERSION_2_3_28);
            configuration.setDefaultEncoding(StandardCharsets.UTF_8.name());
            String standardTemplatePath = templatePath.endsWith(File.separator) ? templatePath.concat(File.separator) : templatePath;
            configuration.setDirectoryForTemplateLoading(new File(resourcePath.concat(standardTemplatePath)));

            // 生成模板
            Template template = configuration.getTemplate(templateName);

            // 填充模板内容参数
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

单元测试：

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
        // 图片 Base64 编码
        String imgBase64Data = imageService.getImgBase64Data("C:\\house.jpg");
        contractInfo.setImgBase64Data(imgBase64Data);

        ObjectMapper objectMapper = new ObjectMapper();
        Map<String, Object> params = objectMapper.convertValue(contractInfo, Map.class);

        String content = templateService.getTemplateContent(templatePath, templateName, params);

        File file = new File("租房合同-打工人.doc");

        try (InputStream in = IOUtils.toInputStream(content, StandardCharsets.UTF_8);
             OutputStream out = new FileOutputStream(file)) {

            byte[] data = new byte[1024];

            int len;
            while (-1 != (len = in.read(data, 0, data.length))) {
                out.write(data, 0, len);
            }
            out.flush();
        } catch (Exception e) {
            LOGGER.error("下载租房合同失败; errMsg: {}", e.getMessage(), e);
        }
    }
}
```

**注意：** 通过这种方式导出的 `Word` 文档，本质上还是 `xml` 文档，因此必须使用 `.doc` 后缀，具体请查看[MsOffice Word docx 研究](https://donehub.github.io/my-blog/2021/07/11/difference_btw_doc_docx/)。

运行起来，导出`租房合同-打工人.doc`。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_57_34_export_word.png)

##### 四、总结

通过将目标模板转换为 `ftl` 文档，再解析得到目标文档的办法，理论上可以应对任何复杂程度的文档导出需求。但这种好办法也有弊端：`ftl` 文档包含太多的内联样式、复杂标签等，可读性太差。当模板发生变化时，手动替换太多的模板参数将会是一种灾难。



> 参考：
>
> * [Java 基于 freemarker 导出 Word 文档(含文本、表格、图片)](https://blog.csdn.net/weixin_42142057/article/details/82495417)
> * [Java 基于 freemarker 导出 Word 文档(含文本、图片)](https://blog.csdn.net/u014231523/article/details/86586721)
> * [Docx 相对于 Doc 的优势](https://www.zhihu.com/question/21547795/answer/18577889)