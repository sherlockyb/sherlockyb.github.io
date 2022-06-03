---
title: Spark读取elasticsearch数据指南
tags:
  - Spark
  - Elasticsearch
categories:
  - Spark
date: 2022-06-03 20:00:00
---

最近要在 Spark job 中通过 Spark SQL 的方式读取 Elasticsearch 数据，踩了一些坑，总结于此。

# 环境说明

* Spark job 的编写语言为 Scala，scala-library 的版本为 2.11.8。

* Spark 相关依赖包的版本为 2.3.2，如 spark-core、spark-sql。

* Elasticsearch 数据

  **schema**

  ```json
  {
    "settings": {
      "number_of_replicas": 1
    },
    "mappings": {
      "label": {
        "properties": {
          "docId": {
            "type": "keyword"
          },
          "labels": {
            "type": "nested",
            "properties": {
              "id": {
                "type": "long"
              },
              "label": {
                "type": "keyword"
              }
            }
          },
          "itemId": {
            "type": "long"
          }
        }
      }
    }
  }
  ```

  **sample data**

  ```json
  {
    "took" : 141,
    "timed_out" : false,
    "_shards" : {
      "total" : 5,
      "successful" : 5,
      "skipped" : 0,
      "failed" : 0
    },
    "hits" : {
      "total" : 17370929,
      "max_score" : 1.0,
      "hits" : [
        {
          "_index" : "aen-label-v1",
          "_type" : "label",
          "_id" : "123_ITEM",
          "_score" : 1.0,
          "_source" : {
            "docId" : "123_ITEM",
            "labels" : [
              {
                "id" : 7378,
                "label" : "1kg"
              }
            ],
            "itemId" : 123
          }
        },
        {
          "_index" : "aen-label-v1",
          "_type" : "label",
          "_id" : "456_ITEM",
          "_score" : 1.0,
          "_source" : {
            "docId" : "456_ITEM",
            "labels" : [
              {
                "id" : 7378,
                "label" : "2kg"
              }
            ],
            "itemId" : 456
          }
        }
      ]
    }
  }
  ```

# 准备工作

既然要用 Spark SQL，当然少不了其对应的依赖，

```groovy
dependencies {
  implementation 'org.apache.spark:spark-core_2.11:2.3.2'
  implementation 'org.apache.spark:spark-sql_2.11:2.3.2'
}
```

对于 ES 的相关库，如同 [官网](https://www.elastic.co/guide/en/elasticsearch/hadoop/current/spark.html) 所说，要在 Spark 中访问 ES，需要将 `elasticsearch-hadoop` 依赖包加入到 Spark job 运行的类路径中，具体而言就是添加到 Spark job 工程的依赖中，公司的 nexus 中当前最新的版本为 7.15.0，且目前我们是使用 gradle 管理依赖，故添加依赖的代码如下，

```groovy
dependencies {
  implementation 'org.elasticsearch:elasticsearch-hadoop:7.15.0'
}
```

# 本地测试

Spark 支持 local 的方式运行 job，即不依赖 Spark 集群，只需要在创建 SparkSession 时采用 local 的模式，

```scala
def getLocalSparkSession: SparkSession = SparkSession.builder()
    .master("local")
    .getOrCreate()
```



# 最终代码

```scala
import com.google.common.base.Joiner
import com.typesafe.scalalogging.LazyLogging
import org.apache.spark.sql.{DataFrame, Row, SaveMode, SparkSession}

object TestMain extends LazyLogging {
  def main(args: Array[String]): Unit = {
    new OfflineMetricsByProfileNewApp().run()
  }
}

class TestApp() extends Serializable with LazyLogging {
  def esHost() = s"es.sherlockyb.club"
  
  def getSparkSession: SparkSession = SparkSession.builder()
    .enableHiveSupport()
    .config("spark.sql.broadcastTimeout", "3600")
    .getOrCreate()

  def getLocalSparkSession: SparkSession = SparkSession.builder()
    .master("local")
    .getOrCreate()
  
  def esDf(spark: SparkSession, indices: Array[String]): DataFrame = {
    spark.read
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", esHost())
      .option("es.port", "9200")
      .option("es.nodes.wan.only", value = true)
      .option("es.resource", Joiner.on(",").join(java.util.Arrays.asList(indices:_*)) + "/label")
      .option("es.scroll.size", 2000)
      .load()
  }
}
```

将 job 工程打包为 Jar，上传到 AWS 的 s3，比如 `s3://sherlockyb-test/1.0.0/artifacts/spark/` 目录下，然后通过 Genie 提交 spark job 到集群测试。Genie 是 Netflix 研发的联合作业执行引擎，提供 REST-full API 来运行各种大数据作业，如 Hadoop、Pig、Hive、Spark、Presto、Sqoop 等。

```python
def run_spark(job_name, spark_jar_name, spark_class_name, arg_str, spark_param=''):
    import pygenie

    pygenie.conf.DEFAULT_GENIE_URL = "genie.sherlockyb.club"

    # Create a job instance and fill in the required parameters
    job = pygenie.jobs.GenieJob() \
        .genie_username('sherlockyb') \
        .job_name(job_name) \
        .job_version('0.0.1') \
        .metadata(teamId='team_account') \
        .metadata(teamCredential='team_password')

    job.cluster_tags(['type:yarn-kerberos', 'sched:default'])
    job.command_tags(['type:spark-submit-kerberos', 'ver:2.3.2'])
    job.command_arguments(
        f"--class {spark_class_name} {spark_param} "
        f"s3a://sherlockyb-test/1.0.0/artifacts/spark/{spark_jar_name} "
        f"{arg_str}"
    )

    # Submit the job to Genie
    running_job = job.execute()
    print('Job link: {}'.format(running_job.job_link))

    # Block and wait until job is done
    running_job.wait()

    print('Job {} finished with status {}'.format(running_job.job_id, running_job.status))
    return running_job.status
```

