import SwiftUI

struct CheckInView: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Text("Did you move\ntoday?")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    Haptics.impact(.medium)
                    onAnswer(true)
                } label: {
                    HStack(spacing: 12) {
                        Text("🙌")
                            .font(.title2)
                        Text("Yes, I moved")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
                    )
                }

                Button {
                    Haptics.impact(.medium)
                    onAnswer(false)
                } label: {
                    HStack(spacing: 12) {
                        Text("😴")
                            .font(.title2)
                        Text("Not today")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 48)
        }
    }
}

#Preview {
    CheckInView(onAnswer: { _ in })
}
