extends RefCounted
## Small Python-like language; no Python runtime, filesystem access or imports.
const COMMANDS := {"motor":2,"servo":2,"drive":2,"wait":1,"stop":0,"print":1}
const MATH_NAMES := ["abs","min","max","sin","cos","clamp","true","false","and","or","not","PI"]
var running := false
var error := ""
var output: Array[String] = []
var variables: Dictionary = {}
var tasks: Array = []
var waiting := 0.0
var elapsed := 0.0
var line := 1

static func regex(pattern: String) -> RegEx:
	var result := RegEx.new()
	result.compile(pattern)
	return result

static func without_comment(source: String) -> String:
	var quote := ""
	var escaped := false
	for i in range(source.length()):
		var ch := source[i]
		if escaped:
			escaped = false
		elif ch == "\\" and not quote.is_empty():
			escaped = true
		elif not quote.is_empty():
			if ch == quote:
				quote = ""
		elif ch in ["'",'"']:
			quote = ch
		elif ch == "#":
			return source.substr(0,i)
	return source

static func arguments(source: String) -> Array[String]:
	var result: Array[String] = []
	if source.strip_edges().is_empty():
		return result
	var quote := ""
	var escaped := false
	var depth := 0
	var start := 0
	for i in range(source.length()):
		var ch := source[i]
		if escaped:
			escaped = false
		elif ch == "\\" and not quote.is_empty():
			escaped = true
		elif not quote.is_empty():
			if ch == quote:
				quote = ""
		elif ch in ["'",'"']:
			quote = ch
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif ch == "," and depth == 0:
			result.append(source.substr(start,i-start).strip_edges())
			start = i+1
	result.append(source.substr(start).strip_edges())
	return result

static func compile(source: String) -> Dictionary:
	if source.length() > 100000:
		return {"error":"Программа слишком длинная"}
	var lines: Array = []
	var number := 0
	for raw in source.replace("\t","    ").split("\n"):
		number += 1
		var text := without_comment(raw)
		if text.strip_edges().is_empty():
			continue
		var indent := text.length()-text.strip_edges(true,false).length()
		if indent % 4 != 0:
			return {"error":"Строка %d: используй отступ в 4 пробела" % number}
		lines.append({"text":text.strip_edges(),"indent":indent,"line":number})
	if lines.is_empty():
		return {"error":"Напиши программу перед запуском"}
	var result := parse_block(lines,0,0)
	if result.has("error"):
		return result
	return {"block":result.block}

static func parse_block(lines: Array, start: int, indent: int) -> Dictionary:
	var block: Array = []
	var cursor := start
	while cursor < lines.size():
		var row: Dictionary = lines[cursor]
		if row.indent < indent:
			break
		if row.indent > indent:
			return {"error":"Строка %d: лишний отступ" % row.line}
		var text: String = row.text
		if text == "else:":
			break
		var node := {"line":row.line}
		if text.begins_with("if ") or text.begins_with("while ") or text.begins_with("for "):
			if not text.ends_with(":"):
				return {"error":"Строка %d: в конце условия нужно двоеточие" % row.line}
			if text.begins_with("for "):
				var match_for := regex("^for ([A-Za-z_][A-Za-z_0-9]*) in range\\((.*)\\):$").search(text)
				if match_for == null:
					return {"error":"Строка %d: используй for i in range(число):" % row.line}
				node.op = "for"
				node.name = match_for.get_string(1)
				node.args = arguments(match_for.get_string(2))
				if node.args.size() < 1 or node.args.size() > 3:
					return {"error":"Строка %d: range принимает от 1 до 3 чисел" % row.line}
			else:
				node.op = "if" if text.begins_with("if ") else "while"
				node.expression = text.substr(3 if node.op == "if" else 6).trim_suffix(":").strip_edges()
			if cursor+1 >= lines.size() or lines[cursor+1].indent != indent+4:
				return {"error":"Строка %d: добавь команды с отступом в 4 пробела" % row.line}
			var child := parse_block(lines,cursor+1,indent+4)
			if child.has("error"):
				return child
			node.body = child.block
			cursor = child.next
			if node.op == "if" and cursor < lines.size() and lines[cursor].indent == indent and lines[cursor].text == "else:":
				if cursor+1 >= lines.size() or lines[cursor+1].indent != indent+4:
					return {"error":"Строка %d: после else нужны команды с отступом" % lines[cursor].line}
				child = parse_block(lines,cursor+1,indent+4)
				if child.has("error"):
					return child
				node.otherwise = child.block
				cursor = child.next
		else:
			var assignment := regex("^([A-Za-z_][A-Za-z_0-9]*)\\s*=\\s*(?!=)(.+)$").search(text)
			var call := regex("^([A-Za-z_][A-Za-z_0-9]*)\\((.*)\\)$").search(text)
			if assignment != null:
				node.op = "assign"
				node.name = assignment.get_string(1)
				node.expression = assignment.get_string(2)
				if node.name in MATH_NAMES or COMMANDS.has(node.name):
					return {"error":"Строка %d: выбери другое имя переменной" % row.line}
			elif call != null and COMMANDS.has(call.get_string(1)):
				node.op = "call"
				node.name = call.get_string(1)
				node.args = arguments(call.get_string(2))
				if node.args.size() != COMMANDS[node.name]:
					return {"error":"Строка %d: неверное количество аргументов %s" % [row.line,node.name]}
			else:
				return {"error":"Строка %d: неизвестная команда. Поддерживаются motor, servo, drive, wait, stop, print" % row.line}
			cursor += 1
		block.append(node)
	if cursor < lines.size() and lines[cursor].indent == indent and lines[cursor].text == "else:" and indent == 0:
		return {"error":"Строка %d: else без if" % lines[cursor].line}
	return {"block":block,"next":cursor}

