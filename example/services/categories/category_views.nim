import asyncdispatch, json, tables, db_sqlite, strutils, httpcore
import easy
import easy / middleware / [ jsondata, querystring ]

import .. / .. / models
import .. / paginator


proc listCategories*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let queryString = request.getMiddlewareData(QueryStringData)

    let pageStr = queryString.get("p")
    let limitStr = queryString.get("l")

    let page = if pageStr.isDigit(): parseInt(pageStr) else: 1
    var limit = if limitStr.isDigit(): parseInt(limitStr) else: 10
    let count = Category.count()

    if limit > 20:
        limit = 20

    let res = newJObject()
    res["items"] = Category.list(page, limit).toJson()
    res["pages"] = request.pages(page, limit, count)

    response.send(res)


proc createCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    if "id" in data:
        data.delete("id")
    data["is_active"] = %false
    let category = Category.parse(data)

    if category.save():
        response.code(Http201).send(category.toJson())
    else:
        response.code(500)


proc retrieveCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let category = Category.retrieve(request.kwargs["id"])

    if not category.isNil:
        response.send(category.toJson())
    else:
        response.code(Http404).send("Category has not been found")


proc updateCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    let category = Category.retrieve(request.kwargs["id"])

    if not category.isNil:
        category.update(data)
        if category.save():
            response.send(category.toJson())
        else:
            response.code(500)
    else:
        response.code(Http404).send("Category has not been found")


proc deleteCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let id = request.kwargs["id"]
    if Category.exists(id):
        Category.delete(id)
        response.code(Http204)
    else:
        response.code(Http404).send("Category has not been found")