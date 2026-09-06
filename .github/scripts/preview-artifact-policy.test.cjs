'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  sanitizeArtifact,
  validateCurrentPullRequest,
  validatePreviewSource,
  validatePreviewUrls,
} = require('./preview-artifact-policy.cjs');

const repository = {
  id: 1345653678,
  default_branch: 'main',
};
const expectedWorkflow = {
  id: 341756850,
  name: 'Deploy Minedart web',
  path: '.github/workflows/deploy-web.yml',
};
const headSha = '48a6cc71fdb804d2b23f89eb05f7e7644265db64';
const buildSha = '2dc348080b0a99ec9d1472cf61606f11a923372b';

function validFixture() {
  const run = {
    id: 34037938388,
    workflow_id: expectedWorkflow.id,
    name: 'Verify and deploy Minedart web',
    path: expectedWorkflow.path,
    event: 'pull_request',
    status: 'completed',
    conclusion: 'success',
    head_sha: headSha,
    repository: {id: repository.id},
    head_repository: {id: repository.id},
    pull_requests: [{number: 5}],
  };
  const pullRequest = {
    number: 5,
    state: 'open',
    head: {sha: headSha, repo: {id: repository.id}},
    base: {ref: 'main', repo: {id: repository.id}},
  };
  const artifacts = [
    {
      id: 9990834806,
      name: `minedart-web-${buildSha}`,
      expired: false,
      digest: 'sha256:example',
      workflow_run: {
        id: run.id,
        repository_id: repository.id,
        head_repository_id: repository.id,
        head_sha: headSha,
      },
    },
  ];
  return {repository, expectedWorkflow, run, pullRequest, artifacts};
}

test('accepts the PR 5 head and its distinct tested merge artifact SHA', () => {
  assert.deepEqual(validatePreviewSource(validFixture()), {
    runId: 34037938388,
    prNumber: 5,
    headSha,
    buildSha,
    artifactId: 9990834806,
  });
});

test('accepts a same-repository stacked base branch', () => {
  const fixture = validFixture();
  fixture.pullRequest.base.ref = 'codex/runtime-ownership-refactor';
  assert.doesNotThrow(() => validatePreviewSource(fixture));
});

test('rejects untrusted, failed, stale, closed, fork, and ambiguous sources', () => {
  const mutations = [
    (fixture) => (fixture.run.workflow_id = 1),
    (fixture) => (fixture.run.path = '.github/workflows/other.yml'),
    (fixture) => (fixture.run.event = 'push'),
    (fixture) => (fixture.run.conclusion = 'failure'),
    (fixture) => (fixture.run.repository.id = 1),
    (fixture) => (fixture.run.head_repository.id = 1),
    (fixture) => (fixture.run.pull_requests = [{number: 5}, {number: 6}]),
    (fixture) => (fixture.pullRequest.state = 'closed'),
    (fixture) => (fixture.pullRequest.head.repo.id = 1),
    (fixture) => (fixture.pullRequest.base.repo.id = 1),
    (fixture) => (fixture.pullRequest.head.sha = 'a'.repeat(40)),
    (fixture) => (fixture.artifacts[0].expired = true),
    (fixture) =>
      fixture.artifacts.push({
        ...fixture.artifacts[0],
        id: 2,
        name: `minedart-web-${'b'.repeat(40)}`,
      }),
    (fixture) => (fixture.artifacts[0].workflow_run.id = 1),
  ];
  for (const mutate of mutations) {
    const fixture = validFixture();
    mutate(fixture);
    assert.throws(() => validatePreviewSource(fixture));
  }
});

test('freshness validation fails after the PR head or state changes', () => {
  const fixture = validFixture();
  assert.doesNotThrow(() =>
    validateCurrentPullRequest({
      repository,
      pullRequest: fixture.pullRequest,
      prNumber: 5,
      headSha,
    }),
  );
  fixture.pullRequest.head.sha = 'a'.repeat(40);
  assert.throws(() =>
    validateCurrentPullRequest({
      repository,
      pullRequest: fixture.pullRequest,
      prNumber: 5,
      headSha,
    }),
  );
});

