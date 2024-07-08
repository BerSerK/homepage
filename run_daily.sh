#!/bin/bash  
# 该脚本用于每日定时执行，生成净值页面
# 把输出重定向到以日期命名的文件.
exec >> /mnt/d/log/homepage/`date +%Y%m%d`.log 2>&1

# 获取当前目录
project_path=$(cd `dirname $0`; pwd)  

# 切换到脚本所在目录
cd $project_path
  
# 执行命令  
/home/alex/anaconda3/bin/ipython $project_path/generate_net_value_page.py send
