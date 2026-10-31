// OrangeOCRHelper: warm single-model OCR subprocess for Orange.
// Pinned llama.cpp (libllama + libmtmd), C++17, arm64. One model resident at
// a time; per-page KV/sampler state is cleared so pages never leak into each
// other. NDJSON IPC on stdin/stdout (protocolVersion 1); diagnostics on stderr
// only. The image marker comes from mtmd_default_marker() exactly once — the
// model card literal is never duplicated. Prompts are pinned per modelID.
//
// Build: scripts/build-ocr-runtime.sh (incremental, no model weights fetched).
// Bundle: Contents/Helpers/OrangeOCRHelper, ad-hoc signed before the app.

#include "arg.h"
#include "chat.h"
#include "common.h"
#include "log.h"
#include "sampling.h"
#include "mtmd.h"
#include "mtmd-helper.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr int kProtocolVersion = 1;
constexpr const char* kRuntimeRevision = "f3586e66bc916d672773d4a6505513ba91a3595c";

void logLine(const std::string& message) {
    LOG_INF("%s\n", message.c_str());
}

std::string jsonEscape(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 2);
    for (char c : value) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[7];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

void emit(const std::string& json) {
    std::cout << json << "\n" << std::flush;
}

// Minimal JSON getter: enough for our fixed command shapes.
std::string field(const std::string& line, const char* key) {
    std::string needle = std::string("\"") + key + "\"";
    auto pos = line.find(needle);
    if (pos == std::string::npos) return "";
    pos = line.find(':', pos + needle.size());
    if (pos == std::string::npos) return "";
    ++pos;
    while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t')) ++pos;
    if (pos >= line.size()) return "";
    if (line[pos] == '"') {
        ++pos;
        std::string value;
        while (pos < line.size() && line[pos] != '"') {
            if (line[pos] == '\\' && pos + 1 < line.size()) {
                ++pos;
                char esc = line[pos++];
                switch (esc) {
                    case 'n': value += '\n'; break;
                    case 'r': value += '\r'; break;
                    case 't': value += '\t'; break;
                    default: value += esc; break;
                }
            } else {
                value += line[pos++];
            }
        }
        return value;
    }
    size_t end = pos;
    while (end < line.size() && line[end] != ',' && line[end] != '}') ++end;
    std::string raw = line.substr(pos, end - pos);
    while (!raw.empty() && (raw.back() == ' ' || raw.back() == '\t')) raw.pop_back();
    return raw;
}

long long fieldInt(const std::string& line, const char* key, long long fallback) {
    std::string raw = field(line, key);
    if (raw.empty()) return fallback;
    try {
        return std::stoll(raw);
    } catch (...) {
        return fallback;
    }
}

std::string pinnedPrompt(const std::string& modelID, const std::string& mode) {
    bool document = (mode == "document");
    if (modelID == "glm-ocr") return "Text Recognition:";
    if (modelID == "paddleocr-vl-1.6") return "OCR:";
    if (modelID == "dots-ocr") return "Extract the text content from this image.";
    if (modelID == "deepseek-ocr-2") return "Free OCR.";
    if (modelID == "qwen3-vl-2b") {
        if (document) {
            return "Transcribe this document as Markdown. Preserve all visible text, reading order, headings, lists, tables and formulas. Do not translate, summarize, or invent content.";
        }
        return "Transcribe all visible text exactly. Preserve reading order and line breaks.";
    }
    if (document) {
        return "Transcribe this document as Markdown. Preserve all visible text, reading order, headings, lists, tables and formulas. Do not translate, summarize, or invent content.";
    }
    return "Transcribe all visible text exactly. Preserve reading order and line breaks.";
}

void emitError(const std::string& requestID, const std::string& code, const std::string& message) {
    std::ostringstream out;
    out << "{\"type\":\"error\",\"protocolVersion\":" << kProtocolVersion
        << ",\"requestID\":\"" << jsonEscape(requestID)
        << "\",\"code\":\"" << jsonEscape(code)
        << "\",\"message\":\"" << jsonEscape(message) << "\"}";
    emit(out.str());
}

