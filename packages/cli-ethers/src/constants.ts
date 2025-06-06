import { join } from 'path'

// Initialize Network Data
const CHAIN_ID = '5124'
const WEBSOCKET_URL = 'wss://node-2.seismicdev.net/ws'

// Initialize Contract Data
const FACTORY_CONTRACT_NAME = 'GoatZKCPFactory'
const JUDGE_CONTRACT_NAME = 'GoatZKCPJudge'
const LOCK_CONTRACT_NAME = 'Lock'
const VERIFIER_CONTRACT_NAME = 'Groth16Verifier'
const CONTRACT_DIR = join(__dirname, '../../../packages/contracts')

export { CHAIN_ID, WEBSOCKET_URL, FACTORY_CONTRACT_NAME, JUDGE_CONTRACT_NAME, LOCK_CONTRACT_NAME, VERIFIER_CONTRACT_NAME, CONTRACT_DIR }