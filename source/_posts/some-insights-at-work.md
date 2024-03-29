---
title: 工作中的一些感悟
tags:
  - 思考
categories:
  - Work
date: 2019-12-21 12:00:00
---


不知不觉工作已三年半，准确的说是三年零五个月。在这过程中，在技术和业务上的成长，多多少少都会有一些，但最大的收获，还是长见识。聊聊几点感受吧。

<!--more-->

## 学会向上汇报

别只顾埋头做事，要做“对”的事情。

这是个人情社会，你的领导也只是普通人，他不太会有大把的精力去关注底下的人每天具体干些什么事情，这种情况下，如果你只知道一味地埋头做事，即便做了很多，加班累成狗，但是领导压根不知道，是没有任何意义的，典型的吃力不讨好。很多时候是需要你主动向上汇报的！定期地跟领导保持正向沟通，积极反馈工作中遇到的问题以及自己的想法，让领导感知到你的付出，当然有产出是最好的了。

什么是“对”的事情？要有全局观，审时度势。当前领导最关心最迫切的事情，就是对的事情。举个栗子，随着用户量的快速增长，系统的压力越来越大，原有最初的系统逐渐暴露问题，甚至因此频繁出现线上故障。这个时候，如果领导发起了“系统压测”的任务，那么当务之急，压测就是最重要的事情，工作的重心应该以此为准。即便此时业务上也有很多新的需求，你也应该做取舍，否则即便你做了一大堆需求，此时的领导根本无暇顾及，他所关注的必然是压测的进度，千万不能捡了芝麻丢了西瓜。

## 打破局限，解决问题才是王道

在遇到紧急情况，如线上故障处理时，快速解决问题才是关键。有的时候我们容易陷入程序员惯有的思维里，遇到问题会习惯性地一上来就尝试用代码去解决，而忽略了一些非代码的简单处理方式，比如粘贴/复制、excel工具、sublime文本替换等。这里列举两个工作中的小例子，深有感悟。

### 栗子1：故障处理

在一次故障处理过程中，需要对一批指定用户做一个操作，这个操作可以通过curl请求来完成，当前已有的是已经导出的以userId逐行排列的userIds.txt文件和请求的url，分别长下面这样子：

```shell
userIds.txt内容：
userId1
userId2
userId3
...
userIdn

url内容：
https://www.yangbing.club/${userId}/doing
```

当时的第一反应就是准备写个shell脚本或者Java的Job来搞这个事，本身逻辑简单，一层循环就能搞定，伪代码大致如下：

```shell
userIds <- userIds.txt
for userId in userIds:
	actualUrl = url.replace("${userId}", userId)
	curl -H 'Cooike: xxx' actualUrl
```

但偏偏shell又不太熟，还得调试，想想就头大。此时组里新来的清华实习生给出了简单粗暴的方式，直接在userIds.txt文件上做文章，用sublime的文本替换功能，将文本中每一行，如第一行userId1的行首`^`替换为请求url中`${userId}`之前的子串**curl -H 'Cooike: xxx' https://www.yangbing.club/**，将行尾`$`替换为url中`${userId}`之后的子串**/doing**，这样就得到如下的结果文件：

```shell
curl -H 'Cooike: xxx' https://www.yangbing.club/userId1/doing
curl -H 'Cooike: xxx' https://www.yangbing.club/userId2/doing
curl -H 'Cooike: xxx' https://www.yangbing.club/userId3/doing
...
curl -H 'Cooike: xxx' https://www.yangbing.club/userIdn/doing
```

然后一行命令就能搞定：

```shell
sh userIds.txt
```

如果处理速度慢了想要并发，又可以通过split命令将userIds.txt按记录行数拆分成多个小文件，然后依次sh，利用操作系统的多进程并发处理。

回想这个事情的处理过程，我们的最终目的实际是为不同的userId生成对应的url，然后curl请求执行。程序员的固有思维就是消除重复，尽可能复用！对于这种userId不同，有相同的url模板的典型case，很自然的想到用循环。而忽略了`ctrl C/V`这种“重复”的快捷方式。

### 栗子2：日常开发

产品有个导数据的需求，要将特定筛选条件下的用户列表导出为Excel文件。这本身并不难，一个常规的Job就能搞定了。

同事A的方案也很常规，算是比较自然的思路，大概构想了一下代码流程，类似这样：组织筛选代码逻辑，将符合条件的用户列表筛出来，然后将列表转换为行数组，并构建标题数组，再通过Excel三方库或公司已有的工具类，将数据写入Excel文件。在这过程中，除了筛选条件的代码逻辑外，转为Excel工具需要的数据格式并生成Excel文件，看起来是最耗时的工作。

这看起来好像没啥问题，但笔者并没有采用上述方案。我们来看下这个需求，首先它是个一次性的，数据导出之后就完事了，也没有后续迭代；其次，Excel文件只是产品所需要结果的一种文件格式，我们只要能确保最终给到产品的是Excel就行，至于我们是通过代码生成Excel的方式，还是借用Office Excel强大功能将其他格式的文件转换为Excel的方式，产品并不关心。而我们又知道，Office Excel可以轻松支持将特定分隔符（如逗号、tab键）的文本文件导入为Excel，因而方案自然就变为：

先筛选出符合条件的用户列表，然后通过**log.info**将每个用户记录User的各字段以逗号","分割打印一行，这样我们就得到了第一版数据——日志文件，大概长这样：

```java
......// 启动日志
2019-11-25 23:00:42 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] job start
2019-11-25 23:00:42 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] user info:10506672,"userName1","address1",2 
2019-11-25 23:00:42 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] user info:10506673,"userName2","address2",3 
2019-11-25 23:00:42 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] user info:10506674,"userName3","address3",2
......
2019-11-25 23:00:45 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] user info:10506694,"userName100","address100",1
2019-11-25 23:00:45 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] has processed 100 users
2019-11-25 23:00:45 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] user info:10506694,"userName101","address101",1
......
2019-11-25 23:00:42 [INFO] [Thread-17] [org.sherlockyb.blogdemos.ExportUserJob] job end
......// job退出日志
```

