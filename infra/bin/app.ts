// The CDK app: one stack named after the app, in project.json's region. scripts\provision.ps1 runs
// it with the context values it looks up (the shared certificate, the Route 53 zone and the GitHub
// repository's token subject) and the database login from the API's .env as parameters.
import { App } from 'aws-cdk-lib';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AppStack, Project } from '../lib/app-stack';

const root = join(__dirname, '..', '..');
const project: Project & { database?: { schema?: string } } = JSON.parse(readFileSync(join(root, 'project.json'), 'utf8'));
const app = new App();
const context = (name: string) => {
  const value = app.node.tryGetContext(name);
  if (!value) throw new Error(`Missing context ${name}; deploy with scripts\\provision.ps1.`);
  return String(value);
};

// The same rules as scripts\common.ps1.
const javaPackage = 'com.acombsdev.' + project.name.replace(/[^A-Za-z0-9]/g, '').toLowerCase();
const dbSchema = project.database?.schema ?? project.name.replace(/[^A-Za-z0-9]/g, '_').toLowerCase();
const target = join(root, `${project.name}-api`, 'target');
const zip = readdirSync(target).find(f => f.endsWith('-lambda.zip'));
if (!zip) throw new Error(`No *-lambda.zip in ${target}; build it with mvn -P lambda package.`);

new AppStack(app, project.name, {
  env: { region: project.aws.region },
  description: `${project.name}: sign-in, UI, API and CloudFront (infra/ in its repository)`,
  project,
  apiZip: join(target, zip),
  javaPackage,
  dbSchema,
  certificateArn: context('certificateArn'),
  hostedZoneId: context('hostedZoneId'),
  githubSubject: context('githubSubject'),
  importOnly: app.node.tryGetContext('importOnly') === 'true',
});
