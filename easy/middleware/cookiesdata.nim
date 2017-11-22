import strutils, times, logging
import cookies, strtabs

import .. / easy
import data

const zeroTime* = fromSeconds(0.0)
const removeTime = fromSeconds(1.0)

type CookieSameSite* {.pure.} = enum
    None, Strict, Lax

type Cookie* = ref object
    name*: string
    value*: string
    domain*: string
    path*: string
    expires*: Time
    secure*: bool
    httpOnly*: bool
    maxAge*: uint
    sameSite*: CookieSameSite

proc new*(T: typedesc[Cookie], name, value: string, domain: string = "", 
         path: string = "", expires: Time = zeroTime, secure: bool = false,
         httpOnly: bool = false, maxAge: uint = 0, sameSite: CookieSameSite = CookieSameSite.None): Cookie =

    Cookie(
        name: name, value: value, domain: domain, path: path, expires: expires,
        secure: secure, httpOnly: httpOnly, maxAge: maxAge, sameSite: sameSite
    )

proc clone*(c: Cookie, name: string = "", value: string = "", domain: string = "",
            path: string = "", expires: Time = zeroTime, secure: bool = false,
            httpOnly: bool = false, maxAge: uint = 0, sameSite: CookieSameSite = CookieSameSite.None): Cookie =
    let name = if name == "": c.name else: name
    let value = if value == "": c.value else: value
    let domain = if domain == "": c.domain else: domain
    let expires = if expires == zeroTime: c.expires else: expires
    let secure = if not secure: c.secure else: secure
    let httpOnly = if not httpOnly: c.httpOnly else: httpOnly
    let maxAge = if maxAge == 0: c.maxAge else: maxAge
    let sameSite = if sameSite == CookieSameSite.None: c.sameSite else: sameSite
    Cookie.new(name, value, domain, path, expires, secure, httpOnly, maxAge, sameSite)

type CookiesMiddleware* = ref object of Middleware
    urlencoded*: bool
type CookiesData* = ref object of MiddlewareData
    cookies: TableRef[string, Cookie]
    locked: bool

proc new*(T: typedesc[CookiesMiddleware], urlencoded: bool = false): CookiesMiddleware =
    CookiesMiddleware(urlencoded: urlencoded)

proc get*(d: CookiesData, n: string): Cookie =
    result = d.cookies.getOrDefault(n)

proc set*(d: CookiesData, c: Cookie): CookiesData {.discardable.} =
    if d.locked:
        warn "Unable to set request cookies"
    else:
        d.cookies[c.name] = c
    result = d

proc del*(d: CookiesData, n: string): CookiesData {.discardable.} =
    if d.locked:
        warn "Unable to del from request cookies"
    else:
        var cookie = d.get(n)
        if not cookie.isNil:
            d.set(cookie.clone(expires = removeTime))
    result = d

method onRequest(middleware: CookiesMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    var requestData = CookiesData(cookies: newTable[string, Cookie](), locked: true)
    for key, value in request.headers.getOrDefault("Cookie").parseCookies():
        if middleware.urlencoded:
            requestData.cookies[key] = Cookie.new(key, value.urldecode())
        else:
            requestData.cookies[key] = Cookie.new(key, value)
    var responseData = CookiesData(cookies: newTable[string, Cookie](), locked: false)
    request.setMiddlewareData(requestData)
    response.setMiddlewareData(responseData)

method onResponse(middleware: CookiesMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    let data = response.getMiddlewareData(CookiesData)

    if data.cookies.len > 0:
        for _, cookie in data.cookies:
            let expires = if cookie.expires != zeroTime: 
                cookie.expires.getGMTime().format("ddd, dd MMM yyy HH:mm:ss") & " GMT" else: ""
            let value = if middleware.urlencoded: cookie.value.urlencode() else: cookie.value
            var cookieString = setCookie(
                cookie.name, value, domain = cookie.domain,
                path = cookie.path, expires = expires, noName = true, 
                secure = cookie.secure, httpOnly = cookie.httpOnly
            )
            if cookie.maxAge > 0.uint:
                cookieString &= "; Max-Age=" & $cookie.maxAge
            if cookie.sameSite != CookieSameSite.None:
                cookieString &= "; SameSite=" & $cookie.sameSite

            response.headers.add("Set-Cookie", cookieString)