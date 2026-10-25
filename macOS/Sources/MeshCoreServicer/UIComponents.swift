import SwiftUI
import MeshCoreKit

// Shared native surfaces; all metrics are supplied by the application model.
enum MeshTheme {
    static let accent = Color(nsColor:NSColor(name:nil) { appearance in
        if appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua { return NSColor(red:0.35,green:0.83,blue:0.76,alpha:1) }
        return NSColor(red:0.02,green:0.43,blue:0.39,alpha:1)
    })
    static let canvas = Color(nsColor:.windowBackgroundColor)
    static let surface = Color(nsColor:.controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let columns = [GridItem(.adaptive(minimum:170),spacing:12)]
}
struct Panel<Content: View>: View {
    var title: String
    var symbol: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:symbol).foregroundStyle(MeshTheme.accent).font(.system(size:15,weight:.semibold)).frame(width:20,height:20)
                VStack(alignment:.leading,spacing:3) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength:0)
            }
            content
        }
        .padding(20).frame(maxWidth:.infinity,alignment:.leading)
        .background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:14))
        .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(MeshTheme.border))
    }
}
struct StatusPill: View {
    var text: String
    var symbol: String = "circle.fill"
    var color: Color = .secondary
    var body: some View {
        Label(text,systemImage:symbol).font(.system(size:11,weight:.medium))
            .padding(.horizontal,9).padding(.vertical,5)
            .foregroundStyle(color).background(color.opacity(0.10),in:Capsule())
            .fixedSize(horizontal:true,vertical:false)
    }
}
struct MessageBanner: View {
    var title: String
    var message: String? = nil
    var symbol: String = "info.circle.fill"
    var color: Color = .teal
    var dismiss: (() -> Void)? = nil
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            Image(systemName:symbol).foregroundStyle(color).font(.system(size:15))
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.callout.weight(.medium))
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer(minLength:0)
            if let dismiss { Button(action:dismiss) { Image(systemName:"xmark").font(.caption) }.buttonStyle(.plain).help("Zavřít oznámení") }
        }.padding(13).frame(maxWidth:.infinity,alignment:.leading)
            .background(color.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(color.opacity(0.15)))
    }
}
struct PageHeading<Actions: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment:.center,spacing:20) {
            VStack(alignment:.leading,spacing:7) {
                Text(eyebrow.uppercased()).font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.6).foregroundStyle(MeshTheme.accent)
                Text(title).font(.system(size:27,weight:.bold,design:.rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength:8)
            actions
        }.padding(.bottom,4)
    }
}
struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName:symbol).foregroundStyle(MeshTheme.accent) }
            Text(value).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:28,alignment:.top) }
        }.padding(17).frame(maxWidth:.infinity,alignment:.leading)
            .background(MeshTheme.surface,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeshTheme.border))
    }
}
struct EmptyWorkspace: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:34,weight:.light)).foregroundStyle(MeshTheme.accent)
                .frame(width:76,height:76).background(MeshTheme.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:410)
        }.padding(36).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
struct KeyLabel: View {
    var key: String
    @State private var copied = false
    var body: some View {
        HStack(alignment:.top,spacing:8) {
            Text(key).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(nil).fixedSize(horizontal:false,vertical:true)
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(key,forType:.string); copied = true } label: { Image(systemName:copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.borderless).help(copied ? "Klíč zkopírován" : "Zkopírovat veřejný klíč")
                .accessibilityLabel("Zkopírovat veřejný klíč")
        }.onChange(of:key) { _,_ in copied = false }
    }
}
func nodeSymbol(_ kind: UInt8) -> String { [1:"person.wave.2",2:"antenna.radiowaves.left.and.right",3:"server.rack",4:"sensor"][kind] ?? "network" }
func nodeColor(_ kind: UInt8) -> Color { [1:Color.blue,2:Color.teal,3:Color.purple,4:Color.orange][kind] ?? .secondary }
struct NodeAvatar: View {
    var kind: UInt8
    var size: CGFloat = 40
    var body: some View {
        Image(systemName:nodeSymbol(kind)).font(.system(size:size*0.42,weight:.medium))
            .foregroundStyle(nodeColor(kind)).frame(width:size,height:size)
            .background(nodeColor(kind).opacity(0.10),in:RoundedRectangle(cornerRadius:size*0.28))
    }
}
struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack(alignment:.firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(minLength:16); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).monospacedDigit() }.font(.callout).padding(.vertical,3)
    }
}
struct WorkspaceScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) { content }.padding(28).frame(maxWidth:1280).frame(maxWidth:.infinity,alignment:.topLeading) }
    }
}
