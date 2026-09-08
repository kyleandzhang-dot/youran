import onnxruntime as ort

print("onnxruntime version:", ort.__version__)

for level_name in ["ORT_DISABLE_ALL", "ORT_ENABLE_BASIC", "ORT_ENABLE_EXTENDED"]:
    so = ort.SessionOptions()
    so.graph_optimization_level = getattr(ort.GraphOptimizationLevel, level_name)
    try:
        sess = ort.InferenceSession(
            "assets/models/model_fp16.onnx",
            sess_options=so,
            providers=["CPUExecutionProvider"],
        )
        print(level_name, "-> OK", [i.name for i in sess.get_inputs()])
    except Exception as e:
        print(level_name, "-> FAILED:", str(e).splitlines()[0])