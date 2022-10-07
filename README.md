
这是对[zhfonts](https://github.com/Fusyong/zhfonts)项目的重构。**尚在设计阶段！**

主要目标：

1. 预制常见的标点压缩规则；
1. 全部使用实测的字模数据，而不是使用预设的比例，以适应字体实际；
1. **拓展、校正还是覆盖系统的`hanzi`脚本的行为？？**

## 符号分类与定义


| 《标点符号用法》     |              |                | 重定义   |          |          |                                                               | 配置加空     |         |      |      |
| -------------------- | ------------ | -------------- | -------- | -------- | -------- | ------------------------------------------------------------- | ------------ | ------- | ---- | ---- |
| 分类                 | 独用占位(角) | 形式           | 补充符号 | 语义单元中的位置 | 禁排     | 备注                                                          | 开明（默认） | 全角    | 半角 | 原样 |
| 句末点号             | 1            | 。？！         | ．       | 后       | 行首禁排 | 忽略`？！` `双用占一，三用占二`的规定，重制统一的标点组占位规则 | 后0.5          | 后0.5     |      |      |
| 句内点号             | 1            | ，、；：       |          | 后       | 行首禁排 |                                                               |              | 后0.5     |      |      |
| 前半标号             | 1            | “‘（［〔【《〈 | 「『〖｛ | 前       | 行尾禁排 |                                                               |              | 前0.5     |      |      |
| 后半标号             | 1            | ”’）］〕】》〉 | 」』〗｝ | 后       | 行首禁排 |                                                               |              | 后0.5     |      |      |
| 省略号               | 2            | `……`           |          | 中^*^       |          | 作为整体                                                      |              |         |      |      |
| 破折号（中后标号）   | 2            | `——`           |          | 中^*^     |          | 作为整体                                                      |              |         |      |      |
| 全角连接号（中标号） | 1            | —～            |          | 中       | 行首禁排 |                                                               |              |         |      |      |
| 半角连间分（中标号） | 0.5          | -·/            | ／       | 中       | 行首禁排 | `/`由`首尾禁排`改为`行首禁排`                                 |              | 前后0.25 |      |      |

^*^ 实际上，省略号、破折号可出现在语义单元的前、中、后各处，但字模占位已经足够宽，两侧不再加空，与“连间分”地位相当。

## 占位规则

* **标点字模占位**
    * **所有字模均预先调整占位，且居中放置。** 居中可简化连用时的定位。
    * 横势标点`……` `——` `—` `～` `-`按《标点符号用法》规定占位，**其余一律占0.5角（quad，下同）。** 
    字模占位窄对断行算法、行尾标点对齐有利。
* **标点组与加空**
    * 各类标点加空配置见上表中的“配置加空”。
    * 语义位置相同的相邻几个标点为一个标点组。如`”〉》`为一个后标点组。
    * 前标点组，根据最前一个标点，在组前加空。如：
        * 全角配置：`囗囗␣《〈“囗囗`
        * 开明配置：`囗囗《〈“囗囗`
    * 后标点组，根据最后一个标点，在组后加空。如
        * 全角配置：`囗囗”〉》␣囗囗` `囗囗！〉》␣囗囗` `囗囗〉》！␣囗囗`
        * 开明配置：`囗囗”〉》囗囗` `囗囗！〉》囗囗` `囗囗〉》！␣囗囗`
    * 中标点组（通常是单个），根据最前一个标点，在组前加空；根据最后一个标点，在组后加空。如：
        * 全角配置：`囗囗␣·␣囗囗` `囗囗␣/␣囗囗` `囗囗～囗囗` `囗囗——囗囗`
        * 开明配置：`囗囗·囗囗` `囗囗/囗囗` `囗囗～囗囗` `囗囗——囗囗`
    * 同一个位置（如前标点组与后标点组之间）只加空一次（取最大值）。如：
        * 全角配置：`囗囗”〉》␣《〈“囗囗` `囗囗”〉》！␣《〈“囗囗`
        * 开明设置：`囗囗”〉》《〈“囗囗` `囗囗”〉》！␣《〈“囗囗`
    * 中标点组，前后有标点组时，直接附着与前后的标点组，其间不加空。如：
        * 全角配置：`囗囗”·“囗囗` `囗囗”·␣囗囗` `囗囗␣·“囗囗`
        * 开明设置：`囗囗”·“囗囗` `囗囗”·囗囗` `囗囗·“囗囗`
* 默认标准空（固定宽度的胶）占位0.5，可通过设置比例调整实际宽度。比如全角配置时，之间只加一次空。
* 标点前后加扩展胶，与系统给汉字后加扩展胶的规则一致。

## TODO & bugs

* [ ] 允许用户扩展符号类别（**或许用宏定义更方便**）：
    * 全角代字符号：□
    * 全角前导符号：☆★○●◎◇◆□
    * 数字序号：㈠㈡㈢⑴⑵⑶⒈⒉⒊ⅠⅡⅢ……



## 