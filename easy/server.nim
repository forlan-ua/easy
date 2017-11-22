import httpcore, nativesockets, mimetypes, asyncdispatch
import types, myasynchttpserver, routes, middleware, response, request


proc new*(T: typedesc[HttpServer], port: int = 5050, address: string = ""): T =
    T(
        mimeTypes: newMimetypes(),
        port: Port(port), 
        address: address, 
        router: Router.new(), 
        reuseAddr: true, 
        reusePort: true
    )

proc registerRoutes*(server: HttpServer, routes: openarray[Route]) =
    server.router.registerRoutes(routes)

proc registerMiddlewares*(server: HttpServer, middlewares: openarray[Middleware]) =
    server.middlewares = @[]
    server.middlewares.add(middlewares)

proc addMiddleware*(server: HttpServer, middleware: Middleware) =
    server.middlewares.add(middleware)

proc sendInterruptResponse(server: HttpServer, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    var i = server.middlewares.len - 1
    while i > -1:
        await server.middlewares[i].onInterrupt(request, response)
        i.dec
    await request.closeRequest(response.code, response.body, response.headers)


proc handle(request: HttpRequest) {.gcsafe, async.} =
    let server = request.server
    var request = request
    var response = HttpResponse.new(server)
    
    for middleware in server.middlewares:
        (request, response) = await middleware.onInit(request, response)
        if response.interrupted:
            await server.sendInterruptResponse(request, response)
            return
    
    var (listener, args, kwargs) = server.router.resolveUrl(request.httpMethod, request.url.path)
    request.patch(server)

    await request.bodyReader(response)
    if response.interrupted:
        await server.sendInterruptResponse(request, response)
        return

    for middleware in server.middlewares:
        await middleware.onRequest(request, response)
        if response.interrupted:
            await server.sendInterruptResponse(request, response)
            return
    
    await listener(request, response, args, kwargs)
    if response.interrupted:
        await server.sendInterruptResponse(request, response)
        return
    
    var i = server.middlewares.len - 1
    while i > -1:
        await server.middlewares[i].onResponse(request, response)
        if response.interrupted:
            await server.sendInterruptResponse(request, response)
            return
        i.dec
    
    await request.closeRequest(response.statusCode, response.body, response.headers)


proc listen*(server: HttpServer, port: int = 0, address: string = "") {.gcsafe, async.} =
    if port > 0:
        server.port = Port(port)
    if address.len > 0:
        server.address = address 
    
    proc internalHandle(request: HttpRequest) {.gcsafe, async.} =
        request.patch(server)
        await handle(request)

    while not server.closed:
        try:
            await server.serve(server.port, internalHandle, server.address)
        except:
            discard