// Split on the helper's own marker, not a model-card literal copy.
std::vector<std::string> splitMarker(const std::string& text, const std::string& marker) {
    std::vector<std::string> segments;
    size_t start = 0;
    size_t pos;
    while ((pos = text.find(marker, start)) != std::string::npos) {
        segments.push_back(text.substr(start, pos - start));
        start = pos + marker.size();
    }
    segments.push_back(text.substr(start));
    return segments;
}

struct LoadedModel {
    common_init_result_ptr llamaInit;
    llama_model* model = nullptr;
    llama_context* lctx = nullptr;
    const llama_vocab* vocab = nullptr;
    common_sampler* sampler = nullptr;
    mtmd::context_ptr vision;
    common_chat_templates_ptr templates;
    bool useJinja = false;
    std::string modelID;
    int nBatch = 512;
    int nThreads = 4;
    bool projectorCPUOnly = false;
    llama_pos nPast = 0;
};

bool endsWith(const std::string& value, const std::string& suffix) {
    return value.size() >= suffix.size() &&
           value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

int doLoad(LoadedModel& loaded, const std::string& line) {
    std::string requestID = field(line, "requestID");
    std::string modelID = field(line, "modelID");
    std::string modelPath = field(line, "modelPath");
    std::string projectorPath = field(line, "projectorPath");
    std::string compute = field(line, "compute");
    std::string quality = field(line, "quality");
    int contextTokens = (int)fieldInt(line, "contextTokens", 8192);
    int maxOutput = (int)fieldInt(line, "maxOutputTokens", 4096);
    int threads = (int)fieldInt(line, "threads", 4);
    (void)maxOutput;

    common_params params;
    params.model.path = modelPath;
    params.mmproj.path = projectorPath;
    params.n_ctx = contextTokens;
    params.n_batch = 512;
    params.n_ubatch = 128;
    params.cpuparams.n_threads = std::max(1, std::min(threads, 8));
    params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    params.sampling.temp = 0.0;  // greedy
    params.sampling.top_k = 1;

    bool wantMetal = (compute == "metal" || compute == "automatic");
    bool cpuOnly = (compute == "cpu") || !wantMetal;
    bool projectorCPU = (modelID == "deepseek-ocr-2");
    int layers = cpuOnly ? 0 : 999;

    params.n_gpu_layers = layers;
    // Projector backend: with split modeling the mmproj runs on the same
    // device grid; DeepSeek-2's projector is forced to CPU per publisher note
    // by keeping the text model CPU-resident for the vision path while the LM
    // still uses Metal through the shared backend scheduler.
    if (projectorCPU && wantMetal) {
        params.n_gpu_layers = layers;  // LM on Metal, vision embeddings decoded on CPU path
    }

    ggml_backend_load_all();
    common_init_result_ptr init = common_init_from_params(params);
    llama_model* model = init ? init->model() : nullptr;
    llama_context* lctx = init ? init->context() : nullptr;
    if (!model || !lctx) {
        emitError(requestID, "modelLoad", "Failed to load model: " + modelPath);
        return 1;
    }

    mtmd_context_params visionParams = mtmd_context_params_default();
    visionParams.use_gpu = wantMetal;
    visionParams.n_threads = params.cpuparams.n_threads;
    visionParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    // Dynamic-resolution guardrails: bounded image tokens, never forced on
    // fixed encoders. Balanced 2048 / high 4096 mirror the Swift-side caps.
    bool high = (quality == "high");
    visionParams.image_max_tokens = high ? 4096 : 2048;
    visionParams.image_min_tokens = 0;
    if (projectorCPU) {
        visionParams.use_gpu = false;  // vision encoder on CPU even when LM uses Metal
    }
    mtmd::context_ptr vision(mtmd_init_from_file(projectorPath.c_str(), model, visionParams));
    if (!vision) {
        emitError(requestID, wantMetal ? "metalInitialization" : "modelLoad",
                  "Failed to init vision context: " + projectorPath);
        return 1;
    }

    if (loaded.sampler) common_sampler_free(loaded.sampler);
    loaded = LoadedModel();
    loaded.llamaInit = std::move(init);
    loaded.model = model;
    loaded.lctx = lctx;
    loaded.vocab = llama_model_get_vocab(model);
    loaded.sampler = common_sampler_init(model, params.sampling);
    loaded.vision = std::move(vision);
    loaded.templates = common_chat_templates_init(model, "");
    loaded.modelID = modelID;
    loaded.nBatch = params.n_batch;
    loaded.nThreads = params.cpuparams.n_threads;
    loaded.projectorCPUOnly = projectorCPU;
    loaded.nPast = 0;

    std::ostringstream out;
    out << "{\"type\":\"ready\",\"protocolVersion\":" << kProtocolVersion
        << ",\"requestID\":\"" << jsonEscape(requestID) << "\"}";
    emit(out.str());
    return 0;
}

int doRecognize(LoadedModel& loaded, const std::string& line) {
    std::string requestID = field(line, "requestID");
    std::string imagePath = field(line, "imagePath");
    std::string mode = field(line, "mode");
    auto started = std::chrono::steady_clock::now();

    if (!loaded.model || !loaded.lctx || !loaded.vision || !loaded.sampler) {
        emitError(requestID, "invalidRequest", "No model loaded.");
        return 1;
    }

    mtmd_helper_init_opt opt = mtmd_helper_init_opt_default();
    auto wrapper = mtmd_helper_bitmap_init_from_file(
        loaded.vision.get(), imagePath.c_str(), false, opt);
    if (!wrapper.bitmap) {
        emitError(requestID, "decodeFailed", "Cannot decode image: " + imagePath);
        return 1;
    }
    mtmd::bitmap_ptr bitmap(wrapper.bitmap);

    // Fresh KV + sampler state per page: nothing carries across pages.
    common_sampler_reset(loaded.sampler);
    llama_memory_clear(llama_get_memory(loaded.lctx), true);
    loaded.nPast = 0;

    const std::string marker = mtmd_default_marker();  // single source of truth
    std::string prompt = pinnedPrompt(loaded.modelID, mode);

    common_chat_msg user;
    user.role = "user";
    user.content = prompt + marker;
    std::string formatted = common_chat_format_single(
        loaded.templates.get(), {}, user, true, loaded.useJinja);

    std::vector<std::string> segments = splitMarker(formatted, marker);
    const mtmd_bitmap* raw = bitmap.get();
    std::vector<const mtmd_bitmap*> bitmaps = {raw};
    if (segments.size() - 1 != bitmaps.size()) {
        emitError(requestID, "decodeFailed", "Prompt/image marker mismatch.");
        return 1;
    }
    std::vector<mtmd_input_text> texts(segments.size());
    std::vector<mtmd_input_part> parts;
    for (size_t i = 0; i < segments.size(); i++) {
        texts[i] = {segments[i].data(), segments[i].size(), false, true};
        parts.push_back({&texts[i], nullptr});
        if (i < bitmaps.size()) parts.push_back({nullptr, bitmaps[i]});
    }
    std::vector<const mtmd_input_part*> partPtrs;
    for (const auto& p : parts) partPtrs.push_back(&p);

    mtmd::input_chunks chunks(mtmd_input_chunks_init());
    int32_t res = mtmd_tokenize_from_parts(loaded.vision.get(), chunks.ptr.get(),
                                           partPtrs.data(), partPtrs.size(), true);
    if (res != 0) {
        emitError(requestID, "contextOverflow", "Prompt too large for context.");
        return 1;
    }

    mtmd::batch_ptr mbatch;
    size_t nChunks = mtmd_input_chunks_size(chunks.ptr.get());
    for (size_t i = 0; i < nChunks; i++) {
        auto chunk = mtmd_input_chunks_get(chunks.ptr.get(), i);
        auto type = mtmd_input_chunk_get_type(chunk);
        if (type == MTMD_INPUT_CHUNK_TYPE_TEXT) {
            llama_pos next = loaded.nPast;
            res = mtmd_helper_eval_chunk_single(loaded.vision.get(), loaded.lctx, chunk,
                                                loaded.nPast, 0, loaded.nBatch,
                                                i == nChunks - 1, &next);
            if (res != 0) {
                emitError(requestID, "decodeFailed", "Text eval failed.");
                return 1;
            }
            loaded.nPast = next;
        } else {
            float* embd = mbatch ? mtmd_batch_get_output_embd(mbatch.get(), chunk) : nullptr;
            if (!embd) {
                mbatch.reset(mtmd_batch_init(loaded.vision.get()));
                res = mtmd_batch_add_chunk(mbatch.get(), chunk);
                if (res != 0) {
                    emitError(requestID, "outOfMemory", "Vision batch rejected chunk.");
                    return 1;
                }
                res = mtmd_batch_encode(mbatch.get());
                if (res != 0) {
                    emitError(requestID, "outOfMemory", "Vision encode failed.");
                    return 1;
                }
                embd = mtmd_batch_get_output_embd(mbatch.get(), chunk);
            }
            if (!embd) {
                emitError(requestID, "outOfMemory", "No vision embeddings.");
                return 1;
            }
            llama_pos next = loaded.nPast;
            res = mtmd_helper_decode_image_chunk(loaded.vision.get(), loaded.lctx, chunk, embd,
                                                 loaded.nPast, 0, loaded.nBatch, &next,
                                                 nullptr, nullptr);
            if (res != 0) {
                emitError(requestID, "decodeFailed", "Image decode failed.");
                return 1;
            }
            loaded.nPast = next;
        }
    }

    std::string generated;
    std::string markdown;
    int inputTokens = (int)loaded.nPast;
    int outputTokens = 0;
    bool truncated = false;
    const int maxTokens = 4096;
    for (int i = 0; i < maxTokens; i++) {
        llama_token token = common_sampler_sample(loaded.sampler, loaded.lctx, -1);
        common_sampler_accept(loaded.sampler, token, true);
        if (llama_vocab_is_eog(loaded.vocab, token)) break;
        std::string piece = common_detokenize(loaded.lctx, {token}, true);
        generated += piece;
        outputTokens++;
        if (i == maxTokens - 1) truncated = true;
        // Greedy single-pass decode of the sampled token.
        common_batch batch(loaded.lctx);
        batch.add(token, loaded.nPast++, {0}, true);
        if (llama_process(loaded.lctx, LLAMA_PROCESS_TYPE_DECODE, batch.get())) {
            emitError(requestID, "decodeFailed", "Decode step failed.");
            return 1;
        }
    }
    if (mode == "document") markdown = generated;

    auto elapsed = std::chrono::steady_clock::now() - started;
    double seconds = std::chrono::duration<double>(elapsed).count();

    std::string compute = loaded.projectorCPUOnly ? "metalTextCPUProjector" : "metal";
    std::ostringstream out;
    out << "{\"type\":\"result\",\"protocolVersion\":" << kProtocolVersion
        << ",\"requestID\":\"" << jsonEscape(requestID) << "\""
        << ",\"text\":\"" << jsonEscape(generated) << "\"";
    if (!markdown.empty()) out << ",\"markdown\":\"" << jsonEscape(markdown) << "\"";
    out << ",\"actualCompute\":\"" << compute << "\""
        << ",\"inputTokens\":" << inputTokens
        << ",\"outputTokens\":" << outputTokens
        << ",\"durationSeconds\":" << seconds
        << ",\"truncated\":" << (truncated ? "true" : "false") << "}";
    emit(out.str());
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    common_init();
    bool capabilities = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--capabilities") == 0) capabilities = true;
    }
    if (capabilities) {
        ggml_backend_load_all();
        int gpuCount = 0;
        for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
            auto dev = ggml_backend_dev_get(i);
            if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) gpuCount++;
        }
        size_t total = 0, freeMem = 0;
        for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
            auto dev = ggml_backend_dev_get(i);
            if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) {
                ggml_backend_dev_memory(dev, &freeMem, &total);
                break;
            }
        }
        std::ostringstream out;
        out << "{\"protocolVersion\":" << kProtocolVersion
            << ",\"runtimeRevision\":\"" << kRuntimeRevision << "\""
            << ",\"cpuAvailable\":true"
            << ",\"metalAvailable\":" << (gpuCount > 0 ? "true" : "false")
            << ",\"recommendedMetalBytes\":" << total << "}";
        emit(out.str());
        return 0;
    }

    logLine("OrangeOCRHelper ready (pinned " + std::string(kRuntimeRevision) + ")");

    LoadedModel loaded;
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::string type = field(line, "type");
        std::string requestID = field(line, "requestID");
        if (type == "shutdown") break;
        if (type == "load") {
            doLoad(loaded, line);
            continue;
        }
        if (type == "recognize") {
            doRecognize(loaded, line);
            continue;
        }
        emitError(requestID, "invalidRequest", "Unknown command.");
    }
    return 0;
}
