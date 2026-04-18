import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';

const APP_ROOT = path.resolve(__dirname, '../..');
const REPO_ROOT = path.resolve(APP_ROOT, '..');
const WINDOWS_SUPPORT_DIR = path.join(APP_ROOT, 'windows');
const WINDOWS_PROGRAM_DATA = process.env.ProgramData || path.join(process.env.SystemDrive || 'C:', 'ProgramData');
const WINDOWS_LOCAL_APP_DATA = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || WINDOWS_PROGRAM_DATA, 'AppData', 'Local');
const LEGACY_CONFIG_CANDIDATES = [
  path.join(APP_ROOT, 'config.json'),
  path.join(process.cwd(), 'config.json'),
];

const configuredBaseDir = process.env.RISCO_BASE_DIR;
const defaultBaseDir = (() => {
  if (configuredBaseDir) return configuredBaseDir;
  if (process.platform === 'win32') {
    const supervised = process.env.RISCO_SUPERVISED === '1' || (process.env.RISCO_SERVICE_MODE && process.env.RISCO_SERVICE_MODE !== 'standalone');
    const rootDir = supervised ? WINDOWS_PROGRAM_DATA : WINDOWS_LOCAL_APP_DATA;
    return path.join(rootDir, 'RiscoGateway');
  }
  if (fs.existsSync('/data')) return '/data';
  return path.join(REPO_ROOT, 'runtime');
})();

const defaultDataDir = process.platform === 'win32'
  ? path.join(defaultBaseDir, 'data')
  : path.join(defaultBaseDir, 'data');

function resolveExistingPath(candidates: string[], fallback: string): string {
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }
  return fallback;
}

const DATA_DIR = process.env.RISCO_DATA_DIR || defaultDataDir;
const CONFIG_PATH = process.env.RISCO_CONFIG_FILE || process.env.RISCO_MQTT_HA_CONFIG_FILE || resolveExistingPath(
  [
    path.join(DATA_DIR, 'config.json'),
    ...LEGACY_CONFIG_CANDIDATES,
  ],
  path.join(DATA_DIR, 'config.json'),
);
const DEFAULT_CONFIG_PATH = process.env.RISCO_DEFAULT_CONFIG_FILE || process.env.RISCO_MQTT_HA_DEFAULT_CONFIG || resolveExistingPath(
  [
    path.join(APP_ROOT, 'config.default.json'),
    path.join(REPO_ROOT, 'runtime', 'config.default.json'),
  ],
  path.join(APP_ROOT, 'config.default.json'),
);
const PUBLIC_DIR = process.env.RISCO_PUBLIC_DIR || path.join(APP_ROOT, 'public');
const USERS_FILE = path.join(DATA_DIR, 'users.json');
const LOGS_DIR = path.join(defaultBaseDir, 'logs');
const HOST_IP_SCRIPT = process.env.RISCO_HOST_IP_SCRIPT || (
  process.platform === 'win32'
    ? path.join(WINDOWS_SUPPORT_DIR, 'set-host-ip.ps1')
    : path.join(REPO_ROOT, 'scripts', 'set-ip-rpi.sh')
);
const SYNC_FIREWALL_SCRIPT = path.join(WINDOWS_SUPPORT_DIR, 'sync-firewall-rules.ps1');
const RESTART_EXIT_CODE = Number(process.env.RISCO_RESTART_EXIT_CODE || 17);
const SERVICE_MODE = process.env.RISCO_SERVICE_MODE || 'standalone';
const APP_PACKAGE_PATH = path.join(APP_ROOT, 'package.json');

export interface RuntimePaths {
  appRoot: string;
  repoRoot: string;
  windowsSupportDir: string;
  dataDir: string;
  configPath: string;
  defaultConfigPath: string;
  publicDir: string;
  usersFile: string;
  logsDir: string;
  hostIpScript: string;
}

export interface PlatformInfo {
  platform: NodeJS.Platform;
  nodeVersion: string;
  appVersion: string;
  serviceMode: string;
  supervised: boolean;
  traySupported: boolean;
  hostIpSupported: boolean;
  dataDir: string;
  configPath: string;
  publicDir: string;
  uptimeSeconds: number;
}

export interface HostIpChangeRequest {
  ip: string;
  cidr: number;
  gateway: string;
  interfaceAlias?: string;
}

export function getRuntimePaths(): RuntimePaths {
  return {
    appRoot: APP_ROOT,
    repoRoot: REPO_ROOT,
    windowsSupportDir: WINDOWS_SUPPORT_DIR,
    dataDir: DATA_DIR,
    configPath: CONFIG_PATH,
    defaultConfigPath: DEFAULT_CONFIG_PATH,
    publicDir: PUBLIC_DIR,
    usersFile: USERS_FILE,
    logsDir: LOGS_DIR,
    hostIpScript: HOST_IP_SCRIPT,
  };
}

function getAppVersion(): string {
  try {
    const raw = fs.readFileSync(APP_PACKAGE_PATH, 'utf-8');
    const pkg = JSON.parse(raw);
    return typeof pkg.version === 'string' ? pkg.version : 'unknown';
  } catch {
    return 'unknown';
  }
}

export function getPlatformInfo(): PlatformInfo {
  return {
    platform: process.platform,
    nodeVersion: process.version,
    appVersion: getAppVersion(),
    serviceMode: SERVICE_MODE,
    supervised: process.env.RISCO_SUPERVISED === '1' || SERVICE_MODE !== 'standalone',
    traySupported: process.platform === 'win32',
    hostIpSupported: fs.existsSync(HOST_IP_SCRIPT),
    dataDir: DATA_DIR,
    configPath: CONFIG_PATH,
    publicDir: PUBLIC_DIR,
    uptimeSeconds: Math.floor(process.uptime()),
  };
}

export function ensureRuntimeDirectories() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(LOGS_DIR, { recursive: true });
}

export function enterRuntimeWorkingDirectory() {
  ensureRuntimeDirectories();
  process.chdir(DATA_DIR);
}

export function requestManagedRestart() {
  setTimeout(() => process.exit(RESTART_EXIT_CODE), 500);
}

export function syncFirewallRulesInBackground() {
  if (process.platform !== 'win32') return;
  if (!fs.existsSync(SYNC_FIREWALL_SCRIPT)) return;
  const child = spawn('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    SYNC_FIREWALL_SCRIPT,
    '-AppRoot',
    APP_ROOT,
    '-DataRoot',
    defaultBaseDir,
  ], { detached: true, stdio: 'ignore' });
  child.unref();
}

export function scheduleHostIpChange(request: HostIpChangeRequest): boolean {
  if (!fs.existsSync(HOST_IP_SCRIPT)) return false;

  if (process.platform === 'win32') {
    const args = [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      HOST_IP_SCRIPT,
      '-Ip',
      request.ip,
      '-Cidr',
      String(request.cidr),
      '-Gateway',
      request.gateway,
    ];
    if (request.interfaceAlias) args.push('-InterfaceAlias', request.interfaceAlias);
    const child = spawn('powershell.exe', args, { detached: true, stdio: 'ignore' });
    child.unref();
    return true;
  }

  const args = [HOST_IP_SCRIPT, request.ip, String(request.cidr), request.gateway];
  const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
  const cmd = isRoot ? HOST_IP_SCRIPT : 'sudo';
  const cmdArgs = isRoot ? [request.ip, String(request.cidr), request.gateway] : args;
  const child = spawn(cmd, cmdArgs, { detached: true, stdio: 'ignore' });
  child.unref();
  return true;
}
