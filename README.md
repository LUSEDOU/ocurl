# OCurl - HTTP Client Specification

## Overview

OCurl is a command-line HTTP client for API testing and automation. It uses plain text `.http` files with variable substitution, environment management, and automatic request dependency resolution.

**Design Philosophy**: OCurl is a technical tool that does exactly what you tell it to. It makes no assumptions about your data, doesn't auto-format responses, and exposes problems immediately rather than hiding them. If you need customization, extend it yourself - it's built to be scriptable and composable with standard Unix tools.

## Installation

```bash
# From source (OCaml required)
git clone https://github.com/LUSEDOU/ocurl
make && make install

# Via OPAM
opam install ocurl
```

## File Format Specification

### Document Structure

`.http` files consist of four distinct sections in strict order:

1. **Import Section** (optional): File and environment imports
2. **Global Section** (optional): Global variables and headers
3. **Environment Section** (optional): Named environment blocks
4. **Request Section** (required): HTTP request definitions

Each request is separated by `###` delimiter.

### Grammar

```
FILE := IMPORT_SECTION? GLOBAL_SECTION? ENVIRONMENT_SECTION? REQUEST_SECTION

IMPORT_SECTION := (@envfile PATH | @import PATH)*

GLOBAL_SECTION := (HEADER | VARIABLE)* EMPTY_LINE

ENVIRONMENT_SECTION := ENVIRONMENT_BLOCK* EMPTY_LINE

ENVIRONMENT_BLOCK := @environment NAME NEWLINE
                     (HEADER | VARIABLE)*
                     EMPTY_LINE

REQUEST_SECTION := (### REQUEST)*

REQUEST := REQUEST_LINE
           QUERY_PARAMS?
           HEADERS?
           EMPTY_LINE
           (BODY | @bodyfile PATH)?
           LAZY_VARIABLES?

REQUEST_LINE := @name NAME NEWLINE
                METHOD (URL | PATH)

QUERY_PARAMS := (? PARAM)+
                (& PARAM)*

PARAM := KEY = VALUE

HEADERS := (HEADER_NAME : HEADER_VALUE NEWLINE)*

VARIABLE := @ IDENTIFIER = VALUE

LAZY_VARIABLE := @ IDENTIFIER = {{ EXPRESSION }}

HEADER := HEADER_NAME : HEADER_VALUE

BODY := (non-empty-line NEWLINE)+ EMPTY_LINE

EMPTY_LINE := NEWLINE NEWLINE
```

### Section 1: Imports

Imports must appear at the very beginning of the file. They are processed in declaration order (later imports overwrite earlier ones).

```http
@envfile .env
@envfile ./config/production.env
@import ./auth.http
@import ./common-headers.http
```

**`.env` File Format**:
```env
API_KEY=sk_live_123
DB_HOST=localhost
BASE_URL=https://api.example.com
```

Rules:
- Syntax: `KEY=VALUE` per line
- No comments supported
- No quoted values: `KEY="VALUE"` is invalid
- Variable names follow `[A-Za-z_][A-Za-z0-9_]*` pattern
- Files are concatenated; any file extension accepted

**`@import` Behavior**:
- Concatenates entire file content at import location
- Accepts any file extension (`.http`, `.txt`, `.log`, etc.)
- Imported variables and headers can be overridden by later declarations
- Name conflicts resolved by last declaration wins

### Section 2: Global Variables and Headers

Global declarations apply to all requests across all environments unless explicitly overridden.

```http
@envfile .env
@import ./common.http

# Global headers (apply to every request)
User-Agent: OCurl/1.0
Accept: application/json

# Global variables (available in all environments)
@ApiVersion = v2
@Timeout = 30
@BaseUrl = https://api.example.com
```

**Rules**:
- Headers: `HeaderName: value` (any casing allowed, PascalCase preferred)
- Variables: `@VariableName = value`
- Section ends at first empty line (double newline)
- Variables can reference other variables: `@FullUrl = {{BaseUrl}}/api` and are
  computed lazily at request time
- Headers cannot be used as variables, but variables can be used in headers
- Only `Host` is special-cased for URL construction

### Section 3: Environment Blocks

Environments provide named configuration sets. Multiple environments can be active simultaneously with right-to-left precedence.

```http
@environment production
Host: api.company.com
@ApiVersion = v2
@RateLimit = 1000

@environment staging
Host: staging.company.com
@ApiVersion = v2-beta
@RateLimit = 100

@environment development
Host: localhost:8080
@ApiVersion = v1
@Debug = true
```

**Rules**:
- Syntax: `@environment name` followed by headers/variables
- Each environment block ends at empty line or next `@environment`
- Environments are selected via CLI: `-e production -e staging`
- Multiple `-e` flags: rightmost wins for conflicts
- Environment variables override global variables
- Environment headers override global headers

**Special Header Removal**:
```http
@environment test
User-Agent:              # Removes inherited User-Agent header
```
Empty value after `:` removes that header completely.

### Section 4: Request Definitions

Each request starts with `###` separator.

#### Request Structure

```http
###
@name request_name
METHOD /path/to/endpoint
?param1={{ var1 | default:abc }}
&param2={{ var2 }}
&literal_param=fixed_value
Header-Name: {{ variable }}
Custom-Header: literal value

{"key": "{{value}}", "nested": { "data": "{{data}}" }}

@result_var = {{ request_name.response.body | jq '.token' }}
@status = {{ request_name.response.status }}
```

#### Method and URL

```http
# Relative path (requires Host header)
GET /api/v2/users

# Absolute URL (ignores Host)
GET https://api.example.com/users

# With variable substitution
POST /api/{{ApiVersion}}/users
PUT {{BaseUrl}}/items/{{itemId}}
```

**Supported Methods**: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`

#### Query Parameters

Query parameters start on the line immediately after the request line:

```http
GET /api/search
?query={{ searchTerm | default:test }}
&limit={{ limit | default:10 }}
&offset=0
&filter=active
```

**Rules**:
- First parameter uses `?`, subsequent use `&`
- Can span multiple lines, each starting with `?` or `&`
- Variable substitution supported: `{{ var | default:value }}`
- Literal values allowed: `&param=literal_value`
- URL encoding is applied automatically
- Complex values: `&coords=1;2;3;4` (semicolons preserved as-is)

**Optional vs Required Parameters**:

OCurl does not distinguish between optional and required query parameters at parse time. If a variable is missing and has no default, the request fails with a dependency error. Use `default:` pipe to make parameters truly optional.

#### Headers

Headers appear after query parameters (or request line if no params):

```http
POST /api/users
?include=profile
Content-Type: application/json
Authorization: Bearer {{ jwt }}
X-Request-ID: {{ request_id | default:auto-generated }}
Custom-Header: literal-value
```

**Rules**:
- Syntax: `HeaderName: value`
- Any casing accepted (PascalCase, camelCase, lowercase)
- Variable substitution: `{{ var }}`
- Lazy evaluation: `{{ login.response.headers.Set-Cookie }}`
- Chain expressions: `{{ user.response.body | jq '.token' }}`
- Literal values mixed with variables: `Bearer {{ token }}`
- Reserved header: `Host` (used for URL construction)

#### Body

Body starts after the first empty line following headers:

```http
POST /api/users
Content-Type: application/json

