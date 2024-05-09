# OCurl

## Description
OCurl is a wrapper of ocurl, that has a more functional interface. The focus
is make a pipeline for testing REST APIs.

## Goals

1. <<url>>

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
standard input. It's the same as `cat urls | xargs curl`

2. .http

Its a file that contains the urls to be requested with their corresponding
methods and headers. The file is a list of requests, each request is separated
by a blank line. The first line of the request is the method, the second line
is the url, and the following lines are the headers. The headers are key-value
pairs separated by a colon. The file is a list of requests, each request is
separated by a blank line.

The common assigne operators are '\s' ':' and '='

```http
GET /api (HTTP/1.1 @optional)
Host localhost:8080
```

And should be called like this:

```console
ocurl ./.http
ocurl -f ./.http
```

Another examples

```http
POST /api/users
Host localhost:8080
Accept application/json
Authorization Bearer token
Content-Type application/json
Data
{
  "name": "John Doe",
  "email": "johndoe@test.xyz"
}

GET /api/users/1
Host localhost:8080
Accept application/json
Authorization Bearer token
```

3. .httpi

Its a file when contains the metadata of the requests. The metadata is the
information that is common to all the requests. From here it can also define
variables that can be used in the requests.

```http
.httpi

Host localhost:8080
Accept application/json
Authorization Bearer token
ApiVersion v1
Api /api/$ApiVersion

.http
GET /api/$ApiVersion/users

GET /api/$ApiVersion/users/1

POST $Api/image
Accept image/png
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

So in case i have a directory structure like this:

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

Host localhost:8080
Accept application/json
Authorization Bearer token
user_id 0000001
```

It will make the following requests:

```http
GET /api/users/index
Host localhost:8080
Accept application/json
Authorization Bearer token

GET /api/users/00001/bookmarks
Host localhost:8080
Accept application/json
Authorization Bearer token

GET /api/index
Host localhost:8080
Accept application/json
Authorization Bearer token

GET /index
Host localhost:8080
Accept application/json
Authorization Bearer token
```

### Pending
1. Find a way to make the requests in parallel. Compatibility with `parallel`
2. Find a way to define methods
3. Define vars per method
4. Add expected response (status, headers, body) See [response](#response)

### Note
$$ to escape the variable


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
Host localhost:8080
Accept application/json
Authorization Bearer $token

$ cat url_test.csv | awk -F, '{print $1 " " $2 " " $3}' | ocurl -i .httpi with id token
GET /users/1
Host localhost:8080
Accept application/json
Authorization Bearer token1

GET /books/2
Host localhost:8080
Accept application/json
Authorization Bearer token1

GET /users/3/books/3
Host localhost:8080
Accept application/json
Authorization Bearer token1

GET /books?user_id=4
Host localhost:8080
Accept application/json
Authorization Bearer token1

$ cat urls | awk "{print
```

5. _

6. response

7. override response

8. .lua
