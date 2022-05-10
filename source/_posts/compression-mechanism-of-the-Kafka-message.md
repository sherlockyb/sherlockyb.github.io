---
title: Kafka消息的压缩机制
tags:
  - Kafka系列
  - 消息队列
  - 源码
categories:
  - Kafka
date: 2022-04-30 22:00:00
---


最近在做 AWS cost saving 的事情，对于 Kafka 消息集群，计划通过压缩消息来减少消息存储所占空间，从而达到减少 cost 的目的。本文将结合源码从 Kafka 支持的消息压缩类型、何时需要压缩、如何开启压缩、何处进行解压缩以及压缩原理来总结 Kafka 整个消息压缩机制。文中所涉及源码部分均来自于 Kafka 当前最新的 3.3.0-SNAPSHOT 版本。

<!--more-->

# Kafka支持的消息压缩类型

## 什么是 Kafka 的消息压缩

在谈消息压缩类型之前，我们先看下 Kafka 中关于消息压缩的定义是什么。

Kafka [官网](https://cwiki.apache.org/confluence/display/KAFKA/Compression) 有这样一段解释：

> 此为 Kafka 中端到端的块压缩功能。如果启用，数据将由 producer 压缩，以压缩格式写入服务器，并由 consumer 解压缩。压缩将提高 consumer 的吞吐量，但需付出一定的解压成本。这在跨数据中心镜像数据时尤其有用。

也就是说，Kafka 的消息压缩是指将消息本身采用特定的压缩算法进行压缩并存储，待消费时再解压。

我们知道压缩就是用时间换空间，其基本理念是基于重复，将重复的片段编码为字典，字典的 key 为重复片段，value 为更短的代码，比如序列号，然后将原始内容中的片段用代码表示，达到缩短内容的效果，压缩后的内容则由字典和代码序列两部分组成。解压时根据字典和代码序列可无损地还原为原始内容。注：有损压缩不在此次讨论范围。

通常来讲，重复越多，压缩效果越好。比如 JSON 是 Kafka 消息中常用的序列化格式，单条消息内可能并没有多少重复片段，但如果是批量消息，则会有大量重复的字段名，批量中消息越多，则重复越多，这也是为什么 Kafka 更偏向块压缩，而不是单条消息压缩。

## 消息压缩类型

目前 Kafka 共支持四种主要的压缩类型：Gzip、Snappy、Lz4 和 Zstd。关于这几种压缩的特性，

| 压缩类型 | 压缩比率 | CPU 使用率 | 压缩速度 | 带宽使用率 |
| -------- | -------- | ---------- | ----------------- | ----------------------- |
| Gzip     | Highest  | Highest    | Slowest           | Lowest                  |
| Snappy   | Medium   | Moderate   | Moderate          | Medium                  |
| Lz4      | Low      | Lowest     | Fastest           | Highest                 |
| Zstd     | Medium   | Moderate   | Moderate          | Medium                  |

从上表可知，Snappy 在 CPU 使用率、压缩比、压缩速度和网络带宽使用率之间实现良好的平衡，我们最终也是采用的该类型进行压缩试点。这里值得一提的是，Zstd 是 Facebook 于 2016 年开源的新压缩算法，压缩率和压缩性能都不错，具有与 Snappy（Google 杰作）相似的特性，直到 Kafka 的 2.1.0 版本才引入支持。

针对这几种压缩本身的性能，Zstd [GitHub 官方](https://github.com/facebook/zstd) 公布了压测对比结果如下，

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
* 系统对消息分发的延迟没有严苛要求，可容忍轻微的延迟增长。

# 如何开启压缩

Kafka 通过配置属性 `compression.type` 控制是否压缩。该属性在 producer 端和 broker 端各自都有一份，也就是说，我们可以选择在 producer 或 broker 端开启压缩，对应的应用场景各有不同。

## 在 Broker 端开启压缩

### compression.type 属性

Broker 端的 `compression.type` 属性默认值为 `producer`，即直接继承 producer 端所发来消息的压缩方式，无论消息采用何种压缩或者不压缩，broker 都原样存储，这一点可以从如下代码片段看出：

```scala
class UnifiedLog(...) extends Logging with KafkaMetricsGroup {
  ...
  private def analyzeAndValidateRecords(records: MemoryRecords,
                                        origin: AppendOrigin,
                                        ignoreRecordSize: Boolean,
                                        leaderEpoch: Int): LogAppendInfo = {
    records.batches.forEach { batch =>
      ...
      val messageCodec = CompressionCodec.getCompressionCodec(batch.compressionType.id)
      if (messageCodec != NoCompressionCodec)
        sourceCodec = messageCodec
    }
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

`sourceCodec` 为 `recordBatch` 上的编码，即表示从 producer 端发来的这批消息的编码。 `targetCodec` 为 broker 端配置的压缩编码，从函数 `getTargetCompressionCodec` 可以看出最终存储消息的目标编码是结合 broker 端的 `compressionType` 和 producer 端的 `producerCompression` 综合判断的：当 `compressionType` 为 `producer` 时直接采用 producer 端的 `producerCompression`，否则就采用 broker 端自身的编码设置 `compressionType`。从 `brokerCompressionCodecs` 的取值可看出，`compression.type` 的可选值为 `[uncompressed, zstd, lz4, snappy, gzip, producer]`。其中 `uncompressed` 与 `none` 是等价的，`producer` 不用多说，其余四个则是标准的压缩类型。

### broker 和 topic 两个级别

在 broker 端的压缩配置分为两个级别：全局的 broker 级别 和 局部的 topic 级别。顾名思义，如果配置的是 broker 级别，则对于该 Kafka 集群中所有的 topic 都是生效的。但如果 topic 级别配置了自己的压缩类型，则会覆盖 broker 全局的配置，以 topic 自己配置的为准。 

#### broker 级别

要配置 broker 级别的压缩类型，可通过 `configs` 命令修改 `compression.type` 配置项取值。此处要使修改生效，是否需要重启 broker 取决于 Kafak 的版本，在 1.1.0 之前，任何配置项的改动都需要重启 broker 才生效，而从 1.1.0 版本开始，Kafka 引入了动态 broker 参数，将配置项分为三类：`read-only`、`per-broker` 和 `cluster-wide`，第一类跟原来一样需重启才生效，而后面两类都是动态生效的，只是影响范围不同，关于 Kafka 动态参数，以后单开博文介绍。从 [官网](https://kafka.apache.org/documentation/#brokerconfigs_compression.type) 可以看到，`compression.type` 是属于 `cluster-wide` 的，如果是 1.1.0 及之后的版本，则无需重启 broker。

#### topic 级别

topic 的配置分为两部分，一部分是 topic 特有的，如 partitions 等，另一部分则是默认采用 broker 配置，但也可以覆盖。如果要定义 topic 级别的压缩，可以在 topic 创建时通过 --config 选项覆盖配置项 `compression.type` 的取值，命令如下：

```shell
sh bin/kafka-topics.sh --create --topic my-topic --replication-factor 1 --partitions 1 --config compression.type=snappy
```

当然也可以通过 `configs` 命令修改 topic 的 `compression.type` 取值，命令如下：

```shell
bin/kafka-configs.sh --entity-type topics --entity-name my-topic --alter --add-config compression.type=snappy
```

## 在 Producer 端压缩

### compression.type 属性

跟 broker 端一样，producer 端的压缩配置属性依然是 `compression.type`，只不过默认值和可选值有所不同。默认值为 `none`，表示不压缩，可选值为枚举类 `CompressionType` 中所有实例对应 `name` 的列表。

### 开启压缩的方式

直接在代码层面更改 producer 的 config，示例如下。但需要注意的是，改完 config 之后，需要重启 producer 端的应用程序，压缩才会生效。

```java
@Configuration
@EnableKafka
public class KafkaProducerConfig {
    @Bean
    public KafkaTemplate<byte[], byte[]> kafkaTemplate() {
        Map<String, Object> config = new HashMap<>();
        config.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, brokerServer);
        config.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, keySerializer);
        config.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, valueSerializer);
        config.put(ProducerConfig.ACKS_CONFIG, "all");
        config.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, "1");
        config.put(ProducerConfig.BATCH_SIZE_CONFIG, "16384");
        config.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);
        config.put(ProducerConfig.RETRY_BACKOFF_MS_CONFIG, "3000");
        config.put(ProducerConfig.LINGER_MS_CONFIG, "1");
        ...
        // 开启 Snappy 压缩
        config.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, CompressionType.SNAPPY.name);

        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(config));
    }
}
```

# 压缩和解压的位置

## 何处会压缩

可能产生压缩的地方有两处：producer 端和 broker 端。

### producer 端

producer 端发生压缩的唯一条件就是在 producer 端为属性 `compression.type` 配置了除 `none` 之外有效的压缩类型。此时，producer 在向所负责的所有 topics 发消息之前，都会将消息压缩处理。

### broker 端

对于 broker 端，产生压缩的情况就复杂得多，这不仅取决于 broker 端自身的压缩编码 `targetCodec` 是否是需要压缩的类型，还取决于 `targetCodec` 跟 producer 端的 `sourceCodec` 是否相同，除此之外，还跟消息格式的 `magic` 版本有关。直接看代码，broker 端的消息读写是由 `UnifiedLog` 负责的，消息持久化的核心入口是 `append` 方法，代码如下：

```scala
class UnifiedLog(...) extends Logging with KafkaMetricsGroup {
  ...
  private def append(records: MemoryRecords,
                     origin: AppendOrigin,
                     interBrokerProtocolVersion: ApiVersion,
                     validateAndAssignOffsets: Boolean,
                     leaderEpoch: Int,
                     requestLocal: Option[RequestLocal],
                     ignoreRecordSize: Boolean): LogAppendInfo = {
    ...
    val appendInfo = analyzeAndValidateRecords(records, origin, ignoreRecordSize, leaderEpoch)

    // return if we have no valid messages or if this is a duplicate of the last appended entry
    if (appendInfo.shallowCount == 0) appendInfo
    else {

      // trim any invalid bytes or partial messages before appending it to the on-disk log
      var validRecords = trimInvalidBytes(records, appendInfo)

      // they are valid, insert them in the log
      lock synchronized {
        maybeHandleIOException(s"Error while appending records to $topicPartition in dir ${dir.getParent}") {
          localLog.checkIfMemoryMappedBufferClosed()
          if (validateAndAssignOffsets) {
            // assign offsets to the message set
            val offset = new LongRef(localLog.logEndOffset)
            appendInfo.firstOffset = Some(LogOffsetMetadata(offset.value))
            val now = time.milliseconds
            val validateAndOffsetAssignResult = try {
              LogValidator.validateMessagesAndAssignOffsets(validRecords,
                topicPartition,
                offset,
                time,
                now,
                appendInfo.sourceCodec,
                appendInfo.targetCodec,
                config.compact,
                config.recordVersion.value,
                config.messageTimestampType,
                config.messageTimestampDifferenceMaxMs,
                leaderEpoch,
                origin,
                interBrokerProtocolVersion,
                brokerTopicStats,
                requestLocal.getOrElse(throw new IllegalArgumentException(
                  "requestLocal should be defined if assignOffsets is true")))
            } catch {
              case e: IOException =>
                throw new KafkaException(s"Error validating messages while appending to log $name", e)
            }
            ...
          } else {
            // we are taking the offsets we are given
            ...
          }
          ...
          maybeDuplicate match {
            case Some(duplicate) =>
              ...
              localLog.append(appendInfo.lastOffset, appendInfo.maxTimestamp, appendInfo.offsetOfMaxTimestamp, validRecords)
              updateHighWatermarkWithLogEndOffset()
              ...
              trace(s"Appended message set with last offset: ${appendInfo.lastOffset}, " +
                s"first offset: ${appendInfo.firstOffset}, " +
                s"next offset: ${localLog.logEndOffset}, " +
                s"and messages: $validRecords")

              if (localLog.unflushedMessages >= config.flushInterval) flush(false)
          }
          appendInfo
        }
      }
    }
  }
}
```

可以看到，先是采用 `analyzeAndValidateRecords` 在 `recordBatch` 的维度对批量消息整体做校验，比如 CRC、size 等，不会细化到单条消息，所以这里不会涉及解压。这一步通过之后，会采用 `LogValidator.validateMessagesAndAssignOffsets` 对 `recordBatch`以及单条消息做进一步验证并为消息分配 `offset`，**该过程可能涉及解压**。完成这一步之后，调用 `localLog.append` 方法将消息追加到本地日志，这一步才是真正的落盘。我们继续关注可能发生解压的 `LogValidator` 部分，代码如下：

```scala
private[log] object LogValidator extends Logging {
  private[log] def validateMessagesAndAssignOffsets(records: MemoryRecords,
                                                    topicPartition: TopicPartition,
                                                    offsetCounter: LongRef,
                                                    time: Time,
                                                    now: Long,
                                                    sourceCodec: CompressionCodec,
                                                    targetCodec: CompressionCodec,
                                                    compactedTopic: Boolean,
                                                    magic: Byte,
                                                    timestampType: TimestampType,
                                                    timestampDiffMaxMs: Long,
                                                    partitionLeaderEpoch: Int,
                                                    origin: AppendOrigin,
                                                    interBrokerProtocolVersion: ApiVersion,
                                                    brokerTopicStats: BrokerTopicStats,
                                                    requestLocal: RequestLocal): ValidationAndOffsetAssignResult = {
    if (sourceCodec == NoCompressionCodec && targetCodec == NoCompressionCodec) {
      // check the magic value
      if (!records.hasMatchingMagic(magic))
        convertAndAssignOffsetsNonCompressed(records, topicPartition, offsetCounter, compactedTopic, time, now, timestampType,
          timestampDiffMaxMs, magic, partitionLeaderEpoch, origin, brokerTopicStats)
      else
        // Do in-place validation, offset assignment and maybe set timestamp
        assignOffsetsNonCompressed(records, topicPartition, offsetCounter, now, compactedTopic, timestampType, timestampDiffMaxMs,
          partitionLeaderEpoch, origin, magic, brokerTopicStats)
    } else {
      validateMessagesAndAssignOffsetsCompressed(records, topicPartition, offsetCounter, time, now, sourceCodec,
        targetCodec, compactedTopic, magic, timestampType, timestampDiffMaxMs, partitionLeaderEpoch, origin,
        interBrokerProtocolVersion, brokerTopicStats, requestLocal)
    }
  }
  ...
}
```

从上可知，当 broker 端配置的压缩编码 `targetCodec` 与所收到的批量消息的压缩编码 `sourceCodec` 都为 `none` 即不压缩时，会再检查消息格式的版本，如果与 broker 端配置的版本不同，则需要先将原批量消息转换为目标版本 `magic` 对应格式的新批量消息，然后再在新批量消息中分配 `offset`；否则直接在原批量消息中就地分配 `offset`，此过程均不涉及解压缩。这里稍微解释下分配 `offset` 的逻辑，我们知道在 Kafka 中 `offset` 是 `partition` 下每条消息的唯一标识，consumer 端也是根据 `offset` 来追踪消费进度，而 `offset` 的生成和写入则是在 broker 端，就是此处提到的 `offset` 分配。理论上说，broker 需要为每条消息都分配一个 `offset` 的，但在实践中，因为用的是 `recordBatch`，内部消息是顺序排列的且总记录数是知道的，而 `recordBatch` 本身会记录 `baseOffset` ，故通常只需设置 `lastOffset`即可。唯一的例外是，当因消息格式转换或解压缩而需要创建新的 `recordBatch`时，会调用 `memoryRecordsBuilder` 的 `appendWithOffset` 方法为每一条消息记录分配 `offset`。

当 `targetCodec` 与 `sourceCodec` 至少有一个不为 `none` 即需要压缩时，情况就复杂一些，具体逻辑都在 `validateMessagesAndAssignOffsetsCompressed`方法中，

```scala
private[log] object LogValidator extends Logging {
  ...
  def validateMessagesAndAssignOffsetsCompressed(...): ValidationAndOffsetAssignResult = {
    ...
    // No in place assignment situation 1
    var inPlaceAssignment = sourceCodec == targetCodec

    var maxTimestamp = RecordBatch.NO_TIMESTAMP
    val expectedInnerOffset = new LongRef(0)
    val validatedRecords = new mutable.ArrayBuffer[Record]

    var uncompressedSizeInBytes = 0

    // Assume there's only one batch with compressed memory records; otherwise, return InvalidRecordException
    // One exception though is that with format smaller than v2, if sourceCodec is noCompression, then each batch is actually
    // a single record so we'd need to special handle it by creating a single wrapper batch that includes all the records
    val firstBatch = getFirstBatchAndMaybeValidateNoMoreBatches(records, sourceCodec)

    // No in place assignment situation 2 and 3: we only need to check for the first batch because:
    //  1. For most cases (compressed records, v2, for example), there's only one batch anyways.
    //  2. For cases that there may be multiple batches, all batches' magic should be the same.
    if (firstBatch.magic != toMagic || toMagic == RecordBatch.MAGIC_VALUE_V0)
      inPlaceAssignment = false

    // Do not compress control records unless they are written compressed
    if (sourceCodec == NoCompressionCodec && firstBatch.isControlBatch)
      inPlaceAssignment = true

    records.batches.forEach { batch =>
      validateBatch(topicPartition, firstBatch, batch, origin, toMagic, brokerTopicStats)
      uncompressedSizeInBytes += AbstractRecords.recordBatchHeaderSizeInBytes(toMagic, batch.compressionType())

      // if we are on version 2 and beyond, and we know we are going for in place assignment,
      // then we can optimize the iterator to skip key / value / headers since they would not be used at all
      val recordsIterator = if (inPlaceAssignment && firstBatch.magic >= RecordBatch.MAGIC_VALUE_V2)
        batch.skipKeyValueIterator(requestLocal.bufferSupplier)
      else
        batch.streamingIterator(requestLocal.bufferSupplier)

      try {
        val recordErrors = new ArrayBuffer[ApiRecordError](0)
        // this is a hot path and we want to avoid any unnecessary allocations.
        var batchIndex = 0
        recordsIterator.forEachRemaining { record =>
          val expectedOffset = expectedInnerOffset.getAndIncrement()
          val recordError = validateRecordCompression(batchIndex, record).orElse {
            validateRecord(batch, topicPartition, record, batchIndex, now,
              timestampType, timestampDiffMaxMs, compactedTopic, brokerTopicStats).orElse {
              if (batch.magic > RecordBatch.MAGIC_VALUE_V0 && toMagic > RecordBatch.MAGIC_VALUE_V0) {
                if (record.timestamp > maxTimestamp)
                  maxTimestamp = record.timestamp

                // Some older clients do not implement the V1 internal offsets correctly.
                // Historically the broker handled this by rewriting the batches rather
                // than rejecting the request. We must continue this handling here to avoid
                // breaking these clients.
                if (record.offset != expectedOffset)
                  inPlaceAssignment = false
              }
              None
            }
          }

          recordError match {
            case Some(e) => recordErrors += e
            case None =>
              uncompressedSizeInBytes += record.sizeInBytes()
              validatedRecords += record
          }
         batchIndex += 1
        }
        processRecordErrors(recordErrors)
      } finally {
        recordsIterator.close()
      }
    }

    if (!inPlaceAssignment) {
      val (producerId, producerEpoch, sequence, isTransactional) = {
        // note that we only reassign offsets for requests coming straight from a producer. For records with magic V2,
        // there should be exactly one RecordBatch per request, so the following is all we need to do. For Records
        // with older magic versions, there will never be a producer id, etc.
        val first = records.batches.asScala.head
        (first.producerId, first.producerEpoch, first.baseSequence, first.isTransactional)
      }
      buildRecordsAndAssignOffsets(toMagic, offsetCounter, time, timestampType, CompressionType.forId(targetCodec.codec),
        now, validatedRecords, producerId, producerEpoch, sequence, isTransactional, partitionLeaderEpoch,
        uncompressedSizeInBytes)
    } else {
      // we can update the batch only and write the compressed payload as is;
      // again we assume only one record batch within the compressed set
      val batch = records.batches.iterator.next()
      val lastOffset = offsetCounter.addAndGet(validatedRecords.size) - 1

      batch.setLastOffset(lastOffset)

      if (timestampType == TimestampType.LOG_APPEND_TIME)
        maxTimestamp = now

      if (toMagic >= RecordBatch.MAGIC_VALUE_V1)
        batch.setMaxTimestamp(timestampType, maxTimestamp)

      if (toMagic >= RecordBatch.MAGIC_VALUE_V2)
        batch.setPartitionLeaderEpoch(partitionLeaderEpoch)

      val recordConversionStats = new RecordConversionStats(uncompressedSizeInBytes, 0, 0)
      ValidationAndOffsetAssignResult(validatedRecords = records,
        maxTimestamp = maxTimestamp,
        shallowOffsetOfMaxTimestamp = lastOffset,
        messageSizeMaybeChanged = false,
        recordConversionStats = recordConversionStats)
    }
  }
  ...
}
```

可以看到，`inPlaceAssignment` 是用于标识是否可以原地修改 `recordBatch` 来分配 `offset`，有三种情况不能原地修改：

* sourceCodec 和 targetCodec 不同，这个比较好理解，编码不同，构建目标 payload 时原 `recordBatch`  自然不能复用。
* 目标消息格式版本 `magic` 与 broker 接收到的 `recordBatch` 的 `magic` 不同，此时需要消息格式转换，需要构建新的 `recordBatch`，这个跟第一种情况是一样的，无法复用原 `recordBatch`。
* 目标消息格式版本为 `V0`，因为老版本 `V0` 格式的消息，需要为每条消息重新分配绝对 `offset`，无法复用原 `recordBatch`。

此时，`inPlaceAssignment` 为 false，直接走 `buildRecordsAndAssignOffsets` 逻辑来构建新的 `recordBatch`，此时是否压缩取决于 `targetCodec`，如果不为`none`，则此处会按照 `targetCodec` 编码进行压缩。

除了上述三种情况之外，都是可以原地修改，此时可以直接复用原 `recordBatch`来构建目标消息的 payload，此时不存在压缩处理。

## 何处会解压

可能发生解压的地方依然是两处：consumer 端和 broker 端。

### consumer 端

consumer 端发生解压的唯一条件就是从 broker 端拉取到的消息是带压缩的。此时，consumer 会根据 `recordBatch` 中 `compressionType` 来对消息进行解压，具体细节后面源码分析部分会讲。

### broker 端

broker 端是否发生解压取决于 producer 发过来的批量消息 `recordBatch` 是否是压缩的：如果 producer 开启了压缩，则会发生解压，否则不会。原因简单说下，在 broker 端持久化消息前，会对消息做各种验证，此时必然会迭代 `recordBatch`，而在迭代的过程中，会直接采用 `recordBatch` 上的 `compressionType` 对消息字节流进行处理，是否解压取决于 `compressionType` 是否是压缩类型。关于这点，可以在 `LogValidator` 的 `validateMessagesAndAssignOffsets` 方法实现中可以看到，在 `convertAndAssignOffsetsNonCompressed`、`assignOffsetsNonCompressed` 和 `validateMessagesAndAssignOffsetsCompressed` 三个不同的分支中，都会看到 `records.batches.forEach {...}` 的身影，而在后面的源码分析中会发现，在 `recordBatch` 的迭代器逻辑中，直接采用的 `compressionType` 的解压逻辑对消息字节流读取的。也就是说，如果 `recordBatch` 是压缩的 ，只要对其进行了迭代访问，则会自动触发解压逻辑。

# 压缩和解压原理

压缩和解压涉及到几个关键的类：`CompressionType` 、`MemoryRecordsBuilder`、`DefaultRecordBatch`、`AbstractLegacyRecordBatch`。其中 `CompressionType` 是压缩相关的枚举，集压缩定义和实现为一体；`MemoryRecordsBuilder` 是负责将新的消息数据写入内存 buffer，即调用 `CompressionType` 中的压缩逻辑 `wrapForOutput` 来写入消息；而 `DefaultRecordBatch` 和 `AbstractLegacyRecordBatch` 则是负责读取消息数据，即调用 `CompressionType` 的解压逻辑 `wrapForInput` 将消息还原为无压缩数据。只不过二者区别是，前者是用于处理新版本格式的消息（即 `magic >= 2`），而后者则是处理老版本格式的消息（即 `magic 为 0 或 1`）。

## CompressionType

在说 `CompressionType` 之前，我们先看下 `CompressionCodec` 这个 Scala 脚本。

### CompressionCodec

部分源码如下，

```scala
...
case object GZIPCompressionCodec extends CompressionCodec with BrokerCompressionCodec {
  val codec = 1
  val name = "gzip"
}

