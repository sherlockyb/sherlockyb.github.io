---
title: Kafka消息的压缩机制
tags:
  - Kafka系列
  - message
categories:
  - Kafka
date: 2022-04-30 22:00:00
---

最近在做 AWS cost saving 的事情，对于 Kafka 消息集群，计划通过压缩消息来减少消息存储所占空间，从而达到减少 cost 的目的。本文将从 Kafka 支持的消息压缩类型、何时需要压缩、如何开启压缩、何处进行压缩以及压缩原理来总结 Kafka 整个压缩机制。

# Kafka支持的消息压缩类型

## 什么是 Kafka 的消息压缩

在谈消息压缩类型之前，我们先看下 Kafka 中关于消息压缩的定义是什么。

Kafka [官网](https://cwiki.apache.org/confluence/display/KAFKA/Compression)有这样一段解释：

> 此为 Kafka 中端到端的块压缩功能。如果启用，数据将由 producer 压缩，以压缩格式写入服务器，并由 consumer 解压缩。压缩将提高 consumer 的吞吐量，但需付出一定的解压成本。这在跨数据中心镜像数据时尤其有用。

也就是说，Kafka 的消息压缩是指将消息本身采用特定的压缩算法进行压缩并存储，待消费时再解压缩。

## 消息压缩类型

目前 Kafka 共支持四种主要的压缩类型：Gzip、Snappy、Lz4 和 Zstd。

