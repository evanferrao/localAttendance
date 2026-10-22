#!/usr/bin/env python3
"""
generate_vector_zip.py

Generates a vector-based registration ZIP archive from a photos ZIP archive.
Extracts 512-dimensional ArcFace face embeddings from student images so that
student registration can be performed securely and privately without distributing
raw student photos.

Folder structure:
Before (photos ZIP):
  - students.csv (or any CSV manifest)
  - photos/
      - REGNO_FULLNAME.jpeg

After (vector ZIP):
  - students.csv (unchanged)
  - vectors/
      - REGNO_FULLNAME.txt  (512-dimensional normalized ArcFace embedding)

Usage:
  python3 generate_vector_zip.py <photos_zip_path> [<output_zip_path>]
  python3 generate_vector_zip.py -i photos.zip -o vectors.zip
"""

import argparse
import io
import os
import sys
import zipfile
from pathlib import Path
from typing import List, Optional, Tuple

import cv2
import numpy as np

# Require Python >= 3.9, <= 3.14 (Recommended: Python 3.10, 3.11, or 3.12)
if sys.version_info < (3, 9) or sys.version_info >= (3, 15):
    print(
        f"[ERROR] Unsupported Python version: {sys.version.split()[0]}. "
        f"generate_vector_zip.py requires Python >= 3.9 and <= 3.14 (Recommended: 3.10 - 3.12).",
        file=sys.stderr,
    )
    sys.exit(1)


IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}


def initialize_face_analyzer(det_size: Tuple[int, int] = (640, 640)):
    """Initialize InsightFace FaceAnalysis for Buffalo_L ArcFace embeddings."""
    try:
        import insightface

        app = insightface.app.FaceAnalysis(
            name='buffalo_l',
            providers=['CPUExecutionProvider'],
        )
        app.prepare(ctx_id=0, det_size=det_size)
        return app
    except Exception as e:
        print(f"Error initializing InsightFace: {e}", file=sys.stderr)
        print("Please ensure insightface, onnxruntime, and opencv are installed:", file=sys.stderr)
        print("  pip install insightface onnxruntime opencv-python-headless", file=sys.stderr)
        raise


def extract_face_embedding(app, image_bytes: bytes) -> Optional[np.ndarray]:
    """
    Decodes image and extracts primary 512-d normalized face embedding.
    Returns normalized numpy array of shape (512,) or None if no face detected.
    """
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        return None

    faces = app.get(img)
    if not faces:
        return None

    # Pick the largest face (by bounding box area) if multiple detected
    primary_face = max(
        faces,
        key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1])
        if hasattr(f, 'bbox') else 0,
    )

    if hasattr(primary_face, 'normed_embedding') and primary_face.normed_embedding is not None:
        emb = primary_face.normed_embedding
    else:
        emb = primary_face.embedding
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm

    return emb.astype(np.float32)


def format_vector_txt(embedding: np.ndarray) -> str:
    """Format 512-d embedding as comma-separated floats in text format."""
    return ", ".join(f"{float(x):.8f}" for x in embedding)


def process_photos_zip(
    input_zip_path: str,
    output_zip_path: Optional[str] = None,
    det_size: Tuple[int, int] = (640, 640),
) -> Tuple[int, int, int]:
    """
    Reads an input photos ZIP and produces an output vector ZIP.
    Returns (total_images, success_count, failed_count).
    """
    input_path = Path(input_zip_path)
    if not input_path.exists():
        raise FileNotFoundError(f"Input ZIP file not found: {input_zip_path}")

    if output_zip_path is None:
        output_path = input_path.with_name(f"{input_path.stem}_vectors.zip")
    else:
        output_path = Path(output_zip_path)

    print(f"Loading Face Analysis model (buffalo_l)...")
    app = initialize_face_analyzer(det_size=det_size)

    total_images = 0
    success_count = 0
    failed_count = 0
    skipped_files: List[Tuple[str, str]] = []

    print(f"Reading input ZIP: {input_path}")
    print(f"Writing output ZIP: {output_path}")

    with zipfile.ZipFile(input_path, 'r') as in_zip, zipfile.ZipFile(output_path, 'w', compression=zipfile.ZIP_DEFLATED) as out_zip:
        file_list = in_zip.namelist()

        # 1. Copy CSV manifest(s) and other non-image metadata files unchanged
        for name in file_list:
            if name.endswith('/'):
                continue
            ext = Path(name).suffix.lower()
            if ext == '.csv' or ext == '.json':
                print(f"  [CSV/MANIFEST] Preserving {name} unchanged")
                data = in_zip.read(name)
                out_zip.writestr(name, data)

        # 2. Process all photos and generate vectors/<REGNO_FULLNAME>.txt
        for name in file_list:
            if name.endswith('/'):
                continue
            ext = Path(name).suffix.lower()
            if ext not in IMAGE_EXTENSIONS:
                continue

            total_images += 1
            filename = Path(name).name
            stem = Path(filename).stem
            vector_filename = f"vectors/{stem}.txt"

            try:
                img_bytes = in_zip.read(name)
                emb = extract_face_embedding(app, img_bytes)

                if emb is not None and len(emb) == 512:
                    vector_str = format_vector_txt(emb)
                    out_zip.writestr(vector_filename, vector_str.encode('utf-8'))
                    success_count += 1
                    print(f"  [OK] {name} -> {vector_filename} (512-d vector)")
                else:
                    failed_count += 1
                    reason = "No face detected"
                    skipped_files.append((name, reason))
                    print(f"  [FAILED] {name}: {reason}", file=sys.stderr)
            except Exception as e:
                failed_count += 1
                skipped_files.append((name, str(e)))
                print(f"  [ERROR] {name}: {e}", file=sys.stderr)

    print("\n" + "=" * 50)
    print("VECTOR ZIP GENERATION COMPLETE")
    print("=" * 50)
    print(f"Output archive : {output_path}")
    print(f"Total photos   : {total_images}")
    print(f"Vectorized     : {success_count}")
    print(f"Failed/Skipped : {failed_count}")

    if skipped_files:
        print("\nSkipped images:")
        for fname, rsn in skipped_files:
            print(f"  - {fname}: {rsn}")

    return total_images, success_count, failed_count


def main():
    parser = argparse.ArgumentParser(
        description="Convert a photos ZIP into a privacy-safe vectors ZIP for face attendance."
    )
    parser.add_argument(
        'input',
        nargs='?',
        help="Path to input photos ZIP archive",
    )
    parser.add_argument(
        '-i', '--input-file',
        dest='input_flag',
        help="Path to input photos ZIP archive",
    )
    parser.add_argument(
        'output',
        nargs='?',
        help="Path to output vectors ZIP archive (optional)",
    )
    parser.add_argument(
        '-o', '--output-file',
        dest='output_flag',
        help="Path to output vectors ZIP archive (optional)",
    )
    parser.add_argument(
        '--det-size',
        type=int,
        default=640,
        help="Face detector input resolution size (default: 640)",
    )

    args = parser.parse_args()
    input_file = args.input or args.input_flag
    output_file = args.output or args.output_flag

    if not input_file:
        parser.print_help()
        sys.exit(1)

    try:
        process_photos_zip(
            input_zip_path=input_file,
            output_zip_path=output_file,
            det_size=(args.det_size, args.det_size),
        )
    except Exception as e:
        print(f"\nExecution failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