这时候，强大的文本编辑工具sublime就登场了。可以看到，日志中除了含有**user info**的行尾是我们需要的数据，其余都是无用信息，冗余数据处理分为如下几步：

* job起始和结束我们通常会打印**job start**和**job end**，那么这两行分别之前和之后的内容可以直接删除

* 像**has processed xxx users**这种打印job进度的信息，可以通过正则**.*has processed [\d]+ users\n**替换为空串，这个地方需要注意一个细节，就是正则中要包含"\n"符号，否则替换后会留下空行，比较尴尬。

* 前面两步处理完后，就剩下数据行了，然后用正则**.*\[org.sherlockyb.blogdemos.ExportUserJob\] user info:**把无用的前缀替换为空串即可。

* 剩下的数据行其实就是标准的CSV格式文件了，改下后缀，然后打开文件，将内容复制到Excel文件即可。或者在打印日志时我们用"\t"分割，这样在得到剩下的数据行时，可以直接复制到新建的Excel文件也是可以的

可以看到，这个方案的核心在于，通过Office Excel已有的强大功能，代替了通过写代码生成Excel的方式，从某种意义上说，这也是复用，只不过复用的不是现有代码，而是现有的软件功能，而这些强大的软件功能，同样也是别人写代码实现的，间接地复用了"已有代码"。

同事A后来听我跟他讲完我的实现方案，表示“秀了我一脸”，真实。。。。

## 用“好工具”，“用好”工具

好的工具能让我们极大地提升做事效率。

以前我对于日常开发工具的认知就是，够用就行，不用太深究，专注代码和技术。直到后来，当我见识到周围的朋友如何熟练地通过各种工具快速达到目的的时候，感觉真的被秀了一脸。

好的工具有哪些呢？笔者有个推荐清单：

* IntelliJ idea，真的比eclipse好用太多，用过的才知道。可配置各种常用快捷键，如项目切换、代码视图回退、代码跳转等
* Sublime，强大的文本编辑工具，日常的文本处理用它就行
* Excel，再普通不过了，基本用过pc的人都了解过一些基本用法，但又有多少人用过筛选、列隐藏、多列排序、指定分隔符导入文本数据等功能呢？多研究多使用，你会发现不一样的天空。
* Alfred，mac下强大的搜索工具，真的很强大。在一个小小的命令框内，它可以快速定位本地文件，使用计算器、词典，等等。比如通过`idea 项目名`，你可以快速打开指定的idea项目，这比你每次点击**File** -> **Open** -> **选择项目目录** -> **ok**，可是要快的多！
* open-falcon，小米开源的监控平台，虽然使用上不太友好，但东西还是挺全的，需要的监控指标和功能基本都有

除了上面列的，还有很多日常可用的工具，基本只要你能想到的，都会有。在挖掘新的可用工具的同时，对于已经经常在使用的工具，可以深究，也许你会发现很多好用的feature，用好它，让你事半功倍。

## 积极主动，要有owner精神

积极主动反映的是良好的工作态度，团队需要积极的氛围，领导更需要积极的人才。

owner精神，则需要较强的责任心，对所参与的业务以及团队负责的业务负责，开发时积极推动项目进度，协调各方优先级，确保项目如期高质量上线；遇到线上故障时，积极响应，确保在最短的时间内解除故障。

## 沟通很重要，对上和对下

没有什么事情是沟通解决不了的，如果有，就多次沟通。

对上沟通，能让领导对你有所知，有所期望，可能还会有额外的指导，能及时暴露风险，尽早解决；对下沟通，能让你带的小伙伴感受到温暖，知道你时刻在关注着他，这是正向反馈。另外，你也能及时了解他当前的状况，如有困惑，帮助他解决，让他少走弯路；如有新的想法，拿出来讨论，或许会给你带来新的启发。

## 爱钻研，有技术追求

我在面试的时候，经常会看这一点。对于爱钻研，有技术追求的候选人，他首先一定是自驱力不错的，因为技术钻研这个事儿纯粹是出于个人意愿，能坚持下来，不容易。其次，他对于技术是有好奇心的，好奇心会驱使他去研究这里面的细节，搞清楚原理，不会浮于表面。

## 反对过度设计与优化

技术架构一定是依托于业务的。

公司发展的不同阶段，业务量级的不同，所需要的技术架构是不一样的。初创期，业务规模小，产品迭代速度快，此时需要的是快速支持，快速开发，比如很多统计数据的场景就直接实时计算了，后端服务可能就是一个单体应用，这些都是可以接受的；随着业务发展，业务形态多样化，用户量快速增长，导致系统压力、复杂度倍增，此时就需要考虑微服务拆分、分布式、性能优化、Redis缓存、分库拆表等技术方案了。

技术架构除了要考虑能否支持业务发展，技术先进性外，也要考虑成本，这里面既有数据库、服务节点等资源成本，也有开发成本，更多时候是取一种折中方案，收益最大化。

## 成也经验，败也经验

过去的经验能让我们在处理新的问题时有参考依据，尽量少走弯路，通常这是没问题的。但有一个误区是，过分相信此前的经验，认为那绝对是对的。工作中就遇到过这类case，关于thrift新增字段，是否需要设置为optional的，同事A很自信地认为用默认的required就行，因为之前这么干过没问题。但很快实验表明，新增required字段，会导致新老版本不兼容，call端会报异常。

经验有对有错，我们需要有质疑心态，不能尽信之。

