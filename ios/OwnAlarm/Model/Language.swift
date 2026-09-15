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

    /// The languages the app offers on this phone: English always, Thai only when the
    /// phone lists Thai somewhere among its languages.
    static func available(in languages: [String] = Locale.preferredLanguages) -> [AppLanguage] {
        languages.contains { code(of: $0) == AppLanguage.thai.rawValue } ? [.english, .thai] : [.english]
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
        ("Every alarm you add keeps its own volume, so a medication reminder can stay quiet while your wake-up alarm is loud.",
         "นาฬิกาปลุกแต่ละรายการมีระดับเสียงของตัวเอง ให้เตือนกินยาดังเบาๆ แต่ปลุกตื่นนอนดังเต็มที่ก็ได้"),
        ("Add an alarm", "เพิ่มนาฬิกาปลุก"),

        // Volume and the test ring
        ("Volume", "ระดับเสียง"),
        ("{0} percent", "{0} เปอร์เซ็นต์"),
        ("Alarm volume", "ระดับเสียงปลุก"),
        ("Test real alarm at {0}%", "ทดลองปลุกจริงที่ {0}%"),
        ("Cancel test", "ยกเลิกการทดลอง"),
        ("Stop test", "หยุดทดลอง"),
        ("Rings in {0} · lock your phone to hear it just as it will ring",
         "จะดังในอีก {0} · ล็อกเครื่องไว้เพื่อฟังเหมือนตอนปลุกจริง"),
        ("Nothing can ring yet — allow Alarms or Notifications for OwnAlarm in Settings.",
         "ยังปลุกไม่ได้ — อนุญาตนาฬิกาปลุกหรือการแจ้งเตือนให้ OwnAlarm ในแอปการตั้งค่า"),
        ("Test · {0}", "ทดลอง · {0}"),

        // Editing an alarm
        ("Cancel", "ยกเลิก"),
        ("Save", "บันทึก"),
        ("Alarm time", "เวลาปลุก"),
        ("Task", "ชื่อการปลุก"),
        ("What is this alarm for?", "ปลุกเพื่ออะไร"),
        ("Repeat", "ทำซ้ำ"),
        ("Sound", "เสียง"),
        ("Volume for this task", "ระดับเสียงของการปลุกนี้"),
        ("The maximum volume depends on your Ringer & Alerts volume — adjust it in Settings › Sounds & Haptics.",
         "ระดับเสียงสูงสุดขึ้นอยู่กับระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ — สามารถปรับได้ที่ การตั้งค่า › เสียงและการสั่น"),
        ("Vibrate", "สั่น"),
        ("Vibrates while it rings · on the Lock Screen, your Haptics setting decides",
         "สั่นระหว่างปลุก · บนหน้าจอล็อกจะเป็นไปตามการตั้งค่าการสั่นของเครื่อง"),
        ("Override Silent & Focus", "ดังผ่านโหมดเงียบและโฟกัส"),
        ("Rings even when the phone is muted", "ดังแม้โทรศัพท์ปิดเสียงอยู่"),
        ("Snooze", "เลื่อนปลุก"),
        ("Snooze length", "เลื่อนปลุกครั้งละ"),
        ("{0} min", "{0} นาที"),
        ("Delete alarm", "ลบนาฬิกาปลุก"),

        // Repeat days
        ("Once", "ครั้งเดียว"),
        ("Every day", "ทุกวัน"),
        ("Mon – Fri", "จันทร์ – ศุกร์"),
        ("Weekends", "เสาร์ – อาทิตย์"),

        // Ringing
        ("Alarm ringing", "นาฬิกากำลังปลุก"),
        ("{0} · at this alarm's volume", "{0} · ตามระดับเสียงของการปลุกนี้"),
        ("Snooze {0} min", "เลื่อนปลุก {0} นาที"),
        ("Slide to stop", "ปัดเพื่อหยุด"),
        ("Stop alarm", "หยุดปลุก"),
        ("Stop", "หยุด"),
        ("Ringing", "กำลังปลุก"),

        // Snoozed
        ("Alarm snoozed", "เลื่อนปลุกแล้ว"),
        ("{0} · snoozed", "{0} · เลื่อนปลุกแล้ว"),
        ("Rings again at {0} · in {1} min", "ปลุกอีกครั้งเวลา {0} · อีก {1} นาที"),
        ("Snoozed", "เลื่อนปลุกแล้ว"),
        ("Snoozed — rings again when the timer ends", "เลื่อนปลุกแล้ว — จะปลุกอีกครั้งเมื่อหมดเวลา"),
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
        ("When off, alarms only show inside the app", "หากปิด การปลุกจะแสดงเฉพาะในแอป"),
        ("Applied to new alarms", "ใช้กับนาฬิกาปลุกที่สร้างใหม่"),
        ("Alarms permission", "สิทธิ์นาฬิกาปลุก"),
        ("Critical Alerts permission", "สิทธิ์การแจ้งเตือนสำคัญ"),
        ("Allowed", "อนุญาตแล้ว"),
        ("Not allowed", "ไม่ได้อนุญาต"),
        ("Checking…", "กำลังตรวจสอบ…"),
        ("Lets alarms ring at their own volume, even in Silent mode",
         "ทำให้นาฬิกาปลุกดังตามระดับที่ตั้งไว้ แม้อยู่ในโหมดเงียบ"),
        ("Without it, alarms follow your ringer volume and Silent mode",
         "หากไม่อนุญาต นาฬิกาปลุกจะดังตามระดับเสียงเรียกเข้าและโหมดเงียบ"),
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
         "{0} ยาวเกินกว่าที่ iOS ให้ใช้เป็นเสียงปลุก จะเล่นตั้งแต่ต้นและหยุดที่ {1} วินาที"),
        ("This song", "เพลงนี้"),
        ("Yours", "ของคุณ"),
        ("Yours · first {0} s rings", "ของคุณ · ดังเพียง {0} วินาทีแรก"),
        ("All tones", "เสียงทั้งหมด"),
        ("Try it for real", "ทดลองปลุกจริง"),
        ("Tap a tone below to hear it · set a level and it rings in {0} s as a real alarm. The maximum volume depends on your Ringer & Alerts volume — adjust it in Settings › Sounds & Haptics.",
         "แตะเสียงด้านล่างเพื่อฟัง · ปรับระดับเสียง แล้วทดลองปลุกในอีก {0} วินาที ระดับเสียงสูงสุดขึ้นอยู่กับระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ — สามารถปรับได้ที่ การตั้งค่า › เสียงและการสั่น"),
        ("Test level", "ระดับเสียงที่ทดลอง"),
        ("{0} · not used yet", "{0} · ยังไม่ได้ใช้"),
        ("{0} · used by 1 alarm", "{0} · ใช้กับนาฬิกาปลุก 1 รายการ"),
        ("{0} · used by {1} alarms", "{0} · ใช้กับนาฬิกาปลุก {1} รายการ"),
        ("Recording loudness {0} of 3", "ความดังของไฟล์เสียง {0} จาก 3"),

        // Membership
        ("Membership", "การเป็นสมาชิก"),
        ("Plan", "แพ็กเกจ"),
        ("Free", "ฟรี"),
        ("Member", "สมาชิก"),
        ("Up to {0} alarms", "ตั้งได้สูงสุด {0} รายการ"),
        ("Unlimited alarms", "ตั้งนาฬิกาปลุกได้ไม่จำกัด"),
        ("Become a member", "สมัครสมาชิก"),
        ("{0} a month", "เดือนละ {0}"),
        ("Loading…", "กำลังโหลด…"),
        ("Needs OwnAlarm from the App Store", "ใช้ได้กับ OwnAlarm จาก App Store เท่านั้น"),
        ("Restore purchases", "กู้คืนการซื้อ"),
        ("Manage subscription", "จัดการการสมัครสมาชิก"),
        ("Waiting for approval", "กำลังรอการอนุมัติ"),
        ("The purchase didn't go through.", "การซื้อไม่สำเร็จ"),
        ("Nothing to restore", "ไม่พบการซื้อที่จะกู้คืน"),
        ("Free plan: up to {0} alarms", "แพ็กเกจฟรีตั้งได้สูงสุด {0} รายการ"),
        ("Become a member for unlimited alarms. Every alarm you have keeps ringing.",
         "สมัครสมาชิกเพื่อตั้งนาฬิกาปลุกได้ไม่จำกัด นาฬิกาปลุกที่มีอยู่ยังดังตามปกติ"),
        ("Membership needs OwnAlarm from the App Store. Every alarm you have keeps ringing.",
         "การสมัครสมาชิกใช้ได้กับ OwnAlarm จาก App Store เท่านั้น นาฬิกาปลุกที่มีอยู่ยังดังตามปกติ"),
        ("Not now", "ไว้ทีหลัง"),

        // The bundled tones
        ("Siren", "ไซเรน"),
        ("Harsh · peaks fast", "แหลม · ดังขึ้นเร็ว"),
        ("Marimba", "มาริมบา"),
        ("Warm · even", "นุ่ม · สม่ำเสมอ"),
        ("Soft bell", "ระฆังเบา"),
        ("Quiet · long decay", "เบา · ค่อยๆ จางหาย"),
        ("Whisper", "กระซิบ"),
        ("Barely there · for night tasks", "แผ่วเบา · สำหรับการปลุกกลางคืน"),
    ]
}
