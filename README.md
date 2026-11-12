# template-0

A full-stack app template: an Angular UI (`template-0-ui`) and a Spring Boot API on AWS Lambda
(`template-0-api`), with Cognito sign-in, a Neon PostgreSQL schema of its own, and CloudFront at
https://template-0.acombs-dev.com and https://api.template-0.acombs-dev.com. See each folder's
README for details.

`project.json` holds the only per-app settings: name, AWS profile and region, domain, Cognito
domain prefix and theme colours, plus an optional `displayName` for the toolbar, page title, welcome
and About (otherwise made from the name: template-0 shows as Template 0). The PowerShell scripts in `scripts\` derive every AWS resource
name from it. Their logs go to `logs\` (git-ignored), and the Cognito IDs AWS assigns to
`config\cognito-pool.json` (git-ignored). The apex domain's DNS is hosted in Route 53, where the
scripts write the app's certificate validation and CloudFront alias records themselves.

GitHub Actions (`.github/workflows/ci.yml`) builds and tests the UI and the API on every push to
`main` and every pull request, and checks the theme palettes match `project.json`. Pushes to `main`
that pass then deploy the UI and the API code, and give the Cognito sign-in page the theme colours,
through an IAM role made by `scripts\create-github-deploy-role.ps1` (step 7 below); until the
repository has that role's ARN as its Actions variable `AWS_DEPLOY_ROLE_ARN`, the deploy jobs are
skipped. To deploy without pushing, run the workflow from the repository's Actions tab (CI > Run
workflow). The deploy never changes the function's settings, so no secrets are stored in GitHub;
after changing `.env` or the Cognito pool, run `scripts\deploy-api.ps1` again.

## Create a new app

```powershell
.\scripts\new-app.ps1 -Name project-1 -Primary '#RRGGBB'
```

copies this project to `..\project-1` with the folders, Java package, names, host
(`project-1.acombs-dev.com` unless `-HostName` is given), Cognito prefix, schema and colours
renamed, writes its `.env` with the shared database login, and starts a git repository. Then run,
from the new folder:

1. `scripts\create-cognito-pool.ps1` - the app's user pool, client and sign-in domain
2. `scripts\apply-migrations.ps1` - its schema and tables in the shared database
3. `scripts\start-all.ps1` - theme palettes, build, tests, and the app at http://localhost:4200/
4. `scripts\deploy-api.ps1` (builds, tests and creates the function), then
   `scripts\create-function-url.ps1` - the API on Lambda
5. `scripts\request-certificate.ps1` - the certificates, with their validation CNAMEs written to
   the Route 53 zone; it waits until both are issued
6. `scripts\create-ui-bucket.ps1`, `scripts\create-cloudfront.ps1`, `scripts\create-api-cloudfront.ps1`
   - the distributions, with alias A/AAAA records for the host and `api.` host in Route 53
7. Commit `src\app\project.settings.ts` (step 1 filled in its Cognito IDs), push to a new GitHub
   repository as the git origin, run `scripts\create-github-deploy-role.ps1`, add the role ARN it
   prints as the repository's Actions variable `AWS_DEPLOY_ROLE_ARN`, then run the workflow (Actions
   > CI > Run workflow) for the first deploy of the UI and the sign-in page's colours

`scripts\set-email-verification.ps1 -Mode Off` lets new accounts register without the code Cognito
emails them: a pre-sign-up Lambda trigger confirms each account and marks its email verified.
`-Mode On` brings the code back.

After that, each push to `main` deploys. `scripts\start-all.ps1` builds and tests both apps locally
before starting them.
