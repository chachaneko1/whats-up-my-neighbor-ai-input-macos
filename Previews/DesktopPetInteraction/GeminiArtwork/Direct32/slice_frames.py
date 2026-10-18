"""Slice all 32 Gemini drawings in source order; no shape interpolation."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parent
source=Image.open(root/'source.png').convert('RGB')
assert source.size==(1456,720)
output=root/'Frames';output.mkdir(exist_ok=True)
size=(416,384);scale=1.46;anchor=np.array([208.,129.])

def components(mask):
 todo=set(zip(*np.where(mask)));groups=[]
 while todo:
  stack=[todo.pop()];group=[]
  while stack:
   y,x=stack.pop();group.append((x,y))
   for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
    q=(y+dy,x+dx)
    if q in todo:todo.remove(q);stack.append(q)
  if len(group)>8:groups.append(group)
 return groups

records=[];frames=[]
for i in range(32):
 rect=(i%8*182,i//8*180,(i%8+1)*182,(i//8+1)*180)
 rgb=np.asarray(source.crop(rect)).astype(float)
 alpha=np.clip(255-np.minimum(rgb[:,:,0],rgb[:,:,2])+rgb[:,:,1],0,255)
 alpha[(np.minimum(rgb[:,:,0],rgb[:,:,2])>150)&(np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1]>90)]=0
 alpha[alpha<32]=0
 ys,xs=np.where(alpha>=128);bbox=(int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1))
 assert min(bbox[0],bbox[1],182-bbox[2],180-bbox[3])>=4,(i,bbox)
 # Remove magenta spill without eroding a mask, pruning limbs or drawing fur.
 t=alpha/255;safe=np.maximum(t,.001)
 clean=rgb.copy();clean[:,:,0]=(rgb[:,:,0]-(1-t)*255)/safe
 clean[:,:,1]=rgb[:,:,1]/safe;clean[:,:,2]=(rgb[:,:,2]-(1-t)*255)/safe
 clean=np.clip(clean,0,255);clean[alpha==0]=0
 rgba=Image.fromarray(np.uint8(np.dstack((clean,alpha))))
 marks=components((rgb.min(2)>210)&(alpha>220));assert len(marks)==3,(i,len(marks))
 marks.sort(key=lambda g:sum(y for x,y in g)/len(g))
 eyes=np.array([[np.mean([x for x,y in g]),np.mean([y for x,y in g])] for g in marks[:2]])
 center=eyes.mean(0);offset=np.rint(anchor-center*scale).astype(int)
 scaled=rgba.resize((round(182*scale),round(180*scale)),Image.Resampling.LANCZOS)
 sb=scaled.getbbox();tx,ty=map(int,offset)
 assert tx+sb[0]>=24 and ty+sb[1]>=24 and tx+sb[2]<=size[0]-24 and ty+sb[3]<=size[1]-24,(i,offset,sb)
 canvas=Image.new('RGBA',size);canvas.alpha_composite(scaled,(tx,ty))
 # Prove compositing did not lose any alpha at the canvas boundary.
 assert np.asarray(canvas)[:,:,3].sum()==np.asarray(scaled)[:,:,3].sum()
 canvas.save(output/f'{i:02}.png');frames.append(canvas)
 records.append({'frame':i,'source_cell':i+1,'crop':rect,'source_opaque_bbox':bbox,
   'scale':scale,'translation':[tx,ty],'output_bbox':canvas.getbbox(),
   'sha256':hashlib.sha256((output/f'{i:02}.png').read_bytes()).hexdigest()})
font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',16)
board=Image.new('RGB',(1664,960),'#f4f2ed');draw=ImageDraw.Draw(board)
animated=[]
for i,im in enumerate(frames):
 x=i%8*208;y=i//8*240;draw.text((x+8,y+8),f'{i+1:02}',font=font,fill='#252526')
 small=im.resize((208,192),Image.Resampling.LANCZOS);board.paste(small,(x,y+30),small)
 bg=Image.new('RGB',(416,384),'#f4f2ed');bg.paste(im,(0,0),im);animated.append(bg)
board.save(root/'切分總覽.png')
animated[0].save(root/'原畫等間隔.gif',save_all=True,append_images=animated[1:],duration=50,loop=0,disposal=2,optimize=False)
manifest={'frames':32,'size':size,'carry_frame':15,'last_frame':31,'frame_interval_ms':50,
 'source_size':source.size,'source_sha256':hashlib.sha256((root/'source.png').read_bytes()).hexdigest(),
 'method':'Direct source-order crops, chroma key, one common scale and eye-centre translation only; no generated in-betweens, shape morph, component pruning, per-frame scale or pose-dependent timing',
 'minimum_canvas_padding_px':24,'records':records}
(root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('32 Gemini drawings sliced; alpha preserved, minimum 24px canvas padding, fixed 50ms per frame.')
