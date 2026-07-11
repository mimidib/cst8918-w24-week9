CST8918 - DevOps: Infrastructure as Code
Prof: Robert McKenney

# Hybrid-A09 Husky and GitHub Actions

## Background

You are the DevOps Engineer on your product development team. Your team has been tasked with creating a CI/CD pipeline for for the infrastructure as code (IaC) project that you have been working on. The IaC project includes a Terraform script that creates an Azure Kubernetes Service (AKS) cluster.

Your team has decided to use GitHub Actions as the CI/CD tool to automate the deployment of the AKS cluster. And, you have been tasked with creating the GitHub Actions workflow file that will be used to deploy the AKS cluster.

## Instructions

### Create a simple terraform script

In the `terraform` folder, create a simple Terraform script that creates at least one resource in Azure. This could be a virtual machine, a storage account, or any other resource that you choose. The purpose of this script is to create a Terraform script that you can use to test the GitHub Actions workflow.

### Code formatting

As a first step in the pipline, you will use Husky to create a pre-commit hook that will run the `terraform fmt` and `terraform validate` command to ensure that commits do not create unnecessary formatting diffs or contain obvious syntax errors.

1. Initialize the _node_ project folder with `npm init -y`
2. Install Husky with `npm install husky --save-dev`
3. Initialize Husky with `npx husky-init`
4. Update the pre-commit hook to run the `terraform fmt` command.

```sh
echo "terraform fmt -check -recursive" > .husky/pre-commit
```

5. Update the pre-commit hook to run the `terraform validate` command.

```sh
echo "terraform validate" >> .husky/pre-commit
```

6. Update the pre-commit hook to run the `terraform tflint` command.

```sh
echo "tflint" >> .husky/pre-commit
```

#### Test the pre-commit hook

Purposely create a formatting diff or syntax error in the Terraform script and commit the changes. The pre-commit hook should prevent the commit from being created.

Then correct the error(s) and commit the changes. The commit should be created successfully.

### GitHub Actions workflow

1. Create a new file called `action-terraform-verify.yml` in the `.github/workflows` folder.
2. Use the following workflow as a starting point:

```yml
name: Validate terraform fmt
on:
  pull_request:
    branches:
      - main
      - master

permissions:
  id-token: write
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    name: terraform fmt check
    outputs:
      CHECK_STATUS: "${{ env.CHECK_STATUS }}"
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 2
      - name: Fetch changed files
        id: pr_files
        uses: jitterbit/get-changed-files@v1
        with:
          format: "space-delimited"
      - name: Configure terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.2.4
      - name: Validate terraform fmt (added_modified)
        run: |
          set +e

          echo "CHECK_STATUS=0" >> $GITHUB_ENV

          for changed_file in ${{ steps.pr_files.outputs.added_modified }}; do
            echo "Checking terraform fmt on ${changed_file}..."

            if [[ $changed_file == *.tf ]]; then
              terraform fmt -check $changed_file
              FMT_STATUS=$(echo $?)

              if [[ $FMT_STATUS -ne 0 ]]; then
                echo "❌ terraform fmt failed - ${changed_file}" >> $GITHUB_STEP_SUMMARY
                echo "CHECK_STATUS=1" >> $GITHUB_ENV
              fi
            fi
          done
      - name: Process check
        if: always()
        run: exit $CHECK_STATUS
```

This will run the `terraform fmt` command on all Terraform files that have been added or modified in the pull request. If the `terraform fmt` command fails, the workflow will fail.

#### Test the GitHub Actions workflow

Purposely create a formatting diff or syntax error in the Terraform script.

Commit the changes using the `--no-verify` option to bypass the pre-commit hook that you created earlier. Then create a pull request. The GitHub Actions workflow should fail.

Then correct the error(s) and commit the changes and push to your branch with the open pull request. The GitHub Actions workflow should pass now.

### Add another GitHub Actions job to validate the Terraform script

It is time to Google and find a GitHub Actions job that will validate the Terraform script. Add this job to the `action-terraform-verify.yml` file.

## Submission

Submit the URL of your GitHub repository.
