---
title: Kafka消息的压缩机制
tags:
  - Kafka系列
  - message
categories:
  - Kafka
date: 2022-04-30 22:00:00
---

最近在做 AWS cost saving 的事情，对于 Kafka 消息集群，计划通过压缩消息来减少消息存储所占空间，从而达到减少 cost 的目的。本文将结合源码从 Kafka 支持的消息压缩类型、何时需要压缩、如何开启压缩、何处进行压缩以及压缩原理来总结 Kafka 整个压缩机制。文中所涉及源码部分都来自于 Kafka 当前最新的 3.3.0-SNAPSHOT 版本。

# Kafka支持的消息压缩类型

## 什么是 Kafka 的消息压缩

在谈消息压缩类型之前，我们先看下 Kafka 中关于消息压缩的定义是什么。

Kafka [官网](https://cwiki.apache.org/confluence/display/KAFKA/Compression)有这样一段解释：

> 此为 Kafka 中端到端的块压缩功能。如果启用，数据将由 producer 压缩，以压缩格式写入服务器，并由 consumer 解压缩。压缩将提高 consumer 的吞吐量，但需付出一定的解压成本。这在跨数据中心镜像数据时尤其有用。

也就是说，Kafka 的消息压缩是指将消息本身采用特定的压缩算法进行压缩并存储，待消费时再解压缩。

我们知道压缩就是用时间换空间，其基本理念是基于重复，将重复的片段编码为字典，字典的 key 为重复片段，value 为更短的代码，比如序列号，然后将原始内容中的片段用代码表示，达到缩短内容的效果，压缩后的内容则由字典和代码序列两部分组成。解压时根据字典和代码序列可无损地还原为原始内容。注：有损压缩不在此次讨论范围。

通常来讲，重复越多，压缩效果越好。JSON是 Kafka 消息中常用的序列化格式，单条消息内可能并没有多少重复片段，但如果是批量消息，则会有大量重复的字段名，批量中消息越多，则重复越多，这也是为什么 Kafka 更偏向块压缩，而不是单条消息压缩。

## 消息压缩类型

目前 Kafka 共支持四种主要的压缩类型：Gzip、Snappy、Lz4 和 Zstd。关于这几种压缩的特性，

| 压缩类型 | Compression ratio | CPU 使用率 | Compression speed | Network bandwidth usage |
| -------- | ----------------- | ---------- | ----------------- | ----------------------- |
| Gzip     | Highest           | Highest    | Slowest           | Lowest                  |
| Snappy   | Medium            | Moderate   | Moderate          | Medium                  |
| Lz4      | Low               | Lowest     | Fastest           | Highest                 |
| Zstd     | Medium            | Moderate   | Moderate          | Medium                  |

从上表可知，Snappy 在 CPU 使用率、压缩比、压缩速度和网络带宽使用率之间实现良好的平衡，我们最终也是采用的该类型进行压缩试点。这里值得一提的是，Zstd 是 Facebook 于 2016 年开源的新压缩算法，压缩率和压缩性能都不错，具有与 Snappy（Google 杰作）相似的特性，直到 Kafka 的 2.1.0 版本才引入支持。

针对这几种压缩本身的性能，Zstd [GitHub 官方](https://github.com/facebook/zstd)公布了压测对比结果如下，

| Compressor name                        | Ratio | Compression | Decompress. |
| -------------------------------------- | ----- | ----------- | ----------- |
| **zstd 1.5.1 -1**                      | 2.887 | 530 MB/s    | 1700 MB/s   |
| [zlib](http://www.zlib.net/) 1.2.11 -1 | 2.743 | 95 MB/s     | 400 MB/s    |
| brotli 1.0.9 -0                        | 2.702 | 395 MB/s    | 450 MB/s    |
| **zstd 1.5.1 --fast=1**                | 2.437 | 600 MB/s    | 2150 MB/s   |
| **zstd 1.5.1 --fast=3**                | 2.239 | 670 MB/s    | 2250 MB/s   |
| quicklz 1.5.0 -1                       | 2.238 | 540 MB/s    | 760 MB/s    |
| **zstd 1.5.1 --fast=4**                | 2.148 | 710 MB/s    | 2300 MB/s   |
| lzo1x 2.10 -1                          | 2.106 | 660 MB/s    | 845 MB/s    |
| [lz4](http://www.lz4.org/) 1.9.3       | 2.101 | 740 MB/s    | 4500 MB/s   |
| lzf 3.6 -1                             | 2.077 | 410 MB/s    | 830 MB/s    |
| snappy 1.1.9                           | 2.073 | 550 MB/s    | 1750 MB/s   |

可以看到 Zstd 可以通过压缩速度为代价获得更高的压缩比，二者之间的权衡可通过 `--fast` 参数灵活配置。

# 何时需要压缩

压缩是需要额外的 CPU 代价的，并且会带来一定的消息分发延迟，因而在压缩前要慎重考虑是否有必要。笔者认为需考虑以下几方面：

* 压缩带来的磁盘空间和带宽节省远大于额外的 CPU 代价，这样的压缩是值得的。
* 数据量足够大且具重复性。消息压缩是批量的，低频的数据流可能都无法填满一个批量，会影响压缩比。数据重复性越高，往往压缩效果越好，例如 JSON、XML 等结构化数据；但若数据不具重复性，例如文本都是唯一的 md5 或 UUID 之类，违背了压缩的重复性前提，压缩效果可能不会理想。
* 系统对消息分发的延迟没有严苛要求，可容忍轻微延迟增大。

# 如何开启压缩

Kafka 通过配置属性 `compression.type` 控制是否压缩。该属性在 producer 端和 broker 端各自都有一份，也就是说，我们可以选择在 producer 或 broker 端开启压缩，对应的应用场景各有不同。

## 在 Broker 端开启压缩

### compress.type 属性

Broker 端的 `compression.type` 属性默认值为 `producer`，即直接继承 producer 端的压缩方式，无论 producer 端采用何种压缩或者不压缩，broker 都原封不动地照单接受并存储，这一点可以从如下代码片段看出：

```scala
class UnifiedLog(...) extends Logging with KafkaMetricsGroup {
  ...
  private def analyzeAndValidateRecords(records: MemoryRecords,
                                        origin: AppendOrigin,
                                        ignoreRecordSize: Boolean,
                                        leaderEpoch: Int): LogAppendInfo = {
    // Apply broker-side compression if any
    val targetCodec = BrokerCompressionCodec.getTargetCompressionCodec(config.compressionType, sourceCodec);
  }
}

object BrokerCompressionCodec {

  val brokerCompressionCodecs = List(UncompressedCodec, ZStdCompressionCodec, LZ4CompressionCodec, SnappyCompressionCodec, GZIPCompressionCodec, ProducerCompressionCodec)
  val brokerCompressionOptions: List[String] = brokerCompressionCodecs.map(codec => codec.name)

  def isValid(compressionType: String): Boolean = brokerCompressionOptions.contains(compressionType.toLowerCase(Locale.ROOT))

  def getCompressionCodec(compressionType: String): CompressionCodec = {
    compressionType.toLowerCase(Locale.ROOT) match {
      case UncompressedCodec.name => NoCompressionCodec
      case _ => CompressionCodec.getCompressionCodec(compressionType)
    }
  }

  def getTargetCompressionCodec(compressionType: String, producerCompression: CompressionCodec): CompressionCodec = {
    if (ProducerCompressionCodec.name.equals(compressionType))
      producerCompression
    else
      getCompressionCodec(compressionType)
  }
}
```

`targetCodec` 为 broker 端用于存储消息最终的目标编码，从函数 `getTargetCompressionCodec` 可以看出是结合 broker 端的 `compressionType` 和 producer 端的 `producerCompression` 综合判断的：当 `compressionType` 为 `producer` 时直接采用 producer 端的 `producerCompression`，否则就采用 broker 端自身的编码设置 `compressionType`。从 `brokerCompressionCodecs` 的取值可看出，`compression.type` 的可选值为 `[uncompressed, zstd, lz4, snappy, gzip, producer]`。其中 `uncompressed` 与 `none` 是等价的，`producer` 不用多说，其余四个则是标准的压缩类型。

### broker 和 topic 两个级别

在 broker 端的压缩配置分为两个级别：全局的 broker 级别 和 局部的topic 级别。