case object SnappyCompressionCodec extends CompressionCodec with BrokerCompressionCodec {
  val codec = 2
  val name = "snappy"
}

case object LZ4CompressionCodec extends CompressionCodec with BrokerCompressionCodec {
  val codec = 3
  val name = "lz4"
}

case object ZStdCompressionCodec extends CompressionCodec with BrokerCompressionCodec {
  val codec = 4
  val name = "zstd"
}

case object NoCompressionCodec extends CompressionCodec with BrokerCompressionCodec {
  val codec = 0
  val name = "none"
}

case object UncompressedCodec extends BrokerCompressionCodec {
  val name = "uncompressed"
}

case object ProducerCompressionCodec extends BrokerCompressionCodec {
  val name = "producer"
}
```

该脚本定义了 `GZIPCompressionCodec` 等共 7 个 case object，可类比于 Java 中枚举，这些 case object 中的 `name` 集合则刚好覆盖了前文所提到的属性 `compression.type` 的所有可选值，包括 producer 端和 broker 端的。而与 `name` 绑定在一起的 `codec` 则是最终真正写入消息体的压缩编码，`name` 只是为了可读性友好。从上可知，压缩编码`codec` 的有效取值只有 `0~4`，分别对应 `none`、`gzip`、`snappy`、`lz4`和`zstd`，而这五种取值恰好是 `CompressionType` 中定义的五种枚举常量。

由此可知，`CompressionCodec`是面向配置属性 `compression.type`的可选值的，并将数值化的压缩编码 `codec` 映射为可读性强的 `name`；而 `CompressionType`则是定义了与压缩编码对应的枚举常量，二者通过 `name` 关联。

### CompressionType 源码

`CompressionType` 定义了与压缩编码对应的五种压缩类型枚举，并且通过用于压缩的 `wrapForOutput`和用于解压的 `wrapForInput`这两个抽象方法将每种压缩类型与对应的压缩实现绑定在一起，既避免了常规的 `if-else` 判断，也将压缩的定义与实现完全收敛到 `CompressionType` ，符合单一职责原则。其实类似这种优雅的设计在 JDK 中也能经常看到其身影，比如 `TimeUnit`。直接看源码，

```java
public enum CompressionType {
    ...
    GZIP(1, "gzip", 1.0f) {
        @Override
        public OutputStream wrapForOutput(ByteBufferOutputStream buffer, byte messageVersion) {
            try {
                return new BufferedOutputStream(new GZIPOutputStream(buffer, 8 * 1024), 16 * 1024);
            } catch (Exception e) {
                throw new KafkaException(e);
            }
        }

        @Override
        public InputStream wrapForInput(ByteBuffer buffer, byte messageVersion, BufferSupplier decompressionBufferSupplier) {
            try {
                // Set output buffer (uncompressed) to 16 KB (none by default) and input buffer (compressed) to
                // 8 KB (0.5 KB by default) to ensure reasonable performance in cases where the caller reads a small
                // number of bytes (potentially a single byte)
                return new BufferedInputStream(new GZIPInputStream(new ByteBufferInputStream(buffer), 8 * 1024),
                        16 * 1024);
            } catch (Exception e) {
                throw new KafkaException(e);
            }
        }
    },
    ...
    ZSTD(4, "zstd", 1.0f) {
        @Override
        public OutputStream wrapForOutput(ByteBufferOutputStream buffer, byte messageVersion) {
            return ZstdFactory.wrapForOutput(buffer);
        }

        @Override
        public InputStream wrapForInput(ByteBuffer buffer, byte messageVersion, BufferSupplier decompressionBufferSupplier) {
            return ZstdFactory.wrapForInput(buffer, messageVersion, decompressionBufferSupplier);
        }
    };
    ...
    // Wrap bufferStream with an OutputStream that will compress data with this CompressionType.
    public abstract OutputStream wrapForOutput(ByteBufferOutputStream bufferStream, byte messageVersion);
    // Wrap buffer with an InputStream that will decompress data with this CompressionType.
    public abstract InputStream wrapForInput(ByteBuffer buffer, byte messageVersion, BufferSupplier decompressionBufferSupplier);

