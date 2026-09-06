'use strict';

const fs = require('node:fs');
const path = require('node:path');

const SOURCE_WORKFLOW_PATH = '.github/workflows/deploy-web.yml';
const SOURCE_WORKFLOW_NAMES = new Set([
  'Deploy Minedart web',
  'Verify and deploy Minedart web',
]);
const SOURCE_ARTIFACT_PATTERN = /^minedart-web-([0-9a-f]{40})$/;
const PREVIEW_PROJECT_HOST = 'castletaste-minedart.pages.dev';

const ALLOWED_ROOT_FILES = new Set([
  '_headers',
  'favicon.png',
  'flutter.js',
  'flutter_bootstrap.js',
  'flutter_service_worker.js',
  'index.html',
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
  'manifest.json',
  'version.json',
]);
const ALLOWED_ROOT_DIRECTORIES = new Set(['assets', 'canvaskit', 'icons']);
const REQUIRED_ROOT_FILES = new Set([
  '_headers',
  'flutter_bootstrap.js',
  'index.html',
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
]);
const FORBIDDEN_NAMES = new Set([
  '_routes.json',
  '_worker.js',
  '_worker.js.map',
  'bun.lock',
  'bun.lockb',
  'functions',
  'package-lock.json',
  'package.json',
  'pnpm-lock.yaml',
  'wrangler.json',
  'wrangler.jsonc',
  'wrangler.toml',
  'yarn.lock',
]);

function fail(message) {
  throw new Error(message);
}

function requirePositiveSafeInteger(value, label) {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    fail(`${label} must be a positive safe integer`);
  }
  return parsed;
}

function requireSha(value, label) {
  if (typeof value !== 'string' || !/^[0-9a-f]{40}$/.test(value)) {
    fail(`${label} must be a lowercase 40-character SHA`);
  }
  return value;
}

function requireSinglePullRequestNumber(run) {
  if (!Array.isArray(run?.pull_requests) || run.pull_requests.length !== 1) {
    fail('source run must belong to exactly one pull request');
  }
  return requirePositiveSafeInteger(
    run.pull_requests[0]?.number,
    'pull request number',
  );
}

function validatePreviewSource({
  repository,
  expectedWorkflow,
  run,
  pullRequest,
  artifacts,
}) {
  const repositoryId = requirePositiveSafeInteger(
    repository?.id,
    'repository id',
  );
  const workflowId = requirePositiveSafeInteger(
    expectedWorkflow?.id,
    'workflow id',
  );
  const runId = requirePositiveSafeInteger(run?.id, 'source run id');
  const prNumber = requireSinglePullRequestNumber(run);

  if (expectedWorkflow?.path !== SOURCE_WORKFLOW_PATH) {
    fail('trusted source workflow path is unexpected');
  }
  if (
    run?.workflow_id !== workflowId ||
    run?.path !== SOURCE_WORKFLOW_PATH ||
    !SOURCE_WORKFLOW_NAMES.has(run?.name)
  ) {
    fail('source run did not execute the trusted web build workflow');
  }
  if (run?.event !== 'pull_request' || run?.status !== 'completed') {
    fail('source run must be a completed pull_request run');
  }
  if (run?.conclusion !== 'success') {
    fail('source run must have succeeded');
  }
  if (
    run?.repository?.id !== repositoryId ||
    run?.head_repository?.id !== repositoryId
  ) {
    fail('source run must build a branch from this repository');
  }

  if (pullRequest?.number !== prNumber || pullRequest?.state !== 'open') {
    fail('source pull request must still be open');
  }
  if (
    pullRequest?.base?.repo?.id !== repositoryId
  ) {
    fail('source pull request must target this repository');
  }
  if (pullRequest?.head?.repo?.id !== repositoryId) {
    fail('fork pull requests cannot publish previews');
  }
  const headSha = requireSha(run?.head_sha, 'source head SHA');
  if (pullRequest?.head?.sha !== headSha) {
    fail('source run is stale for the current pull request head');
  }

  if (!Array.isArray(artifacts)) fail('artifact response must be an array');
  const candidates = artifacts.filter((artifact) =>
    artifact?.name?.startsWith('minedart-web-'),
  );
  if (candidates.length !== 1) {
    fail('source run must contain exactly one Minedart web artifact');
  }
  const artifact = candidates[0];
  const nameMatch = SOURCE_ARTIFACT_PATTERN.exec(artifact.name);
  if (nameMatch === null) fail('source artifact name has an invalid build SHA');
  if (artifact.expired === true) fail('source artifact has expired');
  if (
    artifact?.workflow_run?.id !== runId ||
    artifact?.workflow_run?.repository_id !== repositoryId ||
    artifact?.workflow_run?.head_repository_id !== repositoryId ||
    artifact?.workflow_run?.head_sha !== headSha
  ) {
    fail('source artifact provenance does not match the source run');
  }

  return Object.freeze({
    runId,
    prNumber,
    headSha,
    buildSha: nameMatch[1],
    artifactId: requirePositiveSafeInteger(artifact.id, 'artifact id'),
  });
}

