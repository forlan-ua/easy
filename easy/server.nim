import httpcore, nativesockets, mimetypes, parseutils, strutils, uri, asyncdispatch, asyncnet, tables
import types, routes, middleware, response, request


proc new*(T: typedesc[HttpServer], port: int = 5050, address: string = "", bodyMaxSize: int = 1 shl 24): T =
    T(
        mimeTypes: newMimetypes(),
        port: Port(port),
        address: address, 
        router: Router.new(), 
        reuseAddr: true, 
        reusePort: true,
        bodyMaxSize: bodyMaxSize
    )

proc registerRoutes*(server: HttpServer, routes: openarray[Route]) =
    server.router.registerRoutes(routes)

proc registerMiddlewares*(server: HttpServer, middlewares: openarray[Middleware]) =
    server.middlewares = @middlewares

proc addMiddleware*(server: HttpServer, middleware: Middleware) =
    server.middlewares.add(middleware)

proc handle(server: HttpServer, request: HttpRequest, response: HttpResponse) {.gcsafe, async.} =
    for middleware in server.middlewares:
        await middleware.onRequest(request, response)
        if response.interrupted:
            return

    try:
        let (listener, kwargs) = server.router.resolveUrl(request.httpMethod, request.url.path)
        request.kwargs = kwargs
        await listener(request, response)
    except:
        response.code(Http500).interrupt()
    if response.interrupted:
        return
    
    var i = server.middlewares.high
    while i > -1:
        await server.middlewares[i].onResponse(request, response)
        if response.interrupted:
            return
        i.dec

const maxLine = 8*1024

proc parseProtocol(protocol: string): tuple[orig: string, major, minor: int] =
    var i = protocol.skipIgnoreCase("HTTP/")
    if i != 5:
        raise newException(ValueError, "Invalid request protocol. Got: " &
            protocol)
    result.orig = protocol
    i.inc protocol.parseSaturatedNatural(result.major, i)
    i.inc # Skip .
    i.inc protocol.parseSaturatedNatural(result.minor, i)
    
proc processRequest(server: HttpServer, socket: AsyncSocket) {.gcsafe, async.} =
    var request: HttpRequest
    var response = HttpResponse.new(socket, server)
    var lineFut = newFutureVar[string]("easy.server.processRequest")
    template line(): string = lineFut.mget()
    line = newStringOfCap(80)

    # We should skip at least one empty line before the request
    # https://tools.ietf.org/html/rfc7230#section-3.5
    for i in 0..1:
        line.setLen(0)
        lineFut.clean()
        await socket.recvLineInto(lineFut, maxLength=maxLine)

        if line == "":
            socket.close()
            return

        if line.len > maxLine:
            await response.code(Http413).close()
            return

        if line != "\c\L":
            break

    # First line - GET /path HTTP/1.1
    var i = 0
    for linePart in line.split(' '):
        case i:
            of 0:
                try:
                    request = HttpRequest.new(parseEnum[HttpMethod]("http" & linePart), socket, server)
                except ValueError:
                    waitFor response.code(Http400).close()
                    return
            of 1:
                try:
                    parseUri(linePart, request.url)
                except ValueError:
                    waitFor response.code(Http400).close()
                    return
            of 2:
                try:
                    request.protocol = parseProtocol(linePart)
                except ValueError:
                    waitFor response.code(Http400).close()
                    return
            else:
                waitFor response.code(Http400).close()
                return
        inc i

    # Headers
    while true:
        i = 0
        line.setLen(0)
        lineFut.clean()
        await socket.recvLineInto(lineFut, maxLength=maxLine)

        if line == "":
            socket.close(); 
            return
        if line.len > maxLine:
            response.code(Http413)
            await response.close(); 
            return
        if line == "\c\L": 
            break 

        let (key, value) = parseHeader(line)
        request.headers[key] = value
        # Ensure the socket isn't trying to DoS us.
        if request.headers.len > headerLimit:
            await response.code(Http400).send("Bad Request").close()
            return

    for middleware in server.middlewares:
        (request, response) = await middleware.onInit(request, response)
        if response.interrupted:
            break
            
    if not response.interrupted:
        case request.httpMethod:
            of HttpPost, HttpPut, HttpPatch:
                # Check for Expect header
                if request.headers.hasKey("Expect"):
                    if "100-continue" in request.headers["Expect"]:
                        await response.code(Http100).send("Continue").respond()
                    else:
                        await response.code(Http417).send("Expectation Failed").close()
                        return

                if request.headers.hasKey("Content-Length"):
                    if parseSaturatedNatural(request.headers["Content-Length"], request.contentLength) == 0:
                        await response.code(Http400).send("Bad Request. Invalid Content-Length.").close()
                        return
                    elif request.contentLength > request.bodyMaxSize:
                        await response.code(Http413).close()
                        return
                    await request.readBody(response)
                else:
                    await response.code(Http411).send("Content-Length required.").close()
                    return
            else:
                discard
    
    if not response.interrupted:
        await server.handle(request, response)
    await response.respond()

    if "upgrade" in request.headers.getOrDefault("connection"):
        return

    if (request.protocol == HttpVer11 and
            cmpIgnoreCase(request.headers.getOrDefault("connection"), "close") != 0) or
      (request.protocol == HttpVer10 and
            cmpIgnoreCase(request.headers.getOrDefault("connection"), "keep-alive") == 0):
        discard
    else:
        socket.close()
        return

proc processClient(server: HttpServer, client: AsyncSocket) {.async.} =
    while not client.isClosed:
        await processRequest(server, client)

proc serve(server: HttpServer) {.gcsafe, async.} =
    server.socket = newAsyncSocket()
    if server.reuseAddr:
        server.socket.setSockOpt(OptReuseAddr, true)
    if server.reusePort:
        server.socket.setSockOpt(OptReusePort, true)
    server.socket.bindAddr(server.port, server.address)
    server.socket.listen()
    
    while not server.closed:
        var fut = await server.socket.acceptAddr()
        asyncCheck processClient(server, fut.client)

proc listen*(server: HttpServer, port: int = 0, address: string = "") =
    if port > 0:
        server.port = Port(port)
    if address.len > 0:
        server.address = address

    while not server.closed:
        try:
            waitFor server.serve()
        except:
            discard