    ...
}
```

每种压缩类型对于 `wrapForOutput` 和 `wrapForInput` 两方法的具体实现已经很清楚地阐述了压缩和解压的方式，感兴趣的朋友可以从该入口 `step in` 一探究竟。这里就不细述。当然这只是处理压缩最小的基本单元，为了搞清楚 Kafka 在何处使用它，还得继续看其他几个核心类。

在此之前，就上述源码，抛开本次主题，我还想谈几个值得学习借鉴的细节，

> 1. `Snappy` 和 `Zstd` 都是用的 `XXXFactory` 静态方法来构建 Stream 对象，而其他的比如 `Lz4` 则都是直接通过 `new` 创建的对象。之所以这么做，我们进一步 `step in` 就会发现，对于 `Snappy` 和 `Zstd`，Kafka 都是直接依赖的第三方库，而其他的则是 JDK 或 Kafka 自己的实现。为了减少第三方库的副作用，**通过此方式将第三方库的类的惰性加载做到极致，这也体现出作者对 Java 类加载时机的充分理解，很精致的处理**。
> 2. `Gzip` 的`wrapForInput`实现中，在 [KAFKA-6430](https://issues.apache.org/jira/browse/KAFKA-6430) 这个 Improvement 提交中，input buffer 从 0.5 KB 调大到 8 KB，其目的就是能够在一次 Gzip 压缩中处理更多的字节，以获得更高的性能。至少，从 commit 的描述上看，throughput 能翻倍。
> 3. 抽象方法 `wrapForInput` 中暴露的最后一个 BufferSupplier类型的参数 `decompressionBufferSupplier`，正如方法的参数说明所言，对于比较小的批量消息，如果在 `wrapForInput` 内部新建 buffer，那么每次方法调用都会新分配buffer，这可能比压缩处理本身更耗时，所以该参数给了一个选择的机会，在外面分配内存，然后方法内循环利用。**在日常的编码中，对于循环中所需的空间，我也经常会思考是每次新建好还是先在外面分配，然后内部循环利用更好，case by case**.

## MemoryRecordsBuilder

```java
public class MemoryRecordsBuilder implements AutoCloseable {
    ...
    // Used to append records, may compress data on the fly
    private DataOutputStream appendStream;
    ...

