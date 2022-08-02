####################################################################################
# @title CurvePublisher.py
# @dev This script will strip and update the yield rate on starknet
# we will use AAVE to FTX as per the price provider bootstrap
# this will later be moved to a defi oracle
# NB this function does not affect the existing loan book, only new business
# @author xan-crypto
####################################################################################

import time
import boto3
import json
import ccxt
import requests
import pandas as pd
from datetime import timezone
from datetime import datetime as dt
from retrying import retry
from starknet_py.contract import Contract
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net import AccountClient, KeyPair

# aws ssm
ssm_client = boto3.client('ssm', region_name='eu-west-1')
keys = ssm_client.get_parameters(Names=['CurvePublisher'], WithDecryption=True).get("Parameters")[0].get("Value")
pub_key, pvt_key = keys.split('_pvt_')

# create client account
client = GatewayClient("testnet")
account_client = AccountClient(
    client=client,
    address="0x06875f16514700b2943bff47846594975e57a28cd64822bd1c9d433676757065",
    key_pair=KeyPair(private_key=int(pvt_key),public_key=int(pub_key)))

# all parameters
curve_avg_ts = 0
curve_avg_wait = 300
publish_ts = 0
publish_wait = 86400
run_every = 60
wait = 1
max_fee = int(10**16)
margin = 0.85
min_term = 21
eno_data = False

# getting all the contract addys
file = open('./addys.json')
addys = json.load(file)
file.close()

# pre construct all the contracts that we will need
pp = Contract.from_address_sync(client=account_client, address=addys['pp'])
# ccxt exchange
ftx = ccxt.ftx({'rateLimit': 100, 'options': {'adjustForTimeDifference': True}, 'enableRateLimit': True})
deribit = ccxt.deribit({'rateLimit': 100, 'options': {'adjustForTimeDifference': True}, 'enableRateLimit': True})

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def setCurvePoints(contract, ts_capture, data_len, data):
    time.sleep(wait)
    result = contract.functions["set_curve_points"].invoke_sync(ts_capture=ts_capture, data_len=data_len, data=data, max_fee=max_fee)
    print(dt.utcnow(), 'Published curve points')
    return result

# @dev aave ON rate on USDC borrow rate - get from graphql
def get_aave_on(_yc):
    query = """ query {reserves(where: {id: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb480xb53c1a33016b2dc2ff3653530bff1848a515c8c5"}) {name averageStableRate stableBorrowRate variableBorrowRate}} """
    response = requests.request('post', 'https://api.thegraph.com/subgraphs/name/aave/protocol-v2',json={'query': query})
    response = json.loads(response.content)
    _yc = _yc.append({'source': 'aave','type': 'on','term': 0,'rate': int(response['data']['reserves'][0]['variableBorrowRate']) / 10 ** 27, 'ts_expiry':time.time()}, ignore_index=True)
    return _yc

# @dev deribit for the spot futs basis
def get_deribit_futs(_yc):
    tickers = deribit.public_get_get_instruments({'currency':'BTC','kind':'future', 'expired': False})['result']
    index = float(deribit.public_get_get_index({'currency':'BTC'})['result']['BTC'])
    now = time.time()
    for ticker in tickers:
        if ticker['settlement_period'] != 'perpetual':
            price = deribit.public_get_ticker({'instrument_name':ticker['instrument_name']})
            mid_price = (float(price['result']['best_bid_price']) + float(price['result']['best_ask_price']))*0.5
            term = (float(ticker['expiration_timestamp'])/1000-now)/86400
            # @dev to prevent distorts vs ON from aave, less than x days on futs can behave strangely
            # since close to expiry spot and futs differences can results in large positive / negative rates
            # spots futs basis is lend side, to get borrow side assume x% of realised cash needed for margin
            if term > min_term:
                rate = ((mid_price/index)**(365/term)-1)/margin
                _yc = _yc.append({'source': 'deribit','type': 'futs','term': term,'rate': rate, "ts_expiry":float(ticker['expiration_timestamp'])/1000}, ignore_index=True)
    return _yc

# @dev ftx for the spot futs basis
def get_ftx_futs(_yc):
    futures = ftx.publicGetFutures()
    now = time.time()
    for ticker in futures['result']:
        if ticker['underlying'] == 'BTC' and ticker['type'] == 'future':
            mid_price = (float(ticker['bid']) + float(ticker['ask']))*0.5
            index = float(ticker['index'])
            datetimeObj = dt.strptime(ticker['expiry'][:-6], '%Y-%m-%dT%H:%M:%S')
            datetimeObj = datetimeObj.replace(tzinfo=timezone.utc)
            term = (datetimeObj.timestamp()-now)/86400
            # @dev to prevent distorts vs ON from aave, less than x days on futs can behave strangely
            # since close to expiry spot and futs differences can results in large positive / negative rates
            # spots futs basis is lend side, to get borrow side assume x% of realised cash needed for margin
            if term > min_term:
                rate = ((mid_price/index)**(365/term)-1)/margin
                _yc = _yc.append({'source': 'ftx','type': 'futs','term': term,'rate': rate, "ts_expiry":datetimeObj.timestamp()}, ignore_index=True)
    return _yc

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def bootstrap_yc():
    _yc = pd.DataFrame(columns=['source', 'type', 'term', 'rate', 'ts_expiry'])
    _yc = get_aave_on(_yc)
    # _yc = get_ftx_futs(_yc)
    _yc = get_deribit_futs(_yc)
    _yc = _yc.sort_values(by='term').reset_index(drop=True)
    return _yc

# main prog
global yc
avg_yc = pd.DataFrame()
last_expiry = 0
while True:

    if time.time() > curve_avg_ts:
        curve_avg_ts = time.time() + curve_avg_wait
        try:
            yc = bootstrap_yc()
            # if num of inst changes, fresh process
            if len(yc) != len(avg_yc.columns) or last_expiry != yc.iloc[-1]["ts_expiry"]: avg_yc = pd.DataFrame()
            avg_yc = avg_yc.append(yc.rate)
            avg_yc = avg_yc[-12:].reset_index(drop=True)
            eno_data = True if len(avg_yc) >= 8 else False
            for index,row in yc.iterrows():
                yc.at[index,'rate'] = avg_yc[index].mean()
            # @dev to prevent arbitrage, the curve will be flat from Aave ON or upward sloping
            # reject any rates below Aave ON
            yc = yc.loc[yc.rate >= yc.iloc[0]['rate']].reset_index(drop=True)
            last_expiry = yc.iloc[-1]["ts_expiry"]
            # print(dt.now(), len(avg_yc))
            # print(yc)
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    if time.time() > publish_ts:
        if eno_data:
            try:
                curve = [0,0,0,0,0,0,0,0]
                pts = len(yc)*2
                for i in range(8-pts,8,2):
                    curve[i] = int(int(yc.at[int(i/2)-1, "ts_expiry"])* 10 ** 8)
                    curve[i+1] = int(yc.at[int(i/2)-1, "rate"] * 10 ** 8)
                print(yc)
                setCurvePoints(contract=pp, ts_capture=int(time.time()) * 10 ** 8, data_len=8, data=curve)
                publish_ts = time.time() + publish_wait
            except Exception as e:
                print(dt.utcnow(), 'Error', str(e))
                pass

    time.sleep(run_every)