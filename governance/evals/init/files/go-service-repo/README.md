# go-service-repo

Minimal Go service fixture for the governance-kit init verb. No governance
scaffolding yet — the skill should detect the Go toolchain, pick
Go-appropriate directives, include the Security category, and explicitly
drop stylistic rules. The fixture ships the baseline documents
`required-docs` expects so a clean `init` run can pass `bash run.sh`
without prerequisite cleanup.
