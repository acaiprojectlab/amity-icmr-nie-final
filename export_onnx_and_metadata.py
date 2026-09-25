"""
ONNX Model & Metadata Exporter for Edge Offline Inference
Exports PyTorch GRTT models to .onnx and dumps pre-computed JSON assets for Flutter/mobile.
"""

import json
import os
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import onnx
import onnxruntime as ort

from model_handler import (
    VirusPredictor,
    VIRUS_MAPPING,
    OTHER_VIRUS_MAPPING,
    SYNDROME_EXCLUDED_VIRUSES,
    ALL_SYMPTOMS,
    _try_read_csv,
    _build_excluded_index_set,
    _filter_topk,
)
from pathogen_list import DR_SUSPECTED_PATHOGENS

SYMPTOM_DISPLAY_NAMES = {
    'HEADACHE': 'Headache',
    'IRRITABILITY': 'Irritability',
    'ALTEREDSENSORIUM': 'Altered Sensorium',
    'SOMNOLENCE': 'Somnolence',
    'NECKRIGIDITY': 'Neck Rigidity',
    'SEIZURES': 'Seizures',
    'DIARRHEA': 'Diarrhea',
    'DYSENTERY': 'Dysentery',
    'NAUSEA': 'Nausea',
    'VOMITING': 'Vomiting',
    'ABDOMINALPAIN': 'Abdominal Pain',
    'MALAISE': 'Malaise',
    'MYALGIA': 'Myalgia',
    'ARTHRALGIA': 'Arthralgia',
    'CHILLS': 'Chills',
    'RIGORS': 'Rigors',
    'FEVER': 'Fever',
    'BREATHLESSNESS': 'Breathlessness',
    'COUGH': 'Cough',
    'RHINORRHEA': 'Rhinorrhea',
    'SORETHROAT': 'Sore Throat',
    'BULLAE': 'Bullae',
    'PAPULARRASH': 'Papular Rash',
    'PUSTULARRASH': 'Pustular Rash',
    'MUSCULARRASH': 'Muscular Rash',
    'MACULOPAPULARRASH': 'Maculopapular Rash',
    'ESCHAR': 'Eschar',
    'DARKURINE': 'Dark Urine',
    'HEPATOMEGALY': 'Hepatomegaly',
    'JAUNDICE': 'Jaundice',
    'REDEYE': 'Red Eye',
    'DISCHARGEEYES': 'Discharge Eyes',
    'CRUSHINGEYES': 'Crushing Eyes',
    'SWELLINGEYES': 'Swelling Eyes',
    'RETROORBITALPAIN': 'Retro-orbital Pain',
}

OUTPUT_DIR = Path("mobile_assets")
MODELS_DIR = OUTPUT_DIR / "models"
DATA_DIR = OUTPUT_DIR / "data"

MODELS_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)


def export_model_to_onnx(model, dummy_inputs, output_path, model_name="GRTT"):
    """Export a PyTorch GRTT model to ONNX format."""
    model.eval()
    xb, xc, xcat = dummy_inputs

    input_names = ["xb", "xc", "xcat"]
    output_names = ["logits"]
    dynamic_axes = {
        "xb": {0: "batch_size"},
        "xc": {0: "batch_size"},
        "xcat": {0: "batch_size"},
        "logits": {0: "batch_size"},
    }

    print(f"Exporting {model_name} to {output_path}...")
    torch.onnx.export(
        model,
        (xb, xc, xcat),
        str(output_path),
        export_params=True,
        opset_version=18,
        do_constant_folding=True,
        input_names=input_names,
        output_names=output_names,
        dynamic_axes=dynamic_axes,
        dynamo=False,
    )

    # Validate ONNX model
    onnx_model = onnx.load(str(output_path))
    onnx.checker.check_model(onnx_model)
    print(f"SUCCESS: {model_name} successfully exported and verified with ONNX checker.")


