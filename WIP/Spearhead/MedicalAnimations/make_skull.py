# Skull kill-feed icon (white on transparent), drawn at 4x then downsampled.
from PIL import Image, ImageDraw
S = 512
im = Image.new("L", (S, S), 0); d = ImageDraw.Draw(im)
d.ellipse((76, 40, 436, 380), fill=255)                  # cranium
d.rounded_rectangle((150, 300, 362, 470), 40, fill=255)  # jaw
d.ellipse((130, 190, 240, 300), fill=0)                  # eyes
d.ellipse((272, 190, 382, 300), fill=0)
d.polygon([(256, 300), (226, 352), (286, 352)], fill=0)  # nose
for x in (206, 256, 306):                                # teeth gaps
    d.rectangle((x - 8, 392, x + 8, 470), fill=0)
a = im.resize((128, 128), Image.LANCZOS)
out = Image.new("RGBA", a.size, (255, 255, 255, 0)); out.putalpha(a)
out.save("SkullIcon.png")
