package test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	testStructure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func cleanup(t *testing.T, terraformOptions *terraform.Options, tempTestFolder string) {
	terraform.Destroy(t, terraformOptions)
	os.RemoveAll(tempTestFolder)
}

// Test the Terraform module in examples/complete using Terratest.
func TestExamplesComplete(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())
	attributes := []string{randID}

	rootFolder := "../../"
	terraformFolderRelativeToRoot := "examples/complete"
	varFiles := []string{"fixtures.us-east-2.tfvars"}

	tempTestFolder := testStructure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		// Variables to pass to our Terraform code using -var-file options
		VarFiles: varFiles,
		Vars: map[string]interface{}{
			// The random attribute keeps the domain name unique, so parallel runs
			// (Terraform and OpenTofu) do not collide in the same account and Region.
			"attributes": attributes,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer cleanup(t, terraformOptions, tempTestFolder)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// The domain name defaults to the null-label ID.
	domainName := terraform.Output(t, terraformOptions, "domain_name")
	assert.Equal(t, "eg-ue2-test-codeartifact-"+randID, domainName)

	domainOwner := terraform.Output(t, terraformOptions, "domain_owner")
	assert.Regexp(t, "^[0-9]{12}$", domainOwner)

	// All three tiers of the upstream graph are created.
	repositoryArns := terraform.OutputMap(t, terraformOptions, "repository_arns")
	assert.Len(t, repositoryArns, 4)
	for _, name := range []string{"pypi-store", "npm-store", "packages", "team"} {
		assert.Contains(t, repositoryArns, name)
		assert.Contains(t, repositoryArns[name], ":repository/"+domainName+"/"+name)
	}

	var repositories map[string]struct {
		Name               string   `json:"name"`
		ExternalConnection *string  `json:"external_connection"`
		Upstreams          []string `json:"upstreams"`
	}
	require.NoError(t, json.Unmarshal([]byte(terraform.OutputJson(t, terraformOptions, "repositories")), &repositories))
	assert.Equal(t, []string{"pypi-store", "npm-store"}, repositories["packages"].Upstreams, "Expected upstream order to be preserved")
	assert.Equal(t, []string{"packages"}, repositories["team"].Upstreams)
	require.NotNil(t, repositories["pypi-store"].ExternalConnection)
	assert.Equal(t, "public:pypi", *repositories["pypi-store"].ExternalConnection)

	var endpoints map[string]map[string]string
	require.NoError(t, json.Unmarshal([]byte(terraform.OutputJson(t, terraformOptions, "repository_endpoints")), &endpoints))
	assert.Len(t, endpoints, 4)
	assert.Contains(t, endpoints["packages"]["pypi"], domainName+"-"+domainOwner+".d.codeartifact.us-east-2.amazonaws.com/pypi/packages/")
	assert.Contains(t, endpoints["team"]["npm"], "/npm/team/")

	packageGroupArns := terraform.OutputMap(t, terraformOptions, "package_group_arns")
	assert.Len(t, packageGroupArns, 2)
	assert.Contains(t, packageGroupArns, "first-party")
	assert.Contains(t, packageGroupArns, "internal")

	// A second plan must be empty. Package groups come from the awscc provider, whose
	// attributes are all optional and computed, so this is where a perpetual diff
	// would show up.
	exitCode := terraform.PlanExitCode(t, terraformOptions)
	assert.Equal(t, 0, exitCode, "Expected no changes on a second plan")
}

func TestExamplesCompleteDisabled(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())
	attributes := []string{randID}

	rootFolder := "../../"
	terraformFolderRelativeToRoot := "examples/complete"
	varFiles := []string{"fixtures.us-east-2.tfvars"}

	tempTestFolder := testStructure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		// Variables to pass to our Terraform code using -var-file options
		VarFiles: varFiles,
		Vars: map[string]interface{}{
			"attributes": attributes,
			"enabled":    "false",
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer cleanup(t, terraformOptions, tempTestFolder)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	results := terraform.InitAndApply(t, terraformOptions)

	// Should complete successfully without creating or changing any resources
	assert.Contains(t, results, "Resources: 0 added, 0 changed, 0 destroyed.")
}
