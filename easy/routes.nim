import httpcore, tables, nre, strutils, asyncdispatch, logging, sequtils, algorithm, macros
import types, response


proc new*(T: typedesc[Router]): T = 
    T(
        routes: newSeq[Route](), 
        namedRoutes: initTable[string, seq[string]]()
    )


const EOL = '\0'
const EOP = {'\0', '/'}
const VAR = ':'


proc url*(path: string, listener: UrlListener, name: string = ""): Route =
    RouteSingle(path: path, name: name, listener: listener, multiMethod: true)

proc url*(path: string, listeners: openarray[(HttpMethod, UrlListener)], name: string = ""): Route =
    RouteSingle(path: path, name: name, listeners: listeners.toTable(), multiMethod: false)

proc url*(path: string, routes: openarray[Route], namespace: string = ""): Route =
    RouteGroup(path: path, routes: @routes, namespace: namespace)

var logInst {.compiletime.} = nnkStmtList.newTree()

macro pushLog*(x: untyped): untyped =
    result = logInst

proc log*(x: NimNode) =
    logInst.add(
        nnkCall.newTree(
            ident("echo"),
            newLit(treeRepr(x))
        )
    )
let discardNode* {.compiletime.} = nnkDiscardStmt.newTree(newEmptyNode())

proc toUrlArray*(x: NimNode): NimNode =
    result = nnkBracket.newTree()
    for i in x:
        result.add(
            nnkPar.newTree(
                i[1][0],
                nnkCall.newTree(
                    ident("UrlListener"),
                    i[1][1]
                )
            )
        )

macro `*`*(x: untyped): untyped =
    result = x.toUrlArray()

proc httpMethod*(x: NimNode): NimNode =
    x.expectKind(nnkIdent)
    let httpMethod = $x.ident
    try:
        discard parseEnum[HttpMethod](httpMethod)
        result = x
    except:
        try:
            result = ident(
                system.`$`(parseEnum[HttpMethod]("http" & httpMethod))
            )
        except:
            raise newException(ValueError, "Http method should be a member of HttpMethod")

proc toRoute(path: NimNode, listeners: NimNode, name: NimNode): NimNode =
    result = nnkCall.newTree(
        ident("url"),
        path
    )
    
    if listeners[0].kind == nnkCall:
        var l = nnkBracket.newTree()
        for i in listeners:
            if i[0].kind == nnkIdent:
                l.add(
                    nnkPar.newTree(
                        i[0].httpMethod(),
                        nnkCall.newTree(
                            ident("UrlListener"),
                            i[1][0]
                        )
                    )
                )
            else:
                listeners.expectLen(1)
                l = i
        result.add(l)
    else:
        result.add(listeners[0])

    if name.kind != nnkNone:
        result.add(name)

proc toRoutes(x: NimNode): NimNode =
    result = nnkBracket.newTree()

    for i in x:
        case i.kind:
            of nnkCall:
                i[0].expectKind(nnkStrLit)
                result.add(
                    toRoute(i[0], i[1], newNimNode(nnkNone))
                )
            of nnkInfix:
                assert(i[0].eqIdent("as"))
                result.add(
                    toRoute(i[1], i[3], i[2])
                )
            else:
                discard

proc toRoutes(x: NimNode, name: NimNode): NimNode =
    result = nnkLetSection.newTree(
        nnkIdentDefs.newTree(
            name,
            newEmptyNode(),
            toRoutes(x),
        )
    )

macro routes*(x: untyped): untyped =
    result = toRoutes(x, ident("urls"))

macro routes*(name: untyped, x: untyped): untyped =
    result = toRoutes(x, name)


proc addRoute(router: Router, routes: var seq[Route], namespace_prefix: string = "", url_prefix: string = "") =
    for route in routes:
        if route of RouteGroup:
            let r = route.RouteGroup
            var p = namespace_prefix
            if r.namespace.len > 0:
                if p.len > 0:
                    p.add(":")
                p.add(r.namespace)
            router.addRoute(r.routes, p, url_prefix & r.path)
        else:
            let r = route.RouteSingle
            if r.name.len > 0:
                var n = namespace_prefix
                if n.len > 0:
                    n.add(":")
                n.add(r.name)

                let url = url_prefix & r.path 
                router.namedRoutes[n] = @[]
                var i, j, state: int
                while i < url.len:
                    if url[i] == ':':
                        router.namedRoutes[n].add(url[j ..< i])
                        j = i + 1
                        state = 1
                    elif url[i] == '/':
                        if state == 1:
                            router.namedRoutes[n].add(url[j ..< i])
                            state = 0
                            j = i
                    i.inc
                if j != i - 1:
                    router.namedRoutes[n].add(url[j ..< i])

    routes.sort() do(x, y: Route) -> int:
        result = cmp(x.path.count({'/'}), y.path.count({'/'}))
        if result == 0:
            result = cmp(y of RouteGroup, x of RouteGroup)


proc registerRoutes*(router: Router, routes: openarray[Route]) =
    router.routes = @routes
    router.namedRoutes.clear()
    router.addRoute(router.routes)


proc resolveUrl(routes: seq[Route], url: var string, start: int = 0): (RouteSingle, TableRef[string, string]) {.gcsafe.} =
    result[1] = newTable[string, string]()

    var i, j: int
    
    for route in routes:
        if result[1].len > 0:
            result[1].clear()

        i = start
        j = 0

        while route.path[j] != EOL and url[i] != EOL:
            if route.path[j] == VAR:
                j.inc
                let ni = j
                while route.path[j] notin EOP:
                    j.inc

                let vi = i
                while url[i] notin EOP:
                    i.inc

                if ni != j:
                    result[1][route.path[ni ..< j]] = if vi != i: url[vi ..< i] else: ""
                
                continue
            elif route.path[j] != url[i]:
                break

            i.inc
            j.inc
                
        if route.path[j] == EOL:
            if route of RouteGroup:
                let (r, kwargs) = route.RouteGroup.routes.resolveUrl(url, i)
                if not r.isNil:
                    result[0] = r
                    for k, v in kwargs:
                        result[1][k] = v
                    break
            elif url[i] == EOL:
                result[0] = route.RouteSingle
                break


proc resolveUrl*(router: Router, httpMethod: HttpMethod, url: var string): (UrlListener, TableRef[string, string]) {.gcsafe.} =
    let (route, kwargs) = router.routes.resolveUrl(url)
    result[1] = kwargs

    if not route.isNil:
        if route.multiMethod:
            result[0] = route.listener
        else:
            result[0] = route.listeners.getOrDefault(httpMethod)

    if result[0].isNil:
        result[1].clear()
        result[0] = proc(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
            response.code(Http404).send("Not found")


proc reverseUrl*(router: Router, namespace: string, kwargs: TableRef[string, string] = nil): string =
    let parts = router.namedRoutes.getOrDefault(namespace)
    if not parts.isNil:
        result = ""
        for i, part in parts:
            if i mod 2 == 0:
                result.add(part)
            else:
                echo part
                result.add(kwargs[part])


proc reverseUrl*(router: Router, namespace: string, kwargs: openarray[(string, string)]): string =
    router.reverseUrl(namespace, kwargs.newTable())