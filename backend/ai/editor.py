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

        # Local Diffusion Inpainting Engine (GTX 1660 Super / CUDA)
        self.diffusion_pipe = None

    def _init_diffusion(self) -> bool:
        """Initializes Stable Diffusion Inpainting pipeline on CUDA (GTX 1660 Super)."""
        if self.diffusion_pipe is not None:
            return True

        try:
            import torch
            if not torch.cuda.is_available():
                print("[!] CUDA not available for Diffusion inpainting.")
                return False

            print("[*] Loading Local Diffusion Inpainting on GPU (GTX 1660 Super)...")
            from diffusers import AutoPipelineForInpainting, DPMSolverMultistepScheduler
            pipe = AutoPipelineForInpainting.from_pretrained(
                "runwayml/stable-diffusion-inpainting",
                variant="fp16",
                torch_dtype=torch.float16,
                safety_checker=None,
                requires_safety_checker=False
            )
            # Full float32 on GTX 1660 prevents Turing architecture fp16 underflow/black frames
            pipe = pipe.to(torch.float32)
            pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)
            pipe.enable_attention_slicing()
            # Dynamic CPU/GPU offload keeps idle VRAM at 0.0 GB so the UI remains 100% smooth!
            pipe.enable_model_cpu_offload()
            self.diffusion_pipe = pipe
            print("[+] Local Diffusion Engine initialized with dynamic CPU/GPU offload (0 GB idle VRAM)!")
            return True
        except Exception as e:
            print(f"[!] Warning: Could not initialize Diffusion engine: {e}")
            self.diffusion_pipe = None
            return False

    def _init_lama(self):
        """Initializes LaMa inpainting model via ONNX Runtime."""
        if not os.path.exists(self.lama_path):
            print(f"[!] LaMa model file not found at {self.lama_path}")
            return

        try:
            import onnxruntime as ort
            # Use CPUExecutionProvider for stable Fast Fourier Convolution execution
            selected_providers = ["CPUExecutionProvider"]
            opts = ort.SessionOptions()
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self.lama_session = ort.InferenceSession(self.lama_path, opts, providers=selected_providers)
            print(f"[*] LaMa neural inpainting engine loaded with provider: {self.lama_session.get_providers()[0]}")
        except Exception as e:
            print(f"[!] Warning: Could not initialize LaMa ONNX model ({e}). Using OpenCV inpainting.")
            self.lama_session = None

    def snap_mask_to_edges(self, img_bgr: np.ndarray, rough_mask: np.ndarray, dilation_px: int = 2) -> np.ndarray:
        """
        Automatically snaps a rough, loose brush mask to the exact natural contour/silhouette
        of the foreground object using GrabCut color clustering and edge boundary refinement.
        Strips away mistakenly brushed background pixels and guarantees razor-sharp edges.
        """
        if np.count_nonzero(rough_mask) == 0:
            return rough_mask

        h, w = img_bgr.shape[:2]
        ys, xs = np.where(rough_mask > 0)
        min_x, max_x = np.min(xs), np.max(xs)
        min_y, max_y = np.min(ys), np.max(ys)

        box_w = max_x - min_x
        box_h = max_y - min_y
        pad_x = max(15, int(box_w * 0.15))
        pad_y = max(15, int(box_h * 0.15))

        rx1 = max(0, min_x - pad_x)
        ry1 = max(0, min_y - pad_y)
        rx2 = min(w, max_x + pad_x)
        ry2 = min(h, max_y + pad_y)
        rw = rx2 - rx1
        rh = ry2 - ry1

        if rw < 10 or rh < 10:
            return rough_mask

        crop_img = img_bgr[ry1:ry2, rx1:rx2]
        crop_mask = np.zeros((rh, rw), dtype=np.uint8)

        # 5px margin reserved for definitive background sampling
        rect = (5, 5, max(1, rw - 10), max(1, rh - 10))
        bgd_model = np.zeros((1, 65), np.float64)
        fgd_model = np.zeros((1, 65), np.float64)

        try:
            cv2.grabCut(crop_img, crop_mask, rect, bgd_model, fgd_model, 5, cv2.GC_INIT_WITH_RECT)
            segmented_crop = np.where((crop_mask == cv2.GC_FGD) | (crop_mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
        except Exception as e:
            print(f"[!] GrabCut edge snapping warning: {e}")
            return rough_mask

        # Filter connected components: keep components that intersect with the user's stroke
        crop_rough = rough_mask[ry1:ry2, rx1:rx2]
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(segmented_crop)
        refined_crop = np.zeros_like(segmented_crop)

        for lbl in range(1, num_labels):
            comp_mask = (labels == lbl).astype(np.uint8) * 255
            overlap = np.count_nonzero(cv2.bitwise_and(comp_mask, crop_rough))
            if overlap > 0.05 * stats[lbl, cv2.CC_STAT_AREA]:
                refined_crop = cv2.bitwise_or(refined_crop, comp_mask)

        # Constrain refined mask within the stroke's immediate 6px boundary (prevent background blowup)
        stroke_neighborhood = cv2.dilate(crop_rough, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))
        refined_crop = cv2.bitwise_and(refined_crop, stroke_neighborhood)

        # If GrabCut failed to isolate or eliminated too much, fallback safely to rough mask
        if np.count_nonzero(refined_crop) < 0.30 * np.count_nonzero(crop_rough):
            refined_crop = crop_rough

        # Fill internal holes inside the object contour
        contours, _ = cv2.findContours(refined_crop, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        filled_crop = np.zeros_like(refined_crop)
        for c in contours:
            if cv2.contourArea(c) > 15:
                cv2.drawContours(filled_crop, [c], -1, 255, -1)

        # Micro-dilation (2-3px) so no edge fringe or color halo remains
        if dilation_px > 0:
            k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dilation_px * 2 + 1, dilation_px * 2 + 1))
            filled_crop = cv2.dilate(filled_crop, k, iterations=1)

        final_mask = np.zeros_like(rough_mask)
        final_mask[ry1:ry2, rx1:rx2] = filled_crop
        return final_mask

    def snap_mask_to_hair(self, img_bgr: np.ndarray, rough_mask: np.ndarray) -> np.ndarray:
        """
        Automatically snaps a rough, loose brush mask to the exact natural contour/silhouette
        of the subject's hair. Rejects background bokeh, sky, and walls, and prevents dark paint
        spillover outside the hair boundary.
        """
        if np.count_nonzero(rough_mask) == 0:
            return rough_mask

        h, w = img_bgr.shape[:2]
        ys, xs = np.where(rough_mask > 0)
        pad = max(30, int(max(np.max(xs) - np.min(xs), np.max(ys) - np.min(ys)) * 0.15))
        rx1, ry1 = max(0, np.min(xs) - pad), max(0, np.min(ys) - pad)
        rx2, ry2 = min(w, np.max(xs) + pad), min(h, np.max(ys) + pad)
        rw, rh = rx2 - rx1, ry2 - ry1

        if rw < 10 or rh < 10:
            return rough_mask

        crop_img = img_bgr[ry1:ry2, rx1:rx2]
        crop_rough = rough_mask[ry1:ry2, rx1:rx2]

        gray = cv2.cvtColor(crop_img, cv2.COLOR_BGR2GRAY)
        lab = cv2.cvtColor(crop_img, cv2.COLOR_BGR2LAB)
        L = lab[:, :, 0]
        B = lab[:, :, 2]

        sobelx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
        sobely = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
        edge_mag = np.sqrt(sobelx**2 + sobely**2)

        gc_mask = np.full((rh, rw), cv2.GC_PR_BGD, dtype=np.uint8)
        gc_mask[crop_rough > 0] = cv2.GC_PR_FGD
        gc_mask[(crop_rough > 0) & (L < 85) & (edge_mag > 15)] = cv2.GC_FGD
        is_bg = ((edge_mag < 16) & (L > 120)) | (L > 170) | ((B > 142) & (L > 130))
        gc_mask[(crop_rough > 0) & is_bg] = cv2.GC_BGD

        gc_mask[0:8, :] = cv2.GC_BGD
        gc_mask[-8:, :] = cv2.GC_BGD
        gc_mask[:, 0:8] = cv2.GC_BGD
        gc_mask[:, -8:] = cv2.GC_BGD

        bgd_model = np.zeros((1, 65), np.float64)
        fgd_model = np.zeros((1, 65), np.float64)

        try:
            cv2.grabCut(crop_img, gc_mask, None, bgd_model, fgd_model, 4, cv2.GC_INIT_WITH_MASK)
            segmented_crop = np.where((gc_mask == cv2.GC_FGD) | (gc_mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
            segmented_crop = cv2.bitwise_and(segmented_crop, crop_rough)
        except Exception:
            segmented_crop = crop_rough

        if np.count_nonzero(segmented_crop) < 0.10 * np.count_nonzero(crop_rough):
            segmented_crop = cv2.bitwise_and(crop_rough, (~is_bg).astype(np.uint8)*255)

        final_mask = np.zeros_like(rough_mask)
        final_mask[ry1:ry2, rx1:rx2] = segmented_crop
        return final_mask

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

    def inpaint_image(self, image_input: Any, mask: np.ndarray, snap_edges: bool = True, mode: str = "diffusion", prompt: str = "") -> np.ndarray:
        """
        Erases the masked region and seamlessly reconstructs the background.
        image_input: File path (str) or loaded BGR numpy array.
        mode:
          - 'diffusion': Photorealistic Generative Fill on GTX 1660 Super GPU.
          - 'lama': Fast on-device neural pattern interpolation.
        If snap_edges is True, automatically contours and tightens the mask to the
        exact physical object silhouette using GrabCut before neural inpainting.
        """
        if isinstance(image_input, np.ndarray):
            img_bgr = image_input.copy()
        else:
            img_bgr = cv2.imread(str(image_input))
            if img_bgr is None:
                raise FileNotFoundError(f"Could not load image at {image_input}")

        h, w = img_bgr.shape[:2]

        # Ensure mask is binary (0 or 255) and matches size
        if mask.shape[:2] != (h, w):
            mask = cv2.resize(mask, (w, h), interpolation=cv2.INTER_NEAREST)
        mask = (mask > 50).astype(np.uint8) * 255

        # Check if mask is completely empty
        if np.count_nonzero(mask) == 0:
            return img_bgr

        # Automatically detect and snap to object edges/silhouette
        if snap_edges:
            mask = self.snap_mask_to_edges(img_bgr, mask, dilation_px=2)

        # 1. Use Local Diffusion Generative Inpainting if selected
        if mode == "diffusion":
            try:
                if self._init_diffusion():
                    return self._run_diffusion_inpainting(img_bgr, mask, prompt=prompt)
            except Exception as e:
                print(f"[!] Diffusion inpainting error ({e}). Falling back to LaMa.")

        # 2. Use LaMa Neural Inpainting if model is loaded
        if self.lama_session is not None:
            try:
                return self._run_lama_inpainting(img_bgr, mask)
            except Exception as e:
                print(f"[!] LaMa inpainting error ({e}). Falling back to OpenCV.")

        # 3. High-quality OpenCV Telea inpainting fallback
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        dilated_mask = cv2.dilate(mask, kernel, iterations=2)
        inpainted = cv2.inpaint(img_bgr, dilated_mask, inpaintRadius=7, flags=cv2.INPAINT_TELEA)
        return inpainted

    def _run_diffusion_inpainting(self, img_bgr: np.ndarray, mask_bin: np.ndarray, prompt: str = "") -> np.ndarray:
        """
        Executes Local Stable Diffusion Inpainting on the NVIDIA GTX 1660 Super.
        Generates brand-new photorealistic textures (roads, curbs, leaves) with matching
        perspective and natural camera sensor grain, eliminating watercolor smearing.
        """
        import torch
        from PIL import Image

        img_h, img_w = img_bgr.shape[:2]
        ys, xs = np.where(mask_bin > 0)
        min_x, max_x = np.min(xs), np.max(xs)
        min_y, max_y = np.min(ys), np.max(ys)

        box_w = max_x - min_x
        box_h = max_y - min_y
        center_x = (min_x + max_x) // 2
        center_y = (min_y + max_y) // 2

        # Square crop with 20% margin around target object for contextual awareness
        max_side = max(box_w, box_h)
        crop_size = max(512, int(max_side * 1.45))
        half = crop_size // 2

        c_x1 = max(0, center_x - half)
        c_y1 = max(0, center_y - half)
        c_x2 = min(img_w, center_x + half)
        c_y2 = min(img_h, center_y + half)

        crop_img = img_bgr[c_y1:c_y2, c_x1:c_x2]
        crop_mask = mask_bin[c_y1:c_y2, c_x1:c_x2]
        cur_h, cur_w = crop_img.shape[:2]

        # Pad symmetrically with BORDER_REFLECT_101 to keep exact 1:1 aspect ratio
        pad_top = max(0, half - (center_y - c_y1))
        pad_bottom = max(0, crop_size - cur_h - pad_top)
        pad_left = max(0, half - (center_x - c_x1))
        pad_right = max(0, crop_size - cur_w - pad_left)

        if pad_top > 0 or pad_bottom > 0 or pad_left > 0 or pad_right > 0:
            square_img = cv2.copyMakeBorder(crop_img, pad_top, pad_bottom, pad_left, pad_right, cv2.BORDER_REFLECT_101)
            square_mask = cv2.copyMakeBorder(crop_mask, pad_top, pad_bottom, pad_left, pad_right, cv2.BORDER_CONSTANT, value=0)
        else:
            square_img = crop_img
            square_mask = crop_mask

        sq_size = square_img.shape[0]

        # Dilate mask 4px to ensure zero trace of the object rim remains
        d_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
        dilated_sq_mask = cv2.dilate(square_mask, d_k, iterations=1)

        # Convert to PIL RGB for Diffusion pipeline at 512x512
        sq_rgb = cv2.cvtColor(square_img, cv2.COLOR_BGR2RGB)
        pil_img = Image.fromarray(sq_rgb).resize((512, 512), Image.Resampling.BILINEAR)
        pil_mask = Image.fromarray(dilated_sq_mask).resize((512, 512), Image.Resampling.NEAREST)

        # Photorealistic auto-prompt tuning
        if not prompt or not prompt.strip():
            inpaint_prompt = "clean seamless outdoor background, continuous natural road surface and foliage, sharp high resolution photography, matching sunlight"
        else:
            inpaint_prompt = prompt.strip()

        neg_prompt = "scooter, motorcycle, vehicle, person, human, blurry, smudges, watercolor, cartoon, painterly, artifacts, ghosting, dark blotches"

        # Run diffusion inference on GPU (12 steps with DPMSolver takes ~14s)
        with torch.inference_mode():
            gen_pil = self.diffusion_pipe(
                prompt=inpaint_prompt,
                negative_prompt=neg_prompt,
                image=pil_img,
                mask_image=pil_mask,
                num_inference_steps=12,
                guidance_scale=7.5
            ).images[0]

        # Immediately flush CUDA cache to restore 100% VRAM to desktop UI and display driver
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

        # Convert back to numpy BGR and upscale with Lanczos4
        gen_rgb = np.array(gen_pil)
        gen_bgr_512 = cv2.cvtColor(gen_rgb, cv2.COLOR_RGB2BGR)
        out_square = cv2.resize(gen_bgr_512, (sq_size, sq_size), interpolation=cv2.INTER_LANCZOS4)

        # Un-pad back to actual crop
        out_crop = out_square[pad_top:pad_top+cur_h, pad_left:pad_left+cur_w]
        safe_crop_mask = dilated_sq_mask[pad_top:pad_top+cur_h, pad_left:pad_left+cur_w]

        # Camera sensor grain injection
        bg_pixels = crop_img[safe_crop_mask == 0]
        if len(bg_pixels) > 50:
            gray_bg = cv2.cvtColor(crop_img, cv2.COLOR_BGR2GRAY)
            high_pass = cv2.Laplacian(gray_bg, cv2.CV_32F)
            bg_noise_std = np.std(high_pass[safe_crop_mask == 0])
            if bg_noise_std > 1.0:
                grain = np.random.normal(0, min(bg_noise_std * 0.40, 7.0), out_crop.shape).astype(np.float32)
                out_crop = np.clip(out_crop.astype(np.float32) + grain, 0, 255).astype(np.uint8)

        # Smooth Feathered Gaussian Alpha Blending (Zero watercolor bleed!)
        feather = cv2.GaussianBlur(safe_crop_mask.astype(np.float32) / 255.0, (25, 25), 0)[:, :, np.newaxis]
        blended_crop = (out_crop.astype(np.float32) * feather + crop_img.astype(np.float32) * (1.0 - feather)).astype(np.uint8)

        result_bgr = img_bgr.copy()
        result_bgr[c_y1:c_y2, c_x1:c_x2] = blended_crop
        return result_bgr

    def _run_lama_inpainting(self, img_bgr: np.ndarray, mask_bin: np.ndarray) -> np.ndarray:
        """
        Executes LaMa Inpainting on an aspect-ratio-preserved square crop,
        injects matched camera sensor micro-grain, and applies Poisson gradient blending
        to guarantee 100% seamless photorealism with zero watercolor smearing.
        """
        img_h, img_w = img_bgr.shape[:2]

        ys, xs = np.where(mask_bin > 0)
        min_x, max_x = np.min(xs), np.max(xs)
        min_y, max_y = np.min(ys), np.max(ys)

        box_w = max_x - min_x
        box_h = max_y - min_y
        center_x = (min_x + max_x) // 2
        center_y = (min_y + max_y) // 2

        # Make the crop a SQUARE to preserve exact 1:1 aspect ratio (zero squish/distortion!)
        max_side = max(box_w, box_h)
        crop_size = max(512, int(max_side * 1.6))
        half = crop_size // 2

        c_x1 = max(0, center_x - half)
        c_y1 = max(0, center_y - half)
        c_x2 = min(img_w, center_x + half)
        c_y2 = min(img_h, center_y + half)

        crop_img = img_bgr[c_y1:c_y2, c_x1:c_x2]
        crop_mask = mask_bin[c_y1:c_y2, c_x1:c_x2]
        cur_h, cur_w = crop_img.shape[:2]

        # Pad symmetrically with BORDER_REFLECT_101 to keep exact 1:1 square
        pad_top = max(0, half - (center_y - c_y1))
        pad_bottom = max(0, crop_size - cur_h - pad_top)
        pad_left = max(0, half - (center_x - c_x1))
        pad_right = max(0, crop_size - cur_w - pad_left)

        if pad_top > 0 or pad_bottom > 0 or pad_left > 0 or pad_right > 0:
            square_img = cv2.copyMakeBorder(crop_img, pad_top, pad_bottom, pad_left, pad_right, cv2.BORDER_REFLECT_101)
            square_mask = cv2.copyMakeBorder(crop_mask, pad_top, pad_bottom, pad_left, pad_right, cv2.BORDER_CONSTANT, value=0)
        else:
            square_img = crop_img
            square_mask = crop_mask

        sq_size = square_img.shape[0]

        # Dilate mask 4px so zero trace of the object rim remains (anti-ghosting)
        d_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
        dilated_sq_mask = cv2.dilate(square_mask, d_k, iterations=1)

        # Scale square to 512x512 for LaMa (Aspect Ratio is 1:1, ZERO SQUISH!)
        in_img = cv2.resize(square_img, (512, 512), interpolation=cv2.INTER_AREA)
        in_mask = cv2.resize(dilated_sq_mask, (512, 512), interpolation=cv2.INTER_NEAREST)

        # Normalize inputs for LaMa (RGB [0, 1] float32, NCHW)
        rgb = cv2.cvtColor(in_img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        norm_img = np.transpose(rgb, (2, 0, 1))[np.newaxis, ...]
        norm_mask = (in_mask.astype(np.float32) / 255.0)[np.newaxis, np.newaxis, ...]
        norm_mask = np.where(norm_mask > 0.1, 1.0, 0.0).astype(np.float32)

        input_names = [inp.name for inp in self.lama_session.get_inputs()]
        ort_inputs = {
            input_names[0]: norm_img,
            input_names[1]: norm_mask
        }

        # Run LaMa neural inpainting
        output = self.lama_session.run(None, ort_inputs)[0]
        out_512 = np.clip(output[0].transpose(1, 2, 0), 0, 255).astype(np.uint8)
        out_bgr_512 = cv2.cvtColor(out_512, cv2.COLOR_RGB2BGR)

        # Lanczos4 high-quality resample back to square
        out_square = cv2.resize(out_bgr_512, (sq_size, sq_size), interpolation=cv2.INTER_LANCZOS4)

        # Un-pad back to actual crop size
        out_crop = out_square[pad_top:pad_top+cur_h, pad_left:pad_left+cur_w]
        safe_crop_mask = dilated_sq_mask[pad_top:pad_top+cur_h, pad_left:pad_left+cur_w]

        # Camera sensor grain matching: eliminates the smooth plastic/watercolor look
        bg_pixels = crop_img[safe_crop_mask == 0]
        if len(bg_pixels) > 50:
            gray_bg = cv2.cvtColor(crop_img, cv2.COLOR_BGR2GRAY)
            high_pass = cv2.Laplacian(gray_bg, cv2.CV_32F)
            bg_noise_std = np.std(high_pass[safe_crop_mask == 0])
            if bg_noise_std > 1.0:
                grain = np.random.normal(0, min(bg_noise_std * 0.40, 7.0), out_crop.shape).astype(np.float32)
                out_crop = np.clip(out_crop.astype(np.float32) + grain, 0, 255).astype(np.uint8)

        # Seamless Poisson Gradient Blending
        mask_indices = np.where(safe_crop_mask > 0)
        m_cx = int(np.mean(mask_indices[1]))
        m_cy = int(np.mean(mask_indices[0]))

        try:
            cloned_crop = cv2.seamlessClone(out_crop, crop_img, safe_crop_mask, (m_cx, m_cy), cv2.NORMAL_CLONE)
        except Exception:
            f_mask = cv2.GaussianBlur(safe_crop_mask.astype(np.float32) / 255.0, (5, 5), 0)[:, :, np.newaxis]
            cloned_crop = (out_crop.astype(np.float32) * f_mask + crop_img.astype(np.float32) * (1.0 - f_mask)).astype(np.uint8)

        result_bgr = img_bgr.copy()
        result_bgr[c_y1:c_y2, c_x1:c_x2] = cloned_crop
        return result_bgr

    def darken_hair(self, image_input: Any, mask: np.ndarray, intensity: float = 0.70, snap_edges: bool = True) -> np.ndarray:
        """
        Naturally darkens gray/light hair strands while preserving fine strand textures,
        specular sheen, and hair silhouette. Rejects background bokeh and leaves already-dark
        hair completely unaffected for zero visible stroke boundaries or paint smudges.
        intensity: 0.20 to 1.00 (subtle natural blend to deep rich black).
        """
        if isinstance(image_input, np.ndarray):
            img_bgr = image_input.copy()
        else:
            img_bgr = cv2.imread(str(image_input))
            if img_bgr is None:
                raise FileNotFoundError(f"Could not load image at {image_input}")

        h, w = img_bgr.shape[:2]
        if mask.shape[:2] != (h, w):
            mask = cv2.resize(mask, (w, h), interpolation=cv2.INTER_LINEAR)

        mask_bin = (mask > 20).astype(np.uint8) * 255
        if np.count_nonzero(mask_bin) == 0:
            return img_bgr

        # Automatically detect and snap to hair silhouette/edges, stripping away background bokeh
        if snap_edges:
            mask_bin = self.snap_mask_to_hair(img_bgr, mask_bin)
            if np.count_nonzero(mask_bin) == 0:
                return img_bgr

        # Crop to active bounding box with padding for fast processing on large photos
        ys, xs = np.where(mask_bin > 0)
        pad = max(40, int(max(np.max(xs) - np.min(xs), np.max(ys) - np.min(ys)) * 0.15))
        y1 = max(0, np.min(ys) - pad)
        y2 = min(h, np.max(ys) + pad)
        x1 = max(0, np.min(xs) - pad)
        x2 = min(w, np.max(xs) + pad)

        crop_img = img_bgr[y1:y2, x1:x2]
        crop_mask = mask_bin[y1:y2, x1:x2]

        # Convert to LAB color space
        lab = cv2.cvtColor(crop_img, cv2.COLOR_BGR2LAB).astype(np.float32)
        L = lab[:, :, 0]
        A = lab[:, :, 1]
        B = lab[:, :, 2]

        # Sample natural dark hair reference in the region
        dark_cands = (L > 20) & (L < 80) & (crop_mask > 0)
        if np.count_nonzero(dark_cands) < 30:
            dark_cands = (L > 20) & (L < 80)

        if np.count_nonzero(dark_cands) > 40:
            ref_L = float(np.percentile(L[dark_cands], 25))
            ref_A = float(np.median(A[dark_cands]))
            ref_B = float(np.median(B[dark_cands]))
        else:
            ref_L = 50.0
            ref_A = 130.0
            ref_B = 126.0

        # High-frequency strand texture extraction via edge-preserving filter
        L_uint8 = np.clip(L, 0, 255).astype(np.uint8)
        L_base = cv2.bilateralFilter(L_uint8, d=11, sigmaColor=30, sigmaSpace=7).astype(np.float32)
        strand_detail = L - L_base

        # Skin & Forehead Protection (warm flesh tone)
        skin_score = np.clip((A - 132.0) / 8.0, 0.0, 1.0) * np.clip((B - 133.0) / 8.0, 0.0, 1.0)

        # White/gray hair excess above natural dark hair level
        excess = np.maximum(0.0, L - ref_L)
        # Only blend pixels that are distinctly brighter than natural dark hair (excess > 8)
        # Normal dark hair (L <= ref_L + 8) gets zero change!
        hair_blend = np.clip((excess - 8.0) / 22.0, 0.0, 1.0)

        # Soft feather on the hair mask boundary
        hair_feather = cv2.GaussianBlur(crop_mask.astype(np.float32) / 255.0, (7, 7), 0)

        clamp_intensity = float(np.clip(intensity, 0.20, 1.0))
        active_weight = hair_blend * clamp_intensity * hair_feather * (1.0 - skin_score * 0.95)

        # Natural digital hair dye: replaces gray hair with natural dark hair base + micro strand texture
        L_dyed = ref_L + strand_detail * 0.70
        L_final = np.clip(L * (1.0 - active_weight) + L_dyed * active_weight, 15.0, 255.0)

        # Natural melanin undertone transfer for gray hairs
        A_final = A * (1.0 - active_weight) + ref_A * active_weight
        B_final = B * (1.0 - active_weight) + ref_B * active_weight

        res_lab = np.zeros_like(lab)
        res_lab[:, :, 0] = L_final
        res_lab[:, :, 1] = A_final
        res_lab[:, :, 2] = B_final

        res_crop = cv2.cvtColor(np.clip(res_lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
        # Ensure zero change outside the active hair mask
        mask_3d = (crop_mask > 0)[:, :, np.newaxis]
        res_crop = np.where(mask_3d, res_crop, crop_img)
        result = img_bgr.copy()
        result[y1:y2, x1:x2] = res_crop
        return result

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

        # Copy EXIF metadata from original if possible, resetting orientation to Normal (1)
        # since edited_bgr pixels are already written in upright orientation.
        try:
            with Image.open(original_path) as orig_img:
                exif_obj = orig_img.getexif()
                if exif_obj:
                    # Reset Orientation (0x0112) to 1 (normal) so viewers do not rotate it again
                    exif_obj[0x0112] = 1
                    with Image.open(candidate_path) as edit_img:
                        edit_img.save(candidate_path, exif=exif_obj, quality=96)
        except Exception as e:
            print(f"[!] Warning: Could not preserve EXIF: {e}")

        return candidate_path
