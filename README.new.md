# OCurl - HTTP Testing for Intellectuals

## Introduction

OCurl is a rigorous HTTP client designed for developers who value precision, composability, and explicit configuration over magical automation. It replaces the ceremony of GUI tools like Postman with the power of plain text and Unix philosophy.

**Philosophy**:
- Explicit over implicit
- Composition over inheritance
- Files over databases
- CLI over GUI

## File Format Specification

### Basic Structure

An OCurl file (`.http`) contains environments, imports, and requests:

```http
// @import ./shared.auth.http

// @environment development
Host: localhost:8080
Authorization: Bearer {{DEV_TOKEN}}
@ApiVersion = v1
@UserID = 1001

// @environment production
Host: api.company.com
Authorization: Bearer {{PROD_TOKEN}}
@ApiVersion = v2
@UserID = 1

###
GET /api/{{ApiVersion}}/users/{{UserID}}

###
POST /api/{{ApiVersion}}/users
Content-Type: application/json

{"name": "test_user", "id": {{UserID}}}
```

### Syntax Elements

#### Environments
```http
// @environment name
Variable: header_value  // Applies to all requests
@Variable = value      // Variable declaration
```

#### Imports
```http
// @import path/to/file.http
```

#### Variable Declaration
```http
@VariableName = value
@ApiVersion = v1
@UserID = 1001
```

#### Header Declaration
```http
HeaderName: header_value
Authorization: Bearer token
Content-Type: application/json
```

#### Variable Usage
```http
GET /api/{{VariableName}}/resource
Header: {{VariableName}}
```

**Escaping**: `\{{variable}}` renders as literal `{{variable}}`

#### Header Removal
```http
// Remove header inherited from environment
HeaderName:
Authorization:
```

#### .env File Integration
```http
// @environment development
// @envfile .env.development
Host: {{API_HOST}}
Authorization: Bearer {{API_TOKEN}}
```

### Resolution Rules

1. **Environment Selection**: Must be specified via `--env` flag
2. **Variable Precedence**: Request > Environment > Imported > Base
3. **Header Inheritance**: Environment headers apply to all requests unless overridden or removed
4. **Header Removal**: Empty header value removes inherited header
5. **No Implicit Merging**: Explicit declarations always win

## Examples

### Basic API Testing with Variables
```http
// @environment local
Host: localhost:3000
@ApiVersion = v1
@Token = secret
Authorization: Bearer {{Token}}

###
GET /api/{{ApiVersion}}/users

###
// Override Authorization header
GET /api/{{ApiVersion}}/users/123
Authorization: Bearer different_token

###
// Remove Authorization header for public endpoint
GET /api/{{ApiVersion}}/public
Authorization:
```

### Multi-Environment with .env Files
```http
// @environment staging
// @envfile .env.staging
Host: {{API_HOST}}
Authorization: Bearer {{API_TOKEN}}
@Deployment = staging

// @environment production
// @envfile .env.production
Host: {{API_HOST}}
Authorization: Bearer {{API_TOKEN}}
@Deployment = prod

###
GET /health
X-Deployment: {{Deployment}}
```

**.env.staging**:
```env
API_HOST=staging-api.company.com
API_TOKEN=staging_token_123
```

**.env.production**:
```env
API_HOST=api.company.com
API_TOKEN=prod_token_456
```

### Advanced Header Management
```http
// @environment test
Host: api.test.com
Authorization: Bearer base_token
Content-Type: application/json
@UserID = 1001

###
// Uses all inherited headers
GET /users/{{UserID}}

###
// Override Content-Type
POST /users/{{UserID}}/avatar
Content-Type: multipart/form-data

###
// Remove Authorization for public endpoint
GET /public/feed
Authorization:

###
// Custom headers
GET /admin/users
Authorization: Bearer admin_token
X-Admin: true
```

### Bulk Operations
```http
// @environment production
Host: api.company.com
Authorization: Bearer {{TOKEN}}

###
GET /users/{{UserID}}/bookings
```

```bash
# Process multiple users with 'with' operator
cat user_ids.txt | ocurl --env production api.http with UserID

# CSV processing
cat data.csv | awk -F, '{print $1 " " $2}' | ocurl --env production api.http with UserID,Token
```

