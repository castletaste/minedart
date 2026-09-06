# Pull request preview deployments

Minedart publishes pull request previews through two separate GitHub Actions
workflows. `.github/workflows/deploy-web.yml` builds and tests pull request code
without credentials. `.github/workflows/deploy-pr-preview.yml` runs from the
default branch after that workflow succeeds and performs the credentialed
Cloudflare Pages upload.

The separation is a security boundary. A [`workflow_run` job can access secrets
even when its source workflow could not][workflow-run], so the publisher never
checks out or executes pull request code. It identifies one artifact by its
source run and immutable artifact ID, rejects stale, closed, ambiguous, and fork
sources, and copies only the expected static Flutter bundle shape. `_worker.js`,
`functions`, Wrangler and package-manager configuration, symlinks, special
files, unexpected root paths, and oversized bundles are rejected before the
credentialed job is eligible to start. The sanitized artifact is passed to a
fresh runner and Wrangler runs [Pages Direct Upload][pages-direct-upload] from
an empty working directory.

Successful previews receive an immutable deployment URL and the stable
Cloudflare branch alias `https://pr-<number>.castletaste-minedart.pages.dev`.
The publisher validates both URLs and attaches the immutable URL as the
`Cloudflare Pages preview` commit status on the exact pull request head. The job
summary also records the branch alias, source run, pull request head SHA, and the
build SHA from the source artifact name. It rechecks the open PR and exact head
immediately before invoking Wrangler. Same-repository stacked pull requests are
supported; the publisher still rejects fork heads and foreign base repositories.

## One-time setup

1. Use the existing GitHub environment named `production` for both publishers.
2. Under **Deployment branches and tags**, choose **Selected branches and
   tags**, then add the exact branch rule `main`. Do not use **Protected
   branches only**: when the repository has no branch-protection rule, GitHub
   allows every branch through that policy. Do not add a tag rule or wildcard.
   The environment API should report
   `deployment_branch_policy.protected_branches: false` and
   `deployment_branch_policy.custom_branch_policies: true`, with exactly one
   custom policy: the branch `main`.
3. Keep the existing `CLOUDFLARE_API_TOKEN` environment secret in `production`.
   The token only needs `Account > Cloudflare Pages > Edit` for the account
   containing the `castletaste-minedart` project. No separate preview token or
   copy of its value is required.
4. Keep `CLOUDFLARE_ACCOUNT_ID` as the existing repository secret.
5. Merge the preview infrastructure before expecting automatic previews.

Verify the exact-`main` deployment policy before enabling the preview publisher.
An environment with no policy is not a safe credential boundary for workflows
stored on other same-repository branches. Keep the deployment token as an
environment secret, not a repository secret.

Both publishers use the same credential, so rotating or revoking it affects both
production and previews. Preview jobs inherit any reviewers and wait timers on
`production`, and GitHub records them in that environment's deployment history.
Their Cloudflare destination remains the `pr-<number>` branch specified in the
publish command. The separate `preview` GitHub environment is not used.

Wrangler `4.125.0` is installed from the trusted, committed lockfile with
`npm ci` and lifecycle scripts disabled before the Cloudflare token is passed
to the pinned deployment action. The action finds that exact local version and
does not install packages in its credentialed step. Artifact downloads
explicitly fail on digest mismatch. Sanitized artifact names include both the
publisher run ID and its attempt number, so **Re-run all jobs** does not collide
with an earlier attempt's immutable artifact. The deployment job consumes the
returned artifact ID. No dependency or artifact cache crosses preview runs.

The production deployment uses the same locked, no-credential installation
boundary. Its workflow guard accepts only `refs/heads/main`, and the shared
`production` environment enforces the exact `main` branch for both publishers.

The workflow does not run retroactively when first added to the default branch.
To bootstrap an already verified pull request, manually run **Publish Minedart
PR preview** from the default branch and provide its successful web-build run
ID. Validation still requires an open same-repository PR at the exact source
head and one unexpired artifact. For PR #5, the verified run observed during
implementation was `34037938388`; its artifact was scheduled to expire at
2026-09-07 14:08:07 UTC. Re-run the unprivileged PR workflow if that artifact is
no longer available.

Preview publication intentionally serves pull request JavaScript on a public
Pages origin. The first version accepts only same-repository pull requests to
bound abuse and Cloudflare quota. A previous verified preview remains available
while a newer head is still building. A GitHub head read and Cloudflare upload
cannot form one atomic operation: a push during the final upload can leave the
branch alias on the preceding verified head until the newer build publishes.
The immutable URL and commit status remain attached to the exact old head, so
they never describe newer content. Closed-preview cleanup is a separate
destructive lifecycle and is not performed by this workflow.

[workflow-run]: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run
[pages-direct-upload]: https://developers.cloudflare.com/pages/get-started/direct-upload/
