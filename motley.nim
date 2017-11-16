import asynchttpserver, json
import asyncdispatch, nre, sequtils, tables, strutils, logging


proc splitResults(captures: Captures): tuple[args: seq[string], kwargs: Table[string, string]] =
    result.kwargs = captures.toTable()

    if result.kwargs.len > 0:
        var args = captures.toSeq()

        for key_str, key_int in captures.RegexMatch.pattern.captureNameId:
            args[key_int] = nil

        result.args = filter(args, proc(item: string): bool = not item.isNil)
    else:
        result.args = captures.toSeq()

type HttpRequest = ref object of RootObj
    originalRequest: Request
    
type HttpResponse = ref object of RootObj
    request: HttpRequest
    statusCode: HttpCode
    headers: HttpHeaders

proc close*(res: HttpResponse, content: string) {.async.} = 
    await res.request.originalRequest.respond(res.statusCode, content, res.headers)

proc close*(res: HttpResponse, content: JsonNode) {.async.} =
    res.headers["Content-Type"] = "application/json"
    await res.request.originalRequest.respond(res.statusCode, $content, res.headers)

type UrlListener* = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[void]

type 
    Router = ref object of RootObj
        defaultGroup: RouteGroup
        namedRoutes: Table[string, Route]
        trailingSlash: bool
    Route = ref object of RootObj
        name: string
        reg: Regex
        group: RouteGroup
        case multiMethod: bool:
            of false:
                listeners: Table[HttpMethod, UrlListener]
            else:
                listener: UrlListener
    RouteGroup = ref object of Route
        routes: seq[Route]
    RouteResult = tuple[listener: UrlListener, args: seq[string], kwargs: Table[string, string]]
    

proc newHttpRequest*(request: Request): HttpRequest = HttpRequest(originalRequest: request)
proc newHttpResponse*(request: HttpRequest): HttpResponse = HttpResponse(request: request, statusCode: Http200, headers: newHttpHeaders())
proc newRouter(): Router = Router(namedRoutes: initTable[string, Route]())


proc listener404(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]) {.async.} =
    response.statusCode = Http404
    await response.close("Not found")


proc listener500(request: HttpRequest, response: HttpResponse) {.async.} =
    response.statusCode = Http500
    await response.close("Internal server error")


proc `$`(r: Route): string = 
    result = "{name: " & (if r.name == "": "empty" else: r.name)
    if not r.reg.isNil:
        result &= ", pattern: " & r.reg.pattern
    if r of RouteGroup:
        result &= ", routes: " & $r.RouteGroup.routes
    result &= "}"

proc checkReg(reg: string): Regex = 
    result = re(reg)

proc url*(reg: string, listener: UrlListener, name: string = ""): Route =
    Route(reg: checkReg(reg), name: name, listener: listener, multiMethod: true)

proc url*(reg: string, listeners: openarray[tuple[httpMethod: HttpMethod, listener: UrlListener]], name: string = ""): Route =
    Route(reg: checkReg(reg), name: name, listeners: listeners.toTable(), multiMethod: false)

proc url_import*(urls: openarray[Route], namespace: string = ""): RouteGroup =
    var routes: seq[Route] = @[]
    result = RouteGroup(name: namespace)
    for route in urls:
        route.group = result
        routes.add(route)
    result.routes = routes

proc url*(reg: string, group: RouteGroup): Route =
    result = group
    result.reg = checkReg(reg)

proc registerNames(router: Router, group: RouteGroup, prefix: string = "") =
    for route in group.routes:
        if route.name != "":
            if route of RouteGroup:
                router.registerNames(route.RouteGroup, prefix & route.name & ":")
            else:
                router.namedRoutes[prefix & route.name] = route

proc registerRoutes*(router: Router, urls: openarray[Route]) =
    var routes: seq[Route] = @[]
    for route in urls:
        routes.add(route)
    router.defaultGroup = RouteGroup(name: "", routes: routes)
    router.registerNames(router.defaultGroup)


proc resolveUrl(group: RouteGroup, httpMethod: HttpMethod, url: string, args: var seq[string], kwargs: var Table[string, string]): RouteResult =
    result[0] = listener404
    for route in group.routes:
        let res = url.match(route.reg)
        if res.isNone:
            continue

        let parts = res.get().captures.splitResults()
        args.add(parts.args)
        for key, value in parts.kwargs:
            kwargs[key] = value

        if route of RouteGroup:
            var gurl = url.replace(route.reg, "")
            if not gurl.startsWith("/"):
                gurl = "/" & gurl
            result = route.RouteGroup.resolveUrl(httpMethod, gurl, args, kwargs)
        else:
            if route.multiMethod:
                result = (route.listener, args, kwargs)
            else:
                let listener = route.listeners.getOrDefault(httpMethod)
                if not listener.isNil:
                    result = (listener, args, kwargs)


proc resolveUrl*(router: Router, httpMethod: HttpMethod, url: string): RouteResult =
    var args = newSeq[string]()
    var kwargs = initTable[string, string]()
    result = router.defaultGroup.resolveUrl(httpMethod, url, args, kwargs)


