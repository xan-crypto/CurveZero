####################################################################################
# @title WebAppUpdater.py
# @dev This script will update the S3 on aws to ensure prod web app has latest data
# the type of data updated will be
# - loan / earn / stake rates
# - static data e.g. number of lenders / borrowers
# - price data e.g. price of ETH LPT for portfolio graph
# over time this updater will be responsible for most of the charts/graphs on the web app
# @author xan-crypto
####################################################################################

import time
import boto3
import requests
import pandas as pd
pd.set_option('display.max_rows', 500)
pd.set_option('display.max_columns', 500)
pd.set_option('display.width', 1000)
pd.set_option("precision", 9)
import numpy as np
from datetime import datetime as dt
from json import loads, load, dumps
from starknet_py.contract import Contract
from starknet_py.net.gateway_client import GatewayClient
from retrying import retry
from scipy.interpolate import interp1d
import os

# on local instance
if os.name =='nt':
    os.chdir('C://Users//Xan//PycharmProjects//Cario//Services//OffchainPublisher')

# aws S3 session
session = boto3.Session(region_name='eu-west-1')
s3 = session.resource('s3')
# graphql
url = "https://starknet-archive.hasura.app/v1/graphql"

# testnet client
client = GatewayClient("testnet")
# all parameters
rates_loan_ts, rates_loan_wait = 0, 3600
data_static_ts, data_static_wait = 0, 3600
rates_earn_stake_ts, rates_earn_stake_wait = 0, 86400
data_prices_ts, data_prices_wait = 0, 86400
graphs_ts, graphs_wait = 0, 86400
run_every = 60
wait = 1
czt_price = 1.27

# getting all the contract addys
file = open('./addys.json')
addys = load(file)
file.close()
s3object = s3.Object('curvezero', 'json/data_static.json')
data_static = loads(s3object.get()['Body'].read())

# pre construct all the contracts that we will need
pp = Contract.from_address_sync(addys['pp'], client)
czcore = Contract.from_address_sync(addys['czcore'], client)
settings = Contract.from_address_sync(addys['settings'], client)
oracle = Contract.from_address_sync(addys['oracle'], client)
lp = Contract.from_address_sync(addys['lp'], client)

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def getContractData(contract, call, data=None):
    time.sleep(wait)
    if data == None: result = contract.functions[call].call_sync()
    else: result = contract.functions[call].call_sync(data)
    return result

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def getS3Data(s3object):
    time.sleep(wait)
    return loads(s3object.get()['Body'].read())

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def putS3Data(s3object, data, msg):
    time.sleep(wait)
    result = s3object.put(Body=data)
    print(dt.utcnow(), msg)
    return result

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def getGraphQLData(url, query):
    time.sleep(wait)
    response = requests.post(url, json={'query': query})
    response = loads(response.content.decode())
    temp = pd.DataFrame.from_dict(response['data']['event'])
    return temp

def processGraphQLData(temp,cols):
    df = pd.DataFrame(columns=cols)
    for index,row in temp.iterrows():
        df.at[index, 'ts'] = row['transaction']['block']['timestamp']
        df.at[index, 'block'] = row['transaction']['block_number']
        for item in row['arguments']:
            if item['name'] == 'addy': df.at[index, 'addy'] = item['value']
            else: df.at[index, item['name']] = int(item['decimal'])
    return df

def fillData(df, data):
    df['date'] = pd.to_datetime(df.date)
    df['ts'] = df.date.values.astype(np.int64) // 10 ** 9
    allts = np.arange(int(df.iloc[0]['ts']), int(time.time()), 86400)
    temp = pd.DataFrame(allts, columns=['date'])
    for item in data:
        temp[item[0]] = df[item[0]]
        temp.loc[temp.index >= len(df), item[0]] = item[1]
    temp['date'] = pd.to_datetime(temp.date, unit='s')
    temp['date'] = temp['date'].astype(str)
    temp = temp[-182:].reset_index(drop=True)
    return temp.to_json(orient='table', index=False)