    public MemoryRecordsBuilder(ByteBufferOutputStream bufferStream,
                                byte magic,
                                CompressionType compressionType,
                                TimestampType timestampType,
                                long baseOffset,
                                long logAppendTime,
                                long producerId,
                                short producerEpoch,
                                int baseSequence,
                                boolean isTransactional,
                                boolean isControlBatch,
                                int partitionLeaderEpoch,
                                int writeLimit,
                                long deleteHorizonMs) {
        if (magic > RecordBatch.MAGIC_VALUE_V0 && timestampType == TimestampType.NO_TIMESTAMP_TYPE)
            throw new IllegalArgumentException("TimestampType must be set for magic > 0");
        if (magic < RecordBatch.MAGIC_VALUE_V2) {
            if (isTransactional)
                throw new IllegalArgumentException("Transactional records are not supported for magic " + magic);
            if (isControlBatch)
                throw new IllegalArgumentException("Control records are not supported for magic " + magic);
            if (compressionType == CompressionType.ZSTD)
                throw new IllegalArgumentException("ZStandard compression is not supported for magic " + magic);
            if (deleteHorizonMs != RecordBatch.NO_TIMESTAMP)
                throw new IllegalArgumentException("Delete horizon timestamp is not supported for magic " + magic);
        }
        ...
        this.appendStream = new DataOutputStream(compressionType.wrapForOutput(this.bufferStream, magic));
        ...
    }
  
