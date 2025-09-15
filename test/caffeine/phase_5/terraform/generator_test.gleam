import caffeine/phase_5/terraform/generator

pub fn build_provider_datadog_test() {
  let expected = {
    "terraform {
required_providers {
    datadog = {
      source  = \"DataDog/datadog\"
      version = \"~> 3.0\"
    }
  }
}

provider \"datadog\" {
  api_key = var.DATADOG_API_KEY
  app_key = var.DATADOG_APP_KEY
}"
  }

  let actual = generator.build_provider([generator.Datadog])

  assert actual == expected
}

pub fn build_variables_datadog_test() {
  let expected = {
    "variable \"DATADOG_API_KEY\" {
  type        = string
  description = \"Datadog API key\"
  sensitive   = true
  default     = null
}

variable \"DATADOG_APP_KEY\" {
  type        = string
  description = \"Datadog Application key\"
  sensitive   = true
  default     = null
}"
  }

  let actual = generator.build_variables([generator.Datadog])

  assert actual == expected
}

pub fn build_backend_test() {
  let expected = {
    "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}"
  }

  let actual = generator.build_backend()

  assert actual == expected
}
