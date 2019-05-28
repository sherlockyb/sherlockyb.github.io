---
title: Linux常用命令
date: 2017-04-10 22:50:35
categories:
- Linux
tags: 
- Linux命令
- Shell编程
---

  最近项目中有用到Shell脚本，难免会与一些以前没用到甚至没见过的Linux命令打交道，借此番机会也算是学习一哈，记录在此，以供日后参考。后续若再接触新的命令也会更新到此。

<!--more-->

<style> table th:first-of-type { width: 100px; } </style>

## [tee](http://www.gnu.org/software/coreutils/manual/html_node/tee-invocation.html#tee-invocation)
| 要点   | 说明                                       |
| :--- | ---------------------------------------- |
| 用途   | 重定向输出到多个文件或进程                            |
| 简介   | 该命令读取标准输入，并将内容同时输出到标准输出（屏幕）和多个文件中。       |
| 应用场景 | 当我们重定向输出到文件中时，使用常规的“>”符号无法直接从屏幕上看到原输出，使用tee就可在重定向文件的同时将内容输出到标准输出（屏幕） |
| 用法   | tee [OPTION]...   [FILE]...<br>-a, 追加到给定的文件，没有此选项时默认是覆盖<br>-i, 忽略中断信号 |
| 示例   | ls &#124; tee &#124; out.txt<br>cat 1.txt &#124; tee -a out.txt |
| 注意   | 在使用管道线时，前一个命令的标准错误输出不会被tee读取。            |

## [date](http://www.gnu.org/software/coreutils/manual/html_node/date-invocation.html#date-invocation)

| 要点   | 说明                                       |
| :--- | ---------------------------------------- |
| 简介   | 根据给定格式显示日期时间或设置系统日期时间                    |
| 用法   | date \[OPTION]... \[+FORMAT]<br>date \[-u&#124;--utc&#124;--universal]\[ MMDDhhmm\[\[CC]YY][.ss] ]<br><br>OPTION: -d -f -r -R -rfc-2822 -s -u --help<br>FORMAT: %% %a %A %b %B %c %C %d %D... |
| 示例   | date -d now +%Y%m%d   用指定格式显示当前时间<br>date -r text.log   显示文件最后修改时间<br>date -s "2013-09-06 00:00:00"   设置系统时间 |

## getopts/getopt

| 要点   | 说明                                       |
| :--- | ---------------------------------------- |
| 简介   | 获取并处理命令行参数                               |
| 用法   | getopts option_string variable<br>第一个参数**option_string**是字符串，包括字符和":"，每个字符都是一个有效的选项，若字符后带有":"，表示这个字符有自己的参数。<br>getopts命令会读取命令行参数，当遇到连字符"-"，会判断"-"后的字符是否出现在option_string定义的选项中，若有匹配，则将其赋给第二个参数**variable**；否则将variable设为"?"。若选项有自己的参数，getopts会从命令行该选项后读取参数值：若该值存在，则将被赋给一个特殊变量**OPTARG**中；否则将在OPTARG中存放一个"?"，并在标准错误上显示一条消息。 |
| 注意项  | 1.getopts是shell内置命令，不能处理长选项（如：--prefix=../），而getopt是C的库函数，可处理长选项。<br>2.当option_string以":"开头时，表示区分invalid option错误和miss option argument，对于前者，variable会被设置为"?"，对于后者，variable会被设置为":"（见示例）；当option_string不以":"开头时，对于上述两种错误，variable都被设为"?"。 |
示例如下：

```shell
  while getopts ':hf:g:s:t:' OPTION
  do
  	case $OPTION
  	in
  		h) usage;;			#h后面无":"，表示不带参数，usage是打印用法详情
  		f) FILENAME=$OPTARG;;
  		g) GROUP=$OPTARG;;
  		s) START=$OPTARG;;
  		t) TYPE=$OPTARG;;
  		:) echo "选项\"-$OPTARG\" 后面缺少对应参数，将使用默认值;;
  		\?)echo "错误的选项 -$OPTARG,将退出";;
  	esac
  done
```

## [wc](http://www.gnu.org/software/coreutils/manual/html_node/wc-invocation.html#wc-invocation)

| 要点   | 说明                                       |
| ---- | ---------------------------------------- |
| 简介   | word count，统计给定文件（可指定多个）或标准输入（没给定文件时）中字节数、字符数、词数（以空白符分割的词数）以及行数。 |
| 用法   | **wc** \[*option*]... \[*file*]...<br>option有如下选项：<br>-c, --bytes　　　　打印字节数<br>-m, --chars 　　　　打印字符数<br>-l, --lines　　　　打印行数<br>-L, --max-line-length　　　　打印最长行的长度<br>-w, --words　　　　打印词数，一个词被定义为以空白符分割的字符串<br>    --help　　　　展示帮助信息 |
| 注意   | 输出：wc会为每个文件打印一行计数，如果文件是作为参数，则会为每个文件打印两列：统计数 文件名，并在最后追加一行打印总两列：计数 total。<br>wc通常与管道线结合使用，直接打印计数 |
示例如下：

```shell
wc -l readme.txt version.txt        #统计指定的两个文件的行数，输出如下
27	readme.txt
 1	version.txt
28	total
cat readme.txt | wc -c              #结合管道，只输出统计数，如下
898
ls -l | wc -l                       #统计当前目录下的文件数
8
```

## [cp](http://www.gnu.org/software/coreutils/manual/html_node/cp-invocation.html#cp-invocation)

| 要点   | 说明                                       |
| ---- | ---------------------------------------- |
| 简介   | Copy files and directories，复制一个或多个文件或目录到指定的文件或目录 |
| 用法   | cp [*option*]… *source*... *dest*<br>option有如下选项：<br>-f,--force　　　强行复制文件或目录，不论目标文件或目录是否已存在<br>-i,--interactive　　　覆盖既有文件之前先询问用户<br>-r/R,--recursive　　　递归地复制目录，该选项**只适用于目录**，不能用于复制文件或符号链接<br>-b,--backup[=*method*]　　　为即将删除或覆盖的目标文件进行备份<br>-s,--symbolic-link　　　对源文件建立符号连接，而非复制文件<br>-S,--suffix=*suffix*　　　备份文件时，用指定后缀"*suffix*"代替文件的默认后缀<br>-v,--verbose　　　复制每个文件前，打印文件名<br><br>source(源文件)：指定源文件列表。默认情况下，cp不能复制目录，若要复制目录，必须使用-r选项<br>dest(目标文件或目录)：当source为多个文件时，dest必须是目录 |

示例如下：

```shell
cp file1 file2                       #将file1复制一份，并命名为file2
cp -f file1 dir2/                    #将file1强行复制到目录dir2下
cp -fr dir1 dir2/                    #递归地复制目录dir1到目录dir2下
```