    public void close() {
        ...
        if (numRecords == 0L) {
            buffer().position(initialPosition);
            builtRecords = MemoryRecords.EMPTY;
        } else {
            if (magic > RecordBatch.MAGIC_VALUE_V1)
                this.actualCompressionRatio = (float) writeDefaultBatchHeader() / this.uncompressedRecordsSizeInBytes;
            else if (compressionType != CompressionType.NONE)
                this.actualCompressionRatio = (float) writeLegacyCompressedWrapperHeader() / this.uncompressedRecordsSizeInBytes;

            ByteBuffer buffer = buffer().duplicate();
            buffer.flip();
            buffer.position(initialPosition);
            builtRecords = MemoryRecords.readableRecords(buffer.slice());
        }
    }
    ...
    private int writeDefaultBatchHeader() {
        ...
        DefaultRecordBatch.writeHeader(buffer, baseOffset, offsetDelta, size, magic, compressionType, timestampType,
                baseTimestamp, maxTimestamp, producerId, producerEpoch, baseSequence, isTransactional, isControlBatch,
                hasDeleteHorizonMs(), partitionLeaderEpoch, numRecords);

        buffer.position(pos);
        return writtenCompressed;
    }
    private int writeLegacyCompressedWrapperHeader() {
        ...
        int wrapperSize = pos - initialPosition - Records.LOG_OVERHEAD;
        int writtenCompressed = wrapperSize - LegacyRecord.recordOverhead(magic);
        AbstractLegacyRecordBatch.writeHeader(buffer, lastOffset, wrapperSize);

        long timestamp = timestampType == TimestampType.LOG_APPEND_TIME ? logAppendTime : maxTimestamp;
        LegacyRecord.writeCompressedRecordHeader(buffer, magic, wrapperSize, timestamp, compressionType, timestampType);

        buffer.position(pos);
        return writtenCompressed;
    }
}