## CLI Usage

```bash
# Basic usage (environment required)
ocurl --env development api.http

# With .env file
ocurl --env staging --envfile .env.staging api.http

# Bulk processing with stdin
echo "/api/users/123" | ocurl --env production

# Multiple files
find tests/ -name "*.http" | xargs -I {} ocurl --env staging {}
```

## Intellectual Benefits

- **No Magic**: Every behavior is explicit in file syntax
- **Composable**: Works with standard Unix tools
- **Version Control Friendly**: Plain text files work with git
- **Environment Rigor**: No implicit context switching
- **Clear Header Management**: Explicit override and removal
- **.env Integration**: Standard environment variable support

This specification provides a foundation for sophisticated HTTP testing while maintaining intellectual rigor and Unix philosophy principles.

# OCurl - Technical Specification

## File Format & Syntax

### Environment & Variable Declaration

```http
// Load environment variables from file
@envfile: .env

// Environment blocks define variable sets
@environment maria
@user = Maria123
@password = {{MARIA_PASSWORD}}  // From .env file

@environment luis
@user = luis@prueba.com
@password = {{LUIS_PASSWORD}}

@environment prod
Host: prod.api.com/api

@environment dev
Host: dev.api.com/api
```

### Request Definitions

```http
###
@name login
POST /login
Content-Type: application/json

{
    "username": "{{user}}",
    "password": "{{password}}"
}

// Lazy variable assignment - evaluated when used
@jwt = {{ login.response.body | jq '.access_token' }}

###
@name me
GET /me
Authorization: Bearer {{jwt}}
```

## Variable System

### Types of Variables

**Static Variables**:
```http
@user = Maria123                    // Literal value
@password = {{ENV_VAR}}            // From environment file
@count = 42                        // Number
```

**Lazy Variables** (evaluated when used):
```http
// Response extraction using jq
@jwt = {{ login.response.body | jq '.access_token' }}
@user_id = {{ login.response.body | jq '.user.id' }}

// Response metadata
@status_code = {{ login.response.status }}
@content_type = {{ login.response.headers.Content-Type }}
```

### Response Access Syntax

```
[name].[response].[part]
```

Where:
- `[name]`: Request name (`@name login`)
- `response`: Fixed keyword
- `[part]`: One of:
  - `status`: HTTP status code
  - `body`: Response body
  - `headers`: All headers
  - `headers.HeaderName`: Specific header

## Environment Resolution

### Combining Environments

```bash
# Combine multiple environments
ocurl api.http -e dev -e maria -n login

# Precedence: right-to-left
# - 'maria' overrides 'dev' for conflicting variables
# - 'dev' provides base variables
```

### Variable Override Order
1. Command line `--var` (highest priority)
2. Environment combinations (right-to-left)
3. Individual environment definitions
4. Imported environment files
5. Base file variables (lowest priority)

## Command Line Usage

### Environment Selection
```bash
# Quick form
ocurl api.http -edev -eluis -nme

# Verbose form
ocurl api.http -e dev -e luis -n me

# With explicit variables
ocurl api.http -e dev -n me --var user=CustomUser --var password=xxx
```

### Input Processing
```bash
# CSV input with 'with' operator
grep 'LUIS' users.csv | ocurl api.http -e dev -n login with user,password

# JSON input with mixed variables
jq -r '.password' ~/.secrets.json | ocurl api.http -e dev -n login -vuser=SYSTEM with password

# Multiple variables from stdin
echo "user1 pass1" | ocurl api.http -e dev -n login with user,password
```

## Import System

### File Importing
```http
// Import another .http file (concatenates content)
@import ./auth.http

// Import with environment file
@envfile ./secrets.env
```

**Rules**:
- Imported files are concatenated to current file
- All environments/variables become available in merged scope
- Name conflicts: last definition wins
- Circular imports are detected and rejected

### Environment File Syntax
**.env files**:
```env
MARIA_PASSWORD=abc123
LUIS_PASSWORD=ZZZZ
API_KEY=sk_live_123
```

## Lazy Evaluation System

