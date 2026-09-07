'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {COMMENT_MARKER, publishPreviewComment} = require('./preview-comment.cjs');

const headSha = 'a'.repeat(40);
const buildSha = 'b'.repeat(40);
const deploymentUrl = 'https://1234abcd.castletaste-minedart.pages.dev';
const aliasUrl = 'https://pr-10.castletaste-minedart.pages.dev';

function fixture() {
  const calls = [];
  const state = {
    comments: [],
    statuses: [{
      context: 'Cloudflare Pages preview',
      state: 'success',
      target_url: deploymentUrl,
    }],
    pullRequest: {
      number: 10,
      state: 'open',
      head: {sha: headSha, repo: {id: 123}},
      base: {ref: 'main', repo: {id: 123}},
    },
  };
  const listComments = () => assert.fail('Comments must be paginated');
  const github = {
    paginate: async (method, args) => {
      assert.equal(method, listComments);
      assert.deepEqual(args, {
        owner: 'castletaste', repo: 'minedart', issue_number: 10, per_page: 100,
      });
      calls.push({method: 'list'});
      return state.comments;
    },
    rest: {
      issues: {
        listComments,
        createComment: async (args) => {
          calls.push({method: 'create', args});
          return {data: {html_url: 'https://github.com/castletaste/minedart/pull/10#issuecomment-1'}};
        },
        updateComment: async (args) => {
          calls.push({method: 'update', args});
          return {data: {html_url: 'https://github.com/castletaste/minedart/pull/10#issuecomment-1'}};
        },
      },
      repos: {
        getCombinedStatusForRef: async (args) => {
          assert.deepEqual(args, {owner: 'castletaste', repo: 'minedart', ref: headSha});
          calls.push({method: 'status'});
          return {data: {statuses: state.statuses}};
        },
      },
      pulls: {
        get: async (args) => {
          assert.deepEqual(args, {owner: 'castletaste', repo: 'minedart', pull_number: 10});
          calls.push({method: 'pull'});
          return {data: state.pullRequest};
        },
      },
    },
  };
  const input = {
    github,
    context: {
      ref: 'refs/heads/main',
      repo: {owner: 'castletaste', repo: 'minedart'},
      payload: {repository: {id: 123, default_branch: 'main'}},
    },
    prNumber: 10,
    headSha,
    buildSha,
    sourceRunId: 456,
    deploymentUrl,
    aliasUrl,
  };
  return {input, state, calls};
}

function botComment(body = `${COMMENT_MARKER}\nPrevious build`) {
  return {
    id: 789,
    user: {login: 'github-actions[bot]', type: 'Bot'},
    body,
    html_url: 'https://github.com/castletaste/minedart/pull/10#issuecomment-789',
  };
}

test('creates a preview comment with immutable and alias URLs and distinct SHAs', async () => {
  const {input, calls} = fixture();
  const result = await publishPreviewComment(input);
  assert.equal(result.action, 'created');
  assert.deepEqual(calls.map((call) => call.method), ['list', 'status', 'pull', 'create']);
  const {args} = calls.at(-1);
  assert.equal(args.owner, 'castletaste');
  assert.equal(args.repo, 'minedart');
  assert.equal(args.issue_number, 10);
  assert.ok(args.body.startsWith(`${COMMENT_MARKER}\n`));
  assert.ok(args.body.includes(`[Open this build](${deploymentUrl})`));
  assert.ok(args.body.includes(`[Latest PR preview](${aliasUrl})`));
  assert.ok(args.body.includes(`PR head: \`${headSha}\``));
  assert.ok(args.body.includes(`Tested build: \`${buildSha}\``));
  assert.ok(args.body.includes('https://github.com/castletaste/minedart/actions/runs/456'));
});

test('updates the existing marked bot comment without creating another', async () => {
  const {input, state, calls} = fixture();
  state.comments = [botComment()];
  const result = await publishPreviewComment(input);
  assert.equal(result.action, 'updated');
  assert.equal(calls.at(-1).method, 'update');
  assert.equal(calls.at(-1).args.comment_id, 789);
  assert.equal(calls.some((call) => call.method === 'create'), false);
});

