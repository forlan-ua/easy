import strutils, times, logging, tables, asyncdispatch, httpcore
import cookies, strtabs

import .. / .. / easy
import .. / utils

const zeroTime* = fromSeconds(0.0)
const removeTime = fromSeconds(1.0)

type CookieSameSite* {.pure.} = enum
    None, Strict, Lax

type CookiesMiddleware* = ref object of Middleware
    urlencoded*: bool

type 
    CookiesData* = ref object of MiddlewareData
        requestCookies*: TableRef[string, Cookie]
        responseCookies*: TableRef[string, Cookie]

    Cookie* = ref object
        data: CookiesData
        cName: string
        cValue: string
        cDomain: string
        cPath: string
        cExpires: Time
        cSecure: bool
        cHttpOnly: bool
        cMaxAge: int
        cSameSite: CookieSameSite

proc `$`*(c: Cookie, urlencoded: bool = false): string =
    let expires = if c.cExpires != zeroTime: 
        c.cExpires.getGMTime().format("ddd, dd MMM yyy HH:mm:ss") & " GMT" else: ""
    let name = if urlencoded: c.cName.urlencode() else: c.cName
    let value = if urlencoded: c.cValue.urlencode() else: c.cValue
    result = setCookie(
        name, value, domain = c.cDomain,
        path = c.cPath, expires = expires, noName = true, 
        secure = c.cSecure, httpOnly = c.cHttpOnly
    )
    if c.cMaxAge > 0:
        result.add("; Max-Age=")
        result.add($c.cMaxAge)
    if c.cSameSite != CookieSameSite.None:
        result.add("; SameSite=")
        result.add($c.cSameSite)

proc new*(T: typedesc[Cookie], data: CookiesData, name, value: string, domain: string = "", 
         path: string = "", expires: Time = zeroTime, secure: bool = false,
         httpOnly: bool = false, maxAge: int = -1, sameSite: CookieSameSite = CookieSameSite.None): T =

    T(
        data: data,
        cName: name, cValue: value, cDomain: domain, cPath: path, cExpires: expires,
        cSecure: secure, cHttpOnly: httpOnly, cMaxAge: maxAge, cSameSite: sameSite
    )

proc copy*[T: Cookie](c: T, name: string = nil): T =
    T(
        data: c.data, cName: if name.isNil: c.cName else: name,
        cValue: c.cValue, cDomain: c.cDomain, cPath: c.cPath, cExpires: c.cExpires,
        cSecure: c.cSecure, cHttpOnly: c.cHttpOnly, cMaxAge: c.cMaxAge, cSameSite: c.cSameSite
    )

proc new*(T: typedesc[CookiesMiddleware], urlencoded: bool = true): CookiesMiddleware =
    CookiesMiddleware(urlencoded: urlencoded)
    
proc setCookie*(d: CookiesData, c: Cookie): CookiesData {.discardable.} =
    d.responseCookies[c.cName] = c
    c.data = nil
    result = d

proc name*(c: Cookie): string = c.cName
proc value*(c: Cookie): string = c.cValue
proc `value=`*(c: Cookie, value: string) =
    if c.data.isNil:
        c.cValue = value
    else:
        var cookie = c.copy()
        cookie.cValue = value
        c.data.setCookie(cookie)
proc domain*(c: Cookie): string = c.cDomain
proc `domain=`*(c: Cookie, domain: string) =
    if c.data.isNil:
        c.cDomain = domain
    else:
        var cookie = c.copy()
        cookie.cDomain = domain
        c.data.setCookie(cookie)
proc path*(c: Cookie): string = c.cPath
proc `path=`*(c: Cookie, path: string) =
    if c.data.isNil:
        c.cPath = path
    else:
        var cookie = c.copy()
        cookie.cPath = path
        c.data.setCookie(cookie)
proc expires*(c: Cookie): Time = c.cExpires
proc `expires=`*(c: Cookie, expires: Time) =
    if c.data.isNil:
        c.cExpires = expires
    else:
        var cookie = c.copy()
        cookie.cExpires = expires
        c.data.setCookie(cookie)
proc secure*(c: Cookie): bool = c.cSecure
proc `secure=`*(c: Cookie, secure: bool) =
    if c.data.isNil:
        c.cSecure = secure
    else:
        var cookie = c.copy()
        cookie.cSecure = secure
        c.data.setCookie(cookie)
proc httpOnly*(c: Cookie): bool = c.cHttpOnly
proc `httpOnly=`*(c: Cookie, httpOnly: bool) =
    if c.data.isNil:
        c.cHttpOnly = httpOnly
    else:
        var cookie = c.copy()
        cookie.cHttpOnly = httpOnly
        c.data.setCookie(cookie)
proc maxAge*(c: Cookie): int = c.cMaxAge
proc `maxAge=`*(c: Cookie, maxAge: int) =
    if c.data.isNil:
        c.cMaxAge = maxAge
    else:
        var cookie = c.copy()
        cookie.cMaxAge = maxAge
        c.data.setCookie(cookie)
proc sameSite*(c: Cookie): CookieSameSite = c.cSameSite
proc `sameSite=`*(c: Cookie, sameSite: CookieSameSite) =
    if c.data.isNil:
        c.cSameSite = sameSite
    else:
        var cookie = c.copy()
        cookie.cSameSite = sameSite
        c.data.setCookie(cookie)
    
proc getCookie*(d: CookiesData, n: string): Cookie =
    result = d.responseCookies.getOrDefault(n)
    if result.isNil:
        result = d.requestCookies.getOrDefault(n)

proc delCookie*(d: CookiesData, n: string): CookiesData {.discardable.} =
    var cookie = d.getCookie(n)
    if not cookie.isNil:
        cookie.expires = removeTime
    result = d

method onRequest*(middleware: CookiesMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    var cookies = CookiesData(
        requestCookies: newTable[string, Cookie](),
        responseCookies: newTable[string, Cookie]()
    )
    for key, value in request.headers.getOrDefault("Cookie").parseCookies():
        if middleware.urlencoded:
            cookies.requestCookies[key] = Cookie.new(cookies, key.urldecode(), value.urldecode())
        else:
            cookies.requestCookies[key] = Cookie.new(cookies, key, value)
    request.setMiddlewareData(cookies)
    response.setMiddlewareData(cookies)

method onRespond*(middleware: CookiesMiddleware, response: HttpResponse) {.async, gcsafe.} = 
    let data = response.getMiddlewareData(CookiesData)
    
    if not data.isNil:
        if data.responseCookies.len > 0:
            for _, cookie in data.responseCookies:
                response.headers.add("Set-Cookie", `$`(cookie, middleware.urlencoded))

        data.requestCookies = nil
        data.responseCookies = nil