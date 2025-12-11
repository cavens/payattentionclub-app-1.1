# DeviceActivityMonitorExtension Debug Steps

## Step 1 – Change the extension class

1. Open `DeviceActivityMonitorExtension.swift` (the one inside the extension target).
2. At the top, make sure you have:
   ```swift
   import DeviceActivity
   import Foundation
   import UserNotifications
   ```
3. Replace your class declaration with this minimal version:
   ```swift
   @available(iOS 16.0, *)
   class DeviceActivityMonitorExtension: DeviceActivityMonitor {
       override init() {
           super.init()
           NSLog("EXTENSION: 🚀 init")
       }
       
       override func intervalDidStart(for activity: DeviceActivityName) {
           super.intervalDidStart(for: activity)
           NSLog("EXTENSION: 🟢 intervalDidStart \(activity.rawValue)")
           
           // TEMP: visible proof-of-life via local notification
           let center = UNUserNotificationCenter.current()
           center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
               guard granted else { return }
               let content = UNMutableNotificationContent()
               content.title = "PAC Monitor started"
               content.body = "Activity: \(activity.rawValue)"
               let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
               let request = UNNotificationRequest(
                   identifier: "pac_monitor_test_interval",
                   content: content,
                   trigger: trigger
               )
               center.add(request, withCompletionHandler: nil)
           }
       }
       
       override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                            activity: DeviceActivityName) {
           super.eventDidReachThreshold(event, activity: activity)
           NSLog("EXTENSION: 🔔 eventDidReachThreshold \(event.rawValue)")
       }
   }
   ```
4. **Important**: Make sure there is no `@objc(...)` above the class anymore.

---

## Step 2 – Fix NSExtensionPrincipalClass in the extension Info.plist

1. In Xcode, select the `DeviceActivityMonitorExtension` target in the project navigator.
2. Go to the Build Settings / Info or open the `Info.plist` file for that target.
3. Under the `NSExtension` dictionary, make sure it looks like this:
   ```xml
   <key>NSExtension</key>
   <dict>
       <key>NSExtensionPointIdentifier</key>
       <string>com.apple.deviceactivity.monitor-extension</string>
       <key>NSExtensionPrincipalClass</key>
       <string>$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension</string>
   </dict>
   ```
   - If `NSExtensionPrincipalClass` is currently just `"DeviceActivityMonitorExtension"`, change it to `$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`.

---

## Step 3 – Add a tiny "debug schedule" in MonitoringManager

We want a schedule that starts in 1 minute and ends in 20 minutes, so we don't depend on midnight and weird Screen Time behavior.

In `MonitoringManager.startMonitoring(...)` (in the main app):

1. For now, ignore all your complex 140 events and use a minimal version:
   ```swift
   import DeviceActivity
   import FamilyControls
   
   func startDebugMonitoring() async {
       let center = DeviceActivityCenter()
       
       // Log the authorization status just to be sure
       let status = await AuthorizationCenter.shared.authorizationStatus
       NSLog("MARKERS MonitoringManager: FamilyControls status = \(status.rawValue)")
       
       let now = Date()
       let calendar = Calendar.current
       let startDate = calendar.date(byAdding: .minute, value: 1, to: now)!
       let endDate   = calendar.date(byAdding: .minute, value: 20, to: now)!
       
       let comps: Set<Calendar.Component> = [.hour, .minute, .second]
       let schedule = DeviceActivitySchedule(
           intervalStart: calendar.dateComponents(comps, from: startDate),
           intervalEnd:   calendar.dateComponents(comps, from: endDate),
           repeats: false
       )
       
       let activityName = DeviceActivityName("PAC.DebugActivity")
       
       do {
           try center.startMonitoring(activityName, during: schedule)
           NSLog("MARKERS MonitoringManager: ✅ started debug monitoring")
       } catch {
           NSLog("MARKERS MonitoringManager: ❌ failed debug monitoring: \(error.localizedDescription)")
       }
   }
   ```
2. Call this `startDebugMonitoring()` from somewhere obvious in the app, e.g. a debug button in a view:
   ```swift
   Button("Start Debug Monitoring") {
       Task {
           await startDebugMonitoring()
       }
   }
   ```

---

## Step 4 – Clean & reinstall

1. In Xcode: **Product → Clean Build Folder** (Shift + Cmd + K).
2. On your iPhone: long-press the app icon → **Remove App → Delete**.
3. Build & run the app again from Xcode (device plugged in).
4. Make sure you:
   - Request FamilyControls authorization somewhere in the app.
   - Go to **Settings → Screen Time → [Your App]** and make sure it's allowed to use Screen Time API.

---

## Step 5 – Run the minimal test

1. Open the app on the device.
2. Tap your **"Start Debug Monitoring"** button once.
3. Check Xcode console to see `✅ started debug monitoring` and the FamilyControls status.
4. Leave the screen on or lock/unlock normally, then:
   - Wait ~2–5 minutes (our interval starts in ~1 min, we gave it 20 min total).
5. Watch for:
   - A local notification titled **"PAC Monitor started"**.
   - (Optional) use macOS Console.app → select your iPhone → filter by `EXTENSION:` to see those NSLog lines.

**If that notification appears** → you've confirmed the extension is now loading and `intervalDidStart` is firing. 🎉

Then you can:
- Swap back in your real schedule and events.
- Remove or comment out the debug notification logic.

**If the notification still never appears** after all of this, tell me:
- What `authorizationStatus` you logged.
- Whether your `startDebugMonitoring` prints `✅ started debug monitoring`.

Then we'll know if the issue is still "extension not launched" or we're dealing with even deeper DAM weirdness.