{"name": "{{name}}", "email": "{{email}}", "age": {{age}}}
```

**Single-line body**:
```http
POST /api/simple

{"quick": "{{data}}"}
```

**Multi-line body** (no blank lines allowed inside):
```http
POST /api/complex

{
  "user": {
    "name": "{{name}}",
    "profile": {{ me.response.body | jq '.profile' }}
  },
  "timestamp": "{{timestamp}}"
}
```

**Body Rules**:
- Body starts after first double-newline following headers
- Ends at next double-newline or EOF
- **No blank lines allowed inside body** - blank line terminates body
- Variable substitution: `{{var}}`
- Lazy variables: `{{ request.response.body }}`
- Pipe expressions: `{{ data | jq '.field' }}`
- **No JSON validation** - syntax errors are user responsibility
- **No Content-Type assumptions** - always specify explicitly
- Trailing newlines stripped to create single-line payload

**External Body Files**:
```http
POST /api/bulk
Content-Type: application/json

@bodyfile ./data/payload.json
```

**@bodyfile Rules**:
- Reads entire file content as-is
- Any extension accepted (`.json`, `.xml`, `.txt`, etc.)
- Variables substituted immediately (non-lazy only)
- No validation or parsing of file content
- Lazy variables in body file are NOT supported (performance)

**Form Data Example**:
```http
POST /api/form
Content-Type: application/x-www-form-urlencoded

form1=abc
&form2={{ somevar }}
&form3={{ other.response.body | jq '.field' }}
```

OCurl treats form data as plain text body. Proper encoding is user responsibility.

#### Lazy Variables (Response Chaining)

Lazy variables create dependencies between requests:

```http
###
@name login
POST /auth/login

{"username": "{{user}}", "password": "{{pass}}"}

@jwt = {{ login.response.body | jq '.token' }}
@user_id = {{ login.response.body | jq '.user.id' }}
@session = {{ login.response.headers.Set-Cookie }}

###
@name get_profile
GET /api/users/{{user_id}}
Authorization: Bearer {{jwt}}
Cookie: {{session}}
```

**Response Access Syntax**:
- `{{ request_name.response.status }}` - HTTP status code (e.g., 200, 404)
- `{{ request_name.response.body }}` - Full response body as string
- `{{ request_name.response.headers }}` - All headers as JSON object
- `{{ request_name.response.headers.HeaderName }}` - Specific header value

**Pipe Expressions**:
```http
@token = {{ login.response.body | jq '.access_token' }}
@count = {{ search.response.body | jq '.results | length' }}
@header = {{ api_call.response.headers.X-Custom }}
```

**Lazy Variable Rules**:
- Declared after request body (or after headers if no body)
- Create global scope variables (accessible by any subsequent request)
- Require `@name` on source request (unnamed requests cannot produce variables)
- Evaluation is deferred until variable is used
- Dependencies auto-detected and resolved via topological sort
- Circular dependencies cause immediate failure
- Referenced request executes exactly once per ocurl invocation
- Results cached within single execution, not across invocations

**Dependency Resolution**:
When request B uses `{{var}}` where `@var` references request A:
1. OCurl detects B depends on A
2. A executes first (recursively resolving A's dependencies)
3. A's response stored in memory
4. `@var` pipe expression evaluates
5. B executes with resolved `{{var}}`

If dependencies are satisfied via CLI (`-v var=value`), referenced request does NOT execute.

### Variable Substitution

**Syntax**: `{{ variable_name }}`

**With Defaults**: `{{ variable_name | default:fallback_value }}`

**Examples**:
```http
GET /api/{{version}}/users/{{userId}}
Authorization: Bearer {{ token | default:anonymous }}
?search={{ query | default:* }}

{"name": "{{name}}", "optional": "{{ opt | default:none }}"}
```

**Escaping**: `\{{literal}}` renders as literal `{{literal}}` text

**Variable Resolution**: See "Resolution and Precedence Rules" section below.

## Resolution and Precedence Rules

### Variable Resolution Order (Highest to Lowest Priority)

1. **CLI Variables** (`-v key=value`, left-to-right order)
   ```bash
   ocurl file.http -v user=Alice -v user=Bob  # Bob wins
   ```

2. **Request-scoped Lazy Variables** (declared after request body)
   ```http
   @local_var = {{ some.response.body }}
   ```

3. **Environment Variables** (right-to-left with `-e` flags)
   ```bash
   ocurl file.http -e base -e prod -e override  # override > prod > base
   ```

4. **Global Variables** (order of declaration in file)
   ```http
   @var = first
   @var = second  # second wins
   ```

5. **Imported Variables** (from `@import` and `@envfile`, order matters)

### Header Resolution Order (Highest to Lowest Priority)

1. **Request-level Headers** (defined in request block)
2. **Environment Headers** (from selected `-e` environments)
3. **Global Headers** (defined at file top)
4. **Imported Headers** (from `@import`)

**Header Removal**: Empty value removes inherited header
```http
@environment test
Authorization:    # Removes any inherited Authorization header
```

### Dependency Satisfaction

When `{{var}}` is used in a request:

1. Check CLI variables (`-v var=...`)
2. Check environment variables (active `-e` environments)
3. Check global variables
4. **If variable is lazy (references request)**:
   - Add source request to dependency graph
   - Recursively resolve source request's dependencies
   - Execute source request if not already cached
   - Evaluate pipe expression
   - Substitute result

5. **If variable not found**: Fail with "dependency incomplete" error

**Circular Dependency Detection**:
```http
###
@name A
GET /a
@var_a = {{ B.response.body }}

###
@name B
GET /b
@var_b = {{ A.response.body }}
```
Result: **Immediate failure** - circular dependencies are user errors. OCurl does not attempt recovery.

## Command Line Interface

### Basic Usage

```bash
# Execute single request
ocurl file.http -n request_name

