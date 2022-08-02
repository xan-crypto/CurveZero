####################################################################################
# @title LiquidationService.py
# @dev This script will construct the loan bond and liquidate any loan that trigger below the liquidation threshold
# in time there will be a competitive market for liquidations
# the liqudation fee is currently set to 5% but mkt participants have suggested even 10% might be appropriate
# use rest to update existing data if any... then ws
# @author xan-crypto
###################################################################################

import time
import boto3
import requests
import pandas as pd
pd.set_option('display.max_rows', 500)
pd.set_option('display.max_columns', 500)
pd.set_option('display.width', 1000)
pd.set_option("precision", 9)
from datetime import datetime as dt
from json import loads, load
from starknet_py.contract import Contract
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net import AccountClient, KeyPair
from retrying import retry

# aws ssm
ssm_client = boto3.client('ssm', region_name='eu-west-1')
keys = ssm_client.get_parameters(Names=['LoanLiquidator'], WithDecryption=True).get("Parameters")[0].get("Value")
pub_key, pvt_key = keys.split('_pvt_')

# create client account
client = GatewayClient("testnet")
account_client = AccountClient(
    client=client,
    address="0x023C58f1fE36813778D7bF2b48893E38651a1C1B7D1E77705f09c07507e8C274",
    key_pair=KeyPair(private_key=int(pvt_key),public_key=int(pub_key)))

# graphql
url = "https://starknet-archive.hasura.app/v1/graphql"
# testnet client
client = GatewayClient("testnet")
# all parameters
data_static_ts, data_static_wait = 0, 86400
liquidation_ts, liquidation_wait = 0, 3600
run_every = 60
wait = 1
max_fee = int(10**16)

# getting all the contract addys
file = open('./addys.json')
addys = load(file)
file.close()
# lenders/borrowers/stakers data
global loans, liquidations
# pre construct all the contracts that we will need
settings = Contract.from_address_sync(client=account_client, address=addys['settings'])
oracle = Contract.from_address_sync(client=account_client, address=addys['oracle'])
ll = Contract.from_address_sync(client=account_client, address=addys['ll'])
usdc = Contract.from_address_sync(client=account_client, address=addys['usdc'])
# amm = Contract.from_address_sync('jediswap', client)

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def incAllowance():
    time.sleep(wait)
    result = usdc.functions["ERC20_allowance"].call_sync(owner=int(pub_key), spender=int(addys['czcore'], 16))
    if result.remaining/10**18 < 10**7:
        usdc.functions["ERC20_increaseAllowance"].invoke_sync(spender=int(addys['czcore'], 16),added_value={"low": int(10 ** 7 * 10 ** 18),"high": 0}, max_fee=max_fee)
    return

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def getContractData(contract, call, data=None):
    time.sleep(wait)
    if data is None: _result = contract.functions[call].call_sync()
    else: _result = contract.functions[call].call_sync(data)
    return _result

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def getGraphQLData(_url, _query):
    time.sleep(wait)
    response = requests.post(_url, json={'query': _query})
    response = loads(response.content.decode())
    _temp = pd.DataFrame.from_dict(response['data']['event'])
    return _temp

def getStaticData():
    weth_liquidation_ratio = getContractData(settings, "get_weth_liquidation_ratio")
    grace_period = getContractData(settings, "get_grace_period")
    _static_data = {"weth_liquidation_ratio":weth_liquidation_ratio.ratio / 10 ** 8,
                    "grace_period":grace_period.period / 10 ** 8}
    return _static_data

def processGraphQLData(temp,cols):
    df = pd.DataFrame(columns=cols)
    for index,row in temp.iterrows():
        df.at[index, 'ts'] = row['transaction']['block']['timestamp']
        df.at[index, 'block'] = row['transaction']['block_number']
        for item in row['arguments']:
            if item['name'] == 'addy': df.at[index, 'addy'] = item['value']
            else: df.at[index, item['name']] = int(item['decimal'])
    return df

