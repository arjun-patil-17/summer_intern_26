import numpy as np
from PIL import Image

# 1. Load and resize
img = Image.open("td2.jpg").resize((32, 32))
img_array = np.array(img, dtype=np.float32)

# 2. Normalize to [-1, 1]
img_array = (img_array / 127.5) - 1.0

# =====================================================================
# CRITICAL FIX: Convert from HWC (32,32,3) to PyTorch CHW (3,32,32)
# =====================================================================
img_array = img_array.transpose(2, 0, 1) 

# 3. Quantize to INT8
quantized_img = np.clip(np.round(img_array * 127.0), -127, 127).astype(np.int8)

# 4. Flatten and export
flat_img = quantized_img.flatten()

with open("image_data.h", "w") as f:
    f.write("#ifndef IMAGE_DATA_H\n#define IMAGE_DATA_H\n\n")
    f.write("#include <stdint.h>\n\n")
    f.write(f"const int8_t input_image[{len(flat_img)}] __attribute__((aligned(16))) = {{\n    ")
    for i, val in enumerate(flat_img):
        f.write(f"{val :> 4}, ")
        if (i + 1) % 16 == 0:
            f.write("\n    ")
    f.write("\n};\n\n#endif\n")
print("Success! Correctly ordered image_data.h generated.")