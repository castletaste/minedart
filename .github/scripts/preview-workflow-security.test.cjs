'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const workflow = fs.readFileSync(
  path.join(repositoryRoot, '.github/workflows/deploy-pr-preview.yml'),
  'utf8',
);
const productionWorkflow = fs.readFileSync(
  path.join(repositoryRoot, '.github/workflows/deploy-web.yml'),
  'utf8',
);
const lockfile = JSON.parse(
  fs.readFileSync(
    path.join(repositoryRoot, '.github/preview-tools/package-lock.json'),
    'utf8',
  ),
);

test('installs the locked Wrangler before any Cloudflare credential is exposed', () => {
  const installStep = workflow.indexOf(
    '- name: Install pinned Wrangler without deployment credentials',
  );
  const credential = workflow.indexOf('secrets.CLOUDFLARE_API_TOKEN');
  const deployAction = workflow.indexOf(
    'cloudflare/wrangler-action@ebbaa1584979971c8614a24965b4405ff95890e0',
  );

  assert.ok(installStep >= 0);
  assert.ok(credential > installStep);
  assert.ok(deployAction > installStep);
  assert.match(
    workflow.slice(installStep, deployAction),
    /working-directory: trusted-source\/.github\/preview-tools[\s\S]*npm ci --ignore-scripts --no-audit --no-fund/,
  );
  assert.match(
    workflow.slice(deployAction),
    /workingDirectory: trusted-source\/.github\/preview-tools[\s\S]*wranglerVersion: 4\.125\.0/,
  );
  assert.match(workflow.slice(deployAction), /NPM_CONFIG_OFFLINE: "true"/);
  assert.match(
    workflow.slice(installStep, deployAction),
    /Recheck current PR head immediately before deployment[\s\S]*validateCurrentPullRequest/,
  );
});

test('locks Wrangler and every fetched package by registry integrity', () => {
  assert.equal(lockfile.lockfileVersion, 3);
  assert.equal(lockfile.packages[''].dependencies.wrangler, '4.125.0');
  assert.equal(lockfile.packages['node_modules/wrangler'].version, '4.125.0');

  for (const [name, descriptor] of Object.entries(lockfile.packages)) {
    if (name === '' || descriptor.link) continue;
    assert.match(descriptor.resolved, /^https:\/\/registry\.npmjs\.org\//);
    assert.match(descriptor.integrity, /^sha512-/);
  }
});

test('fails artifact verification closed and reports the immutable deployment', () => {
  assert.equal(workflow.match(/digest-mismatch: error/g)?.length, 2);
  assert.doesNotMatch(workflow, /deployments:\s*write/);
  assert.match(workflow, /target_url: preview\.deploymentUrl/);
  assert.match(workflow, /\[{data: 'Branch alias', header: true}, preview\.aliasUrl\]/);
});

test('production also installs locked Wrangler before exposing credentials', () => {
  const installStep = productionWorkflow.indexOf(
    '- name: Install pinned Wrangler without deployment credentials',
  );
  const credential = productionWorkflow.indexOf(
    'secrets.CLOUDFLARE_API_TOKEN',
  );
  const deployAction = productionWorkflow.indexOf(
    'cloudflare/wrangler-action@ebbaa1584979971c8614a24965b4405ff95890e0',
  );
  const uploadStep = productionWorkflow.indexOf(
    '- name: Upload verified web bundle',
  );
  const downloadStep = productionWorkflow.indexOf(
    '- name: Download verified web bundle',
  );

  assert.ok(installStep >= 0);
  assert.ok(credential > installStep);
  assert.ok(deployAction > installStep);
  assert.ok(downloadStep > uploadStep);
  assert.match(
    productionWorkflow,
    /if: github\.event_name != 'pull_request' && github\.ref == 'refs\/heads\/main'/,
  );
  assert.match(
    productionWorkflow.slice(installStep, deployAction),
    /working-directory: trusted-source\/.github\/preview-tools[\s\S]*npm ci --ignore-scripts --no-audit --no-fund/,
  );
  assert.match(
    productionWorkflow.slice(deployAction),
    /NPM_CONFIG_OFFLINE: "true"[\s\S]*workingDirectory: trusted-source\/.github\/preview-tools[\s\S]*wranglerVersion: 4\.125\.0/,
  );
  assert.match(
    productionWorkflow,
    /pages deploy \$\{\{ github\.workspace \}\}\/app\/build\/web/,
  );
  assert.doesNotMatch(
    productionWorkflow.slice(uploadStep, downloadStep),
    /digest-mismatch:/,
  );
  assert.match(
    productionWorkflow.slice(downloadStep, installStep),
    /digest-mismatch: error/,
  );
});

test('the unprivileged build runs for stacked pull request bases', () => {
  assert.match(productionWorkflow, /\n  pull_request:\n\npermissions:/);
});