### Pipe Commands
Currently supported:
- `jq`: JSON processing (`jq '.access_token'`)
- Future: Other Unix commands may be added

### Evaluation Rules
```http
// Declaration doesn't execute the request
@jwt = {{ login.response.body | jq '.access_token' }}

// Evaluation happens when variable is USED
GET /me
Authorization: Bearer {{jwt}}  // <-- login executes here

// Multiple uses of same lazy variable reuse the cached response
GET /profile
Authorization: Bearer {{jwt}}  // <-- uses cached login response
```

## Execution Model

### Request Flow
1. Parse file, build dependency graph of lazy variables
2. Resolve environment combinations and variable values
3. Execute requests in dependency order
4. Evaluate lazy variables when their dependencies are available
5. Cache responses for reuse in same execution

### Error Handling
- Missing variables: Error before execution
- Failed requests: Subsequent dependent requests fail
- Pipe command failures: Variable evaluation fails
- Circular dependencies: Detection and error

## Examples

### Complete Workflow
```http
@envfile .env
@environment dev
Host: localhost:8080

@environment prod
Host: api.company.com

@environment admin
@user = admin@company.com
@password = {{ADMIN_PASSWORD}}

###
@name login
POST /auth/login
Content-Type: application/json

{"email": "{{user}}", "password": "{{password}}"}

@token = {{ login.response.body | jq '.token' }}

###
@name get_users
GET /api/users
Authorization: Bearer {{token}}
```

```bash
# Different combinations
ocurl api.http -e dev -e admin -n get_users
ocurl api.http -e prod -e admin -n get_users
ocurl api.http -e dev -n login --var user=test@test.com with password
```

This specification provides the technical foundation for implementation while maintaining the practical workflow benefits you need for rapid API testing and environment switching.
# OCurl - HTTP Client for the Intellectual Developer

## Philosophy

OCurl is built on three core principles:

1. **Explicit over Implicit** - No magic, no hidden state, no automatic behavior
2. **Composition over Monoliths** - Small tools that work together via Unix pipes
3. **Files over Databases** - Plain text configuration that works with version control

For developers who prefer `curl` over Postman, but want better organization for complex API workflows.

## Installation

```bash
# From source (OCaml required)
opam install ocurl
git clone https://github.com/yourname/ocurl
make && make install

# Or via package manager (future)
brew install ocurl
```

## Quick Start

### Basic Usage
```http
# api.http
@environment production
Host: api.company.com
@ApiVersion = v1

###
@name get_users
GET /api/{{ApiVersion}}/users

###
@name create_user
POST /api/{{ApiVersion}}/users
Content-Type: application/json

{"name": "{{name}}", "email": "{{email}}"}
```

```bash
# Single request
ocurl api.http -e production -n get_users

# With variable overrides
ocurl api.http -e production -n create_user --var name=John --var email=john@company.com
```

### Environment Switching
```http
# Multiple environments in one file
@environment staging
Host: staging.company.com
@log_level = debug

@environment production
Host: api.company.com
@log_level = info

@environment development
Host: localhost:8080
@log_level = trace
```

```bash
# Switch between environments
ocurl api.http -e staging -n get_users
ocurl api.http -e production -n get_users
ocurl api.http -e development -n get_users
```

## File Format Specification

### Core Structure
OCurl uses `.http` files containing environments, variables, and requests:

```http
// Optional: load environment variables
@envfile .env

// Environment blocks
@environment dev
Host: localhost:8080
@ApiVersion = v1

@environment prod
Host: api.company.com
@ApiVersion = v2

// Request definitions (separated by ###)
###
@name health_check
GET /health

###
@name create_item
POST /api/{{ApiVersion}}/items
Content-Type: application/json

{"name": "{{item_name}}", "type": "{{item_type}}"}
```

### Environment System

**Multiple Environment Combination**:
```bash
# Combine environments (right-to-left precedence)
ocurl api.http -e base -e user1 -e production -n request
```

**Environment Inheritance** (planned):
```http
@environment base
Host: {{HOST}}
@timeout = 30

@environment production
// @extends base
Host: api.company.com

@environment staging
// @extends base
Host: staging.company.com
```

### Variable System

