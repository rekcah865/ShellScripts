#关于orasql

##介绍
[orasql](orasql) 一个在数据库服务器上面通过sqlplus运行Oracle数据库SQL脚本。  
同时会通过orapass获取密码，并保证要运行过程中隐藏密码(ps)。  

##使用方式

    orasql [-L|-S...] <Username> @<SQLFILE>  

* -L, -S: 沿用了sqlplus中的参数，分别代表一次验证登录、silent模式运行。当然也可以用其它sqlplus参数  
* Username: 登录数据库的用户名（密码通过orapass获取），/-代表通过sys dba方式  
* @SQLFILE: 执行SQLFILE，其方式跟sqlplus一样  

##例子

**测试脚本test.sql**  

    cat > /tmp/test.sql <<EOF
    select sysdate from dual;
    exec dbms_lock.sleep(15);
    exit
    EOF

###运行1 - 以sys方式执行
$ orasql / @/tmp/test.sql  

*ps结果*  

    ods      13351  8569  0 13:17 pts/8    00:00:00 bash /u01/usr/ods/ods/bin/orasql / @/tmp/test.sql  
    ods      13359 13351  0 13:17 pts/8    00:00:00 sqlplus   as sysdba @/tmp/test.sql  
    oracle   13361 13359  0 13:17 ?        00:00:00 oracleods (DESCRIPTION=(LOCAL=YES)(ADDRESS=(PROTOCOL=beq)))  

###运行2 - 以普通用户登录执行 
$ orasql -S ods @/tmp/test.sql  

*ps结果*  

    ods      13876  8569  0 13:18 pts/8    00:00:00 bash /u01/usr/ods/ods/bin/orasql -S ods @/tmp/test.sql  
    ods      13889 13876  0 13:18 pts/8    00:00:00 sqlplus -S     @/tmp/test.sql  
    oracle   13891 13889  0 13:18 ?        00:00:00 oracleods (DESCRIPTION=(LOCAL=YES)(ADDRESS=(PROTOCOL=beq)))  

###运行3 - 异常捕捉

* 参数缺少  

$ orasql   

    Too fee parameter passed in!  
    orasql <ORAUSER> <SQL File>  
 
$ orasql ods 
    
    Too fee parameter passed in!  
    orasql <ORAUSER> <SQL File>  

* 获取不到密码  

$ orasql -S odsa @/tmp/test.sql  

    Can not get password from orapass! Exit..  

