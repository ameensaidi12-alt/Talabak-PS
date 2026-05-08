from PIL import Image
import os

def final_zoom_fix(input_path, output_path, crop_percent=0.755):
    if not os.path.exists(input_path):
        print("Error: input path not found")
        return
        
    with Image.open(input_path) as img:
        img = img.convert("RGBA")
        
        width, height = img.size
        # Scaled to exactly 75.5%
        crop_pix = int(width * crop_percent)
        
        # Calculate crop coordinates (centered)
        left = (width - crop_pix) // 2
        top = (height - crop_pix) // 2
        right = left + crop_pix
        bottom = top + crop_pix
        
        cropped_box = img.crop((left, top, right, bottom))
        
        # Resize back to 1024x1024
        final_icon = cropped_box.resize((1024, 1024), Image.Resampling.LANCZOS)
        
        # Save
        final_icon.save(output_path)
        print(f"75.5% Icon saved to {output_path}")

if __name__ == "__main__":
    inp = r"c:\Users\ASUS\Desktop\hatStar\assets\images\logo_transparent.png"
    out = r"c:\Users\ASUS\Desktop\hatStar\assets\images\ultimate_full_bleed.png"
    final_zoom_fix(inp, out, 0.755)
