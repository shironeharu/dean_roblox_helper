; Pure file-buffer matching; shared by the isolated worker and offline checks.
class WarningMatcher {
	static MatchError := 0.15
	static Scales := [1.0, 0.95, 1.05, 0.9, 1.1, 0.85, 1.15, 0.8, 1.2, 0.75, 1.25, 0.7, 1.3, 0.65, 1.35, 0.6, 1.4, 1.45, 1.5]
	static Find(x1, y1, x2, y2, screenshot := 1) {
		global RobberyWarningPatterns
		; 창당 한 번만 캡처하고 나머지 배율은 같은 화면 버퍼를 재사용합니다.
		for scale in this.Scales {
			result := FindText(&fx, &fy, x1, y1, x2, y2, this.MatchError, this.MatchError, RobberyWarningPatterns, screenshot, 0, 0, 20, 10, 1, scale, scale)
			if result
				return result
			screenshot := 0
		}
		return 0
	}
}
