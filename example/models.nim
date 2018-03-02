import json, db_sqlite, strutils, sequtils, tables, typetraits
import database


type ModelValue* = ref object
    name*: string
    kind*: JsonNodeKind
    value*: JsonNode
    changed*: bool

proc sqlValue*(mv: ModelValue): string =
    if mv.value.isNil or mv.value.kind == JNull:
        result = "NULL"
        return

    case mv.kind:
        of JString:
            result = mv.value.getStr().dbQuote()
        of JBool:
            result = $mv.value.getBool().int
        of JInt:
            result = $mv.value.getBiggestInt()
        of JFloat:
            result = $mv.value.getFloat()
        else:
            discard


proc newModelValue*(name: string, kind: JsonNodeKind): ModelValue =
    result = ModelValue(
        name: name,
        kind: kind
    )

type Model* = ref object of RootObj
    fields*: OrderedTable[string, ModelValue]

method table*(m: Model): string {.base, gcsafe.} = discard


proc setVal*(mv: ModelValue, r: string) =
    case mv.kind:
        of JString:
            mv.value = %r
        of JBool:
            if r.len > 0:
                mv.value = %parseInt(r).bool
            else:
                mv.value = newJNull()
        of JInt:
            if r.len > 0:
                mv.value = %parseInt(r)
            else:
                mv.value = newJNull()
        of JFloat:
            if r.len > 0:
                mv.value = %parseFloat(r)
            else:
                mv.value = newJNull()
        else:
            discard


proc parse*(m: Model, raw: openarray[string]) =
    var i = 0
    for key in m.fields.keys():
        m.fields[key].setVal(raw[i])
        i.inc


proc update*(m: Model, json: JsonNode) =
    for key, value in json:
        if key in m.fields:
            if m.fields[key].value != value:
                m.fields[key].value = value
                m.fields[key].changed = true


proc parse*(T: typedesc[Model], json: JsonNode): T =
    result = T.new()
    result.update(json)


proc retrieve*(T: typedesc[Model], id: int|string): T =
    result = T.new()

    var fields: seq[string] = @[]
    var pkName: string
    for key in result.fields.keys():
        if pkName.isNil:
            pkName = key
        fields.add(key)

    let query = "SELECT $# FROM $# WHERE $# = ?" % [
        fields.join(", "),
        result.table(),
        pkName
    ]

    let x = db.getRow(sql(query), id)
    if x[0].len == 0:
        return nil

    result.parse(x)


proc exists*(T: typedesc[Model], id: int|string): bool =
    let tmp = T.new()
    var pkName: string
    for key in tmp.fields.keys():
        pkName = key
        break
    let query = "SELECT $1 FROM $2 WHERE $1 = ?" % [
        pkName,
        tmp.table()
    ]
    result = db.getRow(sql(query), id)[0].len > 0


proc list*(T: typedesc[Model], page: int, limit: int): seq[Model] =
    result = @[]

    let tmp = T.new()
    var fields: seq[string] = @[]
    for key in tmp.fields.keys():
        fields.add(key)
    
    let query = "SELECT $# FROM $# LIMIT $#,$#" % [
        fields.join(", "),
        tmp.table(),
        $((page - 1) * limit),
        $limit
    ]

    for x in db.fastRows(sql(query)):
        let m = T.new()
        m.parse(x)
        result.add(m)

proc count*(T: typedesc[Model]): int =
    let m = T.new()
    parseInt(db.getRow(sql"SELECT COUNT(*) as c_count FROM ?", m.table())[0])


proc insert[T](m: T): bool =
    var fields: seq[string] = @[]
    var values: seq[string] = @[]

    for key, value in m.fields:
        if value.changed:
            fields.add(key)
            values.add(value.sqlValue())
    
    let query = "INSERT INTO $# ($#) VALUES ($#)" % [
        m.table(),
        fields.join(", "),
        values.join(", ")
    ]
    let id = db.tryInsertID(sql(query))
    
    if id > -1:
        var first = true
        for _, field in m.fields:
            if first:
                field.value = %id
                first = false
            field.changed = false
        result = true


proc update[T](m: T): bool =
    var values: seq[string] = @[]

    var item: string
    for key, value in m.fields:
        if item.isNil:
            item = key & " = " & value.sqlValue()
        elif value.changed:
            values.add(key & '=' & value.sqlValue())
    
    let query = "UPDATE $# SET $# WHERE $#" % [
        m.table(),
        values.join(", "),
        item
    ]

    result = db.tryExec(sql(query))

    if result:
        for _, field in m.fields:
            field.changed = false


proc save*[T](m: T): bool =
    for _, field in m.fields:
        if not field.value.isNil:
            result = m.update()
        else:
            result = m.insert()
        break


proc delete*(T: typedesc[Model], id: int|string) =
    let tmp = T.new()
    var pkName: string
    for key, _ in tmp.fields:
        pkName = key
        break
    let query = "DELETE FROM $# WHERE $# = ?" % [
        tmp.table(),
        pkName
    ]
    db.exec(sql(query), id)


proc delete*[T](m: T) =
    var item: string
    for key, field in m.fields:
        item = key & " = " & field.sqlValue()
        break

    let query = "DELETE FROM $# WHERE $#" % [
        m.table,
        item
    ]
    db.exec(sql(query))


proc toJson*(m: Model): JsonNode =
    result = newJObject()
    for key, field in m.fields:
        result[key] = if not field.value.isNil: field.value else: newJNull()


proc toJson*(s: seq[Model]): JsonNode =
    result = newJArray()
    result.elems = s.map(proc(x: Model): JsonNode = x.toJson())


proc toFields*(fields: openarray[ModelValue]): OrderedTable[string, ModelValue] =
    result = initOrderedTable[string, ModelValue]()
    for field in fields:
        result[field.name] = field


type Category* = ref object of Model
proc new*(T: typedesc[Category]): T =
    T(
        fields: [
            newModelValue("id", JString),
            newModelValue("removed", JString),
            newModelValue("name", JString),
            newModelValue("description", JString),
            newModelValue("is_active", JBool),
            newModelValue("position", JInt),
            newModelValue("parent_id", JInt)
        ].toFields()
    )
method table*(m: Category): string {.gcsafe.} = "category"

type Developer* = ref object of Model
proc new*(T: typedesc[Developer]): T =
    T(
        fields: [
            newModelValue("id", JString),
            newModelValue("removed", JString),
            newModelValue("name", JString)
        ].toFields()
    )
method table*(m: Developer): string {.gcsafe.} = "developer"