**Static Variables**:
```http
@user_id = 12345
@api_key = {{API_KEY}}          // From environment file
@endpoint = /api/v1/users
```

**Lazy Variables** (evaluated when used):
```http
@name login
POST /auth/login
{"username": "{{user}}", "password": "{{pass}}"}

// Extract from response using jq
@access_token = {{ login.response.body | jq '.access_token' }}
@user_id = {{ login.response.body | jq '.user.id' }}

// Response metadata
@status_code = {{ login.response.status }}
@content_type = {{ login.response.headers.Content-Type }}
```

**Response Access Syntax**:
```
[name].[response].[part]
```
- `[name]`: Request name (`@name login`)
- `response`: Fixed keyword
- `[part]`: `status`, `body`, `headers`, or `headers.HeaderName`

### Request Definitions

**Basic Request**:
```http
###
@name get_user
GET /api/users/{{user_id}}
Authorization: Bearer {{token}}
```

**Request with Body**:
```http
###
@name create_user
POST /api/users
Content-Type: application/json

{
  "name": "{{name}}",
  "email": "{{email}}",
  "role": "{{role}}"
}
```

**External Body File**:
```http
###
@name create_user
POST /api/users
@bodyfile user_template.json
```

### Import System

**File Import**:
```http
// Import another .http file
@import ./auth.http

// All environments and requests become available
```

**Environment Files**:
```http
// Load variables from .env file
@envfile .env.production
```

**.env file format**:
```env
API_KEY=sk_live_123456
DB_HOST=localhost
SECRET_TOKEN=abc123
```

## Command Line Usage

### Basic Invocation
```bash
# Single request by name
ocurl api.http -e production -n get_users

# Multiple environments
ocurl api.http -e production -e admin_user -n get_users

# Quick form (single letter flags)
ocurl api.http -eprod -nget_users
```

### Variable Management
```bash
# Command-line variable overrides
ocurl api.http -e production -n create_user --var name=Alice --var email=alice@company.com

# Multiple variables
ocurl api.http -e production -n endpoint --var id=123 --var type=user --var action=update
```

### Bulk Processing
```bash
# Process multiple inputs with 'with' operator
echo "user1 pass1" | ocurl auth.http -n login with user,pass

# CSV processing
cat users.csv | ocurl api.http -n create_user with "name,email,department"

# Custom separator
echo "value1;value2;value3" | ocurl api.http -n request with "var1,var2,var3" --separator ";"
```

### Output Handling
```bash
# Save responses to files
ocurl api.http -e production -n get_users --save "responses/{{user_id}}.json"

# Pipe to other tools
ocurl api.http -e production -n get_users | jq '.data[] | select(.active == true)'
```

## Advanced Examples

### Authentication Flow
```http
# auth.http
@environment production
Host: auth.company.com

@environment development
Host: localhost:8081

###
@name login
POST /oauth/token
Content-Type: application/json

{
  "username": "{{user}}",
  "password": "{{pass}}",
  "grant_type": "password"
}

@access_token = {{ login.response.body | jq '.access_token' }}
@refresh_token = {{ login.response.body | jq '.refresh_token' }}

###
@name refresh
POST /oauth/token
Content-Type: application/json

{
  "refresh_token": "{{refresh_token}}",
  "grant_type": "refresh_token"
}
```

```bash
# Manual authentication flow
echo "username password" | ocurl auth.http -e production -n login with user,pass | jq -r '.access_token' | ocurl api.http -e production -n protected_request with access_token
```

### Multi-User Testing
```http
# users.http
@environment maria
@user = maria@company.com
@pass = maria_pass_123
@role = admin

@environment john
@user = john@company.com
@pass = john_pass_456
@role = user

@environment guest
@user = guest@company.com
@pass = guest_pass_789
@role = viewer

###
@name get_profile
GET /api/users/me
Authorization: Bearer {{token}}
```

```bash
# Test all users quickly
for user in maria john guest; do
  echo "Testing $user"
  ocurl auth.http -e $user -n login | jq -r '.access_token' | ocurl users.http -e $user -n get_profile with token
done
```

