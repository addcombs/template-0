// The app's AWS resources, from project.json: Cognito sign-in, the UI bucket, the API on Lambda,
// one CloudFront distribution for both (the UI at /, the API at /api/* and the other API paths),
// its Route 53 records, and the role GitHub Actions deploys with. scripts\provision.ps1 deploys it.
//
// Code versions belong to CI: the `live` alias starts at $LATEST, and each deploy from main
// publishes a version (SnapStart's snapshot) and moves the alias to it. CloudFormation only touches
// the alias again if its definition here changes, so a later `cdk deploy` leaves it where CI put it.
//
// importOnly (cdk import of an app first set up by the old scripts) leaves out what cannot be
// imported, so the first pass adopts only existing resources; a normal deploy then adds the rest.
import { CfnOutput, CfnParameter, Duration, Fn, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export interface Project {
  name: string;
  aws: { profile: string; region: string };
  domain: { apex: string; host: string };
  cognito: { domainPrefix: string; autoConfirm?: boolean };
}

export interface AppStackProps extends StackProps {
  project: Project;
  /** The API's Lambda package, built by `mvn -P lambda package`. */
  apiZip: string;
  /** The API's Java package, e.g. com.acombsdev.template0. */
  javaPackage: string;
  /** The app's schema in the shared database. */
  dbSchema: string;
  /** The shared certificate for the apex and *.apex, in us-east-1. */
  certificateArn: string;
  hostedZoneId: string;
  /** GitHub's token subject for pushes to main, repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main. */
  githubSubject: string;
  importOnly: boolean;
}

// Paths the API answers; everything else is the UI.
const API_PATHS = ['/api/*', '/actuator/*', '/swagger-ui*', '/v3/api-docs*'];

export class AppStack extends Stack {
  readonly distribution: cloudfront.Distribution | undefined;
  readonly uiOrigin: cloudfront.IOrigin | undefined;

  constructor(scope: Construct, id: string, props: AppStackProps) {
    super(scope, id, props);
    const { project, importOnly } = props;
    const app = project.name;
    const host = project.domain.host;
    const urls = ['http://localhost:4200/', `https://${host}/`];
    // Imported resources need a deletion policy, and nothing holding users or files is ever deleted.
    const keep = <T extends { applyRemovalPolicy(p: RemovalPolicy): void }>(r: T) => { r.applyRemovalPolicy(RemovalPolicy.RETAIN); return r; };

    // --- sign-in ---
    const autoConfirm = project.cognito.autoConfirm
      ? keep(new lambda.Function(this, 'AutoConfirm', {
          functionName: `${app}-auto-confirm`,
          description: 'Cognito pre-sign-up trigger: confirms each new account and marks its email verified, so no code is sent.',
          runtime: lambda.Runtime.NODEJS_22_X,
          architecture: lambda.Architecture.ARM_64,
          handler: 'index.handler',
          timeout: Duration.seconds(5),
          role: keep(new iam.Role(this, 'AutoConfirmRole', {
            roleName: `${app}-auto-confirm-lambda`,
            assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
            managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
          })),
          code: lambda.Code.fromInline([
            'exports.handler = async (event) => {',
            '  event.response.autoConfirmUser = true;',
            '  if (event.request.userAttributes.email) event.response.autoVerifyEmail = true;',
            '  return event;',
            '};',
          ].join('\n')),
        }))
      : undefined;

    // These settings match the pools the old scripts made; changing the sign-in attributes or the
    // schema would make CloudFormation replace the pool, and with it every account.
    const pool = keep(new cognito.UserPool(this, 'Users', {
      userPoolName: `${app}-users`,
      featurePlan: cognito.FeaturePlan.ESSENTIALS,
      signInAliases: { email: true },
      autoVerify: { email: true },
      selfSignUpEnabled: true,
      standardAttributes: { email: { required: true, mutable: true }, givenName: { required: false, mutable: true } },
      passwordPolicy: { minLength: 8, requireUppercase: true, requireLowercase: true, requireDigits: true, requireSymbols: false, tempPasswordValidity: Duration.days(7) },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      userVerification: { emailStyle: cognito.VerificationEmailStyle.CODE, emailSubject: 'Your verification code', emailBody: 'Your verification code is {####}. ' },
      mfa: cognito.Mfa.OFF,
      lambdaTriggers: autoConfirm && !importOnly ? { preSignUp: autoConfirm } : undefined,
    }));
    const client = keep(pool.addClient('Ui', {
      userPoolClientName: `${app}-ui`,
      generateSecret: false,
      authFlows: { userSrp: true },
      supportedIdentityProviders: [cognito.UserPoolClientIdentityProvider.COGNITO],
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [cognito.OAuthScope.OPENID, cognito.OAuthScope.EMAIL, cognito.OAuthScope.PROFILE],
        callbackUrls: urls,
        logoutUrls: urls,
      },
      preventUserExistenceErrors: true,
      enableTokenRevocation: true,
    }));
    keep(pool.addDomain('SignIn', {
      cognitoDomain: { domainPrefix: project.cognito.domainPrefix },
      managedLoginVersion: cognito.ManagedLoginVersion.NEWER_MANAGED_LOGIN,
    }));

    // --- buckets ---
    const uiBucket = keep(new s3.Bucket(this, 'UiBucket', { bucketName: `${app}-ui-${this.account}`, blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL }));
    // CI uploads each API build here for update-function-code.
    const deployBucket = keep(new s3.Bucket(this, 'DeployBucket', { bucketName: `${app}-deploy-${this.account}`, blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL }));

    // --- API ---
    // The database login comes from the API's .env as NoEcho parameters, so it is in no template.
    const secret = (name: string) => new CfnParameter(this, name, { type: 'String', noEcho: true }).valueAsString;
    const apiRole = keep(new iam.Role(this, 'ApiRole', {
      roleName: `${app}-api-lambda`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
    }));
    const api = keep(new lambda.Function(this, 'Api', {
      functionName: `${app}-api`,
      runtime: lambda.Runtime.JAVA_21,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 1024,
      timeout: Duration.seconds(30),
      role: apiRole,
      // Wraps the adapter's SpringDelegatingLambdaContainerHandler so response headers reach function URLs.
      handler: `${props.javaPackage}.lambda.FunctionUrlHandler`,
      code: lambda.Code.fromAsset(props.apiZip),
      snapStart: lambda.SnapStartConf.ON_PUBLISHED_VERSIONS,
      environment: {
        MAIN_CLASS: `${props.javaPackage}.ApiApplication`,
        SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE: '2',
        // Lambda's code folder (/var/task) is read-only with 0 bytes free, which makes the
        // disk-space health check report DOWN; /tmp is Lambda's writable scratch space.
        MANAGEMENT_HEALTH_DISKSPACE_PATH: '/tmp',
        // The UI and API now share an origin; this still covers http://localhost:4200 calling a deployed API.
        CORS_ALLOWED_ORIGINS: `https://${host}`,
        DATABASE_SCHEMA: props.dbSchema,
        COGNITO_ISSUER: pool.userPoolProviderUrl,
        COGNITO_CLIENT_ID: client.userPoolClientId,
        DATABASE_URL: secret('DatabaseUrl'),
        DATABASE_USERNAME: secret('DatabaseUsername'),
        DATABASE_PASSWORD: secret('DatabasePassword'),
      },
    }));
    const live = keep(new lambda.CfnAlias(this, 'Live', { functionName: api.functionName, name: 'live', functionVersion: '$LATEST' }));
    const url = keep(new lambda.CfnUrl(this, 'LiveUrl', { targetFunctionArn: api.functionArn, qualifier: 'live', authType: 'NONE' }));
    url.addDependency(live);

    // --- GitHub Actions deploy role: exactly what .github/workflows/ci.yml calls ---
    const providerHost = 'token.actions.githubusercontent.com';
    const deployRole = keep(new iam.Role(this, 'GitHubDeploy', {
      roleName: `${app}-github-deploy`,
      description: `GitHub Actions deploys of ${app}`,
      assumedBy: new iam.WebIdentityPrincipal(`arn:aws:iam::${this.account}:oidc-provider/${providerHost}`, {
        StringEquals: { [`${providerHost}:aud`]: 'sts.amazonaws.com', [`${providerHost}:sub`]: props.githubSubject },
      }),
    }));

    new CfnOutput(this, 'UserPoolId', { value: pool.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: client.userPoolClientId });
    new CfnOutput(this, 'SignInDomain', { value: `${project.cognito.domainPrefix}.auth.${this.region}.amazoncognito.com` });
    new CfnOutput(this, 'Issuer', { value: pool.userPoolProviderUrl });
    new CfnOutput(this, 'DeployRoleArn', { value: deployRole.roleArn });
    if (importOnly) return;

    // --- what the old scripts' resources could not be imported as ---
    // Function URLs with no auth need both permissions.
    new lambda.CfnPermission(this, 'LiveUrlInvokeUrl', {
      functionName: `${api.functionArn}:live`, action: 'lambda:InvokeFunctionUrl', principal: '*', functionUrlAuthType: 'NONE',
    }).addDependency(live);
    new lambda.CfnPermission(this, 'LiveUrlInvoke', {
      functionName: `${api.functionArn}:live`, action: 'lambda:InvokeFunction', principal: '*', invokedViaFunctionUrl: true,
    }).addDependency(live);

    const apiBehavior: cloudfront.BehaviorOptions = {
      // https://<id>.lambda-url.<region>.on.aws/ -> its host name
      origin: new origins.HttpOrigin(Fn.select(2, Fn.split('/', url.attrFunctionUrl)), {
        protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
        readTimeout: Duration.seconds(30),
      }),
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
      // Forwards the Authorization header; the function URL needs its own Host header.
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
    };
    this.uiOrigin = origins.S3BucketOrigin.withOriginAccessControl(uiBucket);
    this.distribution = new cloudfront.Distribution(this, 'Site', {
      comment: app,
      domainNames: [host],
      certificate: acm.Certificate.fromCertificateArn(this, 'Certificate', props.certificateArn),
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      defaultBehavior: {
        origin: this.uiOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      additionalBehaviors: Object.fromEntries(API_PATHS.map(path => [path, apiBehavior])),
    });

    // Alias records (unlike a CNAME, they also work at the apex).
    const zone = route53.HostedZone.fromHostedZoneAttributes(this, 'Zone', { hostedZoneId: props.hostedZoneId, zoneName: project.domain.apex });
    const target = route53.RecordTarget.fromAlias(new targets.CloudFrontTarget(this.distribution));
    new route53.ARecord(this, 'SiteA', { zone, recordName: `${host}.`, target });
    new route53.AaaaRecord(this, 'SiteAaaa', { zone, recordName: `${host}.`, target });

    deployRole.attachInlinePolicy(new iam.Policy(this, 'GitHubDeployPolicy', {
      statements: [
        new iam.PolicyStatement({ actions: ['s3:ListBucket'], resources: [uiBucket.bucketArn] }),
        new iam.PolicyStatement({ actions: ['s3:PutObject', 's3:DeleteObject'], resources: [uiBucket.arnForObjects('*')] }),
        new iam.PolicyStatement({
          actions: ['cloudfront:CreateInvalidation', 'cloudfront:GetInvalidation'],
          resources: [`arn:aws:cloudfront::${this.account}:distribution/${this.distribution.distributionId}`],
        }),
        new iam.PolicyStatement({ actions: ['cloudfront:ListDistributions'], resources: ['*'] }),
        new iam.PolicyStatement({
          actions: ['cognito-idp:DescribeManagedLoginBrandingByClient', 'cognito-idp:UpdateManagedLoginBranding'],
          resources: [pool.userPoolArn],
        }),
        // Lambda reads the uploaded zip with the caller's permissions.
        new iam.PolicyStatement({ actions: ['s3:PutObject', 's3:GetObject'], resources: [deployBucket.arnForObjects(`${app}-api-lambda.zip`)] }),
        new iam.PolicyStatement({
          actions: ['lambda:UpdateFunctionCode', 'lambda:PublishVersion', 'lambda:UpdateAlias', 'lambda:GetFunction', 'lambda:GetFunctionConfiguration'],
          resources: [api.functionArn, `${api.functionArn}:*`],
        }),
      ],
    }));
    new CfnOutput(this, 'DistributionId', { value: this.distribution.distributionId });
  }
}
