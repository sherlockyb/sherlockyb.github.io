---
title: spring事务管理
date: 2017-03-22 23:48:06
categories:
- Spring
tags:
- Spring
- 源码
- 事务管理
---
  对大多数Java开发者来说，Spring事务管理是Spring应用中最常用的功能，使用也比较简单。本文主要从三个方面（基本概述、基于源码的原理分析以及需要注意的细节）来逐步介绍Spring事务管理的相关知识点及原理，作为Spring事务管理的学习总结。

<!--more-->

# Spring事务管理概述

## 一、几个重要概念

### 1.事务隔离级别

  ANSI/ISO SQL92标准定义了4个[隔离级别](http://docs.spring.io/spring/docs/current/javadoc-api/org/springframework/transaction/annotation/Isolation.html)：**READ UNCOMMITED**、**READ COMMITED**、**REPEATABLE READ**和**SERIALIZABLE**，隔离程度由弱到强。不同的事务隔离级别能够解决数据并发问题的能力不同，它与数据库并发性是对立的，两者此消彼长。

### 2.事务传播行为

  事务传播主要是为了描述两个服务接口方法嵌套调用时，被调用者在调用者有无事务时所采取的事务行为。Spring框架在TransactionDefinition接口中固定了7种事务传播行为：**PROPAGATION\_REQUIRED**、 **PROPAGATION\_SUPPORTS**、 **PROPAGATION\_MANDATORY**、     **PROPAGATION\_REQUIRES_NEW**、 **PROPAGATION\_NOT\_SUPPORTED**、 **PROPAGATION\_NEVER**、  **PROPAGATION\_NESTED**。前面的6种是从EJB中引入的，而**PROPAGATION\_NESTED**是Spring特有的。具体可参见[深入浅出事务(4):Spring事务的传播行为](http://pjoc.pub/shen-ru-qian-chu-shi-wu-4-springshi-wu-de-chuan-bo-xing-wei/)，该文结合具体代码示例，通俗易懂。

### 3.事务同步管理器

  **TransactionSynchronizationManager**——事务管理的基石，主要是为了解决事务管理在多线程环境下资源（如Connection、Session等）的并发访问问题：使用ThreadLocal为不同事务线程维护独立的资源副本，以及事务配置属性和运行状态信息，使各个事务线程互不影响。

### 4.事务管理SPI

  [SPI](https://en.wikipedia.org/wiki/Service_provider_interface)（Service Provider Interface）是一个框架开放给第三方的可扩展服务接口，供其具体实现，以支持框架的扩展性和插件式组件。Spring事务管理SPI主要包括3个接口：**PlatformTransactionManager**（进行事务的创建、提交或回滚）、**TransactionDefinition**（定义事务属性，如隔离级别）和**TransactionStatus**（事务运行时状态，如是否已完成）。这三者通过PlatformTransactionManager的如下接口进行关联：

```java
// 根据事务定义创建事务，并由TransactionStatus表示它
TransactionStatus getTransaction(TransactionDefinition definition);
// 根据事务运行时状态提交或回滚事务
void commit(TransactionStatus status);
void rollback(TransactionStatus status);
```

## 二、基本用法

  三种方式：编程、XML配置和注解。第一方式对应用代码侵入性较大，现已较少使用。后面两种则都属于声明式事务管理的方式，两者的共同点是都提供事务管理信息的元数据，只不过方式不同。前者对代码的侵入性最小，也最为常用，后者则属于较为折衷的方案，有一点侵入性，但相对也较少了配置，各有优劣，[依场景需求而定](http://jinnianshilongnian.iteye.com/blog/1879910)。**声明式事务管理**是Spring的一大亮点，利用AOP技术将事务管理作为切面动态织入到目标业务方法中，让事务管理简单易行。

  而不管是使用哪种方式，**数据源**、**事务管理器**都是必须的，一般通过XML的Bean配置：

```xml
...
<bean id="dataSource" class="com.mchange.v2.c3p0.ComboPooledDataSource" destory-method="close">
  <property name="driverClass"><value>${jdbc.driverClass}</value></property>
  <property name="jdbcUrl"><value>${jdbc.jdbcUrl}</value></property>
  <property name="user"><value>${jdbc.username}</value></property>
  <property name="password"><value>${jdbc.password}</value></property>
  <property name="maxPoolSize"><value>${jdbc.maxPoolSize}</value></property>
  <property name="minPoolSize"><value>${jdbc.minPoolSize}</value></property>
  <property name="initialPoolSize"><value>${initialPoolSize}</value></property>
</bean>

<bean id="txManager" class="org.springframework.jdbc.datasource.DataSourceTransactionManager">
  <property name="dataSource">
    <ref local="dataSource" />
  </property>
  <!-- 指定事务管理器标识，可被@Transactional注解引用 -->
  <qualifier value="txManagerA" />
</bean>
...
```

### 1.编程式事务管理

  采用与DAO模板类一样的开闭思想，Spring提供了线程安全的**TransactionTemplate**模板类来处理不变的事务管理逻辑，将变化的部分抽象为回调接口**TransactionCallback**供用户自定义数据访问逻辑。使用示例：

```java
public class ServiceAImpl {
	private DaoA daoA;
	@autowried
	private TransactionTemplate template;
	public void addElement(final Element ele) {
		template.execute(new TransactionCallbackWithoutResult() {
			protected void doInTransactionWithoutResult(TransactionStatus status){
				daoA.addElement(ele);
			}
		});
	}
}
```

  TransactionTemplate的配置信息：

```xml
...
<bean id="transactionTemplate" class="org.springframework.transaction.support.TransactionTemplate">
  <property name="transactionManager">
    <ref local="txManager" />
  </property>
  <property name="isolationLevelName" value="ISOLATION_DEFAULT" />
  <property name="propagationBehaviorName" value="PROPAGATION_REQUIRED" />
</bean>
...
```

  当然，用户也可以不使用TransactionTemplate，而是直接基于原始的[Spring事务管理SPI](#4-事务管理SPI)进行编程式事务管理，只不过这种方式对代码侵入性最大，不推荐使用，这里也就不多做介绍了。

### 2.基于XML配置的事务管理

  Spring早期版本，是通过**TransactionProxyFactoryBean**代理类实施声明式事务配置，由于这种方式的种种弊端，后来引入AOP切面描述语言后，提出一种更简洁的基于Schema的配置方式：**tx/aop命名空间**，使声明式事务配置更简洁便利。

#### 2.1基于Bean的配置

```xml
...
<bean id="serviceATarget" class="org.sherlocky.book.spring3x.service.ServiceAImpl" />
<bean id="serviceA" class="org.springframework.transaction.interceptor.TransactionProxyFactoryBean"
      p:transactionManager-ref="txManager"
      p:target-ref="serviceATarget">
  <property name="transactionAttributes">
    <props>
      <prop key="get*">PROPAGATION_REQUIRED,readOnly</prop>
      <prop key="*">PROPAGATION_REQUIRED</prop>
    </props>
  </property>
</bean>
...
```

#### 2.1基于Schema的配置（常用）

```xml
...
<tx:advice id="txAdvice" transaction-manager="txManager">
  <tx:attributes>
    <tx:method name="create*" propagation="REQUIRED" timeout="300" rollback-for="java.lang.Exception" />
    <tx:method name="delete*" propagation="REQUIRED" timeout="300" rollback-for="java.lang.Exception" />
    <tx:method name="update*" propagation="REQUIRED" timeout="300" rollback-for="java.lang.Exception" />
    <tx:method name="get*" propagation="REQUIRED" read-only="true" timeout="300" />
    <tx:method name="*" propagation="REQUIRED" read-only="true" timeout="300" />
  </tx:attributes>
</tx:advice>

<aop:config>
  <aop:pointcut id="txPointcut" expression="execution(* org.sherlocky.book.spring3x.service.*ServiceA.*(..))" />
  <aop:advisor pointcut-ref="txPointcut" advice-ref="txAdvice" />
</aop:config>
```

#### 2.3基于注解的事务管理

  通过**@Transactional**对需要事务增强的Bean接口、实现类或方法进行标注，在容器中配置**<tx:annotation-driven>**以启用基于注解的声明式事务。注解所提供的事务属性信息与XML配置中的事务信息基本一致，只不过是另一种形式的元数据而已。使用示例：

```java
@Transactional("txManagerA")
public class ServiceAImpl {
	private DaoA daoA;
	public void addElement(final Element ele) {
		...
	}
}
```

# Spring事务管理源码分析-(spring3.1.0)

  源码分析一定要有目的性，至少有一条清晰的主线，比如要搞清楚框架的某一个功能点背后的代码组织，前因后果，而不是一头扎进源码里，无的放矢。本文就从Spring事务管理的三种使用方式入手，逐个分析Spring在背后都为我们做了些什么。

## 一、编程式

### 1.TransactionTemplate

  TransactionTemplate是编程式事务管理的入口，源码如下：

```java
public class TransactionTemplate extends DefaultTransactionDefinition
		implements TransactionOperations, InitializingBean {
	private PlatformTransactionManager transactionManager;
  	...
    public <T> T execute(TransactionCallback<T> action) throws TransactionException {
		if (this.transactionManager instanceof CallbackPreferringPlatformTransactionManager) {
			return ((CallbackPreferringPlatformTransactionManager) this.transactionManager).execute(this, action);【1】
		}
		else {
			TransactionStatus status = this.transactionManager.getTransaction(this);【2】
			T result;
			try {
				result = action.doInTransaction(status);
			}
			catch (RuntimeException ex) {【3】
				// Transactional code threw application exception -> rollback
				rollbackOnException(status, ex);
				throw ex;
			}
			catch (Error err) {【4】
				// Transactional code threw error -> rollback
				rollbackOnException(status, err);
				throw err;
			}
			catch (Exception ex) {【5】
				// Transactional code threw unexpected exception -> rollback
				rollbackOnException(status, ex);
				throw new UndeclaredThrowableException(ex, "TransactionCallback threw undeclared checked exception");
			}
			this.transactionManager.commit(status);
			return result;
		}
	}
}
```

#### 1.1整体概述

  TransactionTemplate提供了唯一的编程入口execute，它接受用于封装业务逻辑的TransactionCallback接口的实例，返回用户自定义的事务操作结果T。具体逻辑：先是判断transactionManager是否是接口CallbackPreferringPlatformTransactionManager的实例，若是则直接委托给该接口的execute方法进行事务管理；否则交给它的核心成员PlatformTransactionManager进行事务的创建、提交或回滚操作。

  CallbackPreferringPlatformTransactionManger接口扩展自PlatformTransactionManger，根据以下的官方源码注释可知，该接口相当于是把事务的创建、提交和回滚操作都封装起来了，用户只需要传入TransactionCallback接口实例即可，而不是像使用PlatformTransactionManger接口那样，还需要用户自己显示调用getTransaction、rollback或commit进行事务管理。

```java
 // Implementors of this interface automatically express a preference for
 // callbacks over programmatic getTransaction, commit and rollback calls.
 interface CallbackPreferringPlatformTransactionManager extends PlatformTransactionManager{...}
```

#### 1.2具体剖析

##### DefaultTransactionDefinition

  可以看到transactionTemplate直接扩展自DefaultTransactionDefinition，让自身具有默认事务定义功能，【1】和【2】处将**this**作为execute或getTransaction的实参传入，说明该事务管理是采用默认的事务配置，可以看下DefaultTransactionDefinition中定义的默认配置：

```java
...
private int propagationBehavior = PROPAGATION_REQUIRED; //常用选择：当前没有事务，则新建；否则加入到该事务中
private int isolationLevel = ISOLATION_DEFAULT;         //使用数据库默认的隔离级别
private int timeout = TIMEOUT_DEFAULT;                  //-1，使用数据库的超时设置
private boolean readOnly = false;                       //非只读事务
```

##### TransactionOperations和InitializingBean

而TransactionOperations和InitializingBean接口分别定义了如下单个方法。InitializingBean是Spring在初始化所管理的Bean时常用的接口，以确保某些属性被正确的设置或做一些初始化时的后处理操作，可参考[InitializingBean的作用](http://blog.csdn.net/maclaren001/article/details/37039749)。

```java
<T> T execute(TransactionCallback<T> action);   //TransactionTemplate的编程接口
void afterPropertiesSet();                      //Bean初始化时调用：在成员变量装配之后
```

TransactionTemplate实现InitializingBean接口，主要是确保其核心成员transactionManager是否已初始化：

```java
public void afterPropertiesSet() {
	if (this.transactionManager == null) {
		throw new IllegalArgumentException("Property 'transactionManager' is required");
	}
}
```

  从【3】【4】【5】可看出，基于TransactionTemplate的事务管理，在发生RuntimeException、Error或Exception时都会回滚，正常时才提交事务。

### 2. PlatformTransactionManager

  该接口在Spring事务管理中扮演着重要角色。看下getTransaction的源码注释：

```java
// Return a currently active transaction or create a new one, according to
// the specified propagation behavior.
```

该方法的主要作用就是根据TransactionDefinition返回当前有效事务或新建事务，其中就包含了[事务传播行为](#2-事务传播行为)的控制逻辑。其**唯一实现**就是该接口对应的抽象类AbstractPlatformTransactionManager，这是典型的接口->抽象类->具体实现类三层结构，以**提高代码复用性**。其中抽象类是负责实现一些共有逻辑，而具体子类则是各自实现差异化功能：

```java
// 声明为final，确保不能再被子类重写
public final TransactionStatus getTransaction(TransactionDefinition definition) throws TransactionException {
		Object transaction = doGetTransaction();
        ...
		if (isExistingTransaction(transaction)) {【1】
			return handleExistingTransaction(definition, transaction, debugEnabled);
		}
        ...
		if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_MANDATORY){
			throw new IllegalTransactionStateException(
					"No existing transaction found for transaction marked with propagation 'mandatory'");
		}
		else if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRED ||
				definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW ||
		    definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
			SuspendedResourcesHolder suspendedResources = suspend(null);【2】
			...
            try {
				...
			}
			catch (RuntimeException ex) {
				resume(null, suspendedResources);【3】
				throw ex;
			}
			catch (Error err) {
				resume(null, suspendedResources);
				throw err;
			}
		}
		else {
			boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
			return prepareTransactionStatus(definition, null, true, newSynchronization, debugEnabled, null);
		}
	}
```

可以看到它会根据【1】处的isExistingTransaction方法判断当前是否有事务而分别作出不同的处理，包括挂起和恢复当前事务等，有兴趣的童鞋可以深入【2】处的supend和【3】处的resume方法，会发现对事务的挂起和恢复操作实际是委托于**TransactionSynchronizationManager**来做的，而该类在前面也提过到，是Spring管理事务资源的，这几个重要接口和类的关系渐渐清晰了，由于篇幅有限，后面打算单独另起一篇细讲。

## 2.声明式

  基于XML和注解的方式都是属于声明式事务管理，只是提供元数据的形式不用，索性就一起讲了。声明式事务的核心实现就是利用AOP技术，将事务逻辑作为环绕增强MethodInterceptor动态织入目标业务方法中。其中的核心类为TransactionInterceptor。从以下代码注释可知，TransactionInterceptor是专用于声明式事务管理的。

```java
// AOP Alliance MethodInterceptor for declarative transaction
// management using the common Spring transaction infrastructure {PlatformTransactionManager}
public class TransactionInterceptor extends TransactionAspectSupport implements MethodInterceptor, Serializable {...}
```

### 1.TransactionInterceptor

```java
// AOP Alliance MethodInterceptor for declarative transaction
// management using the common Spring transaction infrastructure
public class TransactionInterceptor extends TransactionAspectSupport implements MethodInterceptor, Serializable {...}
```

从上述注释中可知该类是专用于声明式事务管理的，它的核心方法如下invoke：

```java
public Object invoke(final MethodInvocation invocation) throws Throwable {
		Class<?> targetClass = (invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null);

		// If the transaction attribute is null, the method is non-transactional.
		final TransactionAttribute txAttr =
				getTransactionAttributeSource().getTransactionAttribute(invocation.getMethod(), targetClass);【1】
		final PlatformTransactionManager tm = determineTransactionManager(txAttr);【2】
		final String joinpointIdentification = methodIdentification(invocation.getMethod(), targetClass);

		if (txAttr == null || !(tm instanceof CallbackPreferringPlatformTransactionManager)) {
			// Standard transaction demarcation with getTransaction and commit/rollback calls.
			TransactionInfo txInfo = createTransactionIfNecessary(tm, txAttr, joinpointIdentification);【3】
			Object retVal = null;
			try {
				// This is an around advice: Invoke the next interceptor in the chain.
				// This will normally result in a target object being invoked.
				retVal = invocation.proceed();
			}
			catch (Throwable ex) {
				// target invocation exception
				completeTransactionAfterThrowing(txInfo, ex);【4】
				throw ex;
			}
			finally {
				cleanupTransactionInfo(txInfo);
			}
			commitTransactionAfterReturning(txInfo);【5】
			return retVal;
		}
  		else {
			try {
				Object result = ((CallbackPreferringPlatformTransactionManager) tm).execute(txAttr,
						new TransactionCallback<Object>() {
							public Object doInTransaction(TransactionStatus status) {
								TransactionInfo txInfo = prepareTransactionInfo(tm, txAttr, joinpointIdentification, status);
								try {
									return invocation.proceed();
								}
							    ...
							}
						});
                ...
			}
			...
		}
	}
```

#### 1.1整体概述

  TransactionInterceptor实现了MethodInterceptor接口，将事务管理的逻辑封装在环绕增强的实现中，而目标业务代码则抽象为MethodInvocation（该接口扩展自Joinpoint，故实际是AOP中的连接点），使得事务管理代码与业务逻辑代码完全分离，可以对任意目标类进行无侵入性的事务织入。具体逻辑：先根据MethodInvocation获取事务属性TransactionAttribute，根据TransactionAttribute得到对应的PlatformTransactionManager，再根据其是否是CallbackPreferringPlatformTransactionManager的实例分别做不同的处理，整体上跟[TransactionTemplate](#1-TransactionTemplate)中大相径庭，后面主要是介绍几点不同的地方。

#### 1.2具体剖析

##### MethodInterceptor

  MethodInterceptor是AOP中的环绕增强接口，同一个连接点可以有多个增强，而TransactionInterceptor扩展自该接口，说明事务管理只是众多横切逻辑中的一种，还有很多其他的，比如像日志记录、性能监控等，对于AOP而言并无区别，它会按照增强的顺序统一处理。关于AOP，后期会单独一篇详细介绍。

##### TransactionAttribute和TransactionAttributeSource

  在代码【1】处，委托给TransactionAttributeSource根据MethodInvocation获取对应的事务属性TransactionAttribute，先来看下TransactionAttribute：

```java
public interface TransactionAttribute extends TransactionDefinition {
	/**
	 * Return a qualifier value associated with this transaction attribute.
	 * <p>This may be used for choosing a corresponding transaction manager
	 * to process this specific transaction.
	 */
	String getQualifier();
	/**
	 * Should we roll back on the given exception?
	 * @param ex the exception to evaluate
	 * @return whether to perform a rollback or not
	 */
	boolean rollbackOn(Throwable ex);	
}
```

就是在TransactionDefinition的基础上增加了两个可定制属性，使用过XML配置和注解方式的童鞋应该都对qualifier和rollback-for再熟悉不过了，那两个新增属性就是为了支持这两个配置项的。再来看下TransactionAttributeSource：

```java
/**
 * Interface used by TransactionInterceptor. Implementations know
 * how to source transaction attributes, whether from configuration,
 * metadata attributes at source level, or anywhere else.
 * @see TransactionInterceptor#setTransactionAttributeSource
 * @see TransactionProxyFactoryBean#setTransactionAttributeSource
 */
public interface TransactionAttributeSource {
	TransactionAttribute getTransactionAttribute(Method method, Class<?> targetClass);
}
```

之所以有这个接口，是因为Spring提供了XML配置、注解等不同的事务元数据形式，即事务属性的来源多样，该接口正是将事务配置的来源进行抽象，不同的来源有对应不同的实现类，接口单一职责，巧妙精简的设计！类图如下，AnnotationTransactionAttributeSource是注解相关，而NameMatchTransactionAttributeSource、MatchAlwaysTransactionAttributeSource等是XML配置相关。

![TransactionAttribute类图](spring-transaction-management/TransactionAttribute.png)

##### TransactionAspectSupport

该抽象父类是事务切面的基本处理类，实现了一些共有方法，如代码【2】处determineTransactionManager(..)根据TransactionAttribute得到对应的PlatformTransactionManager，以及【3】处createTransactionIfNecessary创建事务，【4】处completeTransactionAfterThrowing回滚事务，【5】处commitTransactionAfterReturning提交事务等基本操作，底层同样是委托PlatformTransactionManager进行处理的。这里主要看下事务的回滚操作，跟TransactionTemplate是有区别的：

```java
protected void completeTransactionAfterThrowing(TransactionInfo txInfo, Throwable ex) {
		if (txInfo != null && txInfo.hasTransaction()) {
			...
			if (txInfo.transactionAttribute.rollbackOn(ex)) {【1】
				try {
					txInfo.getTransactionManager().rollback(txInfo.getTransactionStatus());
				}
				catch (TransactionSystemException ex2) {
					logger.error("Application exception overridden by rollback exception", ex);
					ex2.initApplicationException(ex);
					throw ex2;
				}
				catch (RuntimeException ex2) {
					logger.error("Application exception overridden by rollback exception", ex);
					throw ex2;
				}
				catch (Error err) {
					logger.error("Application exception overridden by rollback error", ex);
					throw err;
				}
			}
			else {
              	try {
					txInfo.getTransactionManager().commit(txInfo.getTransactionStatus());
				}
				...
			}
		}
	}
```

从【1】处的transactionAttribute.rollbackon(ex)可看出，事务属性中的rollbackOn是在这里生效的，在发生指定异常时选择回滚或提交，是用户可配置的，而不像TransactionTemplate是固定的全部回滚。

### 2.TransactionProxyFactoryBean

该类是早期[基于Bean的XML配置方式](#2-1基于Bean的配置)实现声明式事务的核心类，之所以放在后面讲，是因为该方式已不被推荐使用，先来看下定义：

```java
/**
 * Proxy factory bean for simplified declarative transaction handling.
 * This is a convenient alternative to a standard AOP
 * {@link org.springframework.aop.framework.ProxyFactoryBean}
 * with a separate {@link TransactionInterceptor} definition.
 *
 * <p><strong>HISTORICAL NOTE:</strong> This class was originally designed to cover the
 * typical case of declarative transaction demarcation: namely, wrapping a singleton
 * target object with a transactional proxy, proxying all the interfaces that the target
 * implements. However, in Spring versions 2.0 and beyond, the functionality provided here
 * is superseded by the more convenient {@code tx:} XML namespace. See the <a
 * href="http://bit.ly/qUwvwz">declarative transaction management</a> section of the
 * Spring reference documentation to understand the modern options for managing
 * transactions in Spring applications.
 * ...
 */
public class TransactionProxyFactoryBean extends AbstractSingletonProxyFactoryBean
		implements BeanFactoryAware {
	private final TransactionInterceptor transactionInterceptor = new TransactionInterceptor();
	private Pointcut pointcut;
    ...
    protected Object createMainInterceptor() {
		this.transactionInterceptor.afterPropertiesSet();
		if (this.pointcut != null) {
			return new DefaultPointcutAdvisor(this.pointcut, this.transactionInterceptor);
		}
		else {
			// Rely on default pointcut.
			return new TransactionAttributeSourceAdvisor(this.transactionInterceptor);
		}
	} 
}
```

源码的声明已经相当清晰，大致说明了该类的来龙去脉，忍不住直接贴上来了，感兴趣可自行阅读。这里主要是看下其实现思路：事务处理逻辑是委托给其成员TransactionInterceptor，而将事务逻辑织入目标类的工作则交由AbstractSingletonProxyFactoryBean来处理。FactoryBean是Spring中广泛使用的用来定制一些较复杂Bean的实例化逻辑，因此从类名上就可看出，AbstractSingletonProxyFactoryBean的主要工作则是实例化并返回一个单例的Proxy对象。有了Proxy对象，织入的工作就轻而易举了，此时TransactionInterceptor只是Proxy的众多Advisor中的一个，最后由Proxy创建拥有了事务增强的代理对象即可。

  以下是AbstractSingletonProxyFactoryBean中Proxy的实例化过程，全部在afterPropertiesSet中完成。其中的createMainInterceptor()是在其子类TransactionProxyFactoryBean中实现的，对应事务增强逻辑。

```java
public abstract class AbstractSingletonProxyFactoryBean extends ProxyConfig
		implements FactoryBean<Object>, BeanClassLoaderAware, InitializingBean {
  ...
  public void afterPropertiesSet() {
		if (this.target == null) {
			throw new IllegalArgumentException("Property 'target' is required");
		}
		if (this.target instanceof String) {
			throw new IllegalArgumentException("'target' needs to be a bean reference, not a bean name as value");
		}
		if (this.proxyClassLoader == null) {
			this.proxyClassLoader = ClassUtils.getDefaultClassLoader();
		}

		ProxyFactory proxyFactory = new ProxyFactory();【1】

		if (this.preInterceptors != null) {
			for (Object interceptor : this.preInterceptors) {
				proxyFactory.addAdvisor(this.advisorAdapterRegistry.wrap(interceptor));
			}
		}

		// Add the main interceptor (typically an Advisor).
		proxyFactory.addAdvisor(this.advisorAdapterRegistry.wrap(createMainInterceptor()));

		if (this.postInterceptors != null) {
			for (Object interceptor : this.postInterceptors) {
				proxyFactory.addAdvisor(this.advisorAdapterRegistry.wrap(interceptor));
			}
		}

		proxyFactory.copyFrom(this);

		TargetSource targetSource = createTargetSource(this.target);
		proxyFactory.setTargetSource(targetSource);

		if (this.proxyInterfaces != null) {
			proxyFactory.setInterfaces(this.proxyInterfaces);
		}
		else if (!isProxyTargetClass()) {
			// Rely on AOP infrastructure to tell us what interfaces to proxy.
			proxyFactory.setInterfaces(
					ClassUtils.getAllInterfacesForClass(targetSource.getTargetClass(), this.proxyClassLoader));
		}

		this.proxy = proxyFactory.getProxy(this.proxyClassLoader);
	}
}
```

从代码【1】处可以看到，ProxyFactory是创建Proxy对象的关键类，感兴趣的童鞋可以跟进ProxyFactory的代码，可发现最终创建Proxy对象的是DefaultAopProxyFactory，细节如下：根据config配置，选择创建我们所熟知的两种AopProxy：JDK的JdkDynamicAopProxy和Cglib的Cglib2AopProxy。

```java
public class DefaultAopProxyFactory implements AopProxyFactory, Serializable {
  	...
	public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
		if (config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config)) {
			Class targetClass = config.getTargetClass();
			if (targetClass == null) {
				throw new AopConfigException("TargetSource cannot determine target class: " +
						"Either an interface or a target is required for proxy creation.");
			}
			if (targetClass.isInterface()) {
				return new JdkDynamicAopProxy(config);
			}
			if (!cglibAvailable) {
				throw new AopConfigException(
						"Cannot proxy target class because CGLIB2 is not available. " +
						"Add CGLIB to the class path or specify proxy interfaces.");
			}
			return CglibProxyFactory.createCglibProxy(config);
		}
		else {
			return new JdkDynamicAopProxy(config);
		}
	}
}
```

# 需要注意的细节

## 一、PROPAGATION_TESTED（嵌套事务）

  当使用PROPAGATION_NESTED时，**底层的数据源必须基于JDBC3.0**。因为Spring所支持的嵌套事务，是基于事务保存点实现的（**JTA除外**），而保存点机制是从JDBC3.0才开始出现的。直接看AbstractPlatformTransactionManager中的处理代码。对于通常的嵌套事务，会在当前所处父事务中创建保存点，然后进行子事务处理；对于JTA事务环境，则是采用嵌套的begin和commit/rollback调用来处理。

```java
	private TransactionStatus handleExistingTransaction(
			TransactionDefinition definition, Object transaction, boolean debugEnabled)
			throws TransactionException {
		...
		if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
			if (!isNestedTransactionAllowed()) {
				throw new NestedTransactionNotSupportedException(
						"Transaction manager does not allow nested transactions by default - " +
						"specify 'nestedTransactionAllowed' property with value 'true'");
			}
			if (debugEnabled) {
				logger.debug("Creating nested transaction with name [" + definition.getName() + "]");
			}
			if (useSavepointForNestedTransaction()) {
				// Create savepoint within existing Spring-managed transaction,
				// through the SavepointManager API implemented by TransactionStatus.
				// Usually uses JDBC 3.0 savepoints. Never activates Spring synchronization.
				DefaultTransactionStatus status =
						prepareTransactionStatus(definition, transaction, false, false, debugEnabled, null);
				status.createAndHoldSavepoint();
				return status;
			}
			else {
				// Nested transaction through nested begin and commit/rollback calls.
				// Usually only for JTA: Spring synchronization might get activated here
				// in case of a pre-existing JTA transaction.
				boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
				DefaultTransactionStatus status = newTransactionStatus(
						definition, transaction, true, newSynchronization, debugEnabled, null);
				doBegin(transaction, definition);
				prepareSynchronization(status, definition);
				return status;
			}
		}
      	...
	}
```

## 二、获取数据连接资源

  当脱离模板类，直接操作底层持久技术的原生API时，就需要通过Spring提供的资源工具类获取线程绑定的资源，而不应该直接从DataSource或SessionFactory中获取，否则容易造成[数据连接泄露](https://my.oschina.net/jiangtao1314/blog/38993)的问题。Spring为不同的持久化技术提供了一套从TransactionSynchronizationManager中获取对应线程绑定资源的工具类：DataSourceUtils（Spring JDBC或iBatis）、SessionFactoryUtils（Hibernate 3.0）等。

## 三、如何标注@Transactional注解

  虽然@Transactional注解可被应用于接口、接口方法、类及类的public方法，但建议在具体实现类上使用@Transactional注解，因为**接口上的注解不能被继承**，这样会有隐患（关于注解的继承，可参考[这里](http://elf8848.iteye.com/blog/1621392)）。当事务配置按如下方式，使用的是子类代理（CGLib）而非接口代理（JDK）时，对应目标类不会添加事务增强！

```xml
<tx:annotation-driven transaction-manager="txManager" proxy-target-class="true" />
```