# With environment
ocurl file.http -e production -n get_users

# Multiple environments (right-to-left precedence)
ocurl file.http -e base -e production -e override -n request

# Override variables
ocurl file.http -e prod -n create_user -v name=John -v email=john@example.com

# External environment file
ocurl file.http --envfile ./secrets.env -n protected_request
```

### Flags

- **`-n, --name NAME`** - Select request by `@name`
- **`-e, --environment ENV`** - Activate environment(s), can be repeated
- **`-v, --var KEY=VALUE`** - Set variable, can be repeated
- **`--envfile PATH`** - Load `.env` file (additional to `@envfile` in .http)
- **`--with VARS`** - Bulk input mode (see below)
- **`--separator SEP`** - Custom input separator (default: space)
- **`-o, --output PATH`** - Output file pattern for bulk mode

### Bulk Input Mode

Execute the same request multiple times with different variable sets:

```bash
# Space-separated (default)
echo "user1 pass1" | ocurl auth.http -n login with user,password
echo "Alice alice@example.com" | ocurl api.http -n create_user with name,email

# Custom separator
echo "Alice;alice@example.com;Engineering" | \
  ocurl api.http -n create_user with name,email,dept --separator ";"

# Alternative syntax (separator in 'with' clause)
echo "Alice;alice@example.com" | \
  ocurl api.http -n create_user with;name,email

# Multiple rows from file
cat users.csv | ocurl api.http -n create_user with name,email,department

# With output files
cat input.txt | ocurl api.http -n process with data -o result_{n}.json
```

**Bulk Mode Rules**:
- Each input line triggers one request execution
- Number of input columns must match number of variables in `with`
- Mismatch causes "dependency incomplete" error for that row
- Errors are independent - one failure doesn't stop others
- Default separator: space (` `)
- Custom separator: `--separator "SEP"` or `with;var1,var2`
- Output without `-o`: concatenated to stdout
- Output with `-o`: uses `{n}` pattern (e.g., `result_{n}.json` → `result_0.json`, `result_1.json`, ...)

**Example Input File** (`users.csv`):
```
Alice alice@example.com Engineering
Bob bob@example.com Marketing
Charlie charlie@example.com Sales
```

```bash
cat users.csv | ocurl api.http -e prod -n create_user with name,email,department
```

Output (stdout):
```json
{"id": 1, "name": "Alice", "email": "alice@example.com", "department": "Engineering"}
{"id": 2, "name": "Bob", "email": "bob@example.com", "department": "Marketing"}
{"id": 3, "name": "Charlie", "email": "charlie@example.com", "department": "Sales"}
```

## Tool Ecosystem

### ocurl-list - Static Analysis

Analyzes `.http` files and outputs structured information about requests, dependencies, and variables.

**Output Format**: S-expressions (machine-readable, optimized for parsing)

```bash
ocurl-list api.http                    # List all requests and variables
ocurl-list api.http --dependencies     # Show dependency graph
ocurl-list api.http --requirements     # List required variables per request
ocurl-list api.http --execution-order  # Topological sort of requests
ocurl-list api.http --json             # Output as JSON instead
```

**S-expression Output Example**:

```lisp
(variables
  (Host "api.example.com")
  (ApiVersion "v2")
  (bookId "13")
  (BaseUrl
    (dependencies (Host))
    (expr "{{ Host }}/api")
  )
  (jwt (ref "login"))
)

(environment
  (name "production")
  (variables
    (Host "api.company.com")
    (RateLimit "1000")
  )
  (headers
    (X-Environment "production")
  )
)

(environment
  (name "development")
  (variables
    (Host "localhost:8080")
    (Debug "true")
  )
)

(request
  (name "login")
  (method "POST")
  (path "/auth/login")
  (query-params
    (remember "{{ remember }}")
  )
  (headers
    (Content-Type "application/json")
  )
  (body "{\"username\":\"{{user}}\",\"password\":\"{{pass}}\"}")
  (dependencies (Host user pass remember))
  (produces
    (jwt "{{ login.response.body | jq '.token' }}")
    (user_id
      (ref "login")
      (expr "{{ login.response.body | jq '.user.id' }}")
    )
  )
  (variables
    (remember false)
  )
)

(request
  (name "getBook")
  (method "GET")
  (path "/api/{{ApiVersion}}/books/{{bookId}}")
  (query-params
    (reviews "true")
    (search "{{ search }}")
  )
  (headers
    (Authorization "Bearer {{jwt}}")
  )
  (dependencies (Host ApiVersion bookId jwt search))
  (variables
    (search "")
  )
)

(request
  (name "updateBook")
  (method "PUT")
  (path "/api/{{ApiVersion}}/books/{{bookId}}")
  (headers
    (Authorization "Bearer {{ jwt }}")
  )
  (body
    (path "./update_book_payload.json")
  )
  (dependencies (Host ApiVersion bookId jwt))
)
```

**Field Explanations**:

- **`variables`**: Global and lazy variables
  - Simple: `(name "value")`
    * Uses `"` when the value is a literal string. If only supports string, int,
      bool and double types.
  - Lazy: `(name (ref "request_name"))`
    * `ref`: Source request name. Not evaulated here, could not exist yet.

- **`environment`**: Environment-specific overrides
  - `variables`: Variables defined in this environment
  - `headers`: Headers defined in this environment

- **`request`**: Individual request definition
  - `name`: Request identifier from `@name`
  - `method`: HTTP method
  - `path`: URL path with variables unresolved
  - `query-params`: Query parameters
    * Key-value pairs, values may contain variables
  - `headers`: Request headers
  - `body`: Request body (if present)
    * Inline body as string
    * External body file path
  - `dependencies`: All variables used by this request
  - `produces`: Variables created by this request's lazy declarations
  - `variables`: Request-scoped variables with defaults

**`--dependencies` Output**:
```lisp
(dependency-graph
  (login (depends-on ()))
  (getBook (depends-on (login)))
  (updateBook (depends-on (login getBook)))
)
```

**`--requirements` Output**:
```lisp
(requirements
  (request "login"
    (required (Host user pass))
    (optional (remember))
  )
  (request "getBook"
    (required (Host ApiVersion bookId))
    (provided-by (login))
  )
)
```

**`--execution-order` Output**:
```lisp
(execution-order
  (login)
  (getBook)
  (updateBook)
)
```

