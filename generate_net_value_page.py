import pandas as pd
import sys
import os
import numpy as np
import datetime as dt

filename = '/mnt/d/code/CTA/fundreport.xlsx'

def generate_page(template_filename, output_filename, df, period = 'week'):
    df.index = range(len(df))
    df['net_value'] = df['net_value']/df['net_value'].iloc[0]
    df['net_value'] = [round(float(a), 3) for a in df['net_value']]
    periodReturn = []
    for i in range(1, len(df)):
        periodReturn.append(df['net_value'].iloc[i]/df['net_value'][i-1] - 1)
    year_period_count = 52
    if period == 'week':
        year_period_count = 52
    elif period == 'day':
        year_period_count = 252
    risk_free_rate = 0.03/252
    sharpe = (np.mean(periodReturn)*np.sqrt(year_period_count) - risk_free_rate)/np.std(periodReturn)    
    print("sharpe:", sharpe)
    date_str = str(list([d.date().strftime('%Y-%m-%d') for d in df['date']]))
    data_str = str(list(df['net_value']))
    draw_down = [0]
    net_value = list(df['net_value'])
    pre_max = net_value[0]
    for i in range(1, len(net_value)):
        if net_value[i] > pre_max:
            pre_max = net_value[i]
        draw_down.append(round(-100*(1-net_value[i]/pre_max), 3))

    df['year'] = [d.year for d in df['date']]
    last_year = df['year'].iloc[-1] - 1
    if last_year in set(df['year']):
        df_last_year = df.loc[df['year'] == last_year]
        ytd = df['net_value'].iloc[-1] / df_last_year['net_value'].iloc[-1] - 1
    else:
        ytd = df['net_value'].iloc[-1] - 1
    ytd = "%.2f%%"%(ytd * 100)
    draw_down_str = str(draw_down)
    template = open(template_filename).read()
    template = template.replace('dates_pos', date_str)
    template = template.replace('net_value_pos', data_str)
    template = template.replace('draw_down_pos', draw_down_str)
    template = template.replace('YTD', ytd)
    fp = open(output_filename,'w')
    fp.write(template)
    fp.close()

def make():
    df = pd.read_excel(filename, sheet_name = '样本外周度', names = ['date', 'net_value'],
                    header=1)
    df = df.loc[df['date']>'2020-01-01']
    print('since 2020:')
    generate_page('net_value_template.html', 'net_value_test.html', df)

def make15(start_time = '2020'):
    df = pd.read_excel(filename, sheet_name = '2020年以后', names = ['date', 'nav'],
                    header=1)

    df = df.dropna()
    start2021 = list(df['date']).index(dt.datetime(2021,1,6))
    nav = []
    nav_start2021 = df['nav'].iloc[start2021]
    for i in range(len(df['nav'])):
        if i <= start2021:
            nav.append(df['nav'].iloc[i])
        else:
            nav_item = (df['nav'].iloc[i] - nav_start2021) * 3 / 5 + nav_start2021
            nav.append(nav_item)
    df['net_value'] = nav
    df = df.drop_duplicates(subset=['date'])
    if start_time == '2021':
        df = df.iloc[start2021:]
        print("since 2021, 15% vol:")     
        generate_page('net_value_template2.html', 'net_value2021.html', df, 'day')
    else:
        print("since 2020, 15% vol:")
        generate_page('net_value_template2.html', 'net_value15.html', df, 'day')
 
def make_yifeng():
    df = pd.read_excel('/mnt/d/code/CTA/翼丰贝叶斯CTA一号产品净值数据.xls', header = 1)
    df = df.dropna()
    df['日期'] = df['估值日期']
    df = df.sort_values("日期")
    df = df.drop_duplicates(subset=['日期'])
    df['date'] = df['日期'].apply(lambda d: dt.datetime.strptime(d, "%Y-%m-%d"))
    df['net_value'] = df['单位净值']

    print("yifeng product:")
    generate_page('net_value_template3.html', 'net_value_prod.html', df, 'day')
    
def send():
    cmd = 'scp net_value.html root@vps.yeshiwei.com:/var/www/html/'
    os.system(cmd)
    cmd = 'scp net_value15.html root@vps.yeshiwei.com:/var/www/html/'
    os.system(cmd)
    cmd = 'scp net_value2021.html root@vps.yeshiwei.com:/var/www/html/'
    os.system(cmd)
    cmd = 'scp net_value_prod.html root@vps.yeshiwei.com:/var/www/html/'
    os.system(cmd)

if __name__ == "__main__":
    make()
    make15()
    make15('2021')
    make_yifeng()
    if len(sys.argv) == 2 and sys.argv[1] == 'send':
        send()