test('accepts only an immutable URL and the exact HTTPS branch alias', () => {
  assert.deepEqual(
    validatePreviewUrls({
      deploymentUrl: 'https://002794db.castletaste-minedart.pages.dev/',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev/',
      prNumber: 5,
    }),
    {
      deploymentUrl: 'https://002794db.castletaste-minedart.pages.dev',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev',
    },
  );
  const invalid = [
    {
      deploymentUrl: 'https://pr-5.castletaste-minedart.pages.dev',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev',
    },
    {
      deploymentUrl: 'http://002794db.castletaste-minedart.pages.dev',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev',
    },
    {
      deploymentUrl: 'https://002794db.evil.pages.dev',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev',
    },
    {
      deploymentUrl: 'https://002794db.castletaste-minedart.pages.dev',
      aliasUrl: 'https://pr-6.castletaste-minedart.pages.dev',
    },
    {
      deploymentUrl: 'https://002794db.castletaste-minedart.pages.dev/path',
      aliasUrl: 'https://pr-5.castletaste-minedart.pages.dev',
    },
  ];
  for (const urls of invalid) {
    assert.throws(() => validatePreviewUrls({...urls, prNumber: 5}));
  }
});

function withArtifact(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'minedart-preview-test-'));
  const source = path.join(root, 'source');
  const destination = path.join(root, 'sanitized');
  fs.mkdirSync(source);
  const required = [
    '_headers',
    'flutter_bootstrap.js',
    'index.html',
    'main.dart.js',
    'main.dart.mjs',
    'main.dart.wasm',
  ];
  for (const name of required) fs.writeFileSync(path.join(source, name), 'ok');
  fs.mkdirSync(path.join(source, 'assets', 'assets', 'audio'), {
    recursive: true,
  });
  fs.writeFileSync(path.join(source, 'assets', 'AssetManifest.bin'), 'asset');
  fs.writeFileSync(
    path.join(source, 'assets', 'assets', 'audio', 'click.wav'),
    'audio',
  );
  fs.mkdirSync(path.join(source, 'canvaskit'));
  fs.writeFileSync(path.join(source, 'canvaskit', 'canvaskit.wasm'), 'wasm');
  try {
    run({root, source, destination});
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
}

test('sanitizes the current static Flutter artifact shape', () => {
  withArtifact(({source, destination}) => {
    const result = sanitizeArtifact(source, destination);
    assert.equal(result.fileCount, 9);
    assert.equal(
      fs.readFileSync(path.join(destination, 'assets', 'AssetManifest.bin'), 'utf8'),
      'asset',
    );
  });
});

test('rejects server code, tool config, unexpected roots, and symlinks', () => {
  const unsafePaths = [
    '_worker.js',
    'functions/handler.js',
    'wrangler.toml',
    'package.json',
    'unexpected.txt',
    'assets/wrangler.jsonc',
  ];
  for (const unsafePath of unsafePaths) {
    withArtifact(({source, destination}) => {
      const target = path.join(source, unsafePath);
      fs.mkdirSync(path.dirname(target), {recursive: true});
      fs.writeFileSync(target, 'unsafe');
      assert.throws(() => sanitizeArtifact(source, destination));
    });
  }

  withArtifact(({source, destination}) => {
    fs.symlinkSync(path.join(source, 'index.html'), path.join(source, 'assets', 'link'));
    assert.throws(() => sanitizeArtifact(source, destination), /symlink/);
  });
});

test('enforces required files and bounded file, count, and total sizes', () => {
  withArtifact(({source, destination}) => {
    fs.rmSync(path.join(source, 'main.dart.wasm'));
    assert.throws(() => sanitizeArtifact(source, destination), /missing required/);
  });
  withArtifact(({source, destination}) => {
    assert.throws(() =>
      sanitizeArtifact(source, destination, {maxFileBytes: 1}),
    );
  });
  withArtifact(({source, destination}) => {
    assert.throws(() => sanitizeArtifact(source, destination, {maxFiles: 1}));
  });
  withArtifact(({source, destination}) => {
    assert.throws(() =>
      sanitizeArtifact(source, destination, {maxTotalBytes: 1}),
    );
  });
});
