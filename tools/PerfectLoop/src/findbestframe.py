
import os
import cv2
from tqdm import tqdm
import numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics.pairwise import cosine_similarity
from skimage.metrics import structural_similarity as ssim


class LoopFrameFinder:
    def __init__(self, video_path, every_n_frames=2, resize_to=(1280, 720)):
        self.video_path = video_path
        self.every_n_frames = every_n_frames
        self.resize_to = resize_to
        self.frames = []
        self.fps = 0
        self.embeddings = None
        self.sim_matrix = None

    def extract_frames(self):
        cap = cv2.VideoCapture(self.video_path)
        if not cap.isOpened():
            raise IOError(f"Cannot open video file: {self.video_path}")
        
        self.fps = cap.get(cv2.CAP_PROP_FPS)
        frames = []

        while True:
            ret, frame = cap.read()
            if not ret:
                break
            frame = cv2.resize(frame, self.resize_to)
            frames.append(frame)
            for _ in range(self.every_n_frames - 1):
                cap.read()
        
        cap.release()
        self.frames = frames

    def compute_embeddings(self):
        self.embeddings = []
        for frame in tqdm(self.frames, desc="Computing embeddings"):
            hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
            h_hist = cv2.calcHist([hsv], [0], None, [32], [0, 180])   # Hue
            s_hist = cv2.calcHist([hsv], [1], None, [32], [0, 256])   # Saturation
            v_hist = cv2.calcHist([hsv], [2], None, [32], [0, 256])   # Value
            
            h_hist = cv2.normalize(h_hist, h_hist).flatten()
            s_hist = cv2.normalize(s_hist, s_hist).flatten()
            v_hist = cv2.normalize(v_hist, v_hist).flatten()

            hist = np.concatenate([h_hist, s_hist, v_hist])
            self.embeddings.append(hist)
        self.embeddings = np.array(self.embeddings)


    def compute_similarity_matrix(self):
        self.sim_matrix = cosine_similarity(self.embeddings)

    def compute_ssim(self, frame1, frame2):
        # Convert to grayscale for SSIM
        gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
        score, _ = ssim(gray1, gray2, full=True)
        return score

    def find_best_match(self, ssim_threshold=0.90, distance_bias_weight=0.2, 
                        min_gap=30, padding=15):
        n = self.sim_matrix.shape[0]
        best_i, best_j, best_score, best_ssim = 0, 0, -1, -1

        for i in range(padding, n - padding):
            for j in range(i + min_gap, n - padding):
                hist_score = self.sim_matrix[i, j]

                # Skip if too close to diagonal
                if abs(j - i) < min_gap:
                    continue

                # Distance bias
                normalized_distance = (j - i) / n
                biased_score = hist_score + distance_bias_weight * normalized_distance

                if biased_score > best_score:
                    ssim_score = self.compute_ssim(self.frames[i], self.frames[j])
                    if ssim_score > ssim_threshold:
                        best_i, best_j = i, j
                        best_score = biased_score
                        best_ssim = ssim_score

        # Fallback: no match passed threshold
        if best_ssim < 0:
            best_i, best_j = np.unravel_index(self.sim_matrix.argmax(), self.sim_matrix.shape)
            best_score = self.sim_matrix[best_i, best_j]
            best_ssim = self.compute_ssim(self.frames[best_i], self.frames[best_j])

        return best_i, best_j, best_score, best_ssim

    def save_ssim_diff_map(self, frame1, frame2, output_dir=".", prefix=""):
        gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
        ssim_score, diff = ssim(gray1, gray2, full=True)
        
        diff = (diff * 255).astype(np.uint8)
        diff_color = cv2.applyColorMap(diff, cv2.COLORMAP_JET)
        
        # Save frames and diff
        # cv2.imwrite(os.path.join(output_dir, f"{prefix}best_start.png"), frame1)
        # cv2.imwrite(os.path.join(output_dir, f"{prefix}best_end.png"), frame2)
        cv2.imwrite(os.path.join(output_dir, f"{prefix}ssim_diff_map.png"), diff_color)
        
        print(f"[INFO] SSIM Score between best pair: {ssim_score:.4f}")
        print(f"[INFO] SSIM diff map saved as {prefix}ssim_diff_map.png")

    def plot_similarity_matrix(self, best_i, best_j, output_path):
        plt.figure(figsize=(10, 8))
        plt.imshow(self.sim_matrix, cmap='viridis', origin='lower', aspect='auto')
        plt.colorbar(label='Cosine Similarity')
        plt.title("Frame Similarity Matrix")

        # Adjust axes to start from 0
        plt.xlim(0, self.sim_matrix.shape[1])
        plt.ylim(0, self.sim_matrix.shape[0])

        # Mark best match
        plt.scatter([best_j], [best_i], color='red', label=f'Best Match: 0 → {best_j - best_i}')
        plt.xlabel("Frame Offset from Start")
        plt.ylabel("Frame Offset from Start")
        plt.legend()
        plt.tight_layout()
        plt.savefig(output_path)
        plt.close()

    def plot_trimmed_similarity_zone(self, front_limit=30, back_start_ratio=0.7, output_path="focused_similarity.png"):
        n = self.sim_matrix.shape[0]
        front_range = range(min(front_limit, n))
        back_start = int(n * back_start_ratio)
        back_range = range(back_start, n)

        trimmed_matrix = self.sim_matrix[np.ix_(front_range, back_range)]
        
        # Normalize for visualization
        norm_matrix = (trimmed_matrix - np.min(trimmed_matrix)) / (np.max(trimmed_matrix) - np.min(trimmed_matrix) + 1e-8)

        plt.figure(figsize=(10, 6))
        plt.imshow(norm_matrix, cmap='plasma', aspect='auto', origin='lower')

        plt.colorbar(label="Normalized Similarity")
        plt.xlabel("Back Frame Offset (from back_start)")
        plt.ylabel("Front Frame Offset (from 0)")
        plt.title("Trimmed Similarity Zone: Start vs End Frame")

        # Explicitly set tick range from 0
        plt.xlim(0, len(back_range))
        plt.ylim(0, len(front_range))

        # Optional: cleaner ticks (fewer steps if matrix is large)
        step_x = max(1, len(back_range) // 10)
        step_y = max(1, len(front_range) // 10)
        plt.xticks(np.arange(0, len(back_range), step_x))
        plt.yticks(np.arange(0, len(front_range), step_y))

        plt.tight_layout()
        plt.savefig(output_path)
        plt.close()


    def save_best_frames(self, best_i, best_j, output_dir):
        if not self.frames:
            print("[WARN] No frames loaded to save.")
            return

        os.makedirs(output_dir, exist_ok=True)
        frame_i_img = self.frames[best_i]
        frame_j_img = self.frames[best_j]

        # Save each frame as image
        path_i = os.path.join(output_dir, f"frame_{best_i}_start.png")
        path_j = os.path.join(output_dir, f"frame_{best_j}_end.png")

        cv2.imwrite(path_i, frame_i_img)
        cv2.imwrite(path_j, frame_j_img)

        print(f"[INFO] Saved best start frame {best_i} at {path_i}")
        print(f"[INFO] Saved best end frame {best_j} at {path_j}")

    def run(self, output_chart="similarity_matrix.png", focused_chart="focused_similarity.png"):
        print("[INFO] Extracting frames from video...")
        self.extract_frames()

        print("[INFO] Computing frame embeddings (this may take a while)...")
        self.compute_embeddings()

        print("[INFO] Computing similarity matrix...")
        self.compute_similarity_matrix()

        print("[INFO] Finding best matching frames with SSIM check...")
        best_i, best_j, hist_score, ssim_score = self.find_best_match()

        output_dir = os.path.dirname(output_chart) or "."

        print("[INFO] Plotting full similarity matrix...")
        self.plot_similarity_matrix(best_i, best_j, output_chart)

        print("[INFO] Plotting focused similarity zone...")
        self.plot_trimmed_similarity_zone(output_path=focused_chart)

        print("[INFO] Saving best matching frames as images...")
        self.save_best_frames(best_i, best_j, output_dir)

        self.save_ssim_diff_map(self.frames[best_i], self.frames[best_j], output_dir=output_dir, prefix="")

        print(f"[INFO] FPS: {self.fps:.2f}")
        print(f"[INFO] Total Frames (sampled): {len(self.frames)}")
        print(f"[RESULT] Best match: frame {best_i} → {best_j} (hist_score: {hist_score:.4f}, ssim_score: {ssim_score:.4f})")

        return {
            "start_frame": best_i,
            "end_frame": best_j,
            "hist_similarity": hist_score,
            "ssim_similarity": ssim_score,
            "fps": self.fps,
            "total_frames": len(self.frames)
        }


