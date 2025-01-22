import pandas as pd
import sys
import os
import numpy as np
import datetime as dt
from tabulate import tabulate
pd.options.mode.chained_assignment = None 

#filename = '/mnt/d/code/CTA/fundreport.xlsx'
filename = '/mnt/d/OneDrive/001我的Quant/data/fundreport.xlsx'
DAY_COUNT_OF_YEAR = 245
WEEK_COUNT_OF_YEAR = 52
YEAYLY_RISK_FREE_RATE = 0.0

def generate_page(template_filename, output_filename, df, period = 'week'):
    #print('-' * 80)
    df = df.loc[df['date'] <= dt.datetime.today()]
    df = df.dropna(subset = ['date', 'net_value']).copy()
    df.index = range(len(df))
    df.loc[:,'net_value'] = df['net_value']/df['net_value'].iloc[0]
    df.loc[:,'net_value'] = [round(float(a), 3) for a in df['net_value']]
    periodReturn = []
    for i in range(1, len(df)):
        periodReturn.append(df['net_value'].iloc[i]/df['net_value'][i-1] - 1)
    year_period_count = WEEK_COUNT_OF_YEAR
    if period == 'week':
        year_period_count = WEEK_COUNT_OF_YEAR
    elif period == 'day':
        year_period_count = DAY_COUNT_OF_YEAR
    risk_free_rate = YEAYLY_RISK_FREE_RATE / DAY_COUNT_OF_YEAR

    vol = np.std(periodReturn) * np.sqrt(year_period_count)
    sharpe = ((np.mean(periodReturn) - risk_free_rate)*np.sqrt(year_period_count) )/np.std(periodReturn)
    
    period_risk_free_return = YEAYLY_RISK_FREE_RATE / year_period_count
    return_tp = []
    for pr in periodReturn:
        if pr < period_risk_free_return:
            return_tp.append( pr - period_risk_free_return )
    sortino =  ((np.mean(periodReturn) - risk_free_rate ) *np.sqrt(year_period_count))/np.std(return_tp)
    def makedata(df):
        date_str = str(list([d.date().strftime('%Y-%m-%d') for d in df['date']]))
        data_str = str(list(df['net_value']))
        draw_down = [0]
        net_value = list(df['net_value'])
        pre_max = net_value[0]
        pre_max_index = 0
        max_draw_down_recovery = 0
        for i in range(1, len(net_value)):
            if net_value[i] > pre_max:
                pre_max = net_value[i]
                draw_down_recovery = i - pre_max_index
                if draw_down_recovery > max_draw_down_recovery:
                    max_draw_down_recovery = draw_down_recovery
                    #print("i", i, "ddr", draw_down_recovery, "mddr", max_draw_down_recovery, "pmi", pre_max_index)
                pre_max_index = i
            draw_down.append(round(-100*(1-net_value[i]/pre_max), 3))
        current_drawdown_period = len(net_value) - pre_max_index
        if current_drawdown_period > max_draw_down_recovery:
            print("Last draw down is not recoved, and have lasts %d periods."%current_drawdown_period)
        return date_str, data_str, draw_down, max_draw_down_recovery
    
    date_str, data_str, draw_down, max_draw_down_recovery = makedata(df)

    yearly_return = df['net_value'].iloc[-1]**(year_period_count/len(df)) - 1
    max_draw_down = - min(draw_down) / 100

    calmar = (yearly_return - YEAYLY_RISK_FREE_RATE) / max_draw_down

    df.loc[:, 'year'] = [d.year for d in df['date']]
    last_year = df['year'].iloc[-1] - 1
    if last_year in set(df['year']):
        df_last_year = df.loc[df['year'] == last_year]
        ytd = df['net_value'].iloc[-1] / df_last_year['net_value'].iloc[-1] - 1
    else:
        ytd = df['net_value'].iloc[-1] - 1
    ytd = "%.2f%%"%(ytd * 100)

    last_year = df['year'].iloc[-1]
    df_last_year = df.loc[df['year'] == last_year]
    # df_last_year 前面加上上一年的最后一天的数据.
    df_pre_year = df.loc[df['year'] == last_year - 1]
    df_last_year = pd.concat([df_pre_year.iloc[-1:], df_last_year])
    df_last_year.index = range(len(df_last_year))
    df_last_year.loc[:,'net_value'] = df_last_year.loc[:,'net_value'] / df_last_year.loc[0,'net_value']
    last_year_date_str, last_year_data_str, last_year_draw_down, _ = makedata(df_last_year)
    last_year_draw_down_str = str(last_year_draw_down)

    max_single_period_drawdwon = (0 if min(periodReturn)>0 else -min(periodReturn))

    print("sharpe:%.2f"%sharpe, "vol:%.3f"%vol, 'last date:', df['date'].iloc[-1].date(), "ytd:", ytd, 
    "mdd:%.3f"%max_draw_down, "sortino: %.3f"%sortino, "calmar: %.3f"%calmar, 'yearly return: %.2f%%'%(100*yearly_return),
    "max single k draw down:%.2f%%"%(100 * max_single_period_drawdwon), "max draw down recovery:", max_draw_down_recovery)

    stats = {"sharpe": sharpe,
            "vol":vol,
            "last_date": df['date'].iloc[-1].date(),
            "ytd":ytd,
            "mdd":max_draw_down,
            "sortino":sortino,
            "calmar":calmar,
            "yearly_return":yearly_return,
            "max_single_k_draw_down":max_single_period_drawdwon,
            "max_draw_down_recovery":max_draw_down_recovery}

    draw_down_str = str(draw_down)
    template = open(template_filename).read()
    
    # last year = 今年.
    template = template.replace('last_year_dates_pos', last_year_date_str)
    template = template.replace('last_year_net_value_pos', last_year_data_str)
    template = template.replace('last_year_draw_down_pos', last_year_draw_down_str)

    template = template.replace('dates_pos', date_str)
    template = template.replace('net_value_pos', data_str)
    template = template.replace('draw_down_pos', draw_down_str)
    
    template = template.replace('YTD', ytd)
    comments =  open("net_value_comment.html").read()
    if output_filename == 'net_value25.html':
        comments += '\n						<li>2021年初我将目标波动率从11%调整成了18%。</li>'
    template = template.replace('comments_pos', comments)
    
    yetan = open("net_value_yetan.html").read()
    template = template.replace('yetan_pos', yetan)
    fp = open(output_filename,'w')
    fp.write(template)
    fp.close()
    print('='*80)
    df.loc[:,['date', 'net_value']].to_csv(output_filename.replace("html", "csv"), index = False)
    return stats

