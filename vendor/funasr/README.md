# FunASR 本地运行时

将官方 `llama-funasr-sensevoice` 放在此目录，供开发构建嵌入：

```bash
# 从项目根目录
bash script/download_funasr_runtime.sh
```

期望文件：

- `llama-funasr-sensevoice`（可执行）

GGUF 模型不提交仓库，由应用设置页下载到：

`~/Library/Application Support/SubForge/models/funasr/`

- `sensevoice-small-q8.gguf`
- `fsmn-vad.gguf`