**JSON Output** (`--json` flag):
```json
{
  "variables": {
    "Host": {"type": "static", "value": "api.example.com"},
    "jwt": {
      "type": "lazy",
      "ref": "login",
      "expr": "{{ login.response.body | jq '.token' }}"
    }
  },
  "requests": [
    {
      "name": "login",
      "method": "POST",
      "path": "/auth/login",
      "dependencies": ["Host", "user", "pass"],
      "produces": ["jwt", "user_id"]
    }
  ]
}
```

### ocurl-compare - Response Analysis

Compares API responses structurally, ignoring specific values.

**Structural Comparison**:
```bash
# Compare live response against baseline
ocurl api.http -e v2 -n endpoint | \
  ocurl-compare structural --baseline v1_response.json

# Compare two saved responses
ocurl-compare structural baseline.json new_response.json
```

**Output**:
```
Structural Differences:
  Added paths:
    $.users[*].metadata
    $.users[*].profile.avatar_url

  Removed paths:
    $.users[*].legacy_id
    $.timestamp

  Type changes:
    $.users[*].name: string -> object
    $.users[*].age: string -> integer
```

**Patch Generation**:
```bash
ocurl-compare patch old.json new.json > changes.patch
```

**Patch Format**:
```diff
--- old.json
+++ new.json
@@ -1,7 +1,8 @@
 {
   "users": [
     {
-      "id": "{{any}}"
+      "id": "{{any}}",
+      "metadata": "{{any}}"
     }
   ]
 }
```

**`{{any}}` Symbol**: Placeholder indicating "any value of this type accepted". Used to focus on structure rather than specific values.

**Patch Application** (manual):
Patches show structural changes for documentation/review. OCurl does not auto-apply patches - this is a comparison tool, not a migration tool.

## Examples

### 1. Simple Request

```http
GET https://api.github.com/users/octocat
```

```bash
ocurl simple.http
```

### 2. Authentication Flow

**File: `auth.http`**
```http
@environment production
Host: auth.company.com

@environment development
Host: localhost:3000

###
@name login
POST /oauth/token
Content-Type: application/json

{"username": "{{user}}", "password": "{{password}}"}

@access_token = {{ login.response.body | jq '.access_token' }}
@refresh_token = {{ login.response.body | jq '.refresh_token' }}

###
@name refresh
POST /oauth/refresh
Content-Type: application/json

{"refresh_token": "{{refresh_token}}"}

@access_token = {{ refresh.response.body | jq '.access_token' }}

###
@name protected_resource
GET /api/protected
Authorization: Bearer {{access_token}}
```

**Usage**:
```bash
# Login and access protected resource (automatic chaining)
ocurl auth.http -e production -n protected_resource \
  -v user=alice -v password=secret123

# Manual token passing
echo "alice secret123" | ocurl auth.http -e prod -n login with user,password | \
  jq -r '.access_token' | \
  xargs -I {} ocurl api.http -e prod -n protected_resource -v access_token={}
```

### 3. Multi-Environment Testing

**File: `users.http`**
```http
@Host = api.company.com

@environment admin
@role = admin
@user_email = admin@company.com

@environment regular_user
@role = user
@user_email = user@company.com

@environment readonly
@role = readonly
@user_email = readonly@company.com

###
@name create_item
POST /api/items
Content-Type: application/json

{
  "name": "{{item_name}}",
  "created_by": "{{user_email}}",
  "role": "{{role}}"
}
```

**Usage**:
```bash
# Test across all roles
for role in admin regular_user readonly; do
  echo "Testing as $role"
  ocurl users.http -e production -e $role -n create_item -v item_name="Test Item"
done
```

### 4. Complex Workflow with Dependencies

**File: `workflow.http`**
```http
@environment production
Host: api.company.com
@ApiVersion = v2

###
@name create_project
POST /api/{{ApiVersion}}/projects
Content-Type: application/json

{"name": "{{project_name}}", "owner": "{{owner_id}}"}

@project_id = {{ create_project.response.body | jq '.id' }}
@project_status = {{ create_project.response.status }}

###
@name add_member
POST /api/{{ApiVersion}}/projects/{{project_id}}/members
Content-Type: application/json

{"user_id": "{{member_id}}", "role": "{{member_role | default:contributor}}"}

@membership_id = {{ add_member.response.body | jq '.membership_id' }}

###
@name verify_membership
GET /api/{{ApiVersion}}/projects/{{project_id}}/members/{{membership_id}}

###
@name create_task
POST /api/{{ApiVersion}}/projects/{{project_id}}/tasks
Content-Type: application/json

{
  "title": "{{task_title}}",
  "assigned_to": "{{membership_id}}",
  "description": "{{task_description | default:No description}}"
}
```

**Usage**:
```bash
# Single execution with dependency chain
ocurl workflow.http -e production -n create_task \
  -v project_name="New Project" \
  -v owner_id=123 \
  -v member_id=456 \
  -v task_title="First Task"

# Bulk create tasks for project
echo "Setup environment Task 1
Implement feature Task 2
Write tests Task 3" | \
  ocurl workflow.http -e production -n create_task \
    with task_title,task_description \
    -v project_name="Bulk Project" \
    -v owner_id=123 \
    -v member_id=456
```

### 5. Bulk User Creation

**File: `bulk_users.http`**
```http
Host: api.example.com

###
@name create_user
POST /api/users
Content-Type: application/json

{
  "name": "{{name}}",
  "email": "{{email}}",
  "department": "{{department}}",
  "role": "{{role | default:user}}"
}
```

**Input: `users.txt`**
```
Alice alice@company.com Engineering developer
Bob bob@company.com Marketing manager
Charlie charlie@company.com Sales user
```

**Usage**:
```bash
cat users.txt | ocurl bulk_users.http -n create_user \
  with name,email,department,role \
  -o user_{n}.json

# Creates: user_0.json, user_1.json, user_2.json
```

## Error Handling

### Error Types

1. **Dependency Incomplete**
   ```
   Error: Variable 'user_id' not found
     Required by: request 'get_profile' (line 23)
     Available variables: access_token, username, email

   Hint: Provide via -v user_id=VALUE or ensure 'login' request executes first
   ```

2. **Circular Dependency**
   ```
   Error: Circular dependency detected
     Chain: login -> get_profile -> update_user -> login

   This is a user error. Restructure requests to break the cycle.
   ```

3. **Request Failed (Server Error)**
   ```
   Error: Request 'login' failed
     Status: 401 Unauthorized
     Response: {"error": "Invalid credentials"}

   Dependent requests skipped: get_profile, update_settings
   ```