### Complex Workflow with Response Chaining
```http
# workflow.http
@environment production
Host: api.company.com

###
@name create_project
POST /api/projects
Content-Type: application/json

{"name": "{{project_name}}", "type": "{{project_type}}"}

@project_id = {{ create_project.response.body | jq '.id' }}

###
@name add_member
POST /api/projects/{{project_id}}/members
Content-Type: application/json

{"user_id": "{{user_id}}", "role": "{{role}}"}

@member_id = {{ add_member.response.body | jq '.id' }}

###
@name verify_member
GET /api/projects/{{project_id}}/members/{{member_id}}
```

```bash
# Execute entire workflow
echo "MyProject web 123 admin" | ocurl workflow.http -e production with "project_name,project_type,user_id,role"
```

## Tool Ecosystem

OCurl is composed of several specialized tools:

- `ocurl` - Core HTTP engine with variable substitution
- `ocurl-list` - Endpoint discovery and analysis
- `ocurl-run` - Flow execution with dependency resolution
- `ocurl-compare` - JSON comparison and diffing
- `ocurl-edit` - Interactive request editing

### Using Companion Tools

```bash
# Discover available endpoints
ocurl-list api.http

# Execute complex workflows
ocurl-run workflow.http -e production

# Compare API responses
ocurl api.http -e v1 -n endpoint | ocurl-compare structural --baseline v2_response.json
```

## Best Practices

### Organization
```
project/
├── http/
│   ├── api.http          # Main API definitions
│   ├── auth.http         # Authentication flows
│   ├── environments/     # Environment-specific files
│   │   ├── production.env
│   │   └── development.env
│   └── templates/        # JSON body templates
│       └── user_create.json
└── scripts/
    └── test_workflow.sh  # Complex testing scripts
```

### Security
```bash
# Keep secrets in .env files (add to .gitignore)
echo ".env.*" >> .gitignore

# Use different .env files per environment
ocurl api.http --envfile .env.production
ocurl api.http --envfile .env.staging
```

### Integration with Existing Tools
```bash
# JQ for JSON processing
ocurl api.http -e production -n get_users | jq '.data[] | select(.active)'

# Makefiles for complex workflows
test:
    @ocurl api.http -e testing -n smoke_test

load_test:
    @seq 1 100 | xargs -n 1 -P 10 ocurl api.http -e staging -n load_endpoint
```

## FAQ

**Q: How is this different from HTTPie or Postman?**
A: OCurl focuses on file-based configuration with explicit variable management, designed for developers who prefer plain text and Unix composition over GUI tools.

**Q: Can I use OCurl in CI/CD pipelines?**
A: Yes! OCurl is designed for automation and returns proper exit codes for successful (2xx) and failed (4xx/5xx) requests.

**Q: What about OAuth2 and other complex auth flows?**
A: OCurl provides the building blocks via response extraction and variable chaining. Complex flows can be implemented as shell scripts that compose OCurl calls.

**Q: Is there a GUI or web interface?**
A: No, and there never will be. OCurl is designed for the keyboard-centric developer.

---

*OCurl - Because your shell history shouldn't be your API documentation.*

# OCurl Tool Suite: ocurl-list & ocurl-compare

## ocurl-list - Endpoint Discovery & Analysis

### Overview
`ocurl-list` parses `.http` files and generates machine-readable output describing endpoints, dependencies, and execution requirements.

### Output Format
Uses a minimal S-expression format for easy parsing and composition:

```
(request
  (name "get_users")
  (method "GET")
  (path "/api/{{ApiVersion}}/users")
  (dependencies (host user_id token))
  (variables ())
)
```

### Dependency Resolution
The tool analyzes variable dependencies and execution chains:

```http
# General
@bookId = 13


@environment production
Host: api.com

@environment dev
Host: localhost:8080

###
@name login
POST /login
{"user": "{{user}}", "password": "{{password}}"}
@jwt = {{ login.response.body | jq '.token' }}

###
@name getBook
GET /books/{{bookId}}
Authorization: Bearer {{jwt}}
```

