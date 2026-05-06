import AppKit
import Foundation

/// Provides bookmarklet scripts for easy cookie extraction from browsers.
enum CookieBookmarklet {
    /// The JavaScript code for the bookmarklet that copies cookies to clipboard.
    static let script = """
    javascript:void(function(){
      var c=document.cookie;
      if(!c){alert('No cookies found on this page. Make sure you are logged in.');return;}
      var t='COOKIES_FOR_codexbar:'+c;
      if(navigator.clipboard&&navigator.clipboard.writeText){
        navigator.clipboard.writeText(c).then(function(){
          alert('Cookies copied to clipboard!\\n\\nNow go to CodexBar Settings → Providers → [Provider] → Cookie Source → Manual → Paste');
        },function(){
          prompt('Copy these cookies:',c);
        });
      }else{
        prompt('Copy these cookies:',c);
      }
    })();
    """

    /// Generate a bookmarklet URL string.
    static var bookmarkletURL: URL? {
        URL(string: script)
    }

    /// Copy the bookmarklet script to clipboard.
    static func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(script, forType: .string)
    }

    /// Create an HTML file with instructions for installing the bookmarklet.
    static func createInstructionsHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>CodexBar Cookie Helper</title></head>
        <body style="font-family: -apple-system, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px;">
        <h1>CodexBar Cookie Helper</h1>
        <h2>Quick Setup (One-time)</h2>
        <ol>
        <li>Drag this link to your browser's bookmarks bar:<br>
        <a href="\(script)" style="display:inline-block;padding:10px 20px;background:#007AFF;color:white;text-decoration:none;border-radius:8px;margin:10px 0;font-weight:bold;">📋 Copy Cookies</a></li>
        </ol>

        <h2>Usage</h2>
        <ol>
        <li>Open the provider's website and log in:
            <ul>
            <li>Zhipu: <a href="https://open.bigmodel.cn/usercenter">open.bigmodel.cn</a></li>
            <li>Doubao: <a href="https://console.volcengine.com/ark">console.volcengine.com</a></li>
            <li>ERNIE: <a href="https://console.bce.baidu.com/qianfan">console.bce.baidu.com</a></li>
            <li>MiMo: <a href="https://platform.xiaomimimo.com/console/balance">platform.xiaomimimo.com</a></li>
            </ul>
        </li>
        <li>Click the "Copy Cookies" bookmarklet in your bookmarks bar</li>
        <li>Go to CodexBar Settings → Providers → [Provider] → Cookie Source → Manual</li>
        <li>Paste (Cmd+V) into the Cookie Header field</li>
        </ol>

        <h2>Why is this needed?</h2>
        <p>macOS security restrictions prevent apps from automatically reading browser cookies.
        This bookmarklet runs inside your browser where it has access to cookies, and copies
        them to your clipboard for easy pasting.</p>
        </body>
        </html>
        """
    }

    /// Save the instructions HTML to a temporary file and open it.
    static func openInstructions() {
        let html = createInstructionsHTML()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarCookieHelper.html")
        do {
            try html.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
        } catch {
            // Fallback: just copy the bookmarklet
            copyToClipboard()
        }
    }
}