```

可以看到，`appendStream` 是用于追加消息到内存 buffer 的，直接采用的 `compressionType` 的压缩逻辑来构建写入流的，如果此处 `compressionType`属于非 `none` 的有效压缩类型，则会产生压缩。此外，从上面 `magic` 的判断逻辑可知，消息的时间戳类型是从大版本 `V1` 开始支持的；而事务消息、控制消息、Zstd 压缩和 `deleteHorizonMs`都是从 `V2` 才开始支持的。这里的 `V1`、`V2` 对应消息格式的版本，其中 `V1` 是从 0.10.0 版本开始引入的，在此之前都是 `V0` 版本，而 `V2` 则是从 0.11.0 版本开始引入，直到现在的最新版依然是 `V2`。

从 `close()` 方法可以看出，`MemoryRecordsBuilder` 在构建 `memoryRecords` 时，会根据消息格式的版本高低，写入不同的 Header。对于新版消息，在 `writeDefaultBatchHeader` 方法中直接调用 `DefaultRecordBatch.writeHeader(...)`写入新版消息特定的 Header；而对于老版消息，则是在 `writeLegacyCompressedWrapperHeader`方法中调用 `AbstractLegacyRecordBatch.writeHeader`  和 `LegacyRecord.writeCompressedRecordHeader` 写入老版消息的 Header。虽然 Header 的格式各不相同，但我们在两种 Header 中都可以看到 `compressionType` 的身影，以此可见，Kafka 是允许多种版本的消息共存的，以及压缩与非压缩消息的共存，因为这些信息是保存在 `recordBatch` 上的，是批量消息级别。

## DefaultRecordBatch

```java
public class DefaultRecordBatch extends AbstractRecordBatch implements MutableRecordBatch {
    ...
    @Override
    public Iterator<Record> iterator() {
        if (count() == 0)
            return Collections.emptyIterator();

        if (!isCompressed())
            return uncompressedIterator();

        // for a normal iterator, we cannot ensure that the underlying compression stream is closed,
        // so we decompress the full record set here. Use cases which call for a lower memory footprint
        // can use `streamingIterator` at the cost of additional complexity
        try (CloseableIterator<Record> iterator = compressedIterator(BufferSupplier.NO_CACHING, false)) {
            List<Record> records = new ArrayList<>(count());
            while (iterator.hasNext())
                records.add(iterator.next());
            return records.iterator();
        }
    }
    ...
}
```

`RecordBatch` 是表示批量消息的接口，对于老版格式的消息（版本 `V0` 和 `V1`），如果没有压缩，只会包含单条消息，否则可以包含多条；而新版格式消息（版本 `V2` 及以上）无论是否压缩，都是通常包含多条消息。且该接口中有一个 `compressionType()`方法来标识该 batch 的压缩类型，它会作为读消息时解压的判断依据。而上面的 `DefaultRecordBatch` 则是该接口的针对新版本格式消息的默认实现，它也实现了 `Iterable<Record>` 接口，因而 `iterator()` 是访问批量消息的核心逻辑，当 `compressionType()` 返回 `none` 时，表示不压缩，直接返回非压缩迭代器，此处跳过，当有压缩时，走的是压缩迭代器，具体实现如下，

```java
    public DataInputStream recordInputStream(BufferSupplier bufferSupplier) {
        final ByteBuffer buffer = this.buffer.duplicate();
        buffer.position(RECORDS_OFFSET);
        return new DataInputStream(compressionType().wrapForInput(buffer, magic(), bufferSupplier));
    }

    private CloseableIterator<Record> compressedIterator(BufferSupplier bufferSupplier, boolean skipKeyValue) {
        final DataInputStream inputStream = recordInputStream(bufferSupplier);

        if (skipKeyValue) {
            // this buffer is used to skip length delimited fields like key, value, headers
            byte[] skipArray = new byte[MAX_SKIP_BUFFER_SIZE];
          
            return new StreamRecordIterator(inputStream) {
                ...
            }
        } else {
            ...  
        }
    }