# main prog
while True:

    # get and store rates for loan yield curve (15mins)
    if time.time() > rates_loan_ts:
        rates_loan_ts = time.time() + rates_loan_wait
        try:
            curve_pts = getContractData(pp,"get_curve_points").data
            if len(curve_pts) >= 2:
                x, y = [], []
                for pt in curve_pts[0::2]: x.append((pt/10**8 - time.time())/86400)
                for pt in curve_pts[1::2]: y.append(pt/10**8)
                linFn = interp1d(x, y, kind='linear')
                df = pd.DataFrame(columns=['days', 'rate'])
                df['days'] = range(0, int(x[-1]))
                df['rate'] = linFn(df['days'].values)
                rates_loan = df.to_json(orient='table', index=False)
                s3object = s3.Object('curvezero', 'json/rates_loan.json')
                result = putS3Data(s3object, rates_loan, 'Updated curve points')
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    # get and store static data for web app (hourly)
    if time.time() > data_static_ts:
        data_static_ts = time.time() + data_static_wait
        s3object = s3.Object('curvezero', 'json/data_static.json')
        data_static = getS3Data(s3object)

        # update lenders
        try:
            lenders = pd.read_csv('./lenders.csv')
            lastBlock = lenders.iloc[-1]['block']
        except:
            lenders = pd.DataFrame()
            lastBlock = 0
        query = """query {event(where: {name: {_eq: "event_lp_deposit_withdraw"}, transmitter_contract: {_eq:"""+'"'+addys['lp'].replace("0x0","0x")+'"'+"""}, transaction: {block_number: {_gt:"""+str(lastBlock)+"""}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
        try:
            temp = getGraphQLData(url, query)
            temp = processGraphQLData(temp,['ts','block','addy','lp_change','capital_change','lp_price','type'])
            lenders = lenders.append(temp)
            lenders = lenders.sort_values(by='block',ascending=True).reset_index(drop=True)
            lenders.to_csv('./lenders.csv', index=False)
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

        # count unique lenders
        lenders.loc[lenders.type==0,'capital_change'] = -lenders.loc[lenders.type==0,'capital_change']
        lenders = lenders[['addy','capital_change']].groupby(by="addy").sum()
        count = len(lenders.loc[lenders.capital_change>=0.01*10**8])
        data_static['lenders'] = count

        # update borrowers
        try:
            borrowers = pd.read_csv('./borrowers.csv')
            lastBlock = borrowers.iloc[-1]['block']
        except:
            borrowers = pd.DataFrame()
            lastBlock = 0
        query1 = """query {event(where: {name: {_eq: "event_cb_loan_book"}, transmitter_contract: {_eq:"""+'"'+addys['cb'].replace("0x0","0x")+'"'+"""}, transaction: {block_number: {_gt:"""+str(lastBlock)+"""}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
        query2 = """query {event(where: {name: {_eq: "event_ll_loan_book"}, transmitter_contract: {_eq:"""+'"'+addys['ll'].replace("0x0","0x")+'"'+"""}, transaction: {block_number: {_gt:"""+str(lastBlock)+"""}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
        try:
            temp = getGraphQLData(url, query1)
            temp = processGraphQLData(temp, ['ts', 'block', 'addy', 'notional', 'collateral', 'start_ts', 'reval_ts', 'end_ts','rate', 'hist_accrual', 'hist_repay', 'liquidate_me'])
            borrowers = borrowers.append(temp)
            temp = getGraphQLData(url, query2)
            temp = processGraphQLData(temp, ['ts', 'block', 'addy', 'notional', 'collateral', 'start_ts', 'reval_ts', 'end_ts','rate', 'hist_accrual', 'hist_repay', 'liquidate_me'])
            borrowers = borrowers.append(temp)
            borrowers = borrowers.sort_values(by='block',ascending=True).reset_index(drop=True)
            borrowers.to_csv('./borrowers.csv', index=False)
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

        # count unique borrowers
        borrowers = borrowers[['addy','notional']].groupby(by="addy").last()
        count = len(borrowers.loc[borrowers.notional >= 0.01*10**8])
        data_static['borrowers'] = count

        # update stakers
        try:
            stakers = pd.read_csv('./stakers.csv')
            lastBlock = stakers.iloc[-1]['block']
        except:
            stakers = pd.DataFrame()
            lastBlock = 0
        query = """query {event(where: {name: {_eq: "event_gt_stake_unstake_claim"}, transmitter_contract: {_eq:"""+'"'+addys['gt'].replace("0x0","0x")+'"'+"""}, transaction: {block_number: {_gt:"""+str(lastBlock)+"""}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
        try:
            temp = getGraphQLData(url, query)
            temp = processGraphQLData(temp, ['ts', 'block', 'addy', 'amount', 'type'])
            stakers = stakers.append(temp)
            stakers = stakers.sort_values(by='block',ascending=True).reset_index(drop=True)
            stakers.to_csv('./stakers.csv', index=False)
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

        # count unique stakers
        stakers.loc[stakers.type==0,'amount'] = -stakers.loc[stakers.type==0,'amount']
        stakers = stakers.loc[(stakers.type==0) | (stakers.type==1)]
        stakers = stakers[['addy','amount']].groupby(by="addy").sum()
        count = len(stakers.loc[stakers.amount>=0.01*10**8])
        data_static['stakers'] = count

        # update avg_loan_rate
        try:
            result = getContractData(czcore,"get_accrued_interest")
            data_static['avg_loan_rate'] = result.wt_avg_rate/10**8
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

        # update settings data
        try:
            accrued_interest = getContractData(settings,"get_accrued_interest_split")
            origination = getContractData(settings,"get_origination_fee")
            deposit = getContractData(settings,"get_min_max_deposit")
            max_capital = getContractData(settings, "get_max_capital")
            loan = getContractData(settings, "get_min_max_loan")
            max_term = getContractData(settings, "get_max_loan_term")
            weth_liquidation_ratio = getContractData(settings, "get_weth_liquidation_ratio")
            weth_ltv = getContractData(settings, "get_weth_ltv")
            weth_liquidation_fee = getContractData(settings, "get_weth_liquidation_fee")
            utilization = getContractData(settings, "get_utilization")
            # update all, ok if fails together
            data_static['accrued_interest_split'] = {"LP":accrued_interest.lp_split/10**8,"IF":accrued_interest.if_split/10**8,"GT":accrued_interest.gt_split/10**8}
            data_static['origination_fee_split'] = {"Fee":origination.fee/10**8,"DF":origination.df_split/10**8,"IF":origination.if_split/10**8}
            data_static['min_deposit'] = deposit.min_deposit / 10 ** 8
            data_static['max_deposit'] = deposit.max_deposit / 10 ** 8
            data_static['min_loan'] = loan.min_loan / 10 ** 8
            data_static['max_loan'] = loan.max_loan / 10 ** 8
            data_static['max_capital'] = max_capital.max_capital / 10 ** 8
            data_static['max_loan_term'] = max_term.max_term / (86400 * 10 ** 8)
            data_static['weth_liquidation_ratio'] = weth_liquidation_ratio.ratio / 10 ** 8
            data_static['weth_ltv'] = weth_ltv.ltv / 10 ** 8
            data_static['weth_liquidation_fee'] = weth_liquidation_fee.fee / 10 ** 8
            data_static['max_utilization'] = utilization.stop / 10 ** 8
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

        # save data in right format
        result = putS3Data(s3object, dumps(data_static), 'Updated static data')

    # get and store rates for earn & stake graph (daily)
    if time.time() > rates_earn_stake_ts:
        rates_earn_stake_ts = time.time() + rates_earn_stake_wait
        s3object_earn = s3.Object('curvezero', 'json/rates_earn.json')
        s3object_stake = s3.Object('curvezero', 'json/rates_stake.json')
        rates_earn = getS3Data(s3object_earn)
        rates_stake = getS3Data(s3object_stake)
        temp_earn = pd.json_normalize(rates_earn, record_path=['data'])
        temp_stake = pd.json_normalize(rates_stake, record_path=['data'])
        try:
            accrued_interest = getContractData(czcore,"get_accrued_interest")
            czstate = getContractData(czcore, "get_cz_state")
            staker_total = getContractData(czcore, "get_staker_total")
            utilization = czstate.loan_total/czstate.capital_total
            current_earn = utilization*accrued_interest.wt_avg_rate/10**8* data_static['accrued_interest_split']['LP']
            total_stake = staker_total.stake_total/10**8*czt_price
            if total_stake == 0: current_stake = 0.00
            else: current_stake = czstate.loan_total / 10 ** 8 * accrued_interest.wt_avg_rate / 10 ** 8 * data_static['accrued_interest_split']['GT']/total_stake
            new_temp_earn = fillData(temp_earn,[('rate',current_earn)])
            result = putS3Data(s3object_earn, new_temp_earn, 'Updated earn rates')
            new_temp_stake = fillData(temp_stake,[('rate',current_stake)])
            result = putS3Data(s3object_stake, new_temp_stake, 'Updated stake rates')
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    # get and store daily price data for portfolio graph (daily)
    # ETH USDC CZT LPT
    if time.time() > data_prices_ts:
        data_prices_ts = time.time() + data_prices_wait
        s3object = s3.Object('curvezero', 'json/data_prices.json')
        data_prices = getS3Data(s3object)
        temp = pd.json_normalize(data_prices, record_path=['data'])
        try:
            eth = getContractData(oracle,"get_oracle_price").price/10**18
            usdc = 1
            czt = czt_price
            lpt = getContractData(lp, "value_lp_token").lp_price / 10 ** 8
            new_temp = fillData(temp,[('ETH',eth),('USDC',usdc),('CZT',czt),('LPT',lpt)])
            result = putS3Data(s3object, new_temp, 'Updated price data')
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    """
    # create depo/withdraw graph loan graph and stake graph
    if time.time() > graphs_ts:
        graphs_ts = time.time() + graphs_wait
        s3object = s3.Object('curvezero', 'json/graph_earn.json')
        lenders = pd.read_csv('./lenders.csv')
        lenders = lenders.loc[lenders.ts > time.time()-86400*365].reset_index(drop=True)
        temp = pd.DataFrame(columns=['type','date','amount'])
        for index,row in lenders.iterrows():
            type = 'Deposit' if row['type'] == 1 else 'Withdraw'
            date = dt.fromtimestamp(row['ts']).strftime("%b")
            amount = row['capital_change']/10**8 if row['type'] == 1 else -row['capital_change']/10**8
            temp = temp.append({'type':type,'date':date,'amount':amount},ignore_index=True)
            df = temp.groupby(['date','type']).sum()

        pd.DatetimeIndex(pd.to_datetime(lenders.ts,unit='s'))[0].month()

        lenders['capital_change'] = lenders['capital_change']/10**8
        try:
            eth = getContractData(oracle,"get_oracle_price").price/10**18
            usdc = 1
            czt = czt_price
            lpt = getContractData(lp, "value_lp_token").lp_price / 10 ** 8
            new_temp = fillData(temp,[('ETH',eth),('USDC',usdc),('CZT',czt),('LPT',lpt)])
            result = putS3Data(s3object, new_temp, 'Updated price data')
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass
    """


    time.sleep(run_every)