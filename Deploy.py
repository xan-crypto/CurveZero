####################################################################################
# @title Deploy script
# @dev uses the starknet cli
# owner addy can be set below
# compiles all contracts and returns contract addys
####################################################################################

import subprocess, time

# compile all
files = [
['starknet-compile', 'Interface/LiquidityProvider.cairo', '--output', 'Compiled/LiquidityProvider_compiled.json', '--abi', 'Compiled/LiquidityProvider_abi.json'],
['starknet-compile', 'Interface/PriceProvider.cairo', '--output', 'Compiled/PriceProvider_compiled.json', '--abi', 'Compiled/PriceProvider_abi.json'],
['starknet-compile', 'Interface/CapitalBorrower.cairo', '--output', 'Compiled/CapitalBorrower_compiled.json', '--abi', 'Compiled/CapitalBorrower_abi.json'],
['starknet-compile', 'Interface/LoanLiquidator.cairo', '--output', 'Compiled/LoanLiquidator_compiled.json', '--abi', 'Compiled/LoanLiquidator_abi.json'],
['starknet-compile', 'Interface/GovenanceToken.cairo', '--output', 'Compiled/GovenanceToken_compiled.json', '--abi', 'Compiled/GovenanceToken_abi.json'],
['starknet-compile', 'Core/InsuranceFund.cairo', '--output', 'Compiled/InsuranceFund_compiled.json', '--abi', 'Compiled/InsuranceFund_abi.json'],
['starknet-compile', 'Core/CZCore.cairo', '--output', 'Compiled/CZCore_compiled.json', '--abi', 'Compiled/CZCore_abi.json'],
['starknet-compile', 'Core/Controller.cairo', '--output', 'Compiled/Controller_compiled.json', '--abi', 'Compiled/Controller_abi.json'],
['starknet-compile', 'Config/Settings.cairo', '--output', 'Compiled/Settings_compiled.json', '--abi', 'Compiled/Settings_abi.json'],
['starknet-compile', 'Testing/ERC20_base.cairo', '--output', 'Compiled/ERC20_base_compiled.json', '--abi', 'Compiled/ERC20_base_abi.json'],
['starknet-compile', 'Testing/Oracle.cairo', '--output', 'Compiled/Oracle_compiled.json', '--abi', 'Compiled/Oracle_abi.json'],
['starknet-compile', 'Config/TrustedAddy.cairo', '--output', 'Compiled/TrustedAddy_compiled.json', '--abi', 'Compiled/TrustedAddy_abi.json']]

for file in files:
    process = subprocess.Popen(file,stdout=subprocess.PIPE,universal_newlines=True)
    while True:
        return_code = process.poll()
        if return_code is not None:
            print('Return code:', return_code, file[1])
            break

# deploy all
owner = '0x00ac1854ff5696a2e83f10da62666dc27d59dd43262bb2ac5fe531f2e93d7dcd'
files = [
['starknet', 'deploy', '--contract', 'Compiled/LiquidityProvider_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/PriceProvider_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/CapitalBorrower_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/LoanLiquidator_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/GovenanceToken_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/InsuranceFund_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/CZCore_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/Controller_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/Settings_compiled.json', '--inputs', owner],
['starknet', 'deploy', '--contract', 'Compiled/ERC20_base_compiled.json', '--inputs', '55534443', '55534443', '1000000000000000000000000', '0', owner],
['starknet', 'deploy', '--contract', 'Compiled/ERC20_base_compiled.json', '--inputs', '4414036', '4414036', '1000000000000000000000000', '0', owner],
['starknet', 'deploy', '--contract', 'Compiled/ERC20_base_compiled.json', '--inputs', '57455448', '57455448', '10000000000000000000000', '0', owner],
['starknet', 'deploy', '--contract', 'Compiled/Oracle_compiled.json', '--inputs', '57455448', '57455448'],
['starknet', 'deploy', '--contract', 'Compiled/TrustedAddy_compiled.json', '--inputs', owner]]
last = files[-1]

for file in files:
    time.sleep(30)
    if file == files[-1]: process = subprocess.Popen(last, stdout=subprocess.PIPE, universal_newlines=True)
    else: process = subprocess.Popen(file,stdout=subprocess.PIPE,universal_newlines=True)
    while True:
        return_code = process.poll()
        if return_code is not None:
            for output in process.stdout.readlines():
                data = output.strip()
                if 'Contract address:' in data:
                    contract_addy = data[data.find(': ')+2:].strip()
                    last.append(contract_addy)
                    print('Return code:', return_code, file[3], contract_addy)
            break
