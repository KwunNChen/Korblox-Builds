# Drag-smear texture for Gore's blood trail Beam. A Beam maps image Y along its length and X across it,
# so streaks are columns, constant along Y (beam joints then don't show). Grey levels are tinted by
# Beam.Color. Fine, low-contrast streaks with a few thin gaps; alpha fades out raggedly toward the sides.
import numpy as np
from PIL import Image
rng = np.random.default_rng(11)
W, H = 512, 64  # X across the smear, Y along it
u = np.linspace(-1, 1, W)
alpha = np.zeros(W); shade = np.zeros(W)
x = 0
while x < W:
    w = int(rng.integers(1, 5))
    gap = rng.random() < 0.07
    alpha[x:x+w] = rng.uniform(0.25, 0.5) if gap else rng.uniform(0.8, 1.0)
    shade[x:x+w] = rng.uniform(0.72, 1.0)
    x += w
k = np.array([0.2, 0.6, 0.2])
alpha = np.convolve(alpha, k, "same"); shade = np.convolve(shade, k, "same")
# soft ragged sides: coverage falls off over the outer third, with stray streaks past it
edge = 0.62 + 0.1 * np.convolve(rng.uniform(-1, 1, W), np.ones(21) / 21, "same")
env = np.clip((1 - np.abs(u)) / (1 - edge), 0, 1) ** 1.6
stray = (rng.random(W) < 0.12) & (np.abs(u) < 0.97)
alpha = np.maximum(alpha * env, np.where(stray, alpha * 0.45, 0))
img = np.zeros((H, W, 4))
img[..., 0] = img[..., 1] = img[..., 2] = (shade * 255)[None, :]
img[..., 3] = (np.clip(alpha, 0, 1) * 255)[None, :]
Image.fromarray(img.astype(np.uint8), "RGBA").save("BloodSmear.png")
print("ok", img.shape)
