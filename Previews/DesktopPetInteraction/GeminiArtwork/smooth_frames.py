"""Build opaque silhouette/face distance-field transitions from accepted poses."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np,json,hashlib
root=Path(__file__).resolve().parent
SAMPLES=16
COUNT=17*SAMPLES+1
output=root/'DenseFrames';output.mkdir(exist_ok=True)
keys=[Image.open(root/'Frames'/f'{i:02}.png').convert('RGBA') for i in range(18)]

def dt1(f):
 n=len(f);v=[0]*n;z=[0.]*(n+1);out=np.empty(n);k=0;z[0]=-1e20;z[1]=1e20
 for q in range(1,n):
  s=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k])
  while s<=z[k]:
   k-=1;s=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k])
  k+=1;v[k]=q;z[k]=s;z[k+1]=1e20
 k=0
 for q in range(n):
  while z[k+1]<q:k+=1
  out[q]=(q-v[k])**2+f[v[k]]
 return out

def edt(mask):
 a=np.where(mask,0.,1e6)
 for y in range(a.shape[0]):a[y]=dt1(a[y])
 for x in range(a.shape[1]):a[:,x]=dt1(a[:,x])
 return np.sqrt(a)
def sdf(mask):return edt(mask)-edt(~mask)

def components(mask):
 todo=set(zip(*np.where(mask)));parts=[]
 while todo:
  queue=[todo.pop()];part=[]
  while queue:
   y,x=queue.pop();part.append((x,y))
   for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
    p=(y+dy,x+dx)
    if p in todo:todo.remove(p);queue.append(p)
  if len(part)>12:parts.append(part)
 parts.sort(key=lambda p:sum(y for x,y in p)/len(p))
 parts[:2]=sorted(parts[:2],key=lambda p:sum(x for x,y in p)/len(p))
 assert len(parts)==3,len(parts)
 return parts

fields=[];face=[];details=[];costs=[]
fur=np.array([16,17,20],dtype=float)
for i,key in enumerate(keys):
 rgba=np.asarray(key).astype(float);mask=rgba[:,:,3]>=128
 fields.append(sdf(mask))
 marks=[]
 for part in components((rgba[:,:,:3].min(2)>180)&(rgba[:,:,3]>200)):
  cx=round(sum(x for x,y in part)/len(part));cy=round(sum(y for x,y in part)/len(part))
  local=np.zeros((48,48),bool)
  for x,y in part:
   lx=x-cx+24;ly=y-cy+24
   assert 0<=lx<48 and 0<=ly<48
   local[ly,lx]=True
  marks.append((np.array([cx,cy],dtype=float),sdf(local)))
 face.append(marks)
 # Fine body creases stay low contrast; white glyphs are rendered once below.
 detail=np.clip(rgba[:,:,:3]-fur,0,45)
 detail[(rgba[:,:,:3].min(2)>100)]=0
 details.append(detail)
 if i:
  band=(abs(fields[i-1])<8)|(abs(fields[i])<8)
  costs.append(float(np.mean(np.minimum(abs(fields[i]-fields[i-1]),40)[band])))
 print(f'Prepared field {i}',flush=True)

frames=[keys[0]]
for i in range(17):
 for sub in range(1,SAMPLES+1):
  t=sub/SAMPLES
  if sub==SAMPLES:im=keys[i+1]
  else:
   field=fields[i]*(1-t)+fields[i+1]*t
   alpha=np.clip(.5-field/1.5,0,1)
   # Preserve one opaque silhouette. Detached fragments from disoccluding
   # tails are removed; intermediate fur stays flat to avoid doubled creases.
   pending=set(zip(*np.where(alpha>.5)));largest=[]
   while pending:
    queue=[pending.pop()];part=[]
    while queue:
     yy,xx=queue.pop();part.append((yy,xx))
     for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
      q=(yy+dy,xx+dx)
      if q in pending:pending.remove(q);queue.append(q)
    if len(part)>len(largest):largest=part
   keep=np.zeros((384,416),np.uint8)
   for yy,xx in largest:keep[yy,xx]=255
   keep=np.asarray(Image.fromarray(keep).filter(ImageFilter.MaxFilter(3)))/255
   alpha=alpha*keep
   rgb=np.broadcast_to(fur,(384,416,3)).copy()
   for (ca,da),(cb,db) in zip(face[i],face[i+1]):
    center=ca*(1-t)+cb*t;glyph=np.clip(.5-(da*(1-t)+db*t)/1.5,0,1)
    x,y=np.rint(center-24).astype(int)
    rgb[y:y+48,x:x+48]=rgb[y:y+48,x:x+48]*(1-glyph[:,:,None])+255*glyph[:,:,None]
   im=Image.fromarray(np.uint8(np.dstack([np.clip(rgb,0,255),alpha*255])))
  frames.append(im)
assert len(frames)==COUNT
for i,im in enumerate(frames):
 bbox=im.getbbox();assert bbox and bbox[0]>0 and bbox[1]>0 and bbox[2]<416 and bbox[3]<384
 im.save(output/f'{i:02}.png')
weights=np.clip(np.array(costs),2,24);weights=np.round(weights,3)
manifest={'frames':COUNT,'samples_per_interval':SAMPLES,'weights':weights.tolist(),
 'method':'Signed-distance silhouette and separately aligned facial glyph interpolation; original Gemini poses at every sixteenth frame',
 'sha256':[hashlib.sha256((output/f'{i:02}.png').read_bytes()).hexdigest() for i in range(COUNT)]}
(root/'dense-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('WEIGHTS',weights.tolist(),flush=True)
board=Image.new('RGB',(1248,960),'#f4f2ed');d=ImageDraw.Draw(board);font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',16)
for i,n in enumerate([0,6,12,16,17,18,19,20,24,28,31,32,36,40,44,48,52,56,60,64,66,67,68]):
 x=i%6*208;y=i//6*240;d.text((x+8,y+8),str(n*4),font=font,fill='#252526')
 im=frames[n*4].resize((208,192),Image.Resampling.LANCZOS);board.paste(im,(x,y+30),im)
board.save(root/'高幀影格檢視.png')
print(f'Generated {COUNT} opaque dense frames; original key poses retained.',flush=True)
