"""Slice Gemini's directly drawn in-betweens. No crossfades or redraws."""
from pathlib import Path
from PIL import Image, ImageFilter, ImageChops, ImageDraw, ImageFont
import json,hashlib
root=Path(__file__).resolve().parent
sheet=Image.open(root/'gemini-inbetweens.png').convert('RGB')
out=root/'Frames';out.mkdir(exist_ok=True)
records=[];generated=[]
def parts(mask):
    unvisited=set(mask);result=[]
    while unvisited:
        todo=[unvisited.pop()];group=[]
        while todo:
            x,y=todo.pop();group.append((x,y))
            for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                q=(x+dx,y+dy)
                if q in unvisited:unvisited.remove(q);todo.append(q)
        result.append(group)
    return result

def native(im):
    result=Image.new('RGBA',(416,384))
    result.alpha_composite(im.resize((418,418),Image.Resampling.LANCZOS),(-1,30))
    bbox=result.getbbox()
    assert bbox and bbox[0]>2 and bbox[1]>2 and bbox[2]<414 and bbox[3]<382,bbox
    return result

for i in range(16):
    cell=sheet.crop((i%4*256,i//4*256,(i%4+1)*256,(i//4+1)*256))
    rgba=Image.new('RGBA',(256,256));pixels=[]
    for r,g,b in cell.get_flattened_data():
        a=max(0,min(255,255-max(0,min(r,b)-g)))
        if a<12:pixels.append((0,0,0,0));continue
        t=a/255
        pixels.append((round(max(0,min(255,(r-(1-t)*255)/t))),round(max(0,min(255,g/t))),round(max(0,min(255,(b-(1-t)*255)/t))),a))
    rgba.putdata(pixels)
    alpha=rgba.getchannel('A');ap=alpha.load()
    group=max(parts((x,y) for y in range(256) for x in range(256) if ap[x,y]>=32),key=len)
    keep=Image.new('L',(256,256));k=keep.load()
    for x,y in group:k[x,y]=255
    rgba.putalpha(ImageChops.multiply(alpha,keep.filter(ImageFilter.MaxFilter(3))))
    bbox=rgba.getbbox();p=rgba.load()
    whites=parts((x,y) for y in range(256) for x in range(256) if min(p[x,y][:3])>200 and p[x,y][3]>220)
    marks=[g for g in whites if len(g)>8]
    marks.sort(key=lambda g:len(g),reverse=True);marks=marks[:3]
    assert len(marks)==3,(i,len(marks))
    marks.sort(key=lambda g:sum(y for x,y in g)/len(g))
    eye_x=sum(sum(x for x,y in g)/len(g) for g in marks[:2])/2
    head_span=max(y for x,y in marks[2])-bbox[1]
    scale=150/head_span
    normalized=Image.new('RGBA',(640,640))
    offset=(round(320-eye_x*scale),round(42-bbox[1]*scale))
    normalized.alpha_composite(rgba.resize((round(256*scale),round(256*scale)),Image.Resampling.LANCZOS),offset)
    generated.append(native(normalized))
    records.append({'cell':i+1,'scale':scale,'offset':offset})

# Gemini put one seated transition between two hanging cells. Reorder that
# source cell before takeoff. All generated cells remain traceable here.
order=[1,2,3,6,4,7,8,9,5,10,11,13,12,14,15,16]
canonical=native(Image.open(root/'canonical.png').convert('RGBA'))
frames=[canonical]+[generated[n-1] for n in order]+[canonical]
for i,im in enumerate(frames):im.save(out/f'{i:02}.png')
board=Image.new('RGB',(1248,720),'#f4f2ed');d=ImageDraw.Draw(board)
font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',16)
previews=[]
for i,im in enumerate(frames):
    x=i%6*208;y=i//6*240;d.text((x+8,y+8),str(i),fill='#252526',font=font)
    small=im.resize((208,192),Image.Resampling.LANCZOS);board.paste(small,(x,y+30),small)
    bg=Image.new('RGB',im.size,'#f4f2ed');bg.paste(im,(0,0),im);previews.append(bg)
board.save(root/'原生影格總覽.png')
previews[0].save(root/'補畫動作.gif',save_all=True,append_images=previews[1:],duration=[400]+[55]*7+[650]+[40]*8+[400],loop=0,disposal=2)
(root/'frame-manifest.json').write_text(json.dumps({'frames':18,'carry_frame':8,'landing_frame':17,'size':[416,384],
 'source_sha256':hashlib.sha256((root/'gemini-inbetweens.png').read_bytes()).hexdigest(),
 'method':'16 directly generated Gemini in-betweens; chroma key, connected matte, uniform scale and face anchoring; canonical idle endpoints',
 'source_order':order,'alignment':records,
 'sha256':[hashlib.sha256((out/f'{i:02}.png').read_bytes()).hexdigest() for i in range(18)]},indent=2)+'\n')
print('Sliced 16 Gemini in-betweens with canonical endpoints; 18 PNGs validated, carry=8, landing=17.')