4. **Pipe Command Failed**
   ```
   Error: Lazy variable evaluation failed
     Variable: jwt
     Expression: {{ login.response.body | jq '.token' }}
     Reason: jq: command not found

   Install jq or modify expression.
   ```

5. **Bulk Input Mismatch**
   ```
   Error: Input column count mismatch (line 3)
     Expected: 3 variables (name, email, department)
     Received: 2 values (Charlie, charlie@example.com)

   Line 3 skipped. Other executions continue.
   ```

6. **Missing Request Name**
   ```
   Error: Request not found
     Requested: -n get_user
     Available: login, create_user, list_users

   Check request @name declarations in file.
   ```

### Error Behavior

- **In bulk mode**: Errors are independent. One failure doesn't stop other rows.
- **In dependency chains**: If request A fails, all requests depending on A are skipped.
- **Missing `jq`**: Lazy variables with `| jq` fail immediately if jq not installed.
- **No retries**: OCurl executes each request exactly once. Retry logic is user responsibility (wrap in shell script).

## Technical Specifications

### Supported Pipe Commands

Currently supported:
- **`jq 'expression'`** - JSON processing (requires jq installed)

Future extensibility: Add custom pipe commands by extending the pipe evaluator. OCurl doesn't restrict which commands can be piped - any executable accepting stdin can be used in theory, but only `jq` is officially documented and tested.

### Execution Model

1. **Parse** `.http` file and build AST
2. **Resolve imports** (@import, @envfile) and merge
3. **Build dependency graph** from lazy variable references
4. **Topological sort** to determine execution order
5. **Detect cycles** - fail immediately if found
6. **Execute requests** in order:
   - Substitute non-lazy variables
   - Check if dependencies satisfied (via CLI or previous execution)
   - Execute request if dependencies not yet satisfied
   - Cache response in memory
   - Evaluate lazy variables using cached responses
7. **Output results** to stdout or files

**Caching Behavior**:
- Responses cached within single `ocurl` invocation
- Cache cleared after process exits
- No persistent cache across invocations
- If same request referenced multiple times, executes only once

**Concurrency**: Linear execution. No parallel requests (future consideration).

### Supported Content Types

OCurl makes **no assumptions** about content types. You must specify `Content-Type` header explicitly:

- `application/json` - JSON bodies
- `application/x-www-form-urlencoded` - Form data
- `text/plain` - Plain text
- `application/xml` - XML
- Any custom type

OCurl does not validate, parse, or format request/response bodies. That's your responsibility or your tools' (e.g., `jq` for JSON).

## Limits & Boundaries

### What OCurl Does NOT Do

**No Automatic Features**:
- No credential storage or management
- No automatic token refresh
- No session persistence across invocations
- No GUI or interactive mode
- No response formatting or pretty-printing
- No built-in retry or timeout configuration
- No parallel request execution
- No JSON schema validation
- No automatic encoding detection

**No Flow Control**:
- No conditionals (if/else)
- No loops (except bulk mode which is data-driven)
- No error recovery or automatic retries
- No rate limiting or throttling
- No request cancellation

**No Complex Authentication**:
- No OAuth flow automation
- No SAML handling
- No certificate-based auth helpers
- No automatic cookie management

**No File Handling**:
- No multipart/form-data file uploads
- No binary response handling (responses treated as text)
- No automatic file download
- No progress indicators for large transfers

**No Assertion Framework**:
- No built-in test assertions
- No response validation
- No schema checking
- Use external tools (jq, grep, etc.) for validation

### Security Constraints

**Explicit Security Model**:
- Secrets must be managed externally (`.env` files, CLI args, stdin)
- No encrypted configuration support
- No credential encryption at rest
- Plaintext `.http` files - do not commit secrets
- Variables visible in process list when using `-v`
- Use `.gitignore` for `.env` files

**Recommendations**:
```bash
# .gitignore
*.env
.env.*
secrets.http

# Safe usage
export TOKEN=$(vault read -field=token secret/api)
ocurl api.http -n request -v token=$TOKEN

# Or use envfile
vault read -field=token secret/api > .env
ocurl api.http --envfile .env -n request
```

### Performance Characteristics

**Linear Execution**:
- Requests execute sequentially in dependency order
- No parallel execution (even for independent requests)
- Each request waits for full response before proceeding

**Response Caching**:
- In-memory only
- Single invocation scope
- No LRU eviction (all responses kept until exit)
- Memory usage grows with number of executed requests

**No Persistent State**:
- Each `ocurl` invocation is independent
- No session files
- No request history
- No automatic token refresh across runs

**Scalability Limits**:
- Bulk mode processes rows sequentially
- Large `.http` files (1000+ requests) may have slow parse times
- Response bodies kept in memory (large responses consume RAM)
- No streaming for large responses

### Variable Limitations

**Name Restrictions**:
- Pattern: `[A-Za-z_][A-Za-z0-9_]*`
- Case-sensitive
- No spaces, hyphens, or special characters
- Reserved: `Host` (special URL construction behavior)

**Value Limitations**:
- No multiline values in variable declarations
- No nested variable substitution: `{{ {{var}} }}` invalid
- No arithmetic: `{{ count + 1 }}` invalid (use jq in lazy vars)
- No string interpolation beyond simple substitution

**Scope Rules**:
- Lazy variables always create global scope
- No request-private variables (except via unique names)
- Variable shadowing follows precedence rules (no warnings)

### Pipe Expression Constraints

**Pipe Syntax**:
- Single pipe chain: `{{ expr | cmd 'arg' }}` valid
- Multiple pipes: `{{ expr | jq '.field' | jq '.nested' }}` **NOT SUPPORTED**
- Workaround: Chain in single jq expression: `{{ expr | jq '.field.nested' }}`

**Command Requirements**:
- Must be executable in `$PATH`
- Must accept stdin and produce stdout
- Exit code 0 = success, non-zero = failure
- Only `jq` is officially supported and documented

**Error Handling**:
- Command not found: immediate error
- Command failure: variable evaluation fails
- Non-zero exit: request fails with pipe error
- No fallback or default on pipe failure

### HTTP Protocol Limitations

**Supported**:
- HTTP/1.1 (primary)
- HTTPS with system certificates
- Standard methods: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- Custom headers (any name/value)
- Query parameters with encoding
- Request bodies (text-based)

**Not Supported**:
- HTTP/2 or HTTP/3 (depends on underlying HTTP library)
- WebSockets
- Streaming responses
- Chunked upload
- Multipart form data with files
- Client certificate authentication
- Custom SSL/TLS configuration
- Proxy configuration (use system proxy settings)
- Cookie jar management (manual via headers)

