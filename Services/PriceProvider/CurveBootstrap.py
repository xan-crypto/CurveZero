####################################################################################
# @title CurveBootstrap.py
# @dev This script will bootstrap the crypto native USD yield curve
# since there is no well defined USD yield curve in crypto, below is how we suggest the bootstrap process be done
# we will use the following rates to build a 5y crypto native USD yield curve
# - AAVE will be used for ON rate
# - Deribit futures will be used for 0-1yr, because of the option market, the longer dated futures here should be more representative of rates
# - deribit is also longer term vs binance / ftx which maxs out at about 6 months
# - Post 1yr we will use a ratioed shift from US treasuries, we will use 0.5/1/2/3/5 US treasury rates
# - the ratioed shift should be appropriate because the treasuries are risk free so the shape should be correct
# - the CurveZero curve is based on over collateralisation hence there should also be no market risk
# - by using the shift from the 1y pt we will capture the native crypto premium but maintain the risk free shape
# @author xan-crypto
####################################################################################

import ccxt
import json
import numpy as np
import pandas as pd
import requests
import time
import investpy
from matplotlib import pyplot as plt

# @dev aave ON rate on USDC - get from graphql
def get_aave_on(_yc):
    query = """ query {reserves(where: {id: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb480xb53c1a33016b2dc2ff3653530bff1848a515c8c5"}) {name averageStableRate stableBorrowRate variableBorrowRate}} """
    response = requests.request('post', 'https://api.thegraph.com/subgraphs/name/aave/protocol-v2',json={'query': query})
    response = json.loads(response.content)
    _yc = _yc.append({'source': 'aave','type': 'on','term': 1,'rate': int(response['data']['reserves'][0]['variableBorrowRate']) / 10 ** 27}, ignore_index=True)
    return _yc

# @dev deribit for the futs
def get_deribit_futs(_yc):
    deribit = ccxt.deribit({'rateLimit': 100, 'options': {'adjustForTimeDifference': True}, 'enableRateLimit': True})
    tickers = deribit.public_get_get_instruments({'currency':'BTC','kind':'future', 'expired': False})['result']
    index = float(deribit.public_get_get_index({'currency':'BTC'})['result']['BTC'])
    now = time.time()
    for ticker in tickers:
        if ticker['settlement_period'] != 'perpetual':
            price = deribit.public_get_ticker({'instrument_name':ticker['instrument_name']})
            mid_price = (float(price['result']['best_bid_price']) + float(price['result']['best_ask_price']))*0.5
            term = (float(ticker['expiration_timestamp'])/1000-now)/86400
            # @dev to prevent distorts vs ON from aave
            if term > 60:
                rate = (mid_price/index)**(365/term)-1
                _yc = _yc.append({'source': 'deribit','type': 'futs','term': term,'rate': rate}, ignore_index=True)
    _yc = _yc.sort_values(by='term')
    return _yc

# @dev investing for treasury bonds
def get_investing_tbonds(_yc):
    tb = investpy.bonds.get_bonds_overview('united states', as_json=False)
    index = tb.loc[tb.name=='U.S. 5Y'].index[0]
    tb = tb[0:index+1]
    tb['last'] = tb['last']/100
    tb['term'] = 0.0
    for i,row in tb.iterrows():
        if row['name'][-1] == 'M': tb.at[i, 'term'] = int(row['name'][-3:-1])/12*365
        elif row['name'][-1] == 'Y': tb.at[i, 'term'] = int(row['name'][-3:-1])*365
    # @dev find base line for extrapolation
    base = np.interp(_yc.iloc[-1]['term'], tb['term'].values, tb['last'].values)
    multiplier = _yc.iloc[-1]['rate']/base
    for i,row in tb.iterrows():
        if row['term'] > _yc.iloc[-1]['term']:
            _yc = _yc.append({'source': 'investing','type': 'bond','term': row['term'],'rate': row['last']*multiplier}, ignore_index=True)
    return _yc

def bootstrap_yc():
    _yc = pd.DataFrame(columns=['source', 'type', 'term', 'rate'])
    _yc = get_aave_on(_yc)
    _yc = get_deribit_futs(_yc)
    _yc = get_investing_tbonds(_yc)
    _yc['yfrac'] = _yc.term / 365
    return _yc

# @dev plot curve
yc = bootstrap_yc()
plt.plot(yc.yfrac.values, yc.rate.values)
plt.axis([0,5,0,0.1])
plt.ylabel('rate')
plt.xlabel('year')
plt.show()
print(yc)
