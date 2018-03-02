import asyncdispatch, json, tables, db_sqlite, strutils, httpcore
import easy
import easy / middleware / [ jsondata, querystring ]

import .. / .. / models
import .. / paginator


proc listDevelopers*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let queryString = request.getMiddlewareData(QueryStringData)

    let pageStr = queryString.get("p")
    let limitStr = queryString.get("l")

    let page = if pageStr.isDigit(): parseInt(pageStr) else: 1
    var limit = if limitStr.isDigit(): parseInt(limitStr) else: 10
    let count = Developer.count()

    if limit > 20:
        limit = 20

    let res = newJObject()
    res["items"] = Developer.list(page, limit).toJson()
    res["pages"] = request.pages(page, limit, count)

    response.send(res)


proc createDeveloper*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    if "id" in data:
        data.delete("id")
    data["is_active"] = %false
    let developer = Developer.parse(data)

    if developer.save():
        response.code(Http201).send(developer.toJson())
    else:
        response.code(500)


proc retrieveDeveloper*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let developer = Developer.retrieve(request.kwargs["id"])

    if not developer.isNil:
        response.send(developer.toJson())
    else:
        response.code(Http404).send("Developer has not been found")


proc updateDeveloper*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    let developer = Developer.retrieve(request.kwargs["id"])

    if not developer.isNil:
        developer.update(data)
        if developer.save():
            response.send(developer.toJson())
        else:
            response.code(500)
    else:
        response.code(Http404).send("Developer has not been found")


proc deleteDeveloper*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let id = request.kwargs["id"]
    if Developer.exists(id):
        Developer.delete(id)
        response.code(Http204)
    else:
        response.code(Http404).send("Developer has not been found")