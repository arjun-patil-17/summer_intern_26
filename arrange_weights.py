import re
import math

def pad_c_header():
    print("Reading original weights.h...")
    try:
        with open("weights.h", "r") as f:
            content = f.read()
    except FileNotFoundError:
        print("Error: weights.h not found in the current directory.")
        return

    # Matches the pattern: const int8_t name[size] = { values };
    pattern = r"const\s+int8_t\s+([a-zA-Z0-9_]+)\[(\d+)\]\s*=\s*\{([^}]+)\};"
    matches = re.findall(pattern, content)

    if not matches:
        print("No weight arrays found. Check the format of weights.h.")
        return

    print(f"Found {len(matches)} arrays. Processing structural channel padding...")

    with open("aligned_weights.h", "w") as f:
        f.write("#ifndef ALIGNED_WEIGHTS_H\n#define ALIGNED_WEIGHTS_H\n\n")
        f.write("#include <stdint.h>\n\n")
        
        for match in matches:
            name = match[0]
            original_size = int(match[1])
            
            # Extract numbers, removing spaces and newlines
            values_str = match[2].replace('\n', '').split(',')
            values = [v.strip() for v in values_str if v.strip()]
            
            padded_values = []
            
            # --- SPECIAL STRUCTURAL ROW PADDING FOR CONV LAYERS ---
            if name == "conv1_weight":
                # 8 channels, 27 weights per channel -> Pad each channel to 32 elements
                orig_ch_size = 27
                padded_ch_size = 32
                num_channels = 8
                for ch in range(num_channels):
                    ch_start = ch * orig_ch_size
                    ch_elements = values[ch_start : ch_start + orig_ch_size]
                    ch_elements.extend(['0'] * (padded_ch_size - orig_ch_size))
                    padded_values.extend(ch_elements)
                    
            elif name == "conv2_weight":
                # 16 channels, 72 weights per channel -> Pad each channel to 80 elements
                orig_ch_size = 72
                padded_ch_size = 80
                num_channels = 16
                for ch in range(num_channels):
                    ch_start = ch * orig_ch_size
                    ch_elements = values[ch_start : ch_start + orig_ch_size]
                    ch_elements.extend(['0'] * (padded_ch_size - orig_ch_size))
                    padded_values.extend(ch_elements)
            
            else:
                # For baseline 1D arrays (Biases / FC weights), pad the tail normally to a 16-byte boundary
                padded_values = list(values)
                remainder = len(padded_values) % 16
                padding_needed = 0 if remainder == 0 else 16 - remainder
                padded_values.extend(['0'] * padding_needed)

            new_size = len(padded_values)
            
            # Write the new padded array to the file
            f.write(f"// {name}: Original size {original_size} bytes -> Channel-Row Padded to {new_size} bytes\n")
            f.write(f"const int8_t {name}[{new_size}] __attribute__((aligned(16))) = {{\n    ")
            
            # Format nicely with 16 numbers per line
            for i, val in enumerate(padded_values):
                f.write(f"{val:>4}, ")
                if (i + 1) % 16 == 0:
                    f.write("\n    ")
                    
            f.write("\n};\n\n")

        f.write("#endif // ALIGNED_WEIGHTS_H\n")
        print("Success! Created structurally aligned 'aligned_weights.h'.")

if __name__ == "__main__":
    pad_c_header()