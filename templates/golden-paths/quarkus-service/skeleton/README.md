# ${{ values.component_id }}

${{ values.description }}

## Architecture & Integration
This project was scaffolded using the **Red Hat Developer Hub Golden Path Template** with:
- **Runtime:** Quarkus 3.x
- **CI/CD:** OpenShift Pipelines (Tekton)
- **GitOps:** OpenShift GitOps (Argo CD)
- **Target Namespace:** `${{ values.namespace }}`
- **Owner:** `${{ values.owner }}`

## Running locally
```bash
mvn quarkus:dev
```
Open `http://localhost:8080/q/swagger-ui` for OpenAPI interactive documentation.
