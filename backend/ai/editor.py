import os
import cv2
import base64
import numpy as np
from PIL import Image, ImageOps
from typing import Optional, Tuple, Dict, Any

class PhotoEditorEngine:
    def __init__(self, models_dir: str, cache_dir: str):
        self.models_dir = models_dir
        self.cache_dir = cache_dir
        self.editor_cache_dir = os.path.join(cache_dir, "editor")
        os.makedirs(self.editor_cache_dir, exist_ok=True)
        os.makedirs(self.models_dir, exist_ok=True)

        self.lama_path = os.path.join(models_dir, "lama_fp32.onnx")
        self.lama_session = None
        self._init_lama()

    def _init_lama(self):
        """Initializes LaMa inpainting model on GTX 1660 Super GPU via DirectML if available."""
        if not os.path.exists(self.lama_path):
            return

        try:
            import onnxruntime as ort
            providers = ort.get_available_providers()
            selected_providers = []
            if "DmlExecutionProvider" in providers:
                selected_providers.append("DmlExecutionProvider")
            selected_providers.append("CPUExecutionProvider")

            opts = ort.SessionOptions()
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self.lama_session = ort.InferenceSession(self.lama_path, opts, providers=selected_providers)
            print(f"[*] LaMa inpainting engine loaded with provider: {self.lama_session.get_providers()[0]}")
        except Exception as e:
            print(f"[!] Warning: Could not initialize LaMa ONNX model ({e}). Using OpenCV inpainting.")
            self.lama_session = None

    def decode_mask_base64(self, mask_base64: str, target_shape: Tuple[int, int]) -> np.ndarray:
        """
        Decodes a Base64-encoded PNG mask from the QML Canvas and resizes it to the exact 
        original target image dimensions (target_h, target_w).
        """
        target_h, target_w = target_shape
        if "," in mask_base64:
            mask_base64 = mask_base64.split(",", 1)[1]

        mask_bytes = base64.b64decode(mask_base64)
        nparr = np.frombuffer(mask_bytes, np.uint8)
        mask_raw = cv2.imdecode(nparr, cv2.IMREAD_UNCHANGED)

        if mask_raw is None:
            return np.zeros((target_h, target_w), dtype=np.uint8)

        # If mask has alpha channel, extract alpha or binarize non-transparent pixels
        if len(mask_raw.shape) == 3 and mask_raw.shape[2] == 4:
            alpha = mask_raw[:, :, 3]
            binary = np.where(alpha > 10, 255, 0).astype(np.uint8)
        elif len(mask_raw.shape) == 3:
            gray = cv2.cvtColor(mask_raw, cv2.COLOR_BGR2GRAY)
            binary = np.where(gray > 10, 255, 0).astype(np.uint8)
        else:
            binary = np.where(mask_raw > 10, 255, 0).astype(np.uint8)

        # Scale accurately to full original image resolution
        if binary.shape[0] != target_h or binary.shape[1] != target_w:
            binary = cv2.resize(binary, (target_w, target_h), interpolation=cv2.INTER_NEAREST)

        return binary

    def inpaint_image(self, image_path: str, mask: np.ndarray) -> np.ndarray:
        """
        Erases the masked region and seamlessly reconstructs the background.
        Uses GTX 1660 Super GPU via LaMa ONNX if available, with automatic OpenCV fallback.
        """
        img_bgr = cv2.imread(image_path)
        if img_bgr is None:
            raise FileNotFoundError(f"Could not load image at {image_path}")

        h, w = img_bgr.shape[:2]

        # Ensure mask is binary (0 or 255) and matches size
        if mask.shape[:2] != (h, w):
            mask = cv2.resize(mask, (w, h), interpolation=cv2.INTER_NEAREST)
        mask = (mask > 50).astype(np.uint8) * 255

        # Check if mask is completely empty
        if np.count_nonzero(mask) == 0:
            return img_bgr

        # 1. Use LaMa ONNX with DirectML GPU acceleration if loaded
        if self.lama_session is not None:
            try:
                return self._run_lama_inpainting(img_bgr, mask)
            except Exception as e:
                print(f"[!] LaMa GPU inpainting encountered an error ({e}). Falling back to OpenCV.")

        # 2. High-quality OpenCV Telea inpainting fallback (0 download, instant)
        # Dilate mask slightly to prevent outline fringing
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        dilated_mask = cv2.dilate(mask, kernel, iterations=2)
        inpainted = cv2.inpaint(img_bgr, dilated_mask, inpaintRadius=7, flags=cv2.INPAINT_TELEA)
        return inpainted

    def _run_lama_inpainting(self, img_bgr: np.ndarray, mask_bin: np.ndarray) -> np.ndarray:
        """
        Executes LaMa Inpainting on cropped bounding region + context margin,
        running on the GPU via DirectML, then cleanly blends back to full resolution.
        """
        h, w = img_bgr.shape[:2]

        # Find bounding box of mask to crop context region (speeds up 24MP photos)
        ys, xs = np.where(mask_bin > 0)
        min_x, max_x = np.min(xs), np.max(xs)
        min_y, max_y = np.min(ys), np.max(ys)

        # Add 60% contextual padding around erased object
        box_w = max_x - min_x
        box_h = max_y - min_y
        pad_x = int(max(box_w * 0.6, 64))
        pad_y = int(max(box_h * 0.6, 64))

        crop_x1 = max(0, min_x - pad_x)
        crop_y1 = max(0, min_y - pad_y)
        crop_x2 = min(w, max_x + pad_x)
        crop_y2 = min(h, max_y + pad_y)

        crop_img = img_bgr[crop_y1:crop_y2, crop_x1:crop_x2]
        crop_mask = mask_bin[crop_y1:crop_y2, crop_x1:crop_x2]
        crop_h, crop_w = crop_img.shape[:2]

        # Resize crop to multiple of 8 for Fourier convolutions (max 768px for real-time GPU speed)
        scale = min(1.0, 768.0 / max(crop_h, crop_w))
        work_w = int(round(crop_w * scale / 8.0) * 8)
        work_h = int(round(crop_h * scale / 8.0) * 8)
        work_w = max(64, work_w)
        work_h = max(64, work_h)

        in_img = cv2.resize(crop_img, (work_w, work_h), interpolation=cv2.INTER_AREA)
        in_mask = cv2.resize(crop_mask, (work_w, work_h), interpolation=cv2.INTER_NEAREST)

        # Format inputs for LaMa (RGB normalized [0, 1] float32, NCHW)
        rgb = cv2.cvtColor(in_img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        norm_img = np.transpose(rgb, (2, 0, 1))[np.newaxis, ...]
        norm_mask = (in_mask.astype(np.float32) / 255.0)[np.newaxis, np.newaxis, ...]
        norm_mask = np.where(norm_mask > 0.1, 1.0, 0.0).astype(np.float32)

        input_names = [inp.name for inp in self.lama_session.get_inputs()]
        ort_inputs = {
            input_names[0]: norm_img,
            input_names[1]: norm_mask
        }

        # Run on GTX 1660 Super GPU via DirectML
        output = self.lama_session.run(None, ort_inputs)[0]
        out_crop = np.clip(output[0].transpose(1, 2, 0) * 255.0, 0, 255).astype(np.uint8)
        out_bgr_crop = cv2.cvtColor(out_crop, cv2.COLOR_RGB2BGR)

        # Resize back to crop size
        out_bgr_crop = cv2.resize(out_bgr_crop, (crop_w, crop_h), interpolation=cv2.INTER_CUBIC)

        # Smooth feather blending back into the full resolution original
        feather_mask = cv2.GaussianBlur(crop_mask.astype(np.float32) / 255.0, (15, 15), 0)
        feather_mask = np.clip(feather_mask * 1.3, 0.0, 1.0)[:, :, np.newaxis]

        blended_crop = (out_bgr_crop * feather_mask + crop_img * (1.0 - feather_mask)).astype(np.uint8)

        result_bgr = img_bgr.copy()
        result_bgr[crop_y1:crop_y2, crop_x1:crop_x2] = blended_crop
        return result_bgr

    def darken_hair(self, image_path: str, mask: np.ndarray, intensity: float = 0.70) -> np.ndarray:
        """
        Naturally darkens hair to rich black/dark tones using LAB color space curve modulation.
        Preserves natural specular reflections, hair shine, and strand definition.
        intensity: 0.0 (no change) to 1.0 (deep natural black).
        """
        img_bgr = cv2.imread(image_path)
        if img_bgr is None:
            raise FileNotFoundError(f"Could not load image at {image_path}")

        h, w = img_bgr.shape[:2]
        if mask.shape[:2] != (h, w):
            mask = cv2.resize(mask, (w, h), interpolation=cv2.INTER_LINEAR)

        # Feather mask edges for natural organic transition with skin and background
        feathered_mask = cv2.GaussianBlur(mask.astype(np.float32) / 255.0, (11, 11), 0)
        if np.max(feathered_mask) == 0:
            return img_bgr

        # Convert to LAB color space (L = Luminance, A = green/red, B = blue/yellow)
        lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
        L = lab[:, :, 0]
        A = lab[:, :, 1]
        B = lab[:, :, 2]

        # 1. Luminance curve modulation:
        # Darkens midtones and gray/light strands while preserving high-contrast hair sheen
        clamp_intensity = np.clip(intensity, 0.0, 1.0)
        # S-curve reduction: L_norm ** 0.6 preserves darkest roots, scales highlights naturally
        L_norm = L / 255.0
        darken_factor = 1.0 - (0.75 * clamp_intensity * np.sqrt(L_norm))
        L_darkened = np.clip(L * darken_factor, 10.0, 255.0)

        # 2. Chroma neutralization (removes brassy yellow/brown/gray tint):
        # Neutral center in 8-bit LAB is 128.0
        A_darkened = 128.0 + (A - 128.0) * (1.0 - 0.60 * clamp_intensity)
        B_darkened = 128.0 + (B - 128.0) * (1.0 - 0.75 * clamp_intensity)

        # Blend with original image using the feathered mask weights
        alpha = feathered_mask[:, :]
        final_L = L_darkened * alpha + L * (1.0 - alpha)
        final_A = A_darkened * alpha + A * (1.0 - alpha)
        final_B = B_darkened * alpha + B * (1.0 - alpha)

        result_lab = np.zeros_like(lab)
        result_lab[:, :, 0] = np.clip(final_L, 0, 255)
        result_lab[:, :, 1] = np.clip(final_A, 0, 255)
        result_lab[:, :, 2] = np.clip(final_B, 0, 255)

        result_bgr = cv2.cvtColor(result_lab.astype(np.uint8), cv2.COLOR_LAB2BGR)
        return result_bgr

    def generate_preview(self, edited_bgr: np.ndarray, image_id: int) -> str:
        """
        Saves a temporary preview JPEG in the editor cache and returns its absolute path.
        """
        preview_filename = f"preview_{image_id}.jpg"
        preview_path = os.path.join(self.editor_cache_dir, preview_filename)
        cv2.imwrite(preview_path, edited_bgr, [cv2.IMWRITE_JPEG_QUALITY, 92])
        return preview_path

    def save_edited_copy(self, original_path: str, edited_bgr: np.ndarray) -> str:
        """
        Saves the edited photo as a non-destructive copy (e.g. filename_edited.jpg)
        in the original directory, preserving original image files completely.
        """
        dirname = os.path.dirname(original_path)
        base, ext = os.path.splitext(os.path.basename(original_path))
        ext = ext.lower()
        if ext not in [".jpg", ".jpeg", ".png", ".webp"]:
            ext = ".jpg"

        # Find non-conflicting filename
        candidate_name = f"{base}_edited{ext}"
        candidate_path = os.path.join(dirname, candidate_name)
        counter = 1
        while os.path.exists(candidate_path):
            candidate_name = f"{base}_edited_{counter}{ext}"
            candidate_path = os.path.join(dirname, candidate_name)
            counter += 1

        # Write high quality copy
        if ext in [".jpg", ".jpeg"]:
            cv2.imwrite(candidate_path, edited_bgr, [cv2.IMWRITE_JPEG_QUALITY, 96])
        else:
            cv2.imwrite(candidate_path, edited_bgr)

        # Copy EXIF metadata from original if possible
        try:
            with Image.open(original_path) as orig_img:
                exif = orig_img.info.get("exif")
                if exif:
                    with Image.open(candidate_path) as edit_img:
                        edit_img.save(candidate_path, exif=exif, quality=96)
        except Exception:
            pass

        return candidate_path
