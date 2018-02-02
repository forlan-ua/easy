import asyncdispatch, json, tables, db_sqlite, strutils, httpcore
import easy
import easy / middleware / [ jsondata, querystring ]
import .. / .. / database


proc categoryToJson(x: seq[string]): JsonNode =
    result = %*{
        "id": parseInt(x[0]),
        "removed": if x[1].len == 0: nil else: x[1],
        "name": x[2],
        "description": x[3],
        "is_active": parseInt(x[4]).bool,
        "position": parseInt(x[5]),
        "parent": if x[6].len > 0: %parseInt(x[6]) else: newJNull()
    }


proc listCategories*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let queryString = request.getMiddlewareData(QueryStringData)

    let pageStr = queryString.get("p")
    let limitStr = queryString.get("l")

    let page = if pageStr.isDigit(): parseInt(pageStr) else: 1
    var limit = if limitStr.isDigit(): parseInt(limitStr) else: 10
    if limit > 20:
        limit = 20

    let count = parseInt(db.getRow(sql"SELECT COUNT(*) as c_count FROM category")[0])

    let res = newJObject()
    res["items"] = newJArray()
    for x in db.fastRows(sql"SELECT * FROM category LIMIT ?,?", (page - 1) * limit, limit):
        res["items"].add(x.categoryToJson())
    
    res["count"] = %count
    res["page"] = %page
    res["limit"] = %limit
    res["prev"] = if page > 1: 
        %(request.url.path & queryString.toString({"p": $(page - 1), "l": $limit})) 
        else: newJNull()
    res["next"] = if page * limit < count: 
        %(request.url.path & queryString.toString({"p": $(page + 1), "l": $limit})) 
        else: newJNull()

    response.send(res)


proc createCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    var fields: seq[string] = @[]
    var values: seq[string] = @[]

    for field in ["name", "description", "position", "parent_id"]:
        fields.add(field)
        if field in data:
            case data[field].kind:
                of JString:
                    values.add(data[field].getStr().dbQuote())
                of JBool:
                    values.add($data[field].getBool().int)
                of JNull:
                    values.add("NULL")
                else:
                    values.add(($data[field]).dbQuote())
        else:
            values.add("NULL")

    fields.add(["is_active", "removed"])
    values.add(["0", "NULL"])

    let query = "INSERT INTO category (" & fields.join(", ") & ") VALUES (" & values.join(", ") & ")"
    let id = db.tryInsertID(sql(query))

    if id > -1:
        let x = db.getRow(sql"SELECT * FROM category WHERE id = ?", id)
        let res = x.categoryToJson()
        response.code(Http201).send(res)
    else:
        response.code(500)


proc retrieveCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let x = db.getRow(sql"SELECT * FROM category WHERE id = ?", request.kwargs["id"])

    if x[0].len > 0:
        let res = x.categoryToJson()
        response.send(res)
    else:
        response.code(Http404).send("Category has not been found")


proc updateCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let data = request.getMiddlewareData(JsonData).data
    if data.isNil:
        response.code(Http400)
        return

    let id = request.kwargs["id"]

    let x = db.getRow(sql"SELECT * FROM category WHERE id = ?", request.kwargs["id"])

    if x[0].len > 0:
        var res = x.categoryToJson()

        var values: seq[string] = @[] 
        for field in ["name", "description", "position", "parent_id", "is_active", "removed"]:
            if field in data:
                res[field] = data[field]
                case data[field].kind:
                    of JString:
                        values.add(field & " = " & data[field].getStr().dbQuote())
                    of JBool:
                        values.add(field & " = " & $data[field].getBool().int)
                    of JNull:
                        values.add(field & " = " & "NULL")
                    else:
                        values.add(field & " = " & ($data[field]).dbQuote())

        let query = "UPDATE category SET " & values.join(", ") & " WHERE id = ?"
        
        if db.tryExec(sql(query), id):
            response.send(res)
        else:
            response.code(500)
    else:
        response.code(Http404).send("Category has not been found")


proc deleteCategory*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let id = request.kwargs["id"]
    if db.getValue(sql"SELECT id FROM category WHERE id = ?", id).len > 0:
        db.exec(sql"DELETE FROM category WHERE id = ?", id)
        response.code(Http204)
    else:
        response.code(Http404).send("Category has not been found")