import Foundation
import Testing
@testable import SubForge

@Test func funASRDownloadsFromModelScopeBeforeOverseasFallbacks() {
    let urls = FunASRModelDownloader.downloadURLs(
        repository: FunASRModel.sensevoiceSmallQ8.repository,
        fileName: FunASRModel.sensevoiceSmallQ8.fileName
    )

    #expect(urls.count == 3)
    #expect(urls[0].absoluteString == "https://www.modelscope.cn/models/FunAudioLLM/SenseVoiceSmall-GGUF/resolve/master/sensevoice-small-q8.gguf")
    #expect(urls[1].host == "hf-mirror.com")
    #expect(urls[2].host == "huggingface.co")
}

@Test func funASRVADUsesTheSameDomesticFirstDownloadOrder() {
    let urls = FunASRModelDownloader.downloadURLs(
        repository: FunASRModelStore.vadRepository,
        fileName: FunASRModelStore.vadFileName
    )

    #expect(urls[0].absoluteString == "https://www.modelscope.cn/models/FunAudioLLM/fsmn-vad-GGUF/resolve/master/fsmn-vad.gguf")
}
