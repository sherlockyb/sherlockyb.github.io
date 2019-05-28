---
title: 从kinit到kerberos安全机制
date: 2017-06-04 14:51:18
categories:
- Linux
tags:
- Shell编程
- kerberos
- 安全
---

　　最近老在项目的shell脚本中看到kinit这个东西，完整的命令是

　　 ```kinit -k -t ./conf/kerberos.keytab sherlocky/admin@EXAMPLE.COM```

　　查阅一番资料后了解到，之所以有这个命令，是由于该shell脚本接下来会访问Hadoop集群，从上面拉取文件做一些处理任务，并将结果存到Hadoop集群上，那么该命令的作用就是进行身份验证（Authentication），确保Hadoop集群资源的安全。这里就牵扯到kerberos协议，本文接下来将对此一一阐述。

<!--more-->

## 一、kinit命令

　　Kinit命令用于获取和缓存principal（当前主体）初始的票据授予票据（TGT），此票据用于Kerberos系统进行身份安全验证，实际上它是MIT在版权许可的条件下为kerberos协议所研发的免费实现工具[MIT Kerberos](http://web.mit.edu/kerberos/dist/index.html)（当前最新版本为[krb5-1.15.1](https://web.mit.edu/kerberos/krb5-1.15/)）的一部分，相关的配套命令还有[klist](https://web.mit.edu/kerberos/krb5-1.12/doc/user/user_commands/klist.html)、[kdestory](https://web.mit.edu/kerberos/krb5-1.12/doc/user/user_commands/kdestroy.html)、[kpasswd](https://web.mit.edu/kerberos/krb5-1.12/doc/user/user_commands/kpasswd.html)、[krb5-config](https://web.mit.edu/kerberos/krb5-1.12/doc/user/user_commands/krb5-config.html)等等，基本用法如下：

**kinit** \[-**V**]\[-**l** *lifetime*] \[-**s** *start_time*]\[-**r** *renewable_life*]\[-**p** | -**P**]\[-**f** | -**F**]\[-**a**]\[-**A**]\[-**C**]\[-**E**]\[-**v**]\[-**R**]\[-**k** \[-**t** *keytab_file*]]\[-**c** *cache_name*]\[-**n**]\[-**S** *service_name*]\[-**I** *input_ccache*]\[-**T** *armor_ccache*]\[-**X** *attribute*\[*=value*]][*principal*]

　　各选项具体含义都不做介绍了，可参考[官网](https://web.mit.edu/kerberos/krb5-1.12/doc/user/user_commands/kinit.html)，较常用的方式就如前言所示，根据指定的事先生成的kerberos.keytab文件为指定个体进行验证。验证通过后，就可以像平常一样进行Hadoop系列操作。那么它是如何进行验证的呢？其中的过程和原理又是怎样的？下面要介绍的kerberos协议细节将会回答你的疑惑。

## 二、Kerberos协议

　　Kerberos（具体可参考[RFC1510](https://tools.ietf.org/html/rfc1510)）是一种网络**身份验证**的协议（注意它只包括验证环节，不负责授权，关于这两者后面会有介绍区分），用户只需输入一次身份验证信息，就可凭借此验证获得的票据授予票据（ticket-granting ticket）访问多个接入Kerberos的服务，即[SSO](https://en.wikipedia.org/wiki/Single_sign-on)（Single Sign On，单点登录）。

### 1.基本概念

- Principal：安全个体，具有唯一命名的客户端或服务器。命名规则：主名称+实例+领域，如本文开头中的`sherlocky/admin@EXAMPLE.COM`
- Ticket：票据，一条包含客户端标识信息、会话密钥和时间戳的记录，客户端用它来向目标服务器认证自己
- Session key：会话密钥，指两个安全个体之间使用的临时加密秘钥，其时效性取决于单点登录的会话时间长短
- AS：认证服务器（Authentication Server），KDC的一部分。通常会维护一个包含安全个体及其秘钥的数据库，用于身份认证
- SS：特定服务的提供端（Service Server）
- TGS：许可证服务器（Ticket Granting Server），KDC的一部分，根据客户端传来的TGT发放访问对应服务的票据
- TGT：票据授予票据（Ticket Granting Ticket），包含客户端ID、客户端网络地址、票据有效期以及*client/TGS*会话密钥
- KDC：Key分发中心（key distribution center），是一个提供票据（tickets）和临时会话密钥（session keys）的网络服务。KDC服务作为客户端和服务器端信赖的第三方，为其提供初始票据（initial ticket）服务和票据授予票据（ticket-granting ticket）服务，前半部分有时被称为AS，后半部分有时则被称为TGS。

　　关于概念的一点补充，博文[Kerberos 服务的工作原理](http://www.360doc.com/content/15/0803/18/13047933_489282618.shtml)中对于TGT和Ticket给出了巧妙的比喻：TGT类似于护照，Ticket则是签证，而访问特定的服务则好比出游某个国家。与护照一样，TGT可标识你的身份并允许你获得多个Ticket（签证），每个Ticket对应一个特定的服务，TGT和Ticket同样具有有效期，过期后就需要重新认证。


### 2.认证过程

　　Kerberos的认证过程可细分为三个阶段：初始验证、获取服务票据和服务验证。第一阶段主要是客户端向KDC中的AS发送用户信息，以请求TGT，然后到第二阶段，客户端拿着之前获得的TGT向KDC中的TGS请求访问某个服务的票据，最后阶段拿到票据（Ticket）后再到该服务的提供端验证身份，然后使用建立的加密通道与服务通信。

#### 2.1 初始验证

　　此过程是客户端向AS请求获取TGT：

> - 客户端向AS发送自身用户信息（如用户ID），该动作通常发生在用户初次登陆或使用kinit命令时
> - AS检查本地数据库是否存在该用户，若存在则返回如下两条信息：
>   - 消息A：使用用户密钥加密的*Client/TGS*会话密钥，我们称之为SK1。其中用户密钥是通过对该用户在数据库中对应的密码hash生成的
>   - 消息B：使用TGS的密钥加密的TGT（包含客户端ID、客户端网络地址、票据有效期和SK1）
> - 当客户端收到消息A和B时，它会尝试用本地的用户密钥（由用户输入的密码或kerberos.keytab文件中的密码hash生成）对A进行解密，只有当本地用户密钥与AS中对应该用户的密钥匹配时才能解密成功。对A解密成功后，客户端就能拿到SK1，才能与TGS进行后续的会话，这里就相当于AS对客户端的一次验证，只有真正拥有正确用户密钥的客户端才能有机会与AS进行后续会话。而对于消息B，由于它是由TGS的密钥加密的，故无法对其解密，也看不到其中的内容。

#### 2.2 获取服务票据

　　此过程则是客户端向TGS请求获取访问对应服务的票据：

> - 当客户端要访问某个服务时，会向TGS发送如下两条消息：
>   - 消息C：消息B的内容（即加密后的TGT）和服务ID
>   - 消息D：通过SK1加密的验证器（Authenticator，包括用户ID和时间戳）
> - TGS收到消息C和D后，首先检查KDC数据库中是否存在所需服务，若存在则用自己的TGS密钥尝试对C中的消息B进行解密，这里也是客户端对TGS的反向认证，只有真正拥有正确密钥的TGS才能对B解密，解密成功后就能拿到其中的SK1，然后再用SK1解密消息D拿到包含用户ID和时间戳的Authenticator，通过比较分别来自C和D的用户ID，如果二者匹配，则向客户端返回如下两条消息：
>   - 消息E：通过SK1加密的Client/SS会话密钥，该会话密钥是KDC新生成的随机密钥，用于将来客户端（Client）与服务端（SS）的通信加密，我们称之为SK2
>   - 消息F：使用服务的密钥加密的client-server票据（Ticket，包含用户ID、用户网络地址、票据有效期和SK2），之所以要用服务的密钥加密，是因为这个Ticket是给服务端看的，但又需要经过客户端传给服务端，且不能让客户端看到。那么就会有人问，为什么KDC不直接把消息E发送给服务端呢，这样岂不省事？问题就在于网络时延，若分开发送，消息E和F就不能确保同时到达服务端，考虑一个极端情况，KDC与服务之前的网络临时不通了，那么这段时间服务端就无法收到消息E，导致验证失败，而实际上该客户端是有访问权限的。通过公钥加密这种方式巧妙地回避了该问题
>
> - 客户端收到消息后，尝试用SK1解密消息E，得到Client/SS会话密钥SK2

#### 2.3 服务验证

　　此过程是客户端与服务端相互验证，并通信

> - 客户端向服务端发送如下两条消息：
>
>   - 消息G：即上一步中的消息F——client-server票据
>
>   - 消息H：通过SK2加密的新的验证器（Authenticator，包含用户ID和时间戳）
>
> - 服务端收到消息后，尝试用自己的密钥解密消息G，这里实际上也是客户端对服务端的一次验证，只有真正拥有正确密钥的服务端才能正确解密，从而有机会拿到Ticket中的SK2，然后再用该SK2解密消息H，同TGS一样，对分别来自Ticket和Authenticator中的用户ID进行验证，如果匹配成功则返回一条确认消息：
>
>   - 消息I：通过SK2加密的新时间戳
>
> - 客户端尝试用SK2解密消息I，得到新时间戳并验证其正确性，验证通过后，客户端与服务端就达到了相互信任，后续的通信都采用SK2加密，就好比建立了一条加密通道，二者即可享受服务与被服务的乐趣了

### 3.前提（环境假设）

- 共享密钥：在协议工作前，客户端与KDC，KDC与服务端都确保有了各自的共享密钥。
- 防Dos攻击：Kerberos协议本身并没有解决Dos攻击（[Denial of service](https://en.wikipedia.org/wiki/Denial-of-service_attack)，拒绝服务）防范问题，通常是由系统管理员和用户自己去定期探测并解决这样的攻击。
- 保障安全个体自身安全：参与到Kerberos协议中的安全个体必须确保其秘钥的安全性，一旦秘钥泄露或被攻击者暴力破解，那么攻击者就能随意地伪装安全个体，做一些不和谐的事情。
- 不循环利用Principal的唯一标识：访问控制的常用方式是通过访问控制列表（access control lists，ACLs）来对特定的安全个体进行授权。如果列表中有条记录对应的安全个体*A*早已被删除，而*A*的唯一标识却被后来新加的某个个体*B*再次利用，那么*B*就会继承之前*A*对应的权限，这是不安全的。避免这种风险的做法就是不复用Principal的唯一标识。
- 时钟同步：参与到协议中的主机必须有个时钟相互之间进行“松散同步”，松散度是可配置的。为什么需要同步各主机的时间呢？实际上从Kerberos的认证过程可以看到，任何人都可以向KDC请求任何服务的TGT，那攻击者就有可能中途截获正常用户的请求包，然后离线解密，就能合法地拿到TGT。为了防止这种重放攻击，票据（Ticket）会包含时间戳信息，即具有一定的有效期，因此如果主机的时钟与Kerberos服务器的时钟不同步，则认证会失败。在实践中，通常用网络时间协议（Network Time Protocol, NTP）软件来同步时钟。

### 4.局限性

- 单点风险：过度依赖于KDC服务，Kerberos协议运转时需要KDC的持续响应，一旦KDC服务挂了，或者KDC数据库被攻破，那么Kerberos协议将无法运转
- 安全个体自身的安全：Kerberos协议之所以能运行在非安全网络之上，关键假设就是主机自身是安全的，一旦主机上的私钥泄露，攻击者将能轻易的伪装该个体实施攻击

## 三、Kerberos应用

### 1.Hadoop安全机制

　　Apache Hadoop 最初设计时并没有考虑安全问题，它不对用户或服务进行验证，任何人都可以向集群提交代码并得到执行，使用Hadoop的组织只能把集群隔离到专有网络，确保只有经过授权的用户才能访问，但这也并不能解决Hadoop集群内部的安全问题。为了增强Hadoop的安全机制，从1.0.0版本以后，引入Kerberos认证机制，即用户跟服务通信以及各个服务之间通信均用Kerberos认证，在用户认证后任务执行、访问服务、读写数据等均采用特定服务发起访问token，让需求方凭借token访问相应服务和数据。下面以Yarn中提交MR任务为例：

> A、用户先向KDC请求TGT，做初始验证
>
> B、用户通过TGT向KDC请求访问服务的Ticket
>
> C、客户端通过ticket向服务认证自己，完成身份认证
>
> D、完成身份认证后，客户端向服务请求若干token供后续任务执行时认证使用
>
> F、客户端连同获取的token一并提交任务，后续任务执行使用token与服务进行认证

## 四、其他安全机制

### 1.OAuth认证

　　OAuth（Open Authorization，开放授权）用于第三方授权服务，现常用的第三方账号登陆都是采用该机制。比如我用github账号登陆LeetCode官网，LeetCode并不需要知道我的github账号、密码，它只需要将登陆请求转给授权方（github），由它进行认证授权，然后把授权信息传回LeetCode实现登陆。

### 2.LDAP

　　LDAP（Lightweight Directory Access Protocol，轻量级目录访问协议）是一种用于访问目录服务的业界标准方法，LDAP目录以树状结构来存储数据，针对读取操作做了特定优化，比从专门为OLTP优化的关系数据库中读取数据快一个量级。LDAP中的安全模型主要通过身份认证、安全通道和访问控制来实现，它可以把整个目录、目录的子树、特定条目、条目属性集火符合某过滤条件的条目作为控制对象进行授权，也可以把特定用户、特定组或所有目录用户作为授权主体进行授权，也可以对特定位置（如IP或DNS名称）进行授权。

### 3.[SSL](SSL/TLS协议运行机制的概述)

SSL（Secure Sockets Layer，安全套接层）是目前广泛应用的加密通信协议，其基本思路是采用公钥加密法，即客户端先向服务器端索要公钥，然后用公钥加密信息，服务端收到密文后用自己的私钥解密。它的安全机制包含如下三点：

> - 连接的私密性：利用会话密钥通过对称加密算法（DES）对传输数据进行加密，并利用RSA对会话密钥本身加密
> - 身份验证：基于数字证书利用数字签名方法进行身份验证，SSL服务器和客户端通过PKI（Public Key Infrastructure）提供的机制从CA获取证书
> - 内容可靠：使用基于密钥的MAC（Message Authentication Code，消息验证码）验证消息的完整性，防窜改
