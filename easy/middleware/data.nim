import math, strutils, unicode, tables
import .. / .. / easy

type HttpDataValues*[T] = ref object of MiddlewareData
    tbl*: TableRef[string, seq[T]]

template data*[T](vals: HttpDataValues[T]): TableRef[string, seq[T]] =
    if not vals.isNil:
        result = vals.tbl

proc add*[T](vals: HttpDataValues[T], key: string, values: varargs[T]) =
    var tbl = vals.tbl.getOrDefault(key)
    if tbl.isNil:
        tbl = @[]
    for value in values:
        tbl.add(value)
    vals.tbl[key] = tbl

proc `[]=`*[T](vals: HttpDataValues[T], key: string, values: varargs[T]) =
    var tbl: seq[T] = @[]
    for value in values:
        tbl.add(value)
    vals.tbl[key] = tbl
    
proc `[]`*[T](vals: HttpDataValues[T], key: T): seq[T] =
    if vals.tbl.hasKey(key):
        result = vals.tbl[key]

proc get*[T](value: seq[T]): T =
    if value.len > 0:
        result = value[0]
    else:
        result = ""

proc newHttpDataValues*[V](T: typedesc[HttpDataValues[V]]): T =
    T(tbl: newTable[string, seq[V]]())