proc newReverseException(name: string, pattern: string = ""): ref Exception =
    var message = ""
    if pattern == "":
        message = "Reverse for `$1` has not been found" % [name]
    else:
        let reg = re(pattern)

        var keys: seq[string] = @[]
        for key, _ in reg.captureNameId():
            keys.add(key)
        let count = reg.captureCount() - keys.len
        
        if count == 0 and keys.len == 0:
            message = "Some shit happens. Review your regular expressions or report a bug."
        if count == 0:
            message = "reverseUrl for `$1` have to has `{$3}` kwargs pair(s)" % [name, keys.join(", ")]
        elif keys.len == 0:
            message = "reverseUrl for `$1` have to has $2 args item(s)" % [name, $count]
        else:
            message = "reverseUrl for `$1` have to has $2 args item(s) and `{$3}` kwargs pair(s)" % [name, $count, keys.join(", ")]

    result = newException(Exception, message)


proc reverseUrl*(router: Router, name: string, args: seq[string], kwargs: Table[string, string]): string =
    let route = router.namedRoutes.getOrDefault(name)

    if not route.isNil:
        var pattern = route.reg.pattern
        var group = route.group
        while not group.isNil:
            pattern = group.reg.pattern & pattern.strip(trailing = false, chars = {'^'})
            group = group.group

        var url = pattern.strip(trailing = false, chars = {'^'}).strip(leading = false, chars = {'$'}).replace("/?", "/").replace("//", "/")
        if not router.trailingSlash:
            url = url.strip(leading = false, chars = {'/'})
        elif not url.endsWith("/"):
            url &= "/"

        result = ""
        var i = 0
        var index = 0
        while i < url.len:
            let c = url[i]
            case c:
                of '(':
                    if i == 0 or url[i - 1] != '\\':
                        i.inc
                        if url[i] == '?':
                            i.inc
                            if url[i] == '<':
                                var name = ""
                                i.inc
                                while url[i] != '>':
                                    name &= url[i]
                                    i.inc
                                if name notin kwargs:
                                    raise newReverseException(name, pattern)
                                result &= kwargs[name]
                            elif url[i] == ':':
                                warn "Your regular expression `$1` for `$2` is too hard for reverseUrl function. The result can be unexpective." % [pattern, name]
                                continue
                        else:
                            if index >= args.len:
                                raise newReverseException(name, pattern)
                            result &= args[index]
                            index.inc
                        i.inc
                        while url[i] != ')' and url[i-1] != '\\': 
                            i.inc
                    else:
                        result &= c
                of ')':
                    if i > 0 and url[i - 1] != '\\':
                        i.inc
                of '?', '*', '+':
                    if i > 0 and url[i - 1] != '\\':
                        warn "Your regular expression `$1` for `$2` is too hard for reverseUrl function. The result can be unexpective." % [pattern, name]
                        i.inc
                    else:
                        result &= c
                of '.':
                    warn "Your regular expression `$1` for `$2` is too hard for reverseUrl function. The result can be unexpective." % [pattern, name]
                    result &= c
                of '|':
                    i.inc
                    if url[i] != '(':
                        i.inc
                    else:
                        i.inc
                        while url[i] != ')' and url[i-1] != '\\':
                            i.inc 
                    warn "Your regular expression `$1` for `$2` is too hard for reverseUrl function. The result can be unexpective." % [pattern, name]
                else:
                    result &= c
            i.inc
    else:
        raise newReverseException(name)

# template reverseUrl*(name: string, args: seq[string], kwargs: Table[string, string]): string = sharedRouter.reverseUrl(name, args, kwargs)
# template reverseUrl*(name: string, args: seq[string]): string = sharedRouter.reverseUrl(name, args, initTable[string, string]())
# template reverseUrl*(name: string, kwargs: Table[string, string]): string = sharedRouter.reverseUrl(name, @[], kwargs)
# template reverseUrl*(name: string): string = sharedRouter.reverseUrl(name, @[], initTable[string, string]())

# template reverseUrl*(name: string, args: seq[string], kwargs: openarray[tuple[key: string, value: string]]): string = sharedRouter.reverseUrl(name, args, kwargs.toTable())
# template reverseUrl*(name: string, kwargs: openarray[tuple[key: string, value: string]]): string = sharedRouter.reverseUrl(name, @[], kwargs.toTable())


type HttpServer = ref object of RootObj
    asyncServer: AsyncHttpServer
    port: Port
    address: string
    router: Router

proc newHttpServer*(port: int = 5050, address: string = ""): HttpServer =
    HttpServer(port: Port(port), address: address, router: newRouter())


proc handle(server: HttpServer, req: Request) {.async.} =
    var (listener, args, kwargs) = server.router.resolveUrl(req.reqMethod, req.url.path)
    var request = newHttpRequest(req)
    var response = newHttpResponse(request)

    var action = listener(request, response, args, kwargs)
    yield action
    if action.failed:
        await listener500(request, response)


proc listen*(server: HttpServer, port: int = 0, address: string = "") =
    if port > 0:
        server.port = Port(port)
    if address.len > 0:
        server.address = address

    server.asyncServer = newAsyncHttpServer(true, true)
    waitFor server.asyncServer.serve(server.port, proc(req: Request) {.async.} = await server.handle(req), server.address)

proc registerRoutes*(server: HttpServer, routes: openarray[Route]) =
    server.router.registerRoutes(routes)

proc my_handler(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]) {.async.} =
    await response.close("CLOSE")

var routes = [
    url("^/$", my_handler)
]

let server = newHttpServer()
server.registerRoutes(routes)
server.listen()