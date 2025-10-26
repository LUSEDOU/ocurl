# OCurl

## Description
OCurl is a wrapper of ocurl, that has a more functional interface. The focus
is make a pipeline for testing REST APIs.

## Goals

1. <\<url\>>

```console
ocurl <<url>>
ocurl http://localhost:8080/api
ocurl -u http://localhost:8080/api
```

This is the simplest form of the command. It will make a GET request to the url.
Works the same as `curl <<url>>`

```console
cat <<urls>> | ocurl
```

This is the same as the previous command, but it will read the urls from the
standard input. It's the same as `cat urls | xargs -I{} curl {}`

2. .http

It's a file that contains the urls to be requested with their corresponding
methods and headers. The file is a list of requests, each request is separated
by a blank line. The first line of the request is the method, the second line
is the url, and the following lines are the headers. The headers are key-value
pairs separated by a colon. The file is a list of requests, each request is
separated by a blank line.

The common assigne operators are '\s' ':' and '='

```http
GET /api HTTP/1.1
Host: localhost:8080
```

* HTTP/1.1 is optional, if not provided, it will use the default HTTP version

And should be called like this:

```console
ocurl ./.http
ocurl -f ./.http
```

Another examples

```http
POST /api/users
Host: localhost:8080
Accept: application/json
Authorization: Bearer token
Content-Type: application/json

{
  "name": "John Doe",
  "email": "johndoe@test.xyz"
}

GET /api/users/1
Host: localhost:8080
Accept: application/json
Authorization: Bearer token
```

3. .httpi

It's a file when contains the metadata of the requests. The metadata is the
information that is common to all the requests. From here it can also define
variables that can be used in the requests.

```http
## .httpi

Host: localhost:8080
Accept: application/json
Authorization: Bearer token
ApiVersion v1
Api /api/$ApiVersion

## .http
GET /api/$ApiVersion/users

GET /api/$ApiVersion/users/1

POST $Api/image
Accept: image/png
```

```console
ocurl .\http .\httpi
ocurl -f .\http -i .\httpi
```

With this the goals are to make a pipeline for testing REST APIs.
Something like this read all the directories and files and convert them to
requests.

```console
find . -type f | sd -e 's/\.*$/' | ocurl -i ./.httpi
```

So in case I have a directory structure like this:

```console
.
├── .httpi
├── api
│   ├── users
│   │   ├── [user_id]
│   │   │   └── bookmarks.js
│   │   └── index.js
│   └── index.js
└── index.js
```

And the files are like this:

```http
.httpi

Host: localhost:8080
Accept: application/json
Authorization: Bearer token
.user_id: 0000001
```

It will make the following requests:

```http
GET /api/users/index
Host: localhost:8080
Accept: application/json
Authorization: Bearer token

GET /api/users/00001/bookmarks
Host: localhost:8080
Accept: application/json
Authorization: Bearer token

GET /api/index
Host: localhost:8080
Accept: application/json
Authorization: Bearer token

GET /index
Host: localhost:8080
Accept: application/json
Authorization: Bearer token
```

### Pending
1. Find a way to make the requests in parallel. Compatibility with `parallel`
2. Find a way to define methods
3. Define vars per method
4. Add expected response (status, headers, body) See [response](#response)

### Note
\$\$ to escape the variable


4. With

The goal is this:
```console
$ head url_test.csv
path,id,token
/users/$id,1,token1
/books/$id,2,token2
/users/$id/books/$id,3,token3
/books?user_id=$id,4,token4

$ cat .httpi
Host: localhost:8080
Accept: application/json
Authorization: Bearer $token

$ cat url_test.csv | awk -F, '{print $1 " " $2 " " $3}' | ocurl -i .httpi with id token
GET /users/1
Host: localhost:8080
Accept: application/json
Authorization: Bearer token1

GET /books/2
Host: localhost:8080
Accept: application/json
Authorization: Bearer token1

GET /users/3/books/3
Host: localhost:8080
Accept: application/json
Authorization: Bearer token1

GET /books?user_id=4
Host: localhost:8080
Accept: application/json
Authorization: Bearer token1
```

Another examples or use cases

* Scrapping
  ```console
  seq 1 10 | awk '{print "https://newsxyz.com/news/$id" $1}' | ocurl with id | .\my_parser.sh
  ```

* Testing
  ```console
  $ cat .httpi
  POST /api/users
  Host: localhost:8080
  Content-Type: application/json
  $ cat data.json
  {
    "name": "John Doe",
    "email": "john@doe.com"
  }
  $ cat data.json | ocurl -i .httpi
  ```

* Login and accessing a protected resource
  ```console
  $ cat login.http
  POST /api/auth
  Content-Type: application/json

  {
    "username": "john",
    "password": "doe"
  }
  $ cat users.http
  GET /api/users
  Authorization Bearer $TOKEN

  $ TOKEN=${ocurl -f login.http | jq -r '.token'}
  $ echo $TOKEN | ocurl -f users.http with TOKEN
  ```


5. _

This could be for a apart cli tool. Like

* This should be the normal behavior
```console
ocurlt run ./http
```

* This should happen without parameters
```console
$ ocurlt
- /api/users
* /api/users/1
- /api/books
- /api/auth

GET /api/users
Host: localhost:8080
```

6. response

The goal is to define the behavior with the response. It could:
* Print the response

  ```console
  $ ocurl https://google.com
  <HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
  <TITLE>301 Moved</TITLE></HEAD><BODY>
  <H1>301 Moved</H1>
  The document has moved
  <A HREF="https://www.google.com/">here</A>.

  </BODY></HTML>
  $ ocurl https://google.com -v
  ...
  $ ocurl https://google.com -M
  *   Trying 142.251.0.138:443...
  ...
  < HTTP/2 301
  < location: https://www.google.com/
  < content-type: text/html; charset=UTF-8
  < content-security-policy-report-only: object-src 'none';base-uri 'self';script-src 'nonce-MXA1UpzjIPzMEeu5o3beEg' 'strict-dynamic' 'report-sample' 'unsafe-eval' 'unsafe-inline' https: http:;report-uri https://csp.withgoogle.com/csp/gws/other-hp
  < date: Fri, 10 May 2024 21:51:37 GMT
  < expires: Sun, 09 Jun 2024 21:51:37 GMT
  < cache-control: public, max-age=2592000
  < server: gws
  < content-length: 220
  < x-xss-protection: 0
  < x-frame-options: SAMEORIGIN
  < alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
  ...
  $ seq 1 10 | ocurl -f .http with user_id
  {"user_id": 1}
  {"user_id": 2}
  {"user_id": 3}
  {"user_id": 4}
  {"user_id": 5}
  {"user_id": 6}
  {"user_id": 7}
  {"user_id": 8}
  {"user_id": 9}
  {"user_id": 10}
  ```
* Save the response in a file

  Each response could be saved providing a filename. The filename could be
  provided with the `-o` flag or with the `with` operator.

  ```console
  ocurl https://google.com > response.html
  seq 1 10 | awk "{print $1 " user_$1.json"} | ocurl -f .http with user_id -o
  find routes -type f | sed 's/\.*$/' | ocurl -f .http -o
  ```

* Compare the response with an expected response




7. override response

8. .lua
