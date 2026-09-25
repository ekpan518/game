class_name EliminationBatchResult
extends RefCounted

var accepted_any: bool = false
var eliminated_ids: Array[int] = []
var killers_by_victim: Dictionary[int, int] = {}
var buffed_killer_ids: Array[int] = []
var result: StringName = &"playing"