def verify_onnx_equivalence(torch_model, onnx_path, dummy_inputs):
    """Verify that ONNX Runtime produces identical output to PyTorch."""
    xb, xc, xcat = dummy_inputs

    # PyTorch inference
    torch_model.eval()
    with torch.no_grad():
        torch_logits = torch_model(xb, xc, xcat).cpu().numpy()
        torch_probs = torch.softmax(torch.from_numpy(torch_logits), dim=1).numpy()

    # ONNX Runtime inference
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    ort_inputs = {
        "xb": xb.cpu().numpy().astype(np.float32),
        "xc": xc.cpu().numpy().astype(np.float32),
        "xcat": xcat.cpu().numpy().astype(np.int64),
    }
    ort_outputs = session.run(None, ort_inputs)
    ort_logits = ort_outputs[0]
    ort_probs = np.exp(ort_logits) / np.sum(np.exp(ort_logits), axis=1, keepdims=True)

    max_diff = np.max(np.abs(torch_logits - ort_logits))
    prob_diff = np.max(np.abs(torch_probs - ort_probs))
    print(f"Verification against PyTorch: Max Logit Diff = {max_diff:.8f}, Max Prob Diff = {prob_diff:.8f}")
    assert max_diff < 1e-4, f"ONNX output differs significantly from PyTorch! Diff: {max_diff}"
    print("✅ ONNX Runtime and PyTorch outputs match perfectly!")


def serialize_preprocessing(preproc):
    """Serialize sklearn imputer, scaler, and label encoders to clean JSON dict."""
    binary_cols = list(preproc.get("binary_cols", []))
    cont_cols = list(preproc.get("cont_cols", []))
    cat_cols = list(preproc.get("cat_cols", []))

    imp_cont = preproc.get("imp_cont") or preproc.get("imputer")
    scaler = preproc.get("scaler")
    le_dict = preproc.get("le_dict") or preproc.get("cat_encoders", {})

    # Expected cont cols from fitted transformer
    fitted_cont_cols = getattr(imp_cont, "feature_names_in_", None)
    expected_cont_cols = list(fitted_cont_cols) if fitted_cont_cols is not None else list(cont_cols)

    imputer_stats = {}
    if imp_cont is not None and hasattr(imp_cont, "statistics_"):
        for col_name, stat_val in zip(expected_cont_cols, imp_cont.statistics_):
            imputer_stats[col_name] = float(stat_val)

    scaler_params = {}
    if scaler is not None and hasattr(scaler, "mean_") and hasattr(scaler, "scale_"):
        for col_name, m, s in zip(expected_cont_cols, scaler.mean_, scaler.scale_):
            scaler_params[col_name] = {"mean": float(m), "scale": float(s)}

    cat_encoders_data = {}
    for col_name, encoder in le_dict.items():
        if hasattr(encoder, "classes_"):
            cat_encoders_data[col_name] = [str(c) for c in encoder.classes_]
        elif isinstance(encoder, dict):
            cat_encoders_data[col_name] = {str(k): int(v) for k, v in encoder.items()}

    return {
        "binary_cols": binary_cols,
        "cont_cols": cont_cols,
        "expected_cont_cols": expected_cont_cols,
        "cat_cols": cat_cols,
        "imputer_statistics": imputer_stats,
        "scaler_params": scaler_params,
        "cat_encoders": cat_encoders_data,
    }


