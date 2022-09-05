# Deployment Frequency
A GitHub Action to roughly calculate DORA deployment frequency

## Calculation: 
- Get the last 100 workflows
- For each workflow, see if it started in the last 30 days, and add it to a secondary filtered list - this is the number of deployments in the last 30 days
- With this filtered list, divide the count by the 30 days for a number of deployments per day
- Then translate to friendly n days/weeks/months. 

## Open questions
- what do to there are multiple workflows?
- need to inject PAT tokens to call private repos 

## Inputs:
- `workflows`: required, string, The name of the workflows to process. Multiple workflows can be separated by `,` (note that currently only the first workflow in the string is processed)
- `owner-repo`: optional, string, defaults to the repo where the action runs. Can target another owner or org and repo. e.g. `'samsmithnz/DevOpsMetrics'`
- `default-branch`: optional, string, defaults to `main` 
- `number-of-days`: optional, integer, defaults to `30` (days)
- `app-id`: required, application id of the registered GitHub app
- `app-install-id`: required, id of the installed instance of the GitHub app
- `app-private-key` required, private key which has been generated for the installed instance of the GitHub app. Must be provided without leading `'-----BEGIN RSA PRIVATE KEY----- '` and trailing `' -----END RSA PRIVATE KEY-----'`.

To test the current repo (same as where the action runs)
```
- uses: samsmithnz/deployment-frequency@main
  with:
    workflows: 'CI'
```

To test another repo, with all arguments
```
- name: Test another repo
  uses: samsmithnz/deployment-frequency@main
  with:
    workflows: 'CI/CD'
    owner-repo: 'samsmithnz/DevOpsMetrics'
    default-branch: 'main'
    number-of-days: 30
```

## Installation/Setup

To use this action you need to register a GitHub App in the first place. The necessary steps are described [here](https://docs.github.com/en/developers/apps/building-github-apps/creating-a-github-app). After the GitHub App has been registered a private key must be generated. [Authenticating with GitHub Apps - GitHub Docs](https://docs.github.com/en/developers/apps/building-github-apps/authenticating-with-github-apps#generating-a-private-key)

In addition the following permissions must defined for the GitHub App ([Editing a GitHub App's permissions - GitHub Docs](https://docs.github.com/en/developers/apps/managing-github-apps/editing-a-github-apps-permissions)):

- Repository permissions - Workflow - Actions - Read-only
- Repository permissions - Workflow - Actions - Metadata

After defining the permissions a private key must also be defined, which then will be used to authenticate as the GitHub App inside the action. [Authenticating with GitHub Apps - GitHub Docs](https://docs.github.com/en/developers/apps/building-github-apps/authenticating-with-github-apps#generating-a-private-key)

After the GitHub App has been registered it must be installed in the organization in which the action is going to be used. - [Installing an app in your organization - GitHub Docs](https://docs.github.com/en/get-started/customizing-your-github-workflow/purchasing-and-installing-apps-in-github-marketplace/installing-an-app-in-your-organization)

