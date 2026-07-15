export const meta = {
  name: 'fix-github-issue',
  description: 'Triage a GitHub issue on CORDOC-LLC/ChessCoach, implement a fix on a branch, and open a PR for review',
  whenToUse: 'Run with args: { issue: <number> } to fix a specific issue, or with no args to pick the oldest open issue automatically. Never merges -- always opens a PR for human review.',
  phases: [
    { title: 'Triage', detail: 'read the issue, reproduce/diagnose, locate the relevant code' },
    { title: 'Implement', detail: 'fix on a branch in an isolated worktree, tests passing' },
    { title: 'Self-review', detail: 'adversarial check: does the diff actually fix the issue, any regressions' },
    { title: 'Open PR', detail: 'push the branch and open a PR referencing the issue' },
  ],
}

const REPO = 'CORDOC-LLC/ChessCoach'
const REPO_PATH = '/Users/kaustubh/Documents/Projects/GemmaChess'

phase('Triage')
const triage = await agent(
  `You're triaging a GitHub issue on the repo ${REPO} (a native iOS/macOS chess coaching app, ` +
  `Swift/SwiftUI, checked out locally at ${REPO_PATH}). ` +
  (args && args.issue
    ? `Fetch issue #${args.issue} with: gh issue view ${args.issue} --repo ${REPO} --json number,title,body,comments,labels`
    : `No specific issue was given -- pick the OLDEST open issue that is not labeled "wontfix" or "duplicate": ` +
      `gh issue list --repo ${REPO} --state open --json number,title,body,labels,createdAt --limit 50, sort by createdAt ascending, ` +
      `and pick the first one that qualifies. If there are zero open issues, say so explicitly and stop -- do not invent one.`) +
  `\n\nOnce you have the issue, cd into ${REPO_PATH} and investigate: read the title/body/comments closely, ` +
  `reproduce the bug in your head against the actual current code (grep/read the relevant files -- do not guess), ` +
  `and form a concrete root-cause hypothesis. Note any ambiguity in the issue (e.g. missing repro steps) as a risk. ` +
  `Do NOT write any code in this phase -- research only.` +
  `\n\nReturn a structured summary: issueNumber, issueTitle, rootCause (specific, cites file:line where possible), ` +
  `filesLikelyInvolved (array of repo-relative paths), planSummary (what the fix should do, 2-4 sentences), ` +
  `risksOrAmbiguity (empty string if none), and reproducible (true/false -- whether you could actually confirm ` +
  `the bug by reading the code, vs. just taking the issue's word for it).`,
  {
    schema: {
      type: 'object',
      properties: {
        issueNumber: { type: 'number' },
        issueTitle: { type: 'string' },
        rootCause: { type: 'string' },
        filesLikelyInvolved: { type: 'array', items: { type: 'string' } },
        planSummary: { type: 'string' },
        risksOrAmbiguity: { type: 'string' },
        reproducible: { type: 'boolean' },
        noOpenIssues: { type: 'boolean' },
      },
      required: ['issueNumber', 'issueTitle', 'rootCause', 'planSummary', 'reproducible'],
    },
  }
)

if (!triage || triage.noOpenIssues) {
  log('No open issue to work on -- stopping.')
  throw new Error('No open GitHub issue available to fix.')
}
log(`Triaged #${triage.issueNumber}: ${triage.issueTitle}`)

phase('Implement')
const branchName = `fix/issue-${triage.issueNumber}`
const implementation = await agent(
  `Implement a fix for GitHub issue #${triage.issueNumber} ("${triage.issueTitle}") on ${REPO}, checked out at ${REPO_PATH}. ` +
  `You're working in your own isolated git worktree -- commit your work there, don't worry about the main checkout. ` +
  `\n\nTriage findings from the previous phase:\n` +
  `- Root cause: ${triage.rootCause}\n` +
  `- Files likely involved: ${(triage.filesLikelyInvolved || []).join(', ') || '(none identified -- find them yourself)'}\n` +
  `- Plan: ${triage.planSummary}\n` +
  (triage.risksOrAmbiguity ? `- Risk/ambiguity noted at triage: ${triage.risksOrAmbiguity}\n` : '') +
  `\n\nVerify the triage's root cause against the actual code before changing anything -- it may be wrong or incomplete. ` +
  `Follow this repo's existing conventions (check CLAUDE.md / .ai/ docs if present, mirror nearby code patterns). ` +
  `Add or update tests that cover the fix. Run the project's test suite (swift test from ${REPO_PATH}, or the ` +
  `relevant subset) and make sure it passes before committing. ` +
  `Create a new branch named "${branchName}" (branch off main) and commit your changes there with a clear, ` +
  `conventional commit message that references "#${triage.issueNumber}". Do not push and do not open a PR -- that's the next phase.` +
  `\n\nReturn: whatWasChanged (2-4 sentences), filesChanged (array of paths), testsPassed (true/false), ` +
  `and testOutput (last ~20 lines of the test run, for the record).`,
  {
    isolation: 'worktree',
    schema: {
      type: 'object',
      properties: {
        whatWasChanged: { type: 'string' },
        filesChanged: { type: 'array', items: { type: 'string' } },
        testsPassed: { type: 'boolean' },
        testOutput: { type: 'string' },
      },
      required: ['whatWasChanged', 'filesChanged', 'testsPassed'],
    },
  }
)

