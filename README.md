# AWS Projects

Hands-on Amazon Web Services builds. I deploy each project for real with the
AWS CLI, record console screenshots from the live run, and then tear it down
with a cleanup script so nothing is left running or billing.

| Project | Services | What it shows |
|---|---|---|
| [Serverless Notes API](Serverless-Notes-API) | Lambda, API Gateway (HTTP API), DynamoDB | A REST API for notes on Graviton Lambda, with least-privilege IAM and on-demand DynamoDB |
| [Secure Static Website](Static-Website-S3-CloudFront-OAC) | S3, CloudFront, Origin Access Control | A private bucket that only CloudFront can read, HTTPS redirects, a custom 404 page and cache invalidation |
| [Event-Driven File Pipeline](Event-Driven-Pipeline-S3-SQS-Lambda) | S3, SQS, Lambda, dead-letter queue | CSV uploads processed automatically, with retries, partial batch failures and a DLQ for bad files |
| [Containerized Web App](Containerized-App-ECS-Fargate-ALB) | ECR, ECS Fargate, Application Load Balancer, CodeBuild | Two ARM64 Fargate tasks behind an ALB, with a rolling update that dropped **0 requests** |
| [Serverless Data Lake](Serverless-Data-Lake-S3-Glue-Athena) | S3, Glue Crawler, Athena | SQL over partitioned CSV, then a CTAS to Parquet that cut data scanned from 12.6 MB to 635 KB |
| [Banking Chatbot](Build-a-Chatbot-with-Amazon-Lex) | Amazon Lex | A conversational bot with custom intents, utterance variations and a tuned fallback intent |

## How I build these projects

- **Scripted, not clicked.** A `deploy.sh` script creates every resource with
  the AWS CLI, so each build can be repeated from scratch.
- **Cleaned up afterwards.** A matching `cleanup.sh` deletes everything the
  deploy created.
- **Security first.** IAM roles are scoped to the exact actions and resources
  each service needs, buckets stay private, and network access is limited to
  the components that need it.
- **Cost aware.** I use Graviton (ARM64) compute, on-demand capacity, the
  smallest Fargate size and Athena scan limits so the projects stay within or
  close to the free tier.
- **Evidence from the real run.** The `screenshots/` folder in each project
  shows the deployed resources and the results.

## Running a project

You need an AWS account, the [AWS CLI](https://aws.amazon.com/cli/) configured
with credentials, and a Bash shell. The containerized app also needs Docker.

```bash
git clone https://github.com/Qwamzz/AWS-Projects.git
cd AWS-Projects/Serverless-Notes-API
./deploy.sh      # creates the resources (us-east-1 by default, override with REGION=...)
./cleanup.sh     # deletes them again when you are done
```

Each project's own README has the architecture diagram, the files, the test
commands and the results.

## Write-ups

Most projects also include a `BLOG.md`, a longer walkthrough of how I built it,
the decisions I made and what I learned along the way.
