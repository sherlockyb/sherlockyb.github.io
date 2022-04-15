---
title: Kafka消息的压缩机制
tags:
  - Kafka系列
  - message
categories:
  - Kafka
date: 2022-04-12 22:00:00
---

最近在做 AWS cost saving 的事情，对于 Kafka 消息集群，计划通过压缩消息来减少消息存储所占空间，从而达到减少 cost 的目的。本文将从 Kafka 支持的消息压缩类型、何时需要压缩、如何开启压缩、何处进行压缩以及压缩原理来总结 Kafka 整个压缩机制。

Kafka的消息压缩