**Output**:
```
(variables
  (bookId 13)
  (jwt
    (references login)
    (values (login.response.body | jq '.token'))
  )

)

(environment
  (name "production")
  (variables (
    (host "api.com")
  ))
)

(environment
  (name "dev")
  (variables (
    (host "localhost:8080")
  ))
)

(request
  (name "login")
  (method "POST")
  (path "/login")
  (dependencies (host user password))
)

(request
  (name "getBook")
  (method "GET")
  (path "/books/{{bookId}}")
  (headers (
    (Authorization "Bearer {{jwt}}")
  ))
  (dependencies (host bookId jwt))
)
```

### Usage Examples

```bash
# List all endpoints with basic info
ocurl-list api.http

# Show detailed dependency graph
ocurl-list api.http --dependencies

# Check if a workflow can execute with given variables
ocurl-list workflow.http --check user=john,pass=xxx

# Generate execution order for a complex workflow
ocurl-list workflow.http --execution-order

# Show required variables for specific request
ocurl-list api.http --requirements getBook
```

### Command Flags
- `--dependencies` - Show full dependency graph
- `--requirements` - List required variables for execution
- `--execution-order` - Show optimal execution sequence
- `--check` - Verify if workflow can run with given variables
- `--format` - Output format (default: s-expr, alternatives: minimal, detailed)

## ocurl-compare - Structural Response Analysis

### Overview
`ocurl-compare` analyzes differences between API responses using structural comparison and patch-based diffs.

### Comparison Modes

#### Structural Comparison (Paths Only)
Ignores values, focuses on JSON structure:

```bash
# Compare two responses
ocurl api.http -e v1 -n endpoint | ocurl-compare structural --baseline v2_response.json

# Output shows added/removed/modified paths
```

**Output Format**:
```
=== Structural Changes ===
Added paths:
  $.users[*].metadata
  $.users[*].preferences

Removed paths:
  $.users[*].legacy_id
  $.users[*].old_settings

Modified paths:
  $.users[*].name (string -> object)
  $.pagination (object -> array)
```

#### Value-Agnostic Patch Format
Generates patch files showing structural differences:

```bash
# Generate patch between two responses
ocurl-compare patch old_response.json new_response.json > api_changes.patch
```

**Patch Format**:
```
--- old_response.json
+++ new_response.json
@@ -1,15 +1,17 @@
 {
   "users": [
     {
-      "id": "{{any}}",
-      "name": "{{any}}",
-      "legacy_id": "{{any}}"
+      "id": "{{any}}",
+      "name": "{{any}}",
+      "metadata": "{{any}}",
+      "preferences": "{{any}}"
     }
   ],
   "pagination": {
-    "page": "{{any}}",
-    "total": "{{any}}"
+    "{{any}}"
   }
 }
```

### Usage Examples

```bash
# Compare two endpoints across versions
ocurl api_v1.http -n get_users | ocurl-compare structural --baseline <(ocurl api_v2.http -n get_users)

# Generate migration patch
ocurl-compare patch legacy_api.json new_api.json > migration.patch

# Batch compare multiple endpoints
find tests/ -name "*.json" -exec ocurl-compare structural --baseline expected.json {} \;

# Monitor API changes over time
ocurl api.http -n health | ocurl-compare structural --baseline last_health.json --save
```

### Command Flags
- `structural` - Compare JSON paths only, ignore values
- `patch` - Generate value-agnostic patch file
- `--baseline` - Baseline file or stream for comparison
- `--save` - Save current output as new baseline
- `--ignore` - Paths to ignore in comparison
- `--output` - Output file for results

### Integration Examples

```bash
# CI/CD pipeline check
ocurl api.http -e production -n critical_endpoint | \
  ocurl-compare structural --baseline expected_structure.json || \
  echo "API structure changed!"

# Migration testing
ocurl-list legacy_api.http | while read endpoint; do
  ocurl legacy_api.http -n $endpoint > legacy.json
  ocurl new_api.http -n $endpoint > new.json
  ocurl-compare patch legacy.json new.json > "diffs/${endpoint}.patch"
done

# Structural regression detection
ocurl api.http -n endpoint | \
  ocurl-compare structural --baseline approved.json | \
  grep -q "Added paths" && \
  echo "New fields detected - requires review"
```

These tools provide the analytical foundation for understanding API dependencies and detecting structural changes across versions.