def updateLoans():
    global loans
    # update loans
    try:
        loans = pd.read_csv('./loans.csv')
        lastBlock = loans.iloc[-1]['block']
    except:
        loans = pd.DataFrame()
        lastBlock = 0
    query = """query {event(where: {name: {_eq: "event_cb_loan_book"}, transmitter_contract: {_eq:""" + '"' + addys['cb'].replace("0x0", "0x") + '"' + """}, transaction: {block_number: {_gt:""" + str(lastBlock) + """}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
    try:
        temp = getGraphQLData(url, query)
        temp = processGraphQLData(temp, ['ts', 'block', 'addy', 'notional','collateral','start_ts','reval_ts','end_ts','rate','hist_accrual','hist_repay','liquidate_me'])
        loans = loans.append(temp)
        loans = loans.sort_values(by='block', ascending=True).reset_index(drop=True)
        loans.to_csv('./loans.csv', index=False)
    except Exception as _e:
        print(dt.utcnow(), 'Error', str(_e))
        pass
    return

def updateLiquidations():
    global liquidations
    # update liquidation
    try:
        liquidations = pd.read_csv('./liquidations.csv')
        lastBlock = liquidations.iloc[-1]['block']
    except:
        liquidations = pd.DataFrame()
        lastBlock = 0
    query = """query {event(where: {name: {_eq: "event_ll_loan_book"}, transmitter_contract: {_eq:""" + '"' + addys['ll'].replace("0x00", "0x") + '"' + """}, transaction: {block_number: {_gt:""" + str(lastBlock) + """}}}, limit: 500, order_by: {transaction: {block: {timestamp: asc}}}) {arguments {name value decimal} transaction{ block_number block {timestamp}}}}"""
    try:
        temp = getGraphQLData(url, query)
        temp = processGraphQLData(temp,['ts', 'block', 'addy', 'notional', 'collateral', 'start_ts', 'reval_ts', 'end_ts','rate', 'hist_accrual', 'hist_repay', 'liquidate_me'])
        liquidations = liquidations.append(temp)
        liquidations = liquidations.sort_values(by='block', ascending=True).reset_index(drop=True)
        liquidations.to_csv('./liquidations.csv', index=False)
    except Exception as e:
        print(dt.utcnow(), 'Error', str(e))
        pass
    return

def buildLoanBook():
    global loans, liquidations
    df = loans.append(liquidations)
    df = df.sort_values(by='block', ascending=True)
    df[['notional','collateral','start_ts','reval_ts','end_ts','rate','hist_accrual','hist_repay']] =df[['notional','collateral','start_ts','reval_ts','end_ts','rate','hist_accrual','hist_repay']]/10**8
    df = df.groupby(by="addy").last()
    df = df.loc[df.notional!=0]
    df['grace_period'] = 0
    df['collateral_value'] = 0
    df['loan_os_lr'] = 0
    eth = getContractData(oracle, "get_oracle_price").price / 10 ** 18
    for index, row in df.iterrows():
        df.at[index, 'accrued_interest'] = max(df.at[index,'notional']-df.at[index,'hist_repay'],0)*(time.time() - df.at[index,'reval_ts'])/(31557600)*df.at[index,'rate']
        df.at[index, 'loan_os'] = df.at[index,'notional'] + df.at[index,'hist_accrual'] + df.at[index,'accrued_interest'] - df.at[index,'hist_repay']
        df.at[index, 'collateral_value'] = df.at[index, 'collateral'] * eth
        df.at[index, 'loan_os_lr'] = df.at[index, 'loan_os'] * static_data["weth_liquidation_ratio"]
        df.at[index, 'grace_period'] = df.at[index, 'end_ts'] + static_data["grace_period"]
    return df

def findLiquidations(df):
    df = df.loc[(df.liquidate_me==1) | (df.grace_period < time.time()) | (df.loan_os_lr > df.collateral_value)]
    return df

@retry(wait_fixed=10000, stop_max_attempt_number=3)
def liquidateThisLoan(contract, user, amount):
    time.sleep(wait)
    result = contract.functions["liquidate_loan"].invoke_sync(user=int(user, 16), amount=amount, max_fee=max_fee)
    print(dt.utcnow(), 'User liquidated',user,amount)
    return result


def liquidateLoan(df):
    for index, row in df.iterrows():
        liquidateThisLoan(contract=ll, user=str(index), amount=int(120000*10**8))
        # need some optimization here
        # how much to liquidate
        # convert some weth to eth if gas balance running low
        # then swap from weth back to usdc before next call
    incAllowance()
    return

# main prog
while True:

    # check periodically if the liquidation ratio / static data has changed
    if time.time() > data_static_ts:
        try:
            static_data = getStaticData()
            data_static_ts = time.time() + data_static_wait
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    # check periodically for liquidation opportunities
    if time.time() > liquidation_ts:
        try:
            updateLoans()
            updateLiquidations()
            loanBook = buildLoanBook()
            insolvent = findLiquidations(loanBook)
            liquidateLoan(insolvent)
            liquidation_ts = time.time() + liquidation_wait
        except Exception as e:
            print(dt.utcnow(), 'Error', str(e))
            pass

    time.sleep(run_every)

for index, row in insolvent.iterrows():
    print(index, row)