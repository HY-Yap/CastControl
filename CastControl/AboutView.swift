//
//  AboutView.swift
//  CastControl
//

import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CastControl")
                        .font(.title3.weight(.semibold))

                    Text("v0.1.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("A tiny menu bar utility for switching display modes\nand hiding desktop clutter before presenting.")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Developer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Yap Han Yang")
                    .font(.system(size: 13))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 190)
        .background(.regularMaterial)
        .background(AboutWindowConfigurator())
    }
}

private struct AboutWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
    }
}