def make_outsample(output_filename = 'net_value_weekly15.html', start_date = '2020-01-01', leverage_up_2021 = False):
    df = pd.read_excel(filename, sheet_name = '样本外周度', names = ['date', 'net_value'], na_values=['#REF!'],
                    header=1)
    df = df.loc[df['date']>start_date]
    print('since %s, weekly:'%(start_date))
    if leverage_up_2021:
        return generate_page('net_value_template.html', 'net_value25.html', df)

    start2021 = list(df['date']).index(dt.datetime(2021,1,8))
    nav = []
    nav_start2021 = df['net_value'].iloc[start2021]
    for i in range(len(df['net_value'])):
        if i <= start2021:
            nav.append(df['net_value'].iloc[i])
        else:
            nav_item = (df['net_value'].iloc[i] - nav_start2021) * 3 / 5 + nav_start2021
            nav.append(nav_item)
    df.loc[:,'net_value'] = nav
    df = df.drop_duplicates(subset=['date'])
    return generate_page('net_value_template.html', output_filename, df)

def make15(start_time = '2020'):
    sheet_name = '2020年以后'
    print("filename:", filename, "sheet:", sheet_name)
    # df = pd.read_excel(filename, sheet_name = sheet_name, names = ['date', 'nav'],
    #                header=0, na_values=['#REF!'])
    df = pd.read_excel(filename, sheet_name = sheet_name, names = ['date', 'nav'],
                    header=0)
    print("data: ", df.head())
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
    df.loc[:, 'net_value'] = nav
    df = df.drop_duplicates(subset=['date'])
    if start_time == '2021':
        df = df.iloc[start2021:]
        print("since 2021, 15% vol:")     
        return generate_page('net_value_template2.html', 'net_value2021.html', df, 'day')
    else:
        print("since 2020, 15% vol:")
        return generate_page('net_value_template2.html', 'net_value.html', df, 'day')
 