function validateCurrentPullRequest({repository, pullRequest, prNumber, headSha}) {
  const repositoryId = requirePositiveSafeInteger(
    repository?.id,
    'repository id',
  );
  if (
    pullRequest?.number !== requirePositiveSafeInteger(prNumber, 'PR number') ||
    pullRequest?.state !== 'open' ||
    pullRequest?.head?.repo?.id !== repositoryId ||
    pullRequest?.base?.repo?.id !== repositoryId ||
    pullRequest?.head?.sha !== requireSha(headSha, 'expected head SHA')
  ) {
    fail('pull request changed after preview validation');
  }
}

function parseStaticPagesUrl(value, label) {
  if (typeof value !== 'string') fail('preview URL must be a string');
  let url;
  try {
    url = new URL(value.trim());
  } catch (_) {
    fail(`${label} is invalid`);
  }
  if (
    url.protocol !== 'https:' ||
    url.port !== '' ||
    url.username !== '' ||
    url.password !== '' ||
    (url.pathname !== '' && url.pathname !== '/') ||
    url.search !== '' ||
    url.hash !== ''
  ) {
    fail(`${label} must be a bare HTTPS origin`);
  }
  return url;
}

function validatePreviewUrls({deploymentUrl, aliasUrl, prNumber}) {
  const immutable = parseStaticPagesUrl(
    deploymentUrl,
    'immutable deployment URL',
  );
  const alias = parseStaticPagesUrl(aliasUrl, 'preview alias URL');
  const expectedAliasHost = `pr-${requirePositiveSafeInteger(
    prNumber,
    'PR number',
  )}.${PREVIEW_PROJECT_HOST}`;
  if (alias.hostname !== expectedAliasHost) {
    fail('preview URL does not match the expected Cloudflare branch alias');
  }
  const deploymentLabel = immutable.hostname.slice(
    0,
    -(PREVIEW_PROJECT_HOST.length + 1),
  );
  if (
    !immutable.hostname.endsWith(`.${PREVIEW_PROJECT_HOST}`) ||
    !/^[a-z0-9](?:[a-z0-9-]{6,62}[a-z0-9])$/.test(deploymentLabel) ||
    deploymentLabel === `pr-${prNumber}`
  ) {
    fail('deployment URL is not an immutable Cloudflare Pages URL');
  }
  return Object.freeze({
    deploymentUrl: `https://${immutable.hostname}`,
    aliasUrl: `https://${expectedAliasHost}`,
  });
}

function validatePathSegment(segment) {
  const lower = segment.toLowerCase();
  if (
    segment.length === 0 ||
    segment.length > 255 ||
    segment.startsWith('.') ||
    /[\u0000-\u001f\u007f]/.test(segment) ||
    FORBIDDEN_NAMES.has(lower) ||
    lower.startsWith('wrangler.')
  ) {
    fail(`unsafe artifact path segment: ${JSON.stringify(segment)}`);
  }
}