```

我们可以看到，`compressedIterator()` 在构造 Stream 迭代器之前，调用了 `recordInputStream(...)`，该方法中通过 `compressionType` 的解压逻辑对原数据进行了解压。

## AbstractLegacyRecordBatch

```java
public abstract class AbstractLegacyRecordBatch extends AbstractRecordBatch implements Record {
    ...
    CloseableIterator<Record> iterator(BufferSupplier bufferSupplier) {
        if (isCompressed())
            return new DeepRecordsIterator(this, false, Integer.MAX_VALUE, bufferSupplier);

        return new CloseableIterator<Record>() {
            private boolean hasNext = true;

            @Override
            public void close() {}

            @Override
            public boolean hasNext() {
                return hasNext;
            }

            @Override
            public Record next() {
                if (!hasNext)
                    throw new NoSuchElementException();
                hasNext = false;
                return AbstractLegacyRecordBatch.this;
            }

            @Override
            public void remove() {
                throw new UnsupportedOperationException();
            }
        };
    }
    ...
    private static class DeepRecordsIterator extends AbstractIterator<Record> implements CloseableIterator<Record> {
        private DeepRecordsIterator(AbstractLegacyRecordBatch wrapperEntry,
                                    boolean ensureMatchingMagic,
                                    int maxMessageSize,
                                    BufferSupplier bufferSupplier) {
            LegacyRecord wrapperRecord = wrapperEntry.outerRecord();
            this.wrapperMagic = wrapperRecord.magic();
            if (wrapperMagic != RecordBatch.MAGIC_VALUE_V0 && wrapperMagic != RecordBatch.MAGIC_VALUE_V1)
                throw new InvalidRecordException("Invalid wrapper magic found in legacy deep record iterator " + wrapperMagic);

            CompressionType compressionType = wrapperRecord.compressionType();
            if (compressionType == CompressionType.ZSTD)
                throw new InvalidRecordException("Invalid wrapper compressionType found in legacy deep record iterator " + wrapperMagic);
            ByteBuffer wrapperValue = wrapperRecord.value();
            if (wrapperValue == null)
                throw new InvalidRecordException("Found invalid compressed record set with null value (magic = " +
                        wrapperMagic + ")");

            InputStream stream = compressionType.wrapForInput(wrapperValue, wrapperRecord.magic(), bufferSupplier);
            ...
        }
    }
}
```

`AbstractLegacyRecordBatch` 跟前面的 `DefaultRecordBatch` 大同小异，同样也是 `iterator()` 入口，当开启了压缩时，返回压缩迭代器 `DeepRecordsIterator`，只是名字不同而已，迭代器内部依然是直接通过 `compressionType` 的解压逻辑对数据流进行解压。