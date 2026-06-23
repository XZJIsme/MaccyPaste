import Cocoa

class About {
  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "GitHub",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://github.com/XZJIsme/MaccyPaste", range: NSRange(location: 0, length: 6))
    return string
  }

  private var attribution: NSMutableAttributedString {
    let text = "Based on Maccy by Alexey Rodionov and contributors."
    let string = NSMutableAttributedString(
      string: text,
      attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
    )
    string.addAttribute(.link, value: "https://github.com/p0deje/Maccy", range: NSRange(location: 9, length: 5))
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(attribution)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
