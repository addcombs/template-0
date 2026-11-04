# template-0

A full-stack app template: an Angular UI (`template-0-ui`) and a Spring Boot API on AWS Lambda
(`template-0-api`), with Cognito sign-in, a Neon PostgreSQL schema of its own, and CloudFront at
https://template-0.acombs-dev.com and https://api.template-0.acombs-dev.com. See each folder's
README for details.

`project.json` holds the only per-app settings: name, AWS profile and region, domain, Cognito
domain prefix and theme colours. The PowerShell scripts in `scripts\` derive every AWS resource
name from it. Their logs go to `logs\` and the IDs AWS assigns to `state\` (both git-ignored).

## Create a new app

```powershell
.\scripts\new-app.ps1 -Name project-1 -Primary '#RRGGBB' -Secondary '#RRGGBB'
```

copies this project to `..\project-1` with the folders, Java package, names, host
(`project-1.acombs-dev.com` unless `-HostName` is given), Cognito prefix, schema and colours
renamed, writes its `.env` with the shared database login, and starts a git repository. Then run,
from the new folder:

1. `scripts\create-cognito-pool.ps1` - the app's user pool, client and sign-in domain
2. `scripts\apply-migrations.ps1` - its schema and tables in the shared database
3. `scripts\start-all.ps1` - theme palettes, build, tests, and the app at http://localhost:4200/
4. `scripts\brand-managed-login.ps1` - the sign-in page in the app's colours
5. `scripts\build-lambda.ps1`, `scripts\deploy-api.ps1`, then `scripts\create-function-url.ps1` -
   the API on Lambda
6. `scripts\request-certificate.ps1` - add the CNAMEs it prints at the DNS provider and re-run it
   until both certificates are issued
7. `scripts\create-ui-bucket.ps1`, `scripts\create-cloudfront.ps1`,
   `scripts\create-api-cloudfront.ps1`, `scripts\deploy-ui.ps1`
8. At the DNS provider: CNAMEs for the host and `api.` host to the CloudFront domains the scripts
   print

After that, `scripts\build-lambda.ps1` then `scripts\deploy-api.ps1`, and `scripts\deploy-ui.ps1`
deploy changes, and `scripts\test-all.ps1` runs both apps' tests.
