class_name LoadingScreen
extends CanvasLayer
## Full-screen loading overlay shown when the match scene opens, until the match really starts.
## HeroSpawner feeds it the loading progress; GamePlay hides it on start_game.

@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel
@onready var percent_label: Label = %PercentLabel
@onready var root: Control = $Root

var _shown_progress := 0.0
var _target_progress := 0.0


func _ready() -> void:
	visible = true
	set_progress(0.0)
	set_status("Loading heroes...")


func _process(delta: float) -> void:
	# Ease the bar toward the real value so it doesn't jump in big steps
	_shown_progress = move_toward(_shown_progress, _target_progress, delta * 1.5)
	progress_bar.value = _shown_progress * 100.0
	percent_label.text = "%d%%" % int(round(_shown_progress * 100.0))


## [param value] from 0 to 1
func set_progress(value: float) -> void:
	_target_progress = clampf(value, 0.0, 1.0)
	if _target_progress < _shown_progress:
		_shown_progress = _target_progress


func set_status(text: String) -> void:
	status_label.text = text


## Fades out and removes the overlay
func finish() -> void:
	set_progress(1.0)
	_shown_progress = 1.0
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