def make_yifeng():
    df = pd.read_excel('/mnt/d/code/cfmmc_crawler/翼丰贝叶斯CTA一号私募证券投资基金.xlsx', converters = {'date':str})
    df = df.dropna()
    df = df.sort_values("date")
    df = df.drop_duplicates(subset=['date'])
    df.loc[:, 'date'] = df['date'].apply(lambda d: dt.datetime.strptime(d, "%Y%m%d"))
    print("yifeng product:")
    return generate_page('net_value_template3.html', 'net_value_prod.html', df, 'day')
    
def make_yifeng_week():
    df = pd.read_excel('/mnt/d/code/CTA/翼丰贝叶斯CTA一号产品净值表（数据更新至20220610）.xls', header = 1, converters = {'估值日期':str})
    df = df.rename({"估值日期":"date", "累计单位净值":"net_value"}, axis = 1)
    df['date'] = df['date'].apply(lambda x: x.split(" ")[0])
    df['date'] = df['date'].apply(lambda x: "".join(x.split("-")))
    df = df.dropna()
    df = df.sort_values("date")
    df = df.drop_duplicates(subset=['date'])
    df.loc[:, 'date'] = df['date'].apply(lambda d: dt.datetime.strptime(d, "%Y%m%d"))
    df = df.sort_values(by = "date", ascending=True)
    print("yifeng product:")
    return generate_page('net_value_template3.html', 'net_value_prod_week.html', df, 'week')

def send():
    files = ['net_value.html', 'net_value25.html', 'net_value_weekly15.html', 'net_value_weekly15_full.html', 'net_value2021.html', 'net_value_prod.html', 'net_value_prod_week.html']
    net_value_list = [ '<li><a href = "%s">%s</a></li>\n'%(x, x.split(".")[0]) for x in files]
    '''
    net_value_list_page = open("net_value_list_template.html").read().replace("net_value_list", "".join(net_value_list))
    fp = open("net_value_list.html", 'w')
    fp.write(net_value_list_page)
    fp.close()
    files.append('net_value_list.html')
    '''
    for filename in files:
        cmd = 'scp %s ubuntu@vps.yeshiwei.com:/var/www/html/cta/'%(filename)
        os.system(cmd)
        if filename != 'net_value_list.html':
            filename = filename.replace("html", "csv")
            cmd = 'scp %s ubuntu@vps.yeshiwei.com:/var/www/html/cta/'%(filename)
            os.system(cmd)
    print("send done.")
    
if __name__ == "__main__":
    data = {}
    data["2020年以来标准产品"] = make15()
    data["2021年以来标准产品"] = make15('2021')
    print("*" * 18 + "周度原始" + "*" * 18)
    data["2020年以来实际自营周度"] = make_outsample(None, "2020-01-01", True)
    print("*" * 18 + " 周度标准 " + "*" * 18)
    data["2020年以来标准自营周度"] = make_outsample()
    data["2018年以来标准产品周度"] = make_outsample('net_value_weekly15_full.html', '2018-01-01')
    #data["翼丰产品"] = make_yifeng()
    #data["翼丰周度"] = make_yifeng_week()
    df = pd.DataFrame(data).T
    print(tabulate(df, headers='keys', tablefmt='psql'))
    df.to_excel("/mnt/d/code/CTA/stats_result.xlsx")
    if len(sys.argv) == 2 and sys.argv[1] == 'send':
        send()
