"""
prepare_dataset.py
Automates merging, renaming, and stratified train/val/test splitting
across 5 currencies (INR, KES, EGP, UGX, USD) plus a background negative class.
"""

import os
import shutil
import random
from pathlib import Path

# Mapping of raw dataset directory paths to standardized class prefixes
# Update the raw paths according to where your downloaded datasets reside.
SOURCE_MAPPINGS = {
    "raw_datasets/india": "INR_",
    "raw_datasets/kenya": "KES_",
    "raw_datasets/egypt": "EGP_",
    "raw_datasets/uganda": "UGX_",
    "raw_datasets/usa": "USD_",
    "raw_datasets/background": "Background"
}

OUTPUT_ROOT = Path("dataset")
SPLITS = {
    "train": 0.70,
    "val": 0.15,
    "test": 0.15
}

VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

def prepare_directories():
    for split in SPLITS.keys():
        os.makedirs(OUTPUT_ROOT / split, exist_ok=True)

def process_and_split(seed=42):
    random.seed(seed)
    prepare_directories()
    
    total_images_processed = 0

    for source_dir, prefix in SOURCE_MAPPINGS.items():
        src_path = Path(source_dir)
        if not src_path.exists():
            print(f"[!] Warning: Source directory '{src_path}' not found. Skipping...")
            continue
            
        print(f"[*] Processing directory: {src_path} with prefix '{prefix}'")
        
        # Iterate over each denomination subfolder inside the currency directory
        for denom_dir in src_path.iterdir():
            if not denom_dir.is_dir():
                continue
                
            clean_name = (denom_dir.name
                          .replace("ksh", "")
                          .replace("rs", "")
                          .replace("usd", "")
                          .replace("egp", "")
                          .replace("ugx", "")
                          .strip("_")
                          .strip())
            
            target_class = "Background" if prefix == "Background" else f"{prefix}{clean_name}"
            
            images = [f for f in denom_dir.glob("*.*") if f.suffix.lower() in VALID_EXTENSIONS]
            random.shuffle(images)
            
            n_total = len(images)
            if n_total == 0:
                print(f"  [?] Class '{target_class}' has 0 valid images. Skipping.")
                continue
                
            n_train = int(n_total * SPLITS["train"])
            n_val = int(n_total * SPLITS["val"])
            
            split_dict = {
                "train": images[:n_train],
                "val": images[n_train:n_train + n_val],
                "test": images[n_train + n_val:]
            }
            
            for split_name, file_list in split_dict.items():
                dest_dir = OUTPUT_ROOT / split_name / target_class
                dest_dir.mkdir(parents=True, exist_ok=True)
                for img_file in file_list:
                    dest_file = dest_dir / img_file.name
                    # Avoid overwriting files with identical names
                    if dest_file.exists():
                        dest_file = dest_dir / f"{img_file.stem}_{random.randint(1000, 9999)}{img_file.suffix}"
                    shutil.copy2(img_file, dest_file)
            
            total_images_processed += n_total
            print(f"  [+] Class '{target_class}': {n_total} images distributed "
                  f"(train={len(split_dict['train'])}, val={len(split_dict['val'])}, test={len(split_dict['test'])})")

    print(f"\n[DONE] Finished processing. Total images structured: {total_images_processed}")

if __name__ == "__main__":
    process_and_split()
