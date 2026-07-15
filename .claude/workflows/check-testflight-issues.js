export const meta = {
  name: 'check-testflight-issues',
  description: 'Pull new TestFlight crash reports and tester feedback from App Store Connect, file each as a GitHub issue',
  whenToUse: 'Run periodically (e.g. via /schedule) to keep GitHub issues in sync with what TestFlight testers are hitting. Each new crash/feedback item becomes one issue with a hidden dedup marker, so re-running never files duplicates. Filed issues are picked up naturally by the fix-github-issue workflow -- this workflow never writes code, only files issues.',
  phases: [
    { title: 'Fetch', detail: 'pull crash + screenshot feedback submissions from App Store Connect' },
    { title: 'File issues', detail: 'dedup against existing issues, file GitHub issues for anything new' },
  ],
}

const REPO = 'CORDOC-LLC/ChessCoach'
const BUNDLE_ID = 'com.cordoc.gemmachess'
const API_KEY_ID = 'U966DLSPKS'
const API_ISSUER_ID = 'bdde267c-1386-420e-8c20-9c1440dfe6a2'
const KEY_PATH = `/Users/kaustubh/.private_keys/AuthKey_${API_KEY_ID}.p8`

phase('Fetch')
const fetched = await agent(
  `Fetch recent TestFlight crash reports and tester feedback for the app with bundle ID ${BUNDLE_ID} from the ` +
  `App Store Connect API.\n\n` +
  `Authenticate with a JWT signed using the ES256 private key at ${KEY_PATH}, issuer ID "${API_ISSUER_ID}", ` +
  `key ID "${API_KEY_ID}" (standard App Store Connect API JWT: header {alg: ES256, kid: <keyId>, typ: JWT}, ` +
  `payload {iss: <issuerId>, iat: now, exp: now+1200, aud: "appstoreconnect-v1"}). Use whatever tool is convenient ` +
  `(python3 with pyjwt+cryptography, or a small script) -- pip install pyjwt cryptography if not already available.\n\n` +
  `Steps:\n` +
  `1. GET https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=${BUNDLE_ID} (URL-encode the brackets: ` +
  `filter%5BbundleId%5D=${BUNDLE_ID}) to get the app's numeric id.\n` +
  `2. GET https://api.appstoreconnect.apple.com/v1/apps/{appId}/betaFeedbackCrashSubmissions?limit=50 -- crash reports.\n` +
  `3. GET https://api.appstoreconnect.apple.com/v1/apps/{appId}/betaFeedbackScreenshotSubmissions?limit=50 -- tester ` +
  `feedback with an optional comment and screenshot.\n` +
  `4. For each crash submission, also fetch its crash log detail if there's a related crashLog/watchCrashLog endpoint, ` +
  `so you can include a real trace, not just metadata.\n\n` +
  `Return a normalized list. For EACH item, extract whatever fields the API actually returned (don't invent missing ` +
  `ones): id (the App Store Connect submission id -- this is the stable dedup key), kind ("crash" or "feedback"), ` +
  `deviceModel, osVersion, appVersion, appBuild, createdDate, comment (tester's text feedback, if any), ` +
  `crashTraceSummary (first ~30 lines of the crash log if you fetched one, else empty string).`,
  {
    schema: {
      type: 'object',
      properties: {
        items: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              kind: { type: 'string', enum: ['crash', 'feedback'] },
              deviceModel: { type: 'string' },
              osVersion: { type: 'string' },
              appVersion: { type: 'string' },
              appBuild: { type: 'string' },
              createdDate: { type: 'string' },
              comment: { type: 'string' },
              crashTraceSummary: { type: 'string' },
            },
            required: ['id', 'kind'],
          },
        },
      },
      required: ['items'],
    },
  }
)

const items = (fetched && fetched.items) || []
log(`Fetched ${items.length} TestFlight crash/feedback submission(s).`)

if (items.length === 0) {
  log('Nothing new from TestFlight -- done.')
} else {
  phase('File issues')
  const results = await parallel(items.map((item) => async () => {
    const marker = `testflight-feedback-id:${item.id}`
    return agent(
      `You're filing (or skipping) a GitHub issue on ${REPO} for a TestFlight ${item.kind} report.\n\n` +
      `Dedup marker for this item: "${marker}" -- this MUST appear verbatim in the issue body (in an HTML comment, ` +
      `e.g. <!-- ${marker} -->), so future runs can detect it's already filed.\n\n` +
      `First, check for an existing issue: gh issue list --repo ${REPO} --search "${marker} in:body" --state all --json number,url. ` +
      `If one already exists (open or closed), do NOT create a new one -- return alreadyExists: true and its URL.\n\n` +
      `Otherwise, create a new issue with gh issue create --repo ${REPO}. Add the label "testflight" (create it first ` +
      `if it doesn't exist: gh label create testflight --repo ${REPO} --color FF6B6B --description "Reported via TestFlight" ` +
      `2>/dev/null || true).\n\n` +
      `Title: a short, specific summary (e.g. "Crash on iPhone 15, iOS 18.2 after scanning a board" or ` +
      `"TestFlight feedback: <short paraphrase>") -- under 70 chars.\n\n` +
      `Body must include:\n` +
      `- The hidden marker comment: <!-- ${marker} -->\n` +
      `- "Reported via TestFlight" and the item kind (crash or feedback)\n` +
      `- Device: ${item.deviceModel || 'unknown'}, OS: ${item.osVersion || 'unknown'}, ` +
      `App version/build: ${item.appVersion || '?'} (${item.appBuild || '?'}), reported ${item.createdDate || 'unknown date'}\n` +
      (item.comment ? `- Tester comment: "${item.comment}"\n` : '') +
      (item.crashTraceSummary ? `- Crash trace (partial):\n\`\`\`\n${item.crashTraceSummary}\n\`\`\`\n` : '') +
      `- A note that this issue was filed automatically from TestFlight feedback and needs triage\n\n` +
      `Return: alreadyExists (bool), issueUrl (string, the existing or newly created issue's URL).`,
      {
        schema: {
          type: 'object',
          properties: { alreadyExists: { type: 'boolean' }, issueUrl: { type: 'string' } },
          required: ['alreadyExists', 'issueUrl'],
        },
      }
    )
  }))

  const created = results.filter(Boolean).filter((r) => !r.alreadyExists)
  const skipped = results.filter(Boolean).filter((r) => r.alreadyExists)
  log(`Filed ${created.length} new issue(s), skipped ${skipped.length} already-filed duplicate(s).`)
}

return {
  itemsFetched: items.length,
}
