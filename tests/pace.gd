extends Node
func _ready():
	var players := []
	for i in 8:
		players.append({"id": "p%d" % i, "name": "봇%d" % i, "bot": true})
	var m := Match.new(players, 4242)
	m.start()
	var times := []
	var draws := 0
	var last_round := 0
	while m.state["phase"] != "over":
		m.advance(0.25)
		if m.state["phase"] == "battle" and int(m.state["round"]) != last_round:
			last_round = int(m.state["round"])
			for bt in m.state["battles"]:
				times.append(float(bt["end_time"]))
				if int(bt["winner"]) == -1:
					draws += 1
	times.sort()
	print("battles=%d median=%.1f p90=%.1f max=%.1f draws=%d rounds=%d" % [times.size(), times[times.size()/2], times[int(times.size()*0.9)], times[-1], draws, m.state["round"]])
	get_tree().quit()
