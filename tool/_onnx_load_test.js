/**
 * ONNX 模型实际加载测试（验证「Load Model」链路）。
 * 在 electron_server 目录下运行：
 *   ELECTRON_RUN_AS_NODE=1 node_modules/electron/dist/electron.exe ../tool/_onnx_load_test.js
 */
const path = require('path');
const fs = require('fs');

const ROOT = process.cwd();
const NM = path.join(ROOT, 'node_modules');
const ort = require(path.join(NM, 'onnxruntime-node'));

const MODELS = [
  ['ppocrv5/cls', 'onnx_models/ppocrv5/cls/cls.onnx'],
  ['ppocrv5/det', 'onnx_models/ppocrv5/det/det.onnx'],
  ['ppocrv5/rec', 'onnx_models/ppocrv5/rec/rec.onnx'],
  ['faces/faceLandMark', 'onnx_models/faces/faceLandMark/faceLandMark.onnx'],
  ['faces/insightFace', 'onnx_models/faces/insightFace/model.onnx'],
  ['places365/resnet50', 'onnx_models/places365/resnet50_places365.onnx'],
];

(async () => {
  console.log('onnxruntime-node 版本 :', ort.env && ort.env.versions ? ort.env.versions.node : '(unknown)');
  console.log('可用执行后端        :', ort.getAvailableExecutionProviders ? ort.getAvailableExecutionProviders().join(', ') : '(n/a)');
  console.log('');

  let ok = 0;
  let bad = 0;
  for (const [name, rel] of MODELS) {
    const p = path.join(ROOT, ...rel.split('/'));
    if (!fs.existsSync(p)) {
      console.log(`  FAIL  ${name}  -> 文件不存在: ${p}`);
      bad++;
      continue;
    }
    const sizeMiB = (fs.statSync(p).size / 1024 / 1024).toFixed(1);
    const t0 = Date.now();
    try {
      // 只建会话、不推理，验证模型能被解析并准备就绪
      const session = await ort.InferenceSession.create(p, { executionProviders: ['cpu'] });
      const inputs = session.inputNames.join(', ');
      const outputs = session.outputNames.join(', ');
      const dt = Date.now() - t0;
      console.log(`  ok    ${name}  (${sizeMiB} MiB, ${dt} ms)`);
      console.log(`          inputs : ${inputs}`);
      console.log(`          outputs: ${outputs}`);
      await session.release();
      ok++;
    } catch (e) {
      console.log(`  FAIL  ${name}  (${sizeMiB} MiB)  ->  ${String((e && e.message) || e).split('\n')[0]}`);
      bad++;
    }
  }
  console.log(`\n模型加载：成功 ${ok} / 失败 ${bad}`);
  process.exit(bad === 0 ? 0 : 1);
})();