**Redirect Behavior**:
Implementation-defined (likely follows redirects automatically). Use underlying HTTP library's default behavior.

**Timeout Behavior**:
Implementation-defined. No explicit timeout configuration. Use system defaults or wrap in `timeout` command:
```bash
timeout 30s ocurl api.http -n slow_request
```

### Dependency Resolution Constraints

**Topological Sort**:
- Requires DAG (Directed Acyclic Graph)
- Circular dependencies fail immediately
- No heuristic resolution attempts

**Complexity**:
- Large dependency chains (50+ requests) may be slow to analyze
- Deep nesting (10+ levels) may hit recursion limits

**Ambiguity**:
If variable can be satisfied multiple ways (CLI, environment, global), OCurl picks first match in precedence order without warning about alternatives.

### Bulk Mode Constraints

**Input Format**:
- Line-based only
- Single separator character
- No quoted fields (CSV-style quoting not supported)
- Separator in data requires custom separator choice
- Empty fields treated as empty strings, not missing

**Output Format**:
- Stdout: concatenated JSON (one per line) or raw responses
- File mode: one file per execution, sequential numbering
- No error output separation (errors go to stderr, success to stdout/file)

**Scalability**:
- No parallelism
- Row N+1 doesn't execute until row N completes
- Large input files (10,000+ rows) will be slow

### File Format Limitations

**No Comments**:
```http
# This is NOT a comment
GET /api/endpoint  # Neither is this
```
Comments are not supported. Text outside structured sections is ignored or may cause parse errors.

**No Includes with Parameters**:
```http
@import ./template.http?param=value  # NOT SUPPORTED
```
Imports are static file concatenation only.

**No Conditional Sections**:
```http
@if production
Host: api.production.com
@else
Host: localhost
@endif
```
Not supported. Use separate environment blocks.

**Whitespace Sensitivity**:
- Empty line (double newline) has semantic meaning
- Trailing spaces in headers/values preserved
- Leading spaces in body preserved
- Inconsistent whitespace may cause parse errors

**No Line Continuations**:
```http
Header: very-long-value-that-spans \
  multiple lines  # NOT SUPPORTED
```
Headers and values must be single-line.

### Environment File Constraints

**`.env` Syntax**:
```env
# Valid
KEY=value
KEY=value with spaces
KEY=

# Invalid
KEY="quoted value"  # Quotes included literally
KEY = value         # Spaces around = invalid
# This is a comment  # Comments not supported
export KEY=value    # export keyword invalid
```

**Limitations**:
- No quotes (they become part of value)
- No comments
- No multiline values
- No variable expansion: `KEY2=$KEY1/path` doesn't expand
- No `export` or shell syntax

## Project Structure Recommendations

```
project/
├── .gitignore
├── http/
│   ├── api.http              # Main API definitions
│   ├── auth.http             # Authentication flows
│   ├── admin.http            # Admin endpoints
│   │
│   ├── environments/
│   │   ├── base.env          # Shared config
│   │   ├── production.env    # Production secrets
│   │   ├── staging.env       # Staging secrets
│   │   └── development.env   # Dev config
│   │
│   ├── workflows/
│   │   ├── user_onboarding.http
│   │   ├── data_migration.http
│   │   └── nightly_jobs.http
│   │
│   └── common/
│       ├── headers.http      # Common headers
│       └── auth.http         # Reusable auth requests
│
├── scripts/
│   ├── test_all_envs.sh      # Cross-environment testing
│   ├── bulk_import.sh        # Bulk data scripts
│   └── ci_smoke_tests.sh     # CI integration
│
├── data/
│   ├── users.csv             # Bulk input data
│   └── payloads/
│       ├── create_user.json
│       └── update_profile.json
│
└── docs/
    └── api_workflows.md      # Documentation
```

**`.gitignore` Template**:
```gitignore
# Environment secrets
*.env
.env
.env.*
!.env.example

# Sensitive HTTP files
*secrets.http
*prod.http

# Output files
*.response.json
output_*.json
results/
```

## Advanced Patterns

### Pattern 1: Conditional Execution via Environments

Simulate conditionals using environment selection:

```http
@environment use_auth
@auth_header = Authorization: Bearer {{token}}

@environment no_auth
@auth_header =

###
@name api_call
GET /api/resource
{{auth_header}}
```

```bash
# With auth
ocurl api.http -e use_auth -n api_call -v token=abc123

# Without auth
ocurl api.http -e no_auth -n api_call
```

### Pattern 2: Retry Logic (External)

```bash
#!/bin/bash
# retry.sh
MAX_RETRIES=3
RETRY_DELAY=5

for i in $(seq 1 $MAX_RETRIES); do
  if ocurl api.http -n flaky_request; then
    echo "Success on attempt $i"
    exit 0
  fi
  echo "Attempt $i failed, retrying in ${RETRY_DELAY}s..."
  sleep $RETRY_DELAY
done

echo "Failed after $MAX_RETRIES attempts"
exit 1
```

### Pattern 3: Response Validation

```bash
# Test status code
ocurl api.http -n health_check | jq -e '.status == "ok"' || exit 1

# Test response structure
ocurl api.http -n get_user | jq -e 'has("id") and has("email")' || exit 1

# Compare against baseline
ocurl api.http -n endpoint | ocurl-compare structural --baseline baseline.json
```

### Pattern 4: Token Refresh Flow

```http
@environment api
Host: api.example.com

###
@name login
POST /auth/login

{"username": "{{user}}", "password": "{{pass}}"}

@access_token = {{ login.response.body | jq '.access_token' }}
@refresh_token = {{ login.response.body | jq '.refresh_token' }}
@expires_at = {{ login.response.body | jq '.expires_at' }}

###
@name protected_call
GET /api/protected
Authorization: Bearer {{access_token}}

###
@name refresh_access
POST /auth/refresh

{"refresh_token": "{{refresh_token}}"}

@access_token = {{ refresh_access.response.body | jq '.access_token' }}
```

**Shell Script for Auto-Refresh**:
```bash
#!/bin/bash
# auto_refresh.sh

# Login
TOKENS=$(ocurl api.http -e api -n login -v user=alice -v pass=secret)
ACCESS=$(echo "$TOKENS" | jq -r '.access_token')
REFRESH=$(echo "$TOKENS" | jq -r '.refresh_token')

# Make call
ocurl api.http -e api -n protected_call -v access_token="$ACCESS"

# If expired (you check manually or detect 401), refresh
if [ $? -ne 0 ]; then
  NEW_ACCESS=$(ocurl api.http -e api -n refresh_access -v refresh_token="$REFRESH" | jq -r '.access_token')
  ocurl api.http -e api -n protected_call -v access_token="$NEW_ACCESS"
fi
```

