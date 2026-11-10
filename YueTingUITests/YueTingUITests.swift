import XCTest

/// 主流程冒烟测试。前提：曲库里已经有歌，且包含周杰伦的「晴天」
final class YueTingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// 曲库扫描、点歌播放、迷你条、全屏播放页
    func testPlayFromLibrary() {
        let (cell, title) = firstSong()
        cell.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "点歌后应出现迷你播放条")
        XCTAssertTrue(mini.staticTexts[title].exists, "迷你条应显示刚点的「\(title)」")
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5), "点歌后应开始播放")
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5), "应打开全屏播放页")
        attach("now-playing")
    }

    /// 暂停时拖进度条：位置立刻变到目标处并保持；播放时拖动松手后不跳回旧位置
    func testSeekPausedAndPlaying() {
        openPlayer()
        let slider = app.otherElements["播放进度"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        // 暂停状态拖到 70%
        let toggle = app.buttons["playPause"]
        toggle.tap()
        XCTAssertTrue(wait(toggle, label: "播放"), "应已暂停")
        drag(slider, to: 0.7)
        let paused = seconds(slider)
        print("[YT] 暂停拖到 70% 后位置 \(paused)s / \(total(slider))s")
        XCTAssertGreaterThan(paused, total(slider) * 0.6, "暂停时拖动应生效")
        sleep(2)
        XCTAssertEqual(seconds(slider), paused, accuracy: 1, "暂停时位置应保持不动")
        // 继续播放，应从拖到的位置往后走
        // 等待按钮变化和读取无障碍值本身要一两秒，所以按实际经过的时间算上限
        let resumedAt = Date()
        toggle.tap()
        XCTAssertTrue(wait(toggle, label: "暂停"), "应已继续播放")
        sleep(2)
        let resumed = seconds(slider)
        let elapsed = Date().timeIntervalSince(resumedAt)
        print("[YT] 继续播放 \(elapsed)s 后 \(resumed)s")
        XCTAssertGreaterThanOrEqual(resumed, paused)
        XCTAssertLessThan(resumed, paused + elapsed + 2)
        // 播放状态拖到 20%，松手后连续采样，不应出现回到 70% 附近的值
        drag(slider, to: 0.2)
        var samples: [Double] = []
        for _ in 0..<10 { samples.append(seconds(slider)); usleep(100_000) }
        print("[YT] 播放中拖到 20% 后采样 \(samples)")
        let target = total(slider) * 0.2
        XCTAssertTrue(samples.allSatisfy { abs($0 - target) < 6 }, "松手后不应闪回旧位置：\(samples)")
        attach("after-seek")
    }

    /// 上一首：即使当前歌已经播了一会，也应直接回到上一首，而不是本曲从头播
    func testPreviousAfterPlaying() {
        let (cell, first) = firstSong()
        cell.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        leaveRhythm()
        // 播放页盖在歌曲列表上，列表里的歌名仍在无障碍树中，所以只看播放页的标题
        let title = app.staticTexts["nowPlayingTitle"]
        XCTAssertTrue(wait(title, label: first))
        app.buttons["下一首"].firstMatch.tap()
        let second = NSPredicate(format: "label != %@", first)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: second, evaluatedWith: title)], timeout: 3), .completed, "应已切到下一首")
        sleep(5)
        app.buttons["上一首"].tap()
        XCTAssertTrue(wait(title, label: first), "播了 5 秒后点上一首应回到「\(first)」，实际是「\(title.label)」")
    }

    /// 歌词：播放页底部按钮切到歌词，再切回封面。歌词内容取决于网络，这里只看能切换、有内容或状态提示
    func testLyricsToggle() {
        openPlayer()
        // 上次停在歌词页时会记住，先切回封面
        if app.buttons["显示封面"].waitForExistence(timeout: 2) {
            app.buttons["显示封面"].tap()
        }
        app.buttons["显示歌词"].tap()
        let lyrics = app.descendants(matching: .any)["lyrics"].firstMatch
        XCTAssertTrue(lyrics.waitForExistence(timeout: 3), "应显示歌词区域")
        attach("lyrics")
        app.buttons["显示封面"].tap()
        XCTAssertTrue(app.buttons["显示歌词"].waitForExistence(timeout: 3), "应切回封面")
    }

    /// 歌词播放效果：拖动歌词出现定位线，点「从这里播放」跳过去；点歌词回到封面。
    /// 前提：曲库里有「起风了」且已取到网易云逐字歌词
    func testLyricsBrowse() {
        app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("起风了")
        let hit = row("起风了")
        XCTAssertTrue(hit.waitForExistence(timeout: 3))
        hit.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        if app.buttons["显示歌词"].waitForExistence(timeout: 2) {
            app.buttons["显示歌词"].tap()
        }
        let lyrics = app.descendants(matching: .any)["lyrics"].firstMatch
        XCTAssertTrue(lyrics.waitForExistence(timeout: 3))
        drag(app.otherElements["播放进度"], to: 0.3)
        sleep(3)
        attach("lyrics-playing")
        lyrics.swipeUp(velocity: .slow)
        let play = app.buttons["从这里播放"]
        XCTAssertTrue(play.waitForExistence(timeout: 2), "拖动歌词时应出现定位线")
        attach("lyrics-browsing")
        play.tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 2), "点播放后定位线应消失")
        sleep(2)
        attach("lyrics-after-jump")
        // 播到中间切下一首，歌词应从第一行开始，不沿用上一首的滚动位置
        app.buttons["下一首"].firstMatch.tap()
        sleep(2)
        attach("lyrics-next-song")
        lyrics.tap()
        XCTAssertTrue(app.buttons["显示歌词"].waitForExistence(timeout: 3), "点歌词应回到封面")
    }

    /// 律动模式：底部按钮打开后铺满全屏；播放中 3 秒没操作控件收起，只留进度条（仍可拖动）；
    /// 点画面呼出控件，再从底部按钮回到封面。前提：曲库里有「起风了」
    func testRhythm() {
        app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("起风了")
        let hit = row("起风了")
        XCTAssertTrue(hit.waitForExistence(timeout: 3))
        hit.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        // 上次停在律动模式时会记住；控件可能已经自动收起，先点画面呼出再退出
        let rhythm = app.descendants(matching: .any)["rhythm"].firstMatch
        if rhythm.waitForExistence(timeout: 2) {
            exitRhythm(rhythm)
        }
        app.buttons["律动模式"].tap()
        XCTAssertTrue(rhythm.waitForExistence(timeout: 3), "应显示律动画面")
        attach("rhythm-chrome")
        let slider = app.otherElements["播放进度"]
        // 拖回开头看前奏里玩球的小狗
        drag(slider, to: 0)
        for i in 1...4 {
            sleep(2)
            attach("rhythm-intro-\(i)")
        }
        // 等了这么久控件已经收起，点一下呼出再拖
        if !app.buttons["playPause"].exists {
            rhythm.tap()
        }
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 3))
        drag(slider, to: 0.25)
        // 拖动算一次操作，3 秒后才收起
        XCTAssertTrue(app.buttons["playPause"].exists, "刚拖完进度条控件不应收起")
        XCTAssertTrue(app.buttons["playPause"].waitForNonExistence(timeout: 6), "播放中没操作应收起控件")
        XCTAssertTrue(slider.exists, "收起控件后进度条仍要显示")
        for i in 1...8 {
            usleep(400_000)
            attach("rhythm-\(i)")
        }
        // 收起状态下进度条照样能拖
        let before = seconds(slider)
        drag(slider, to: 0.6)
        XCTAssertGreaterThan(seconds(slider), before + 20, "收起控件后进度条应能拖动")
        // 拖到快结束，看接球的小猫
        drag(slider, to: 0.93)
        for i in 1...6 {
            sleep(2)
            attach("rhythm-end-\(i)")
        }
        rhythm.tap()
        XCTAssertTrue(app.buttons["退出律动"].waitForExistence(timeout: 3), "点画面应呼出控件")
        attach("rhythm-shown")
        exitRhythm(rhythm)
        XCTAssertTrue(app.buttons["律动模式"].waitForExistence(timeout: 3), "应回到封面")
        XCTAssertFalse(rhythm.exists)
    }

    /// 歌词微调：封面页按钮置灰，歌词页底部按钮打开面板，提前 / 延后按 0.1、0.5 秒累加，还原回到同步；律动模式里也有这个按钮
    func testLyricsOffset() {
        openPlayer()
        // 封面页的微调按钮在，但置灰点不了
        if app.buttons["显示封面"].waitForExistence(timeout: 2) {
            app.buttons["显示封面"].tap()
        }
        XCTAssertTrue(app.buttons["歌词微调"].waitForExistence(timeout: 3), "封面页也应有微调按钮")
        XCTAssertFalse(app.buttons["歌词微调"].isEnabled, "封面页的微调按钮应置灰")
        attach("cover-bottom")
        app.buttons["显示歌词"].tap()
        let open = app.buttons["歌词微调"]
        XCTAssertTrue(open.isEnabled, "歌词页的微调按钮应能点")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "歌词页应有微调按钮")
        open.tap()
        let value = app.staticTexts["lyricsOffset"]
        XCTAssertTrue(value.waitForExistence(timeout: 3), "应打开微调面板")
        // 上次调过会记住，先还原
        if app.buttons["还原"].isEnabled {
            app.buttons["还原"].tap()
        }
        XCTAssertTrue(wait(value, label: "歌词与歌曲同步"))
        app.buttons["提前 0.5 秒"].tap()
        app.buttons["提前 0.5 秒"].tap()
        app.buttons["延后 0.1 秒"].tap()
        XCTAssertTrue(wait(value, label: "歌词提前 0.9 秒"), "实际是「\(value.label)」")
        attach("lyrics-offset")
        closeSheet(value)
        XCTAssertTrue(value.waitForNonExistence(timeout: 3), "下拉应关掉微调面板")
        XCTAssertEqual(open.value as? String, "歌词提前 0.9 秒", "按钮上应带着当前微调")
        open.tap()
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        app.buttons["延后 0.5 秒"].tap()
        app.buttons["延后 0.5 秒"].tap()
        XCTAssertTrue(wait(value, label: "歌词延后 0.1 秒"), "实际是「\(value.label)」")
        app.buttons["还原"].tap()
        XCTAssertTrue(wait(value, label: "歌词与歌曲同步"))
        closeSheet(value)
        XCTAssertTrue(value.waitForNonExistence(timeout: 3), "下拉应关掉微调面板")
        app.buttons["律动模式"].tap()
        XCTAssertTrue(app.buttons["歌词微调"].waitForExistence(timeout: 3), "律动模式也应有微调按钮")
        exitRhythm(app.descendants(matching: .any)["rhythm"].firstMatch)
    }

    /// 播放模式：一个按钮按 列表循环 → 单曲循环 → 随机播放 轮流切换，每次切换弹一下提示，过一会自己消失
    func testPlayMode() {
        openPlayer()
        let button = app.buttons["playMode"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        let order = ["列表循环", "单曲循环", "随机播放"]
        // 上次的模式会记住，先转到列表循环
        for _ in 0..<3 where button.label != order[0] { button.tap() }
        XCTAssertEqual(button.label, order[0])
        for name in order.dropFirst() + [order[0]] {
            button.tap()
            // 提示只停 1.5 秒，先看提示再看按钮
            let toast = app.staticTexts["toast"]
            XCTAssertTrue(toast.waitForExistence(timeout: 1) && toast.label == name, "应弹出「\(name)」提示，实际是「\(toast.label)」")
            if name == "随机播放" {
                attach("mode-shuffle")
            }
            XCTAssertTrue(wait(button, label: name), "应切到「\(name)」，实际是「\(button.label)」")
        }
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["toast"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 4), .completed, "提示应自己消失")
        attach("mode-bottom")
        app.buttons["播放队列"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3), "应打开播放队列")
    }

    /// 搜索：拼音首字母、点歌手标签
    func testSearch() {
        app.tabBars.buttons["搜索"].tap()
        let chip = app.buttons["周杰伦"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "没输入时应显示歌手标签")
        chip.tap()
        let jay = app.collectionViews.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "周杰伦 · "))
        XCTAssertTrue(jay.firstMatch.waitForExistence(timeout: 3), "点标签后应搜出周杰伦的歌")
        let field = app.searchFields.firstMatch
        field.tap()
        // 光标应在末尾：直接删一个字应剩「周杰」
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "周杰")
        field.buttons.firstMatch.tap()
        field.typeText("qt")
        XCTAssertTrue(row("晴天").waitForExistence(timeout: 3), "拼音首字母 qt 应搜出「晴天」")
        attach("search")
    }

    /// 新建歌单并加歌
    func testPlaylist() {
        let (cell, title) = firstSong()
        cell.press(forDuration: 1)
        app.buttons["加入歌单…"].tap()
        app.buttons["新建歌单"].tap()
        app.textFields["歌单名称"].typeText("测试歌单")
        app.buttons["创建"].tap()
        app.tabBars.buttons["歌单"].tap()
        XCTAssertTrue(app.staticTexts["测试歌单"].waitForExistence(timeout: 3))
        app.staticTexts["测试歌单"].tap()
        XCTAssertTrue(row(title).waitForExistence(timeout: 3), "歌单里应有「\(title)」")
        attach("playlist")
        // 清理：删掉这个歌单
        app.buttons["更多"].tap()
        app.buttons["删除歌单"].tap()
        app.buttons["删除歌单"].firstMatch.tap()
    }

    /// 桌面歌词：歌曲页齿轮进设置，打开开关后不马上弹出；退到后台时浮出歌词长条，回到 App 收起，开关一直开着。
    /// 第一轮在桌面上点长条的关闭：长条收起、歌照样放；第二轮退到后台长条还会出来。最后关掉
    func testDesktopLyrics() {
        let (cell, _) = firstSong()
        cell.tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].buttons["暂停"].waitForExistence(timeout: 5))
        app.buttons["设置"].tap()
        let toggle = app.switches["desktopLyrics"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "设置里应有桌面歌词开关")
        XCTAssertTrue(app.switches["lockScreenLyrics"].exists)
        XCTAssertFalse(app.buttons["完成"].exists, "设置页不要完成按钮")
        if toggle.value as? String == "1" {
            toggle.switches.firstMatch.tap()
        }
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for round in 1...2 {
            XCUIDevice.shared.press(.home)
            sleep(3)
            let shot = XCTAttachment(screenshot: springboard.screenshot())
            shot.name = "desktop-lyrics-home-\(round)"
            shot.lifetime = .keepAlways
            add(shot)
            if round == 1 {
                // 长条左上角的关闭
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.047, dy: 0.0715)).tap()
                sleep(2)
                let closed = XCTAttachment(screenshot: springboard.screenshot())
                closed.name = "desktop-lyrics-closed"
                closed.lifetime = .keepAlways
                add(closed)
            }
            app.activate()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            sleep(1)
            attach("desktop-lyrics-back-\(round)")
            XCTAssertEqual(toggle.value as? String, "1", "回到 App 后开关应还开着")
        }
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.otherElements["miniPlayer"].buttons["暂停"].waitForExistence(timeout: 5), "关掉长条后歌应还在放")
    }

    /// 曲库三个 Tab：底部迷你播放条不挡住列表最后一行；歌曲、歌手右边首字母索引能跳；专辑最后一格是「单曲」
    func testLibraryLayout() {
        let (cell, _) = firstSong()
        cell.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        // 歌曲：点索引最后一个字母，再滚到底，最后一行「N 首歌曲」要在迷你条上面
        let index = app.descendants(matching: .any)["sectionIndex"].firstMatch
        XCTAssertTrue(index.waitForExistence(timeout: 3), "歌曲列表右边应有首字母索引")
        let letters = index.staticTexts
        print("[YT] 歌曲索引 \(letters.allElementsBoundByIndex.map(\.label))")
        letters.element(boundBy: letters.count - 1).tap()
        sleep(1)
        attach("songs-index-last")
        let count = app.staticTexts["songCount"]
        for _ in 0..<6 where !count.isHittable { app.collectionViews.firstMatch.swipeUp(velocity: .fast) }
        sleep(1)
        XCTAssertTrue(count.exists)
        print("[YT] 最后一行 \(count.frame) 迷你条 \(mini.frame)")
        XCTAssertLessThanOrEqual(count.frame.maxY, mini.frame.minY + 1, "最后一行不应被迷你条挡住")
        attach("songs-bottom")
        // 歌手：按住索引从上往下划，松手后列表停在后面的字母
        app.tabBars.buttons["歌手"].tap()
        XCTAssertTrue(index.waitForExistence(timeout: 3), "歌手列表右边应有首字母索引")
        let first = index.staticTexts.element(boundBy: 0), last = index.staticTexts.element(boundBy: index.staticTexts.count - 1)
        first.press(forDuration: 0.1, thenDragTo: last)
        sleep(1)
        attach("artists-index")
        // 专辑：滚到底最后一格是「单曲」，点进去是单曲列表
        app.tabBars.buttons["专辑"].tap()
        let singles = app.buttons["singles"]
        for _ in 0..<15 where !singles.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        XCTAssertTrue(singles.exists, "专辑最后应有「单曲」")
        // 中心露出来时下沿可能还在迷你条后面，再划两下到底
        for _ in 0..<2 { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        sleep(1)
        print("[YT] 单曲格 \(singles.frame) 迷你条 \(mini.frame)")
        XCTAssertLessThanOrEqual(singles.frame.maxY, mini.frame.minY + 1, "单曲格不应被迷你条挡住")
        attach("albums-bottom")
        singles.tap()
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "单曲")).firstMatch.waitForExistence(timeout: 3), "应打开单曲列表")
        attach("singles")
    }

    /// 在线整理专辑：设置里点按钮，等查完，专辑页「单曲」变少。会真的改曲库里的专辑（设置里可以还原）
    func testOrganizeAlbums() {
        app.tabBars.buttons["专辑"].tap()
        let singles = app.buttons["singles"]
        for _ in 0..<15 where !singles.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        print("[YT] 整理前 \(singles.label)")
        app.tabBars.buttons["歌曲"].tap()
        app.buttons["设置"].tap()
        let start = app.buttons["organizeAlbums"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "设置里应有在线整理专辑")
        // 上次整理过就先还原，从头查一遍
        let restore = app.buttons["还原专辑信息"]
        if restore.isEnabled {
            restore.tap()
            sleep(1)
        }
        start.tap()
        let progress = app.descendants(matching: .any)["albumProgress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "应显示整理进度")
        attach("organize-progress")
        XCTAssertTrue(progress.waitForNonExistence(timeout: 1500), "应查完")
        attach("organize-done")
        app.swipeDown(velocity: .fast)
        app.tabBars.buttons["专辑"].tap()
        sleep(1)
        attach("albums-after")
        for _ in 0..<20 where !singles.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        print("[YT] 整理后 \(singles.label)")
        attach("albums-after-bottom")
    }

    func testFindCovers() {
        attach("songs-before")
        app.buttons["设置"].tap()
        let start = app.buttons["findCovers"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5), "设置里应有在线补封面")
        start.tap()
        let progress = app.descendants(matching: .any)["coverProgress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "应显示补封面进度")
        sleep(20)
        attach("covers-progress")
        XCTAssertTrue(progress.waitForNonExistence(timeout: 2400), "应查完")
        attach("covers-done")
        app.swipeDown(velocity: .fast)
        sleep(1)
        attach("songs-after")
        app.tabBars.buttons["专辑"].tap()
        sleep(1)
        attach("albums-covers")
        let singles = app.buttons["singles"]
        for _ in 0..<20 where !singles.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .fast) }
        singles.tap()
        sleep(1)
        attach("singles-covers")
    }

    // MARK: - 工具

    /// 歌曲列表里的那一行（迷你播放条里也有同名文字，要区分开）
    /// 律动场景：挨个换主题，每个主题拍前奏（小狗的家）、中间（卡片和架子）、唱完（小猫的家）三张，最后换回奶油拼板
    func testRhythmThemes() {
        app.tabBars.buttons["搜索"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("起风了")
        let hit = row("起风了")
        XCTAssertTrue(hit.waitForExistence(timeout: 3))
        hit.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        let rhythm = app.descendants(matching: .any)["rhythm"].firstMatch
        if rhythm.waitForExistence(timeout: 2) {
            exitRhythm(rhythm)
        }
        XCTAssertFalse(app.buttons["rhythmTheme"].exists, "场景按钮只在律动模式里有")
        app.buttons["律动模式"].tap()
        XCTAssertTrue(rhythm.waitForExistence(timeout: 3), "应显示律动画面")
        let slider = app.otherElements["播放进度"]
        let button = app.buttons["rhythmTheme"]
        for id in ["starry", "sakura", "snow", "ocean", "neon", "autumn", "cream"] {
            if !button.exists {
                rhythm.tap()
            }
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.tap()
            let item = app.buttons["theme-\(id)"]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "场景面板里应有 \(id)")
            item.tap()
            XCTAssertTrue(item.isSelected, "点过的场景应选中")
            if id == "starry" {
                attach("theme-sheet")
            }
            // 点面板上方露出来的律动画面关掉面板；往下拖有时拖过头，把播放页也一起拖下去
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            XCTAssertTrue(item.waitForNonExistence(timeout: 3), "场景面板应关掉")
            for (shot, at) in [("intro", 0.0), ("mid", 0.4), ("end", 0.96)] {
                if !app.buttons["playPause"].exists {
                    rhythm.tap()
                }
                XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 3))
                drag(slider, to: at)
                sleep(3)
                attach("theme-\(id)-\(shot)")
            }
            // 拍完结尾拉回开头，免得接下来换场景时歌放完、播放页自己收起
            drag(slider, to: 0)
        }
        exitRhythm(rhythm)
    }

    /// 列表里的一首歌：只找带「歌手 · 专辑」那行字的歌曲行（搜索结果里专辑排在前面，也叫这个名字）。
    /// 不用 collectionViews.firstMatch：键盘的联想栏也是 CollectionView，层级更浅，会先被找到
    private func row(_ title: String) -> XCUIElement {
        let detail = NSPredicate(format: "elementType == %d AND label CONTAINS ' · '", XCUIElement.ElementType.staticText.rawValue)
        return app.cells.containing(detail).staticTexts[title].firstMatch
    }

    /// 「歌曲」列表里的第一首：第 0 行是「播放 / 随机播放」按钮，后面夹着首字母分段的标题（只有一个字），
    /// 有歌名和「歌手 · 专辑」两行字的才是歌；歌名是这一行的第一个文字
    private func firstSong() -> (XCUIElement, String) {
        let cells = app.collectionViews.firstMatch.cells
        XCTAssertTrue(cells.element(boundBy: 1).waitForExistence(timeout: 10), "曲库里应该有歌")
        let cell = (1..<min(cells.count, 6)).map { cells.element(boundBy: $0) }.first { $0.staticTexts.count >= 2 } ?? cells.element(boundBy: 1)
        return (cell, cell.staticTexts.firstMatch.label)
    }

    /// 律动模式的控件播放中 3 秒没操作会自动收起，可能刚好在点按钮前收起，点空了反而把控件呼出来；
    /// 所以按当前状态重试：按钮不在就点画面呼出，在就点「退出律动」，直到回到封面
    private func exitRhythm(_ rhythm: XCUIElement) {
        let exit = app.buttons["退出律动"], enter = app.buttons["律动模式"]
        for _ in 0..<3 {
            if !exit.exists {
                rhythm.tap()
            }
            if exit.waitForExistence(timeout: 2) {
                exit.tap()
            }
            if enter.waitForExistence(timeout: 2) {
                return
            }
        }
        XCTFail("没能退出律动模式")
    }

    /// 按住面板里的 e 往下拖到底，关掉面板（从屏幕中间往下划会划到后面的歌词上）
    private func closeSheet(_ e: XCUIElement) {
        let start = e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)))
    }

    private func wait(_ e: XCUIElement, label: String) -> Bool {
        let p = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: e)], timeout: 4) == .completed
    }

    private func openPlayer() {
        firstSong().0.tap()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.buttons["暂停"].waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5))
        leaveRhythm()
    }

    /// 上次停在律动模式时播放页会记住，打开就是律动画面、控件可能已收起；先回到封面
    private func leaveRhythm() {
        let rhythm = app.descendants(matching: .any)["rhythm"].firstMatch
        if rhythm.waitForExistence(timeout: 2) {
            exitRhythm(rhythm)
        }
    }

    private func drag(_ slider: XCUIElement, to fraction: CGFloat) {
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// 无障碍值形如「1:23，共 3:20」
    private func seconds(_ slider: XCUIElement) -> Double {
        parse((slider.value as? String ?? "").components(separatedBy: "，")[0])
    }

    private func total(_ slider: XCUIElement) -> Double {
        parse((slider.value as? String ?? "").components(separatedBy: "共 ").last ?? "")
    }

    private func parse(_ s: String) -> Double {
        s.trimmingCharacters(in: .whitespaces).split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