test('an identical rerun does not rewrite the comment', async () => {
  const {input, state, calls} = fixture();
  await publishPreviewComment(input);
  const comment = botComment(calls.at(-1).args.body);
  state.comments = [comment];
  calls.length = 0;
  const result = await publishPreviewComment(input);
  assert.deepEqual(result, {action: 'unchanged', commentUrl: comment.html_url});
  assert.deepEqual(calls.map((call) => call.method), ['list', 'status', 'pull']);
});

test('never edits human, other bot, unmarked, or quoted-marker comments', async () => {
  const {input, state, calls} = fixture();
  state.comments = [
    {...botComment(), user: {login: 'castletaste', type: 'User'}},
    {...botComment(), user: {login: 'other[bot]', type: 'Bot'}},
    {...botComment(), user: {login: 'github-actions[bot]', type: 'User'}},
    botComment('Unrelated automation result'),
    botComment(`Quoted: ${COMMENT_MARKER}\nPrevious build`),
    {id: 890, body: null},
  ];
  assert.equal((await publishPreviewComment(input)).action, 'created');
  assert.equal(calls.at(-1).method, 'create');
});

test('closed and superseded PR heads leave the existing comment alone', async () => {
  for (const change of [
    (pr) => { pr.state = 'closed'; },
    (pr) => { pr.head.sha = 'c'.repeat(40); },
  ]) {
    const {input, state, calls} = fixture();
    state.comments = [botComment()];
    change(state.pullRequest);
    assert.equal((await publishPreviewComment(input)).action, 'skipped');
    assert.deepEqual(calls.map((call) => call.method), ['list', 'status', 'pull']);
  }
});

test('a pending, failed, absent, or newer preview status blocks stale comments', async () => {
  for (const statuses of [
    [],
    [{context: 'Another check', state: 'success', target_url: deploymentUrl}],
    [{context: 'Cloudflare Pages preview', state: 'pending', target_url: deploymentUrl}],
    [{context: 'Cloudflare Pages preview', state: 'failure', target_url: deploymentUrl}],
    [{context: 'Cloudflare Pages preview', state: 'success',
      target_url: 'https://8765dcba.castletaste-minedart.pages.dev'}],
  ]) {
    const {input, state, calls} = fixture();
    state.statuses = statuses;
    assert.equal((await publishPreviewComment(input)).action, 'skipped');
    assert.deepEqual(calls.map((call) => call.method), ['list', 'status']);
  }
});

test('rejects foreign repositories and mismatched PRs before any write', async () => {
  for (const change of [
    (pr) => { pr.head.repo.id = 999; },
    (pr) => { pr.base.repo.id = 999; },
    (pr) => { pr.number = 11; },
  ]) {
    const {input, state, calls} = fixture();
    change(state.pullRequest);
    await assert.rejects(publishPreviewComment(input), /pull request changed/);
    assert.deepEqual(calls.map((call) => call.method), ['list', 'status', 'pull']);
  }
});

test('invalid URLs, identifiers, and nondefault refs fail before accessing GitHub', async () => {
  for (const change of [
    (input) => { input.deploymentUrl = 'https://example.com'; },
    (input) => { input.aliasUrl = 'https://pr-11.castletaste-minedart.pages.dev'; },
    (input) => { input.prNumber = -1; },
    (input) => { input.headSha = 'short'; },
    (input) => { input.buildSha = 'B'.repeat(40); },
    (input) => { input.sourceRunId = 0; },
    (input) => { input.sourceRunId = Number.MAX_SAFE_INTEGER + 1; },
    (input) => { input.context.ref = 'refs/heads/untrusted'; },
  ]) {
    const {input, calls} = fixture();
    change(input);
    await assert.rejects(publishPreviewComment(input));
    assert.deepEqual(calls, []);
  }
});

test('API failures propagate without retrying a possibly completed write', async () => {
  const {input, calls} = fixture();
  input.github.rest.issues.createComment = async () => {
    calls.push({method: 'create'});
    throw new Error('GitHub unavailable');
  };
  await assert.rejects(publishPreviewComment(input), /GitHub unavailable/);
  assert.deepEqual(calls.map((call) => call.method), ['list', 'status', 'pull', 'create']);
});
