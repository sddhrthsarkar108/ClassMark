import SwiftUI

struct ContentView: View {
    @State private var isButtonPressed = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "graduationcap.fill")
                .imageScale(.large)
                .foregroundColor(.accentColor)
                .font(.system(size: 60))
            
            Text("ClassMark")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Classroom Management Made Easy")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Button(action: {
                // Add haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                // Toggle the button state
                isButtonPressed.toggle()
                
                print("Button tapped!")
            }) {
                Text(isButtonPressed ? "Welcome!" : "Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(minWidth: 120)
                    .padding()
                    .background(isButtonPressed ? Color.green : Color.blue)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
            
            if isButtonPressed {
                Text("Ready to manage your classroom!")
                    .foregroundColor(.green)
                    .padding()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(), value: isButtonPressed)
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 