// strlib — a TinyGo reactor library exporting string functions over the
// wasmtk Canonical ABI, consumable by `wasmtk bindgen`.
//
// TinyGo's //go:wasmexport only accepts numeric/pointer signatures, so the
// canonical string convention is written by hand here (the same shape wasic
// generates): strings cross as (ptr, len) UTF-8; a returned string is a
// callee-allocated i32 pointer to an [dataPtr, len] pair, released by
// cabi_post_<name>. Memory is the module's own, allocated via the exported
// cabi_realloc (a linkname wrapper over TinyGo's malloc). Build:
//
//	wasmtk modc --lang=go tests/go_fixtures/strlib
package main

import "unsafe"

// Link to TinyGo's C allocator so host-allocated / returned buffers are
// readable and freeable across the boundary.
//
//go:linkname cmalloc malloc
func cmalloc(size uintptr) unsafe.Pointer

//go:linkname cfree free
func cfree(ptr unsafe.Pointer)

// cabi_realloc — the Canonical ABI allocator primitive. Only the fresh-alloc
// case (ptr==0) is exercised by string lowering; realloc/free-through is not
// needed for the bump-style host marshalling.
//
//go:wasmexport cabi_realloc
func cabiRealloc(ptr uint32, oldSize uint32, align uint32, newSize uint32) uint32 {
	return uint32(uintptr(cmalloc(uintptr(newSize))))
}

// goStr reads a (ptr, len) UTF-8 argument as a Go string (no copy).
func goStr(ptr uint32, length uint32) string {
	return unsafe.String((*byte)(unsafe.Pointer(uintptr(ptr))), int(length))
}

// retStr writes s into fresh memory as a canonical [dataPtr, len] pair and
// returns the pair pointer (the callee-allocated return convention).
func retStr(s string) uint32 {
	b := []byte(s)
	dataPtr := uint32(uintptr(cmalloc(uintptr(len(b)))))
	copy(unsafe.Slice((*byte)(unsafe.Pointer(uintptr(dataPtr))), len(b)), b)
	pairPtr := uint32(uintptr(cmalloc(8)))
	pair := unsafe.Slice((*uint32)(unsafe.Pointer(uintptr(pairPtr))), 2)
	pair[0], pair[1] = dataPtr, uint32(len(b))
	return pairPtr
}

// freeRet releases a pair pointer and its data (paired with each string return).
func freeRet(pairPtr uint32) {
	pair := unsafe.Slice((*uint32)(unsafe.Pointer(uintptr(pairPtr))), 2)
	cfree(unsafe.Pointer(uintptr(pair[0])))
	cfree(unsafe.Pointer(uintptr(pairPtr)))
}

//go:wasmexport greet
func greet(namePtr uint32, nameLen uint32) uint32 {
	return retStr("Hello, " + goStr(namePtr, nameLen) + "!")
}

//go:wasmexport cabi_post_greet
func cabiPostGreet(pairPtr uint32) { freeRet(pairPtr) }

//go:wasmexport strLen
func strLen(sPtr uint32, sLen uint32) uint32 {
	return uint32(len(goStr(sPtr, sLen)))
}

func main() {}
