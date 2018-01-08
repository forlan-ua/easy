import asyncdispatch, streams, httpcore, mimetypes, tables, nre, uri, asyncnet


type
    HttpStatusCode* = HttpCode

    Middleware* = ref object of RootObj
    
    MiddlewareData* = ref object of RootObj
    
    HttpServer* = ref object of RootObj
        socket*: AsyncSocket
        reuseAddr*: bool
        reusePort*: bool

        bodyMaxSize*: int
        middlewares*: seq[Middleware]
        port*: Port
        address*: string
        router*: Router
        mimeTypes*: MimeDB
        closed*: bool

    HttpRequest* = ref object of RootObj
        socket*: AsyncSocket
        server*: HttpServer
        headers*: HttpHeaders
        protocol*: tuple[orig: string, major, minor: int]
        url*: Uri
        middlewareData*: seq[MiddlewareData]

        httpMethod*: HttpMethod
        
        contentLength*: int
        body*: string
        bodyMaxSize*: int
    
    HttpResponse* = ref object of RootObj
        socket*: AsyncSocket
        server*: HttpServer
        statusCode*: HttpCode
        headers*: HttpHeaders
        middlewareData*: seq[MiddlewareData]
        body*: string
        interrupted*: bool

    UrlListener* = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[void] {.gcsafe.}
        
    Router* = ref object of RootObj
        defaultGroup*: RouteGroup
        namedRoutes*: Table[string, Route]

    Route* = ref object of RootObj
        name*: string
        reg*: Regex
        group*: RouteGroup
        case multiMethod*: bool:
            of false:
                listeners*: Table[HttpMethod, UrlListener]
            else:
                listener*: UrlListener
    RouteGroup* = ref object of Route
        routes*: seq[Route]

proc `$`(statusCode: HttpStatusCode): string =
    case statusCode.int:
        of 100: "Continue"
        of 101: "Switching Protocols"
        of 102: "Processing"
    
        of 200: "OK"
        of 201: "Created"
        of 202: "Accepted"
        of 203: "Non-Authoritative Information"
        of 204: "No Content"
        of 205: "Reset Content"
        of 206: "Partial Content"
        of 207: "Multi-Status"
        of 208: "Already Reported"
        of 226: "IM Used"
    
        of 300: "Multiple Choices"
        of 301: "Moved Permanently"
        of 302: "Moved Temporarily"
        of 303: "Found"
        of 304: "Not Modified"
        of 305: "Use Proxy"
        of 306: ""
        of 307: "Temporary Redirect"
        of 308: "Permanent Redirect"
    
        of 400: "Bad Request"
        of 401: "Unauthorized"
        of 402: "Payment Required"
        of 403: "Forbidden"
        of 404: "Not Found"
        of 405: "Method Not Allowed"
        of 406: "Not Acceptable"
        of 407: "Proxy Authentication Required"
        of 408: "Request Timeout"
        of 409: "Conflict"
        of 410: "Gone"
        of 411: "Length Required"
        of 412: "Precondition Failed"
        of 413: "Payload Too Large"
        of 414: "URI Too Long"
        of 415: "Unsupported Media Type"
        of 416: "Range Not Satisfiable"
        of 417: "Expectation Failed"
        of 418: "I'm a teapot"
        of 421: "Misdirected Request"
        of 422: "Unprocessable Entity"
        of 423: "Locked"
        of 424: "Failed Dependency"
        of 426: "Upgrade Required"
        of 428: "Precondition Required"
        of 429: "Too Many Requests"
        of 431: "Request Header Fields Too Large"
        of 444: ""
        of 449: "Retry With"
        of 451: "Unavailable For Legal Reasons"
    
        of 500: "Internal Server Error"
        of 501: "Not Implemented"
        of 502: "Bad Gateway"
        of 503: "Service Unavailable"
        of 504: "Gateway Timeout"
        of 505: "HTTP Version Not Supported"
        of 506: "Variant Also Negotiates"
        of 507: "Insufficient Storage"
        of 508: "Loop Detected"
        of 509: "Bandwidth Limit Exceeded"
        of 510: "Not Extended"
        of 511: "Network Authentication Required"
        of 520: "Unknown Error"
        of 521: "Web Server Is Down"
        of 522: "Connection Timed Out"
        of 523: "Origin Is Unreachable"
        of 524: "A Timeout Occurred"
        of 525: "SSL Handshake Failed"
        of 526: "Invalid SSL Certificate"
        else: ""

proc respond*(socket: AsyncSocket, code: HttpCode, content: string, headers: HttpHeaders): Future[void] =
    let content = if content.len > 0: content else: $code.HttpStatusCode
    let status = $code.int & " " & $code.HttpStatusCode

    var msg = "HTTP/1.1 " & status & "\c\L"
    if headers.len > 0:
        for k, v in headers:
            msg.add(k & ": " & v & "\c\L")
    msg.add("Content-Length: ")
    # this particular way saves allocations:
    msg.add(content.len)
    msg.add("\c\L\c\L")
    msg.add(content)

    result = socket.send(msg)