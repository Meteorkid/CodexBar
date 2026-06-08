import Foundation
import Testing
@testable import CodexBarCore

struct BedrockAWSSignerTests {
    @Test
    func `signs request deterministically for fixed date`() throws {
        var request = URLRequest(
            url: try #require(URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model")))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)

        let credentials = BedrockAWSSigner.Credentials(
            accessKeyID: "AKIATEST",
            secretAccessKey: "secret",
            sessionToken: "session-token")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        BedrockAWSSigner.sign(
            request: &request,
            credentials: credentials,
            region: "us-east-1",
            service: "bedrock",
            date: date)

        let authorization = request.value(forHTTPHeaderField: "Authorization")
        #expect(authorization?.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIATEST/") == true)
        #expect(authorization?.contains("SignedHeaders=") == true)
        #expect(request.value(forHTTPHeaderField: "X-Amz-Security-Token") == "session-token")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Date")?.hasSuffix("Z") == true)
    }
}
