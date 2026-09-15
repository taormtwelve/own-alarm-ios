import Foundation

/// The languages the app speaks: English, and Thai.
///
/// Every line the app shows is written in English in the code and passed through the
/// chosen language — `language("Save")` — which gives the Thai for it, or the English
/// itself when there is no Thai, so a missing line shows in English rather than not
/// at all. Numbers and names go in through `{0}`, `{1}`, so each language can put them
/// where its grammar wants them.
///
/// Plain Foundation: the model tests check it anywhere, and the widget extension
/// compiles this file too.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case thai = "th"

    var id: String { rawValue }

    /// Each language names itself, so it can be found by someone who reads only it.
    var label: String {
        switch self {
        case .english: return "English"
        case .thai: return "ไทย"
        }
    }

    /// The app's language on first launch: Thai when the phone is set to Thai, English
    /// for any other language.
    static func preferred(from languages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = languages.first, code(of: first) == AppLanguage.thai.rawValue else {
            return .english
        }
        return .thai
    }

    /// "th" from "th-TH", "th_TH" or "th_TH@calendar=buddhist".
    static func code(of identifier: String) -> String {
        String(identifier.prefix { $0 != "-" && $0 != "_" && $0 != "@" }).lowercased()
    }

    // MARK: Text

    /// `english` in this language, with `{0}`, `{1}`… replaced by `arguments`.
    func callAsFunction(_ english: String, _ arguments: Any...) -> String {
        let template = self == .thai ? (Self.thaiText[english] ?? english) : english
        return Self.fill(template, with: arguments.map { "\($0)" })
    }

    /// The text either side of the `{0}` in a line — for a line built around a live
    /// view, such as a running countdown, that cannot become part of a string.
    func around(_ english: String) -> (before: String, after: String) {
        let text = callAsFunction(english)
        guard let marker = text.range(of: "{0}") else { return (text, "") }
        return (String(text[..<marker.lowerBound]), String(text[marker.upperBound...]))
    }

    /// Puts `arguments` in place of `{0}`, `{1}`… in one pass, so an argument that
    /// happens to contain "{1}" — a task's name, say — is left as it is.
    static func fill(_ template: String, with arguments: [String]) -> String {
        guard !arguments.isEmpty else { return template }
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result.append(contentsOf: rest[..<open])
            let inside = rest[rest.index(after: open)...]
            if let close = inside.firstIndex(of: "}"),
               let index = Int(inside[..<close]), arguments.indices.contains(index) {
                result.append(contentsOf: arguments[index])
                rest = inside[inside.index(after: close)...]
            } else {
                result.append("{")
                rest = inside
            }
        }
        result.append(contentsOf: rest)
        return result
    }

    // MARK: Dates and times

    /// The locale to write times and weekday names in: the phone's own when it is set
    /// to this language, keeping its regional habits, otherwise the language's own.
    func locale(from device: Locale = .current) -> Locale {
        Self.code(of: device.identifier) == rawValue ? device : Locale(identifier: standardLocale)
    }

    private var standardLocale: String {
        switch self {
        case .english: return "en_US"
        case .thai: return "th_TH"
        }
    }

    /// The phone's calendar, naming its weekdays in this language.
    func calendar(from device: Calendar = .current) -> Calendar {
        var calendar = device
        calendar.locale = locale(from: device.locale ?? .current)
        return calendar
    }

    // MARK: Thai

    /// Thai for every line the app shows, keyed by its English.
    static let thaiText: [String: String] = Dictionary(thaiLines, uniquingKeysWith: { first, _ in first })

    /// Pairs rather than a dictionary literal: a line entered twice there would crash
    /// the app at launch. A model test checks there are no repeats.
    static let thaiLines: [(String, String)] = [
        // Tabs and the alarm list
        ("Alarms", "นาฬิกาปลุก"),
        ("Sounds", "เสียง"),
        ("Settings", "การตั้งค่า"),
        ("Alarm", "นาฬิกาปลุก"),
        ("New alarm", "นาฬิกาปลุกใหม่"),
        ("{0} alarm", "นาฬิกาปลุก {0}"),
        ("Delete", "ลบ"),
        ("No alarms yet", "ยังไม่มีนาฬิกาปลุก"),
        ("Every alarm you add keeps its own volume, so a medication reminder can stay quiet while a wake-up is loud.",
         "นาฬิกาปลุกทุกรายการที่คุณเพิ่มมีระดับเสียงของตัวเอง เตือนกินยาจึงดังเบาๆ ได้ ขณะที่ปลุกตื่นนอนดังได้เต็มที่"),
        ("Add an alarm", "เพิ่มนาฬิกาปลุก"),

        // Volume and the test ring
        ("Volume", "ระดับเสียง"),
        ("{0} percent", "{0} เปอร์เซ็นต์"),
        ("Alarm volume", "ระดับเสียงปลุก"),
        ("Test real alarm at {0}%", "ทดสอบปลุกจริงที่ {0}%"),
        ("Cancel test", "ยกเลิกการทดสอบ"),
        ("Stop test", "หยุดทดสอบ"),
        ("Rings in {0} · lock the phone to hear it as the Lock Screen alarm",
         "ดังในอีก {0} · ล็อกโทรศัพท์เพื่อฟังแบบการปลุกบนหน้าจอล็อก"),
        ("Nothing can ring yet — allow Alarms or Notifications for OwnAlarm in Settings.",
         "ยังไม่มีอะไรดังได้ — อนุญาตนาฬิกาปลุกหรือการแจ้งเตือนให้ OwnAlarm ในการตั้งค่า"),
        ("Test · {0}", "ทดสอบ · {0}"),

        // Editing an alarm
        ("Cancel", "ยกเลิก"),
        ("Save", "บันทึก"),
        ("Alarm time", "เวลาปลุก"),
        ("Task", "งาน"),
        ("What is this alarm for?", "ปลุกเพื่ออะไร"),
        ("Repeat", "ทำซ้ำ"),
        ("Sound", "เสียง"),
        ("Volume for this task", "ระดับเสียงของงานนี้"),
        ("The maximum volume depends on your Ringer & Alerts volume — adjust it in Settings › Sounds & Haptics.",
         "ระดับเสียงสูงสุดขึ้นอยู่กับระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ — สามารถปรับได้ที่ การตั้งค่า › เสียงและการสั่น"),
        ("Vibrate", "สั่น"),
        ("Buzzes while it rings · on the Lock Screen, iOS's Haptics setting decides",
         "สั่นขณะปลุก · บนหน้าจอล็อก ขึ้นอยู่กับการตั้งค่าการสั่นของ iOS"),
        ("Override Silent & Focus", "ดังผ่านโหมดเงียบและโฟกัส"),
        ("Rings even when the phone is muted", "ดังแม้โทรศัพท์ปิดเสียงอยู่"),
        ("Snooze", "เลื่อนปลุก"),
        ("Snooze length", "ระยะเลื่อนปลุก"),
        ("{0} min", "{0} นาที"),
        ("Delete alarm", "ลบนาฬิกาปลุก"),

        // Repeat days
        ("Once", "ครั้งเดียว"),
        ("Every day", "ทุกวัน"),
        ("Mon – Fri", "จันทร์ – ศุกร์"),
        ("Weekends", "สุดสัปดาห์"),

        // Ringing
        ("Alarm ringing", "นาฬิกากำลังปลุก"),
        ("{0}, at full task volume", "{0} ที่ระดับเสียงเต็มของงาน"),
        ("Snooze {0} min", "เลื่อนปลุก {0} นาที"),
        ("Slide to stop", "เลื่อนเพื่อหยุด"),
        ("Stop alarm", "หยุดปลุก"),
        ("Stop", "หยุด"),
        ("Ringing", "กำลังปลุก"),

        // Snoozed
        ("Alarm snoozed", "เลื่อนปลุกแล้ว"),
        ("{0} · snoozed", "{0} · เลื่อนปลุกแล้ว"),
        ("Rings again at {0} · in {1} min", "ปลุกอีกครั้งเวลา {0} · อีก {1} นาที"),
        ("Snoozed", "เลื่อนปลุกอยู่"),
        ("Snoozed — rings again when the timer ends", "เลื่อนปลุกอยู่ — จะปลุกอีกครั้งเมื่อหมดเวลา"),
        ("Pause", "หยุดพัก"),
        ("Paused", "หยุดพักอยู่"),
        ("Resume", "ทำต่อ"),
        ("in {0}m", "อีก {0} นาที"),
        ("in {0}h", "อีก {0} ชม."),
        ("in {0}h {1}m", "อีก {0} ชม. {1} นาที"),

        // Settings
        ("Clock", "นาฬิกา"),
        ("Time format", "รูปแบบเวลา"),
        ("24-hour", "24 ชั่วโมง"),
        ("AM / PM", "12 ชั่วโมง"),
        ("Match device", "ตามเครื่อง"),
        ("When an alarm rings", "เมื่อนาฬิกาปลุกดัง"),
        ("Show on Lock Screen", "แสดงบนหน้าจอล็อก"),
        ("Off, the alarm only takes over inside the app", "หากปิด การปลุกจะแสดงเฉพาะในแอป"),
        ("Applied to new alarms", "ใช้กับนาฬิกาปลุกที่สร้างใหม่"),
        ("Alarms permission", "สิทธิ์นาฬิกาปลุก"),
        ("Critical Alerts permission", "สิทธิ์การแจ้งเตือนสำคัญ"),
        ("Allowed", "อนุญาตแล้ว"),
        ("Not allowed", "ไม่ได้อนุญาต"),
        ("Checking…", "กำลังตรวจสอบ…"),
        ("What lets an alarm ring at its own volume through Silent",
         "สิ่งที่ทำให้นาฬิกาปลุกดังตามระดับของตัวเองผ่านโหมดเงียบ"),
        ("Without it, alarms follow the ringer and the mute switch",
         "หากไม่มี นาฬิกาปลุกจะดังตามระดับเสียงเรียกเข้าและสวิตช์ปิดเสียง"),
        ("Appearance", "ลักษณะที่ปรากฏ"),
        ("Light", "สว่าง"),
        ("Dark", "มืด"),
        ("Auto", "อัตโนมัติ"),
        ("Language", "ภาษา"),

        // Sounds
        ("Alarm tones", "เสียงปลุก"),
        ("Sound & loudness", "เสียงและความดัง"),
        ("Done", "เสร็จสิ้น"),
        ("Music or Files", "เพลงหรือไฟล์"),
        ("Only the first {0} seconds will ring", "จะดังเพียง {0} วินาทีแรก"),
        ("OK", "ตกลง"),
        ("{0} is longer than iOS allows for an alarm sound. It plays from the start and stops at {1} seconds.",
         "{0} ยาวเกินกว่าที่ iOS อนุญาตสำหรับเสียงปลุก จะเล่นตั้งแต่ต้นและหยุดที่ {1} วินาที"),
        ("This song", "เพลงนี้"),
        ("Yours", "ของคุณ"),
        ("Yours · first {0} s rings", "ของคุณ · ดังเพียง {0} วินาทีแรก"),
        ("All tones", "เสียงทั้งหมด"),
        ("Try it for real", "ลองฟังของจริง"),
        ("Tap a tone below to hear it · set a level and it rings in {0} s as a real alarm. 100% is your Ringer & Alerts volume — raise it in Settings › Sounds & Haptics if you want louder.",
         "แตะเสียงด้านล่างเพื่อฟัง · ตั้งระดับแล้วจะดังเป็นการปลุกจริงในอีก {0} วินาที 100% คือระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ — เพิ่มได้ที่ การตั้งค่า › เสียงและการสั่น หากต้องการให้ดังขึ้น"),
        ("Test level", "ระดับทดสอบ"),
        ("Sound test", "ทดสอบเสียง"),
        ("{0} · not used yet", "{0} · ยังไม่ได้ใช้"),
        ("{0} · used by 1 alarm", "{0} · ใช้กับนาฬิกาปลุก 1 รายการ"),
        ("{0} · used by {1} alarms", "{0} · ใช้กับนาฬิกาปลุก {1} รายการ"),
        ("Recording loudness {0} of 3", "ความดังของไฟล์เสียง {0} จาก 3"),

        // The bundled tones
        ("Siren", "ไซเรน"),
        ("Harsh · peaks fast", "แหลม · ดังขึ้นเร็ว"),
        ("Marimba", "มาริมบา"),
        ("Warm · even", "นุ่ม · สม่ำเสมอ"),
        ("Soft bell", "ระฆังเบา"),
        ("Quiet · long decay", "เบา · ค่อยๆ จางยาว"),
        ("Whisper", "กระซิบ"),
        ("Barely there · for night tasks", "แผ่วเบา · สำหรับงานกลางคืน"),
    ]
}
