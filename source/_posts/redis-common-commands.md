---
title: 「Redis基础」常用命令有哪些
date: 2018-12-06 22:18:56
categories:
- redis
tags:
- Redis基础
---

 按照Redis[官方文档](https://redis.io/commands)，Redis命令根据其操作对象的不同，可大体分为Strings、Lists、Hashes、Sets、Sorted Sets、Streams、Keys、Pub/Sub、Cluster、Connection、Geo、HyperLogLog、Scripting、Server、Transactions共15种类别。这类别序列中**Cluster**及其左边的应该是我们在开发过程中用的最为频繁的，其右边的命令则接触不多，一般是碰到对应的问题才会涉及。下面根据类别的所属范畴，来依次熟悉下常用的几种命令。

# 操作Key的命令

Redis本质是内存k-v数据库，其中的`k`就是我们所说的Key，`v`则是Redis支持的各种数据类型，后面会提到。存入Redis的所有数据都会与特定的Key关联，反过来，数据的读取也是基于Key的。我们经常会关心Redis中有哪些Key、有没有我所找的Key、某个Key的过期时间还剩多少等等之类，都可由Redis内置命令来得到。

## [KEYS pattern](https://redis.io/commands/keys)