### Pattern 5: Multi-Stage Pipeline

```bash
#!/bin/bash
# pipeline.sh

# Stage 1: Create resources
ocurl workflow.http -n create_project -v name="Pipeline Project" -v owner=123 > project.json
PROJECT_ID=$(jq -r '.id' project.json)

# Stage 2: Configure resources
ocurl workflow.http -n configure_project -v project_id="$PROJECT_ID" -v settings=@config.json

# Stage 3: Validate
ocurl workflow.http -n validate_project -v project_id="$PROJECT_ID" | \
  jq -e '.status == "ready"' && echo "Pipeline succeeded"
```

### Pattern 6: Environment-Specific Overrides

```http
@import ./base.http

@environment local
Host: localhost:8080
@Debug = true
@LogLevel = trace

@environment staging
Host: staging.api.com
@Debug = true
@LogLevel = debug

@environment production
Host: api.com
@Debug = false
@LogLevel = error
@RateLimit = 1000

###
@name api_call
GET /api/endpoint
X-Debug: {{Debug}}
X-Log-Level: {{LogLevel}}
```

### Pattern 7: Data Transformation Pipeline

```bash
# Extract, transform, load pattern
ocurl api.http -n extract_users | \
  jq '[.users[] | {id: .id, email: .email}]' | \
  ocurl api.http -n bulk_update with id,email --separator '\n'
```

### Pattern 8: Parallel Execution (External)

```bash
#!/bin/bash
# parallel.sh - Use GNU parallel for concurrent requests

cat user_ids.txt | parallel -j 10 \
  "ocurl api.http -n get_user -v user_id={} > user_{}.json"

# Or with xargs
cat user_ids.txt | xargs -I {} -P 10 \
  ocurl api.http -n get_user -v user_id={} -o user_{}.json
```

## Troubleshooting

### Common Issues

**Issue**: Variable not found
```
Error: Variable 'api_key' not found
```
**Solution**:
- Check spelling and case sensitivity
- Verify variable declared in active environment
- Provide via `-v api_key=VALUE`
- Check precedence rules

**Issue**: Circular dependency
```
Error: Circular dependency detected
  Chain: A -> B -> C -> A
```
**Solution**: User error. Restructure requests to break cycle. Consider intermediate requests or pass values via CLI.

**Issue**: jq command not found
```
Error: Lazy variable evaluation failed
  Reason: jq: command not found
```
**Solution**: Install jq: `brew install jq` / `apt-get install jq` / download from https://jqlang.github.io/jq/

**Issue**: Request fails but no error details
```
Error: Request 'api_call' failed
  Status: 500 Internal Server Error
```
**Solution**: Inspect response body (printed to stderr or stdout depending on implementation). Check server logs. Verify request format matches API expectations.

**Issue**: Body contains literal `{{variable}}`
```
{"name": "{{user}}"}  # Rendered literally
```
**Solution**: Variable not defined. Check spelling, provide via `-v`, or verify environment active.

**Issue**: Bulk mode column mismatch
```
Error: Input column count mismatch (line 5)
  Expected: 3, Received: 2
```
**Solution**: Ensure every input line has exactly the number of columns specified in `with` clause. Check for missing separators.

**Issue**: Empty response body
**Solution**: Check if endpoint returns empty body (valid for 204 No Content). Verify URL and headers correct. Check server logs.

### Debugging Tips

**Verbose Mode** (if implemented):
```bash
ocurl --verbose api.http -n request
```

**Inspect Resolved Variables**:
```bash
ocurl-list api.http --requirements
```

**Test Variable Substitution**:
Create minimal test request to isolate variable issues:
```http
###
@name test
GET https://httpbin.org/anything
X-Test-Var: {{my_var}}
```

**Verify Dependency Graph**:
```bash
ocurl-list api.http --dependencies
```

**Test Pipe Expressions Manually**:
```bash
echo '{"token": "abc123"}' | jq '.token'
```

**Check Environment Resolution**:
```bash
ocurl-list api.http  # Shows all environments and variables
```

**Isolate Request**:
Copy single request to new file to test independently:
```http
###
@name isolated_test
GET https://httpbin.org/get
```

## Integration Examples

### CI/CD Pipeline (GitHub Actions)

```yaml
name: API Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install OCurl
        run: |
          # Install from release or build from source
          wget https://github.com/LUSEDOU/ocurl/releases/latest/download/ocurl
          chmod +x ocurl
          sudo mv ocurl /usr/local/bin/

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Run smoke tests
        env:
          API_KEY: ${{ secrets.API_KEY }}
          API_URL: https://staging.api.com
        run: |
          echo "API_KEY=$API_KEY" > .env
          echo "Host=$API_URL" >> .env

          ocurl http/api.http --envfile .env -e staging -n health_check
          ocurl http/api.http --envfile .env -e staging -n auth_test

      - name: Run full test suite
        run: ./scripts/test_all.sh
```

### Docker Integration

```dockerfile
FROM ocaml:4.14 AS builder
WORKDIR /app
COPY . .
RUN opam install -y ocurl && make

FROM alpine:latest
RUN apk add --no-cache jq curl
COPY --from=builder /app/ocurl /usr/local/bin/
ENTRYPOINT ["ocurl"]
```

**Usage**:
```bash
docker run --rm -v $(pwd)/http:/http ocurl-image /http/api.http -n request
```

### Makefile Integration

```makefile
.PHONY: test-api test-staging test-prod

test-api:
	@echo "Testing API endpoints..."
	@ocurl http/api.http -e development -n health_check
	@ocurl http/api.http -e development -n user_flow

test-staging:
	@echo "Testing staging environment..."
	@ocurl http/api.http --envfile .env.staging -e staging -n smoke_tests

test-prod:
	@echo "Testing production (read-only)..."
	@ocurl http/api.http --envfile .env.prod -e production -n health_check

load-test:
	@echo "Running load test..."
	@cat data/test_users.csv | ocurl http/api.http -e staging -n create_user with name,email,dept
```

### Shell Completion (Example for Bash)