func start(compiled: Dictionary) -> void:
	running = true
	error = ""
	output.clear()
	variables.clear()
	tasks.clear()
	waiting = 0
	elapsed = 0
	push_block(compiled.block)

func push_block(block: Array) -> void:
	for i in range(block.size()-1,-1,-1):
		tasks.append(block[i])

func fail(message: String) -> void:
	error = "Строка %d: %s" % [line,message]
	running = false

func evaluate(source: String, robot: Node) -> Variant:
	if source.length() > 2048:
		fail("слишком длинное выражение")
		return null
	var text := source
	# Sensor calls are substituted only outside string literals.
	var strings := regex("\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'")
	var spans := strings.search_all(text)
	var cursor := 0
	var substituted := ""
	for span in spans:
		substituted += sensors(text.substr(cursor,span.get_start()-cursor),robot)
		substituted += span.get_string()
		cursor = span.get_end()
	substituted += sensors(text.substr(cursor),robot)
	text = substituted
	var tokens := strings.sub(text,"",true)
	if tokens.contains("[") or tokens.contains("{") or tokens.contains(";") or tokens.contains(":"):
		fail("используй числа, переменные и арифметику")
		return null
	for token in regex("[A-Za-z_][A-Za-z_0-9]*").search_all(tokens):
		var name := token.get_string()
		if not variables.has(name) and not name in MATH_NAMES:
			fail("неизвестное имя: " + name)
			return null
	var expression := Expression.new()
	var names: PackedStringArray = []
	var values: Array = []
	for name in variables:
		names.append(name)
		values.append(variables[name])
	if expression.parse(text,names) != OK:
		fail("неверное выражение: " + expression.get_error_text())
		return null
	var value = expression.execute(values,null,false)
	if expression.has_execute_failed():
		fail("ошибка выражения: " + expression.get_error_text())
		return null
	if value is float and not is_finite(value):
		fail("результат должен быть конечным числом")
		return null
	return value

func sensors(text: String, robot: Node) -> String:
	text = regex("\\bTrue\\b").sub(text,"true",true)
	text = regex("\\bFalse\\b").sub(text,"false",true)
	text = regex("distance\\s*\\(\\s*\\)").sub(text,str(robot.distance_sensor()),true)
	text = regex("time\\s*\\(\\s*\\)").sub(text,str(elapsed),true)
	for port in range(1, (2 if robot.assembly.is_empty() else robot.actuators.motors.size())+1):
		text = regex("encoder\\s*\\(\\s*%d\\s*\\)" % port).sub(text,str(robot.encoder_for_port(port)),true)
	return text

func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func advance(delta: float, robot: Node) -> void:
	if not running:
		return
	elapsed += delta
	waiting = maxf(0,waiting-delta)
	if waiting > 0:
		return
	# Loops without waits yield regularly, keeping the app and Stop responsive.
	for _step in range(100):
		if tasks.is_empty():
			running = false
			return
		var node: Dictionary = tasks.pop_back()
		line = node.line
		match node.op:
			"assign":
				var value = evaluate(node.expression,robot)
				if not running:
					return
				variables[node.name] = value
			"if", "while":
				var condition = evaluate(node.expression,robot)
				if not running:
					return
				if condition:
					if node.op == "while":
						tasks.append(node)
					push_block(node.body)
				elif node.op == "if":
					push_block(node.get("otherwise",[]))
			"for":
				var args: Array[int] = []
				for argument in node.args:
					var value = evaluate(argument,robot)
					if not running:
						return
					if not numeric(value) or value != int(value) or absf(value) > 1000000:
						fail("range принимает целые числа от -1000000 до 1000000")
						return
					args.append(int(value))
				var begin := 0 if args.size() == 1 else args[0]
				var end := args[0] if args.size() == 1 else args[1]
				var increment := args[2] if args.size() == 3 else 1
				if increment == 0:
					fail("шаг range не может быть нулём")
					return
				tasks.append({"op":"for_step","name":node.name,"current":begin,"end":end,"increment":increment,"body":node.body,"line":line})
			"for_step":
				if node.current < node.end if node.increment > 0 else node.current > node.end:
					variables[node.name] = node.current
					var next := node.duplicate()
					next.current += node.increment
					tasks.append(next)
					push_block(node.body)
			"call":
				var args: Array = []
				for argument in node.args:
					args.append(evaluate(argument,robot))
					if not running:
						return
				if node.name == "print":
					output.append(str(args[0]))
					if output.size() > 300:
						output.pop_front()
					continue
				for value in args:
					if not numeric(value):
						fail("аргументы команды должны быть числами")
						return
				var command_error := ""
				match node.name:
					"motor": command_error = robot.command_motor(args[0],args[1])
					"servo": command_error = robot.command_servo(args[0],args[1])
					"drive":
						if absf(args[0]) > 100 or absf(args[1]) > 100:
							command_error = "мощность мотора: от -100 до 100"
						else:
							robot.command_drive(args[0],args[1])
					"wait":
						if args[0] < 0 or args[0] > 3600:
							command_error = "wait принимает от 0 до 3600 секунд"
						else:
							waiting = args[0]
							return
					"stop": robot.stop()
				if not command_error.is_empty():
					fail(command_error)
					return
