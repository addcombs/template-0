# project-0 API

Spring Boot account API for project-0 (UI: `../project-0-ui`), backed by the existing PostgreSQL table `admin.users`. It expects that schema and table to exist; Hibernate validates the schema at startup and does not create or modify database objects.

All application endpoints are under `/api/account` and require a verified Cognito ID token. The health check and API documentation endpoints are public.

## Requirements

- Java 21
- Maven 3.6.3 or later
- PostgreSQL connection details for the database containing `admin.users`

## Database migration

For an existing database, back up the data and inspect case-insensitive duplicate emails before applying the migration:

```sql
SELECT lower(email), count(*) FROM admin.users
WHERE email IS NOT NULL GROUP BY lower(email) HAVING count(*) > 1;
```

Resolve any duplicates deliberately before applying `db\migrations\001-account-identity.sql` once, using your PostgreSQL client or database SQL editor. For example, from this directory, with `psql` installed and your connection configured securely:

```powershell
psql -h HOST -U DATABASE_ROLE -d DBNAME -v ON_ERROR_STOP=1 -f db\migrations\001-account-identity.sql
```

The migration adds the Cognito subject and a case-insensitive unique email index in a transaction. It fails if duplicates exist. It applies to a database that already has `admin.users` without these columns. A fresh database must first have the `admin.users` table (including the `cognito_sub` column and unique lower-case email index) created; this project does not create or alter databases and no migration is applied automatically. The application cannot start against an out-of-date schema because Hibernate validates it (`ddl-auto=validate`).

## Configuration

All settings are supplied through environment variables; nothing is stored in source. All five are required to start the application.

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | JDBC URL, e.g. `jdbc:postgresql://HOST/DBNAME?sslmode=require` |
| `DATABASE_USERNAME` | Database role |
| `DATABASE_PASSWORD` | Database password |
| `COGNITO_ISSUER` | Issuer URL of your Cognito user pool, `https://cognito-idp.REGION.amazonaws.com/POOL_ID` |
| `COGNITO_CLIENT_ID` | Cognito app client ID that ID tokens must be issued for |

Optional: `CORS_ALLOWED_ORIGINS`, comma-separated browser origins allowed to call the API cross-origin (e.g. `https://project-0.acombs-dev.com`). Unset allows none. `deploy-api` sets it to the UI's domain.

```powershell
$env:DATABASE_URL = "jdbc:postgresql://HOST/DBNAME?sslmode=require"
$env:DATABASE_USERNAME = "YOUR_DATABASE_ROLE"
$env:DATABASE_PASSWORD = "YOUR_DATABASE_PASSWORD"
$env:COGNITO_ISSUER = "https://cognito-idp.REGION.amazonaws.com/POOL_ID"
$env:COGNITO_CLIENT_ID = "YOUR_APP_CLIENT_ID"
```

There are deliberately no defaults for the Cognito settings. The backend validates the ID token's signature, issuer, expiration, audience, token use, subject, and verified email using the pool's public keys.

## Build and run

From this directory:

```powershell
mvn --batch-mode --no-transfer-progress verify   # build and run the unit tests
mvn spring-boot:run                              # run (requires the environment variables above)
```

The unit tests do not need a database or Cognito. Running the application requires a reachable PostgreSQL database with the expected schema and a Cognito pool.

## Endpoints

With the API running locally, open Swagger UI at
`http://localhost:8080/swagger-ui.html` or retrieve the generated OpenAPI JSON
at `http://localhost:8080/v3/api-docs`. Documentation covers `/api/account`
only. In Swagger UI, use **Authorize** with a valid Cognito ID token to call it.
Both documentation endpoints are public; when deployed they are served at the API's own
host, e.g. `https://api.project-0.acombs-dev.com/swagger-ui.html`.

| Method | Path | Behavior |
|---|---|---|
| `GET` | `/api/account` | Get current user's details, linking an existing row by verified email if necessary; `404` if absent |
| `PUT` | `/api/account` | Create or update current user's details |

The account endpoint takes `firstName` and `lastName` (required, maximum 100 characters) and `phoneNumber` (optional, maximum 40 characters). It obtains email and subject exclusively from the verified ID token; the client cannot change email. IDs and account audit fields are system-managed. A row linked to a different subject or a changed verified email causes `409` and requires administrative resolution.