```bash
# ocurl-completion.bash
_ocurl_completion() {
    local cur prev opts
    cur="${COMP_WORDS[COMP_CUR_WORD]}"
    prev="${COMP_WORDS[COMP_CUR_WORD-1]}"
    opts="-n --name -e --environment -v --var --with --separator --envfile -o --output"

    case "${prev}" in
        -n|--name)
            # Complete with request names from file
            local names=$(ocurl-list "${COMP_WORDS[1]}" 2>/dev/null | grep "name" | awk '{print $2}')
            COMPREPLY=( $(compgen -W "${names}" -- ${cur}) )
            return 0
            ;;
        -e|--environment)
            # Complete with environment names
            local envs=$(ocurl-list "${COMP_WORDS[1]}" 2>/dev/null | grep "environment" | awk '{print $2}')
            COMPREPLY=( $(compgen -W "${envs}" -- ${cur}) )
            return 0
            ;;
        *)
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
    esac
}

complete -F _ocurl_completion ocurl
```

## Implementation Notes for Developers

### Architecture Recommendations

**Module Structure**:
```
ocurl/
├── lib/
│   ├── ast.ml          # AST types
│   ├── lexer.mll       # Lexer
│   ├── parser.mly      # Parser
│   ├── resolver.ml     # Variable resolution
│   ├── executor.ml     # HTTP execution
│   ├── dependency.ml   # Dependency graph
│   └── pipe.ml         # Pipe expression evaluator
├── bin/
│   ├── main.ml         # ocurl CLI
│   ├── list.ml         # ocurl-list CLI
│   └── compare.ml      # ocurl-compare CLI
└── test/
    ├── test_parser.ml
    ├── test_resolver.ml
    └── test_executor.ml
```

**Key Algorithms**:

1. **Dependency Resolution**: Kahn's algorithm or DFS for topological sort
2. **Variable Substitution**: Two-pass (lazy detection, then substitution)
3. **Environment Merging**: Right-fold with precedence tracking

**Libraries** (OCaml):
- `menhir` - Parser generator
- `cohttp-lwt-unix` or `piaf` - HTTP client
- `yojson` - JSON handling
- `re` or `str` - Regex
- `cmdliner` - CLI parsing
- `lwt` - Async I/O

### Testing Strategy

**Unit Tests**:
- Parser: Each syntax element
- Resolver: Precedence rules, circular detection
- Executor: Request construction, response handling
- Pipe: Command execution, error handling

**Integration Tests**:
- Full workflows with multiple requests
- Cross-environment scenarios
- Bulk mode with various inputs
- Error conditions

**Test Fixtures**:
```
test/
├── fixtures/
│   ├── simple.http
│   ├── complex_workflow.http
│   ├── circular_deps.http
│   └── environments/
│       ├── test.env
│       └── invalid.env
└── expected/
    ├── simple_output.json
    └── complex_output.json
```

### Performance Considerations

**Optimization Opportunities**:
- Lazy parse: Don't parse unused request bodies until needed
- Streaming: For large response bodies
- Parallel independent requests (future)
- Response body size limits

**Benchmarks**:
- Parse 1000-request file: < 1s
- Execute 100-request chain: depends on network, < 10s overhead
- Bulk 10,000 rows: linear time, ~= 10,000 * avg_request_time

### Error Messages Guidelines

**Good Error Messages**:
```
Error: Variable 'user_id' not found
  Location: request 'get_profile', line 23, header 'X-User-ID'
  Available variables: access_token, username, email, jwt

  Suggestions:
    - Check spelling (did you mean 'username'?)
    - Provide via: -v user_id=VALUE
    - Ensure 'login' request executes first (provides: jwt, user_id)
```

**Bad Error Messages**:
```
Error: parse error
Error: undefined variable
Error: failed
```

### Extensibility Points

**Custom Pipe Commands**:
```ocaml
(* pipe.ml *)
type pipe_command =
  | Jq of string
  | Custom of string * string list  (* command, args *)

let eval_pipe cmd input =
  match cmd with
  | Jq expr -> Unix.exec "jq" [expr] ~input
  | Custom (exe, args) -> Unix.exec exe args ~input
```

**Custom Output Formats** (ocurl-list):
```ocaml
type output_format = SExpr | JSON | YAML | Custom of string

let format_output ~format ast =
  match format with
  | SExpr -> format_sexpr ast
  | JSON -> format_json ast
  | Custom formatter -> Unix.exec formatter [] ~input:(format_json ast)
```

## FAQ

**Q: Can I use OCurl without environments?**
A: Yes. Environments are optional. You can define global variables and use CLI variables only.

**Q: How do I handle secrets securely?**
A: Use `.env` files (git-ignored), environment variables, or pass via stdin. Never commit secrets to `.http` files.

**Q: Can I use OCurl in CI/CD?**
A: Yes. Exit codes propagate (0 = success, non-zero = failure). Perfect for smoke tests and health checks.

**Q: Does OCurl support GraphQL?**
A: Not specifically, but you can make GraphQL requests as POST with JSON body:
```http
POST https://api.example.com/graphql
Content-Type: application/json

{"query": "{ user(id: \"{{user_id}}\") { name email } }"}
```

**Q: How do I debug variable substitution?**
A: Use `ocurl-list file.http --requirements` to see what variables each request needs and where they come from.

**Q: Can I share `.http` files across teams?**
A: Yes, but keep secrets in separate `.env` files. Commit `.http` and `.env.example`, ignore `.env`.

**Q: Does OCurl follow redirects?**
A: Implementation-defined (depends on HTTP library). Typically yes for 3xx responses.

**Q: Can I customize timeout values?**
A: Not directly. Wrap in `timeout` command: `timeout 30s ocurl file.http -n request`

**Q: How do I test against multiple API versions?**
A: Use environments:
```http
@environment v1
@ApiVersion = v1

@environment v2
@ApiVersion = v2

###
GET /api/{{ApiVersion}}/users
```

**Q: Can I use OCurl with REST, SOAP, or other protocols?**
A: OCurl is HTTP-focused. SOAP works if you construct XML body manually. Non-HTTP protocols unsupported.

---

## Specification Completeness

This README serves as the **complete specification** for OCurl. All behavior, syntax, and constraints are defined here. Ambiguities should be resolved by:

1. Testing with reference implementation
2. Filing issues for clarification
3. Referring to grammar section for syntax
4. Checking error handling section for edge cases

**For Implementers**: This document is normative. All implementations must conform to these rules. Deviations should be explicitly documented as extensions.

**For Users**: This document defines expected behavior. If OCurl behaves differently, it's a bug.

**Version**: 1.0.0 (Venice OCaml Conference 2025)
