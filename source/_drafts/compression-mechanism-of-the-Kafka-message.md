---
title: Kafka消息的压缩机制
tags:
  - Kafka系列
  - message
categories:
  - Kafka
date: 2022-04-12 22:00:00
---

最近在做 AWS cost saving 的事情，对于 Kafka 消息集群，计划通过压缩消息来减少消息存储所占空间，从而达到减少 cost 的目的。本文将从 Kafka 消息的压缩类型出发，来总结 Kafka 整个压缩机制。