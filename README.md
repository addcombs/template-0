# template-0

A full-stack app template: an Angular UI (`template-0-ui`) and a Spring Boot API on AWS Lambda
(`template-0-api`), with Cognito sign-in, a Neon PostgreSQL schema of its own, and one CloudFront
distribution at https://template-0.acombs-dev.com that serves the UI and sends `/api/*`,
`/actuator/*` and the API docs to the API. See each folder's README for details.

`project.json` holds the only per-app settings: name, AWS profile and region, domain, Cognito
domain prefix and theme colours, plus an optional `displayName` for the toolbar, page title, welcome
and About (otherwise made from the name: template-0 shows as Template 0). `cognito.autoConfirm: true`
adds a pre-sign-up trigger that confirms each new account and marks its email verified, so
registering needs no emailed code.

`infra\` is a CDK app (TypeScript) with every AWS resource the app runs on: the user pool, client and
sign-in domain, the UI and deploy buckets, the API's function, `live` alias and function URL, the
distribution and its Route 53 records, and the role GitHub Actions deploys with. All of them share
one certificate for `acombs-dev.com` and `*.acombs-dev.com`, which the first app set up requests.
`scripts\provision.ps1` deploys it all; the PowerShell scripts' logs go to `logs\` (git-ignored), and
the Cognito IDs to `config\cognito-pool.json` (git-ignored).

GitHub Actions (`.github/workflows/ci.yml`) builds and tests the UI, the API and the infra code on
every push to `main` and every pull request, and checks the theme palettes match `project.json`.
Pushes to `main` that pass then deploy the UI and the API code, and give the Cognito sign-in page the
theme colours. To deploy without pushing, run the workflow from the repository's Actions tab (CI >
Run workflow). The deploy never changes the stack or the function's settings, so no secrets are
stored in GitHub; after changing `.env`, `project.json` or `infra\`, run `scripts\provision.ps1` again.

## Create a new app

```powershell
.\scripts\new-app.ps1 -Name project-1 -Primary '#RRGGBB' -Provision
```

copies this project to `..\project-1` with the folders, Java package, names, host
(`project-1.acombs-dev.com` unless `-HostName` is given), Cognito prefix, schema and colours
renamed, writes its `.env` with the shared database login, and starts a git repository. With
`-Provision` it then runs the new app's `scripts\provision.ps1` (otherwise run it yourself from the
new folder), which:

1. creates the GitHub repository (public; `-Visibility private` for private) and pushes
2. requests the shared certificate if no app has yet
3. deploys the stack in `infra\` (the first time in a region, bootstraps the CDK there)
4. writes the Cognito IDs to `config\cognito-pool.json` and the UI's settings
5. applies the database migrations
6. sets the repository's `AWS_DEPLOY_ROLE_ARN` and waits for the first deploy

The GitHub CLI must be signed in with the `workflow` scope (`gh auth refresh -h github.com -s workflow`)
so the push can include the workflow file.

After that, each push to `main` deploys. `scripts\start-all.ps1` builds and tests both apps locally
before starting them.
