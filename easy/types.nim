import asyncdispatch, streams, httpcore, mimetypes, tables, nre, uri, asyncnet


type
    Middleware* = ref object of RootObj
    MiddlewareData* = ref object of RootObj
    
    HttpServer* = ref object of RootObj
        socket*: AsyncSocket
        reuseAddr*: bool
        reusePort*: bool

        middlewares*: seq[Middleware]
        port*: Port
        address*: string
        router*: Router
        mimeTypes*: MimeDB
        closed*: bool

    HttpRequest* = ref object of RootObj
        client*: AsyncSocket
        httpMethod*: HttpMethod
        headers*: HttpHeaders
        protocol*: tuple[orig: string, major, minor: int]
        url*: Uri
        hostname*: string
        body*: string

        server*: HttpServer
        middlewareData*: seq[MiddlewareData]
        contentLength*: int
        bodyStream*: Stream
        bodyChunkSize*: uint32
        bodyStreamFile*: string
    
    HttpResponse* = ref object of RootObj
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