function sanitizeArtifact(
  sourceDirectory,
  destinationDirectory,
  {
    maxFiles = 20000,
    maxFileBytes = 25 * 1024 * 1024,
    maxTotalBytes = 256 * 1024 * 1024,
  } = {},
) {
  const source = path.resolve(sourceDirectory);
  const destination = path.resolve(destinationDirectory);
  if (source === destination || destination.startsWith(`${source}${path.sep}`)) {
    fail('sanitized destination must be outside the source artifact');
  }
  const sourceStat = fs.lstatSync(source);
  if (!sourceStat.isDirectory() || sourceStat.isSymbolicLink()) {
    fail('source artifact must be a real directory');
  }
  if (fs.existsSync(destination)) fail('sanitized destination already exists');

  const files = [];
  let totalBytes = 0;
  const presentRootFiles = new Set();

  function walk(relativeDirectory) {
    const absoluteDirectory = path.join(source, relativeDirectory);
    const entries = fs.readdirSync(absoluteDirectory).sort();
    for (const name of entries) {
      validatePathSegment(name);
      const relativePath = path.join(relativeDirectory, name);
      if (relativePath.length > 1024) fail('artifact path is too long');
      const absolutePath = path.join(source, relativePath);
      const stat = fs.lstatSync(absolutePath);
      if (stat.isSymbolicLink()) fail(`artifact contains symlink: ${relativePath}`);

      if (relativeDirectory === '') {
        if (stat.isDirectory() && !ALLOWED_ROOT_DIRECTORIES.has(name)) {
          fail(`unexpected artifact root directory: ${name}`);
        }
        if (stat.isFile() && !ALLOWED_ROOT_FILES.has(name)) {
          fail(`unexpected artifact root file: ${name}`);
        }
      }

      if (stat.isDirectory()) {
        walk(relativePath);
        continue;
      }
      if (!stat.isFile()) fail(`artifact contains special file: ${relativePath}`);
      if (stat.size > maxFileBytes) {
        fail(`artifact file exceeds the size limit: ${relativePath}`);
      }
      totalBytes += stat.size;
      if (totalBytes > maxTotalBytes) fail('artifact exceeds the total size limit');
      files.push(relativePath);
      if (relativeDirectory === '') presentRootFiles.add(name);
      if (files.length > maxFiles) fail('artifact exceeds the file count limit');
    }
  }

  walk('');
  for (const required of REQUIRED_ROOT_FILES) {
    if (!presentRootFiles.has(required)) {
      fail(`artifact is missing required file: ${required}`);
    }
    if (fs.statSync(path.join(source, required)).size === 0) {
      fail(`required artifact file is empty: ${required}`);
    }
  }

  fs.mkdirSync(destination);
  for (const relativePath of files) {
    const target = path.join(destination, relativePath);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.copyFileSync(
      path.join(source, relativePath),
      target,
      fs.constants.COPYFILE_EXCL,
    );
  }
  return Object.freeze({fileCount: files.length, totalBytes});
}

if (require.main === module) {
  const [, , command, source, destination] = process.argv;
  if (command !== 'sanitize' || !source || !destination) {
    console.error('Usage: node preview-artifact-policy.cjs sanitize SOURCE DEST');
    process.exitCode = 2;
  } else {
    const result = sanitizeArtifact(source, destination);
    console.log(
      `Sanitized ${result.fileCount} static files (${result.totalBytes} bytes).`,
    );
  }
}

module.exports = {
  SOURCE_WORKFLOW_PATH,
  requireSinglePullRequestNumber,
  sanitizeArtifact,
  validateCurrentPullRequest,
  validatePreviewSource,
  validatePreviewUrls,
};
