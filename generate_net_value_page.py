import pandas as pd
import sys
import os
import numpy as np

filename = '/mnt/c/Users/abstr/Dropbox/myQuant/CTA/FundReport.xlsx'
def make():
    df = pd.read_excel(filename, sheet_name = '样本外周度', names = ['date', 'net_value'],
                    header=1)
    df['net_value'] = [round(float(a), 3) for a in df['net_value']]
    weeklyReturn = []
    for i in range(1, len(df)):
        weeklyReturn.append(df['net_value'].iloc[i]/df['net_value'][i-1] - 1)
    sharpe = np.mean(weeklyReturn)*np.sqrt(52)/np.std(weeklyReturn)
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
    df = pd.read_excel(filename, sheet_name = '阶段二', header = 0)
    ytd = "%.2f%%"%(list(df['YTD'])[-1]*100)
    draw_down_str = str(draw_down)
    template = open('net_value_template.html').read()
    template = template.replace('dates_pos', date_str)
    template = template.replace('net_value_pos', data_str)
    template = template.replace('draw_down_pos', draw_down_str)
    template = template.replace('YTD', ytd)
    fp = open('net_value.html','w')
    fp.write(template)
    fp.close()

def send():
    cmd = 'scp net_value.html root@vps.yeshiwei.com:/var/www/html/'
    os.system(cmd)

if __name__ == "__main__":
    make()
    if len(sys.argv) == 2 and sys.argv[1] == 'send':
        send()