def export_all():
    print("Initializing VirusPredictor...")
    predictor = VirusPredictor()

    # 1. Export Model 1 (Major classes)
    m1_xb = torch.zeros((1, len(predictor.preprocessing1["binary_cols"])), dtype=torch.float32)
    m1_xc = torch.zeros((1, len(predictor.preprocessing1["scaler"].mean_)), dtype=torch.float32)
    m1_xcat = torch.zeros((1, len(predictor.preprocessing1["cat_cols"])), dtype=torch.long)

    m1_path = MODELS_DIR / "grtt_major.onnx"
    export_model_to_onnx(predictor.model1, (m1_xb, m1_xc, m1_xcat), m1_path, "Model 1 (Major GRTT)")
    verify_onnx_equivalence(predictor.model1, m1_path, (m1_xb, m1_xc, m1_xcat))

    # 2. Export Model 2 (Other viruses)
    m2_xb = torch.zeros((1, len(predictor.preprocessing2["binary_cols"])), dtype=torch.float32)
    m2_xc = torch.zeros((1, len(predictor.preprocessing2["scaler"].mean_)), dtype=torch.float32)
    m2_xcat = torch.zeros((1, len(predictor.preprocessing2["cat_cols"])), dtype=torch.long)

    m2_path = MODELS_DIR / "grtt_other.onnx"
    export_model_to_onnx(predictor.model2, (m2_xb, m2_xc, m2_xcat), m2_path, "Model 2 (Other Viruses GRTT)")
    verify_onnx_equivalence(predictor.model2, m2_path, (m2_xb, m2_xc, m2_xcat))

    # 3. Export Model Configurations & Normalization Parameters
    model_config = {
        "model1": serialize_preprocessing(predictor.preprocessing1),
        "model2": serialize_preprocessing(predictor.preprocessing2),
        "virus_mapping": {int(k): v for k, v in VIRUS_MAPPING.items()},
        "other_virus_mapping": {int(k): v for k, v in OTHER_VIRUS_MAPPING.items()},
        "syndrome_exclusions": {int(k): list(v) for k, v in SYNDROME_EXCLUDED_VIRUSES.items()},
        "symptoms": ALL_SYMPTOMS,
        "symptom_display_names": SYMPTOM_DISPLAY_NAMES,
    }

    with open(DATA_DIR / "model_config.json", "w", encoding="utf-8") as f:
        json.dump(model_config, f, indent=2)
    print(f"✅ Saved model_config.json ({os.path.getsize(DATA_DIR / 'model_config.json') / 1024:.1f} KB)")

    # 4. Export State & District Mapping JSON
    state_map_df = pd.read_csv("state_encoding_map.csv")
    district_map_df = pd.read_csv("district_encoding_map.csv")
    district_state_df = pd.read_csv("district_state_mapping.csv")

    state_district_data = {}
    for _, s_row in state_map_df.iterrows():
        s_name = s_row["state_name"]
        s_code = int(s_row["encoded_value"])

        # Find districts for this state
        d_filtered = district_state_df[district_state_df["state"] == s_name]
        districts = []
        for _, d_row in d_filtered.iterrows():
            d_name = d_row["district_name"]
            d_code = int(d_row["district_encoded"])
            districts.append({"name": d_name, "encoded": d_code})

        state_district_data[s_name] = {
            "state_name": s_name,
            "state_encoded": s_code,
            "districts": districts,
        }

    with open(DATA_DIR / "state_district_map.json", "w", encoding="utf-8") as f:
        json.dump(state_district_data, f, indent=2)
    print(f"✅ Saved state_district_map.json ({len(state_district_data)} states)")

    # 5. Export Syndrome Mapping JSON
    syndrome_df = pd.read_csv("SyndromeMapping.csv")
    syndromes = []
    for _, row in syndrome_df.dropna(subset=["Overall_Syndromes", "Encoded_Value"]).iterrows():
        syndromes.append({
            "overall_syndrome": str(row["Overall_Syndromes"]),
            "syndrome_label": str(row["Syndrome_Label"]),
            "encoded_value": int(row["Encoded_Value"]),
        })

    with open(DATA_DIR / "syndrome_mapping.json", "w", encoding="utf-8") as f:
        json.dump(syndromes, f, indent=2)
    print(f"✅ Saved syndrome_mapping.json ({len(syndromes)} syndrome options)")

    # 6. Export Pathogen List JSON
    with open(DATA_DIR / "pathogen_list.json", "w", encoding="utf-8") as f:
        json.dump(DR_SUSPECTED_PATHOGENS, f, indent=2)
    print(f"✅ Saved pathogen_list.json ({len(DR_SUSPECTED_PATHOGENS)} pathogens)")

    print("\n🎉 All ONNX models and JSON metadata assets exported successfully!")


if __name__ == "__main__":
    export_all()