if (!implementation || !implementation.testsPassed) {
  log(`Implementation did not report passing tests for #${triage.issueNumber} -- stopping before opening a PR.`)
  throw new Error(`Fix for issue #${triage.issueNumber} failed tests; not opening a PR.`)
}

phase('Self-review')
const review = await agent(
  `Adversarially review a fix for GitHub issue #${triage.issueNumber} ("${triage.issueTitle}") on the branch ` +
  `"${branchName}" in the repo at ${REPO_PATH} (fetch it if needed: git fetch origin ${branchName} or check the local branch). ` +
  `Diff it against main: git diff main...${branchName}. ` +
  `\n\nOriginal issue root cause per triage: ${triage.rootCause}\n` +
  `What the implementer says they changed: ${implementation.whatWasChanged}\n` +
  `\n\nYour job is to try to refute that this actually fixes the issue: does the diff address the root cause, or just ` +
  `a symptom? Does it introduce any obvious regression, edge case, or break an existing test's intent? Is the fix ` +
  `scoped tightly to the issue (no unrelated changes)? Default to skeptical -- only pass if you're genuinely convinced.` +
  `\n\nReturn: verdict ("pass" or "fail"), reasoning (2-4 sentences), and concerns (array of strings, empty if none).`,
  {
    schema: {
      type: 'object',
      properties: {
        verdict: { type: 'string', enum: ['pass', 'fail'] },
        reasoning: { type: 'string' },
        concerns: { type: 'array', items: { type: 'string' } },
      },
      required: ['verdict', 'reasoning'],
    },
  }
)

if (!review || review.verdict !== 'pass') {
  log(`Self-review failed for #${triage.issueNumber}: ${review ? review.reasoning : 'no review result'}`)
  throw new Error(`Self-review did not pass for issue #${triage.issueNumber}; not opening a PR. Concerns: ${review ? JSON.stringify(review.concerns) : 'n/a'}`)
}

phase('Open PR')
const pr = await agent(
  `Push the branch "${branchName}" (in the repo at ${REPO_PATH} or its worktree -- find wherever the commits for this ` +
  `branch actually live) to origin, and open a PR against main on ${REPO} using the gh CLI (already authenticated). ` +
  `\n\nPR title: a conventional-commit-style summary of the fix (under 70 chars). ` +
  `PR body must include:\n` +
  `- "Fixes #${triage.issueNumber}"\n` +
  `- A short summary of the root cause and the fix (use the triage/implementation findings below)\n` +
  `- A "Test plan" section noting that the test suite passes and what was added/changed\n` +
  `- A note that this PR was opened automatically and should be reviewed before merging\n` +
  `\nRoot cause: ${triage.rootCause}\n` +
  `What changed: ${implementation.whatWasChanged}\n` +
  `Files changed: ${(implementation.filesChanged || []).join(', ')}\n` +
  `\nDo NOT merge the PR. Return the PR URL.`,
  { schema: { type: 'object', properties: { prUrl: { type: 'string' } }, required: ['prUrl'] } }
)

log(`Opened PR for issue #${triage.issueNumber}: ${pr ? pr.prUrl : '(unknown -- check logs)'}`)

return {
  issueNumber: triage.issueNumber,
  issueTitle: triage.issueTitle,
  branchName,
  prUrl: pr ? pr.prUrl : null,
  reviewVerdict: review.verdict,
}
