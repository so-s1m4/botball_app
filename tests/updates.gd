extends SceneTree
const Updater = preload("res://src/update_checker.gd")

func _initialize() -> void:
	assert(Updater.is_newer("v0.2.0", "0.1.0"))
	assert(Updater.is_newer("v0.10.0", "0.9.9"))
	assert(not Updater.is_newer("v0.2.0", "0.2.0"))
	assert(not Updater.is_newer("v0.1.9", "0.2.0"))
	assert(not Updater.is_newer("v0.3.0-beta", "0.2.0"))
	assert(not Updater.is_newer("bad", "0.2.0"))
	var release := {"tag_name": "v0.3.0", "assets": [{"name": "Botball-Lab-macOS.dmg", "size": 1024, "browser_download_url": Updater.DOWNLOAD_PREFIX + "v0.3.0/Botball-Lab-macOS.dmg"}]}
	assert(not Updater.release_download(release).is_empty())
	release["prerelease"] = true
	assert(Updater.release_download(release).is_empty())
	release["prerelease"] = false
	release.assets[0].browser_download_url = "https://example.com/untrusted.dmg"
	assert(Updater.release_download(release).is_empty())
	release["assets"] = "bad response"
	assert(Updater.release_download(release).is_empty())
	call_deferred("check_responses")

func check_responses() -> void:
	var updater := Updater.new()
	root.add_child(updater)
	var current := Updater.version_numbers(ProjectSettings.get_setting("application/config/version"))
	var next := "v%d.%d.%d" % [current[0], current[1], current[2]+1]
	var release := {"tag_name":next, "assets":[{"name":"Botball-Lab-macOS.dmg", "size":1024, "browser_download_url":Updater.DOWNLOAD_PREFIX+next+"/Botball-Lab-macOS.dmg"}]}
	updater.completed(HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(release).to_utf8_buffer())
	assert(updater.download_button.visible)
	assert(updater.dialog.visible)
	updater.dialog.hide()
	updater.download_button.visible = false
	updater.completed(HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray())
	assert(not updater.dialog.visible)
	updater.manual = true
	updater.completed(HTTPRequest.RESULT_SUCCESS, 200, [], 'invalid json'.to_utf8_buffer())
	assert(updater.dialog.visible)
	assert(not updater.download_button.visible)
	updater.free()
	print("PASS: release versions, trusted DMG URLs, offline and malformed responses")
	quit()
