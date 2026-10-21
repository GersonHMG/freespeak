"""Builds the app icon images from the original logo artwork.

The original (assets/branding/source/logo_original.jpg) is a white glyph on a
teal rounded square, with a white margin and drop shadow around it -- fine
as a picture, wrong as an icon, since every platform cuts its own shape. This
lifts the glyph out and re-lays it on flat teal:

  assets/branding/icon.png             full-bleed square (iOS, web, old Android)
  assets/branding/icon_foreground.png  glyph only, sized for Android's
                                       adaptive-icon safe zone

Run from the project root, then regenerate the platform icons:

  python tool/make_icons.py
  dart run flutter_launcher_icons
"""
from PIL import Image, ImageDraw
import numpy as np
src=np.array(Image.open('assets/branding/source/logo_original.jpg').convert('RGB')).astype(float)
r,g,b=src[...,0],src[...,1],src[...,2]
teal=(g-r>80)&(b-r>80)
TEAL=(28,196,209)
inside=np.zeros(teal.shape,bool)
for y in range(1024):
    xs=np.where(teal[y])[0]
    if len(xs): inside[y,xs.min():xs.max()+1]=True
for _ in range(10):  # erode away the square's anti-aliased rim
    e=inside.copy()
    e[1:]&=inside[:-1]; e[:-1]&=inside[1:]; e[:,1:]&=inside[:,:-1]; e[:,:-1]&=inside[:,1:]
    inside=e
alpha=np.clip((r-TEAL[0])/(255-TEAL[0]),0,1)*inside
alpha=np.clip((alpha-0.3)/0.55,0,1)  # crisp edges: drop the JPEG's soft glow
A=Image.fromarray((alpha[128:896,128:896]*255).astype('uint8'))

def glyph_layer(scale):
    n=int(1024*scale); off=(1024-n)//2
    L=Image.new('L',(1024,1024),0); L.paste(A.resize((n,n),Image.LANCZOS),(off,off))
    a=np.array(L)
    # the stem runs off the bottom of the source square (and the rim trim
    # shaved its last pixels); carry its last clean row down to the edge
    rows=[y for y in range(1023,0,-1) if (a[y]>250).sum()>=4]
    yref=rows[0]-3
    a[yref:]=a[yref]
    print(scale,'stem row',yref,np.where(a[yref]>128)[0][[0,-1]])
    return Image.fromarray(a)
def white_on(bg,L):
    out=Image.new('RGBA',(1024,1024),bg)
    out.paste(Image.new('RGBA',(1024,1024),(255,255,255,255)),(0,0),L); return out
full=white_on(TEAL+(255,),glyph_layer(0.82)); full.convert('RGB').save('assets/branding/icon.png')
white_on((255,255,255,0),glyph_layer(0.60)).save('assets/branding/icon_foreground.png')
