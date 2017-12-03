import math, strutils, unicode, tables
import .. / .. / easy

type HttpDataValues* = ref object of MiddlewareData
    tbl*: TableRef[string, seq[string]]

proc add*(vals: HttpDataValues, key: string, values: openarray[string]) =
    var data = vals.tbl.getOrDefault(key)
    if data.isNil:
        data = @[]
    for value in values:
        data.add(value)
    vals.tbl[key] = data
template add*(vals: HttpDataValues, key: string, value: string) = 
    vals.add(key, [value])

proc `[]=`*(vals: HttpDataValues, key: string, values: openarray[string]) =
    var data: seq[string] = @[]
    for value in values:
        data.add(value)
    vals.tbl[key] = data
template `[]=`*(vals: HttpDataValues, key: string, value: string) = 
    vals[key] = [value]
    
proc `[]`*(vals: HttpDataValues, key: string): seq[string] =
    if vals.tbl.hasKey(key):
        result = vals.tbl[key]
    else:
        result = @[]

proc get*(value: seq[string]): string =
    if value.len > 0:
        result = value[0]
    else:
        result = ""

proc newHttpDataValues*[T](): T = 
    T(tbl: newTable[string, seq[string]]())

proc urlencode*(str: string): string =
    result = ""
    for rune in str.runes():
        var bytes = 0
        var code = rune.int
        
        if code <= 0x7F:
            if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
                result.add($rune)
                continue
            result.add('%')
            result.add(code.toHex(2))
            continue
        elif code <= 0x7FF:
            bytes = 2
        elif code <= 0xFFFF:
            bytes = 3
        elif code <= 0x1FFFFF:
            bytes = 4
        elif code <= 0x3FFFFFF:
            bytes = 5
        elif code <= 0x7FFFFFFF:
            bytes = 6
        
        var str = ""
        for i in 1 .. bytes - 1:
            str = "%" & ((code and 0b00111111) or 0b10000000).toHex(2) & str
            code = code shr 6
        
        result.add('%')
        result.add((((2^bytes - 1) shl (8 - bytes)) or code).toHex(2))
        result.add(str)

proc urldecode*(str: string): string =
    result = ""
    var i = 0
    let l = str.len
    while i < l:
        let ch = str[i]
        if ch == '%':
            i += 2
            var firstByte = str[i-1..i].parseHexInt()
            if (firstByte and 0b10000000) == 0:
                result.add($firstByte.Rune)
            else:
                var code = 0
                var mask = 0b01000000
                var firstByteMask = 0b01111111
                var pow = 0

                while (firstByte and mask) == mask:
                    i += 3
                    let nextByte = str[i-1..i].parseHexInt() and 0b00111111
                    code = (code shl 6) or nextByte

                    mask = mask shr 1
                    firstByteMask = firstByteMask shr 1
                    pow.inc

                code = code or ((firstByteMask and firstByte) shl 6*pow)
                result.add($code.Rune)
        else:
            result.add(ch)
        i.inc