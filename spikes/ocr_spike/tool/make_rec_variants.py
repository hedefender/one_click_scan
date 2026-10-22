"""Derives a recognition-model variant from the PP-OCRv5 ONNX files that
tool/fetch_assets.sh downloads (same weights, same Apache-2.0 licence):

  rec_<k>_am.onnx   original graph + ArgMax/ReduceMax after the Softmax, so the
                    model returns [B,T] indices and [B,T] probabilities instead
                    of [B,T,C] probabilities (far less data crosses the plugin
                    channel; greedy CTC decoding gives the same text).

Needs `pip install onnx` (Python with wheels, e.g. 3.12).
Run from spikes/ocr_spike: python tool/make_rec_variants.py
"""
import os

import onnx
from onnx import TensorProto, helper

MODELS = os.path.join(os.path.dirname(__file__), '..', 'assets', 'models')


def add_argmax(model):
    g = model.graph
    probs = g.output[0].name
    del g.output[:]
    g.node.extend([
        helper.make_node('ArgMax', [probs], ['idx'], axis=2, keepdims=0),
        helper.make_node('ReduceMax', [probs], ['prob'], axes=[2], keepdims=0),
    ])
    g.output.extend([
        helper.make_tensor_value_info('idx', TensorProto.INT64, ['b', 't']),
        helper.make_tensor_value_info('prob', TensorProto.FLOAT, ['b', 't']),
    ])
    onnx.checker.check_model(model)
    return model


for key in ['greek', 'latin', 'eslav']:
    src = os.path.join(MODELS, f'rec_{key}.onnx')
    am = add_argmax(onnx.load(src))
    onnx.save(am, os.path.join(MODELS, f'rec_{key}_am.onnx'))
    print(key, 'ok')
