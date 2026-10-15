import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, DownloadSimple, MagnifyingGlass, Plus, Play, ArrowClockwise, Check, X, BookOpen, Waveform, CaretRight, Trash, CircleNotch } from '@phosphor-icons/react';
import { GIFEncoder, quantize, applyPalette } from 'gifenc';

const ASSET = './assets/neko-base.png';
const W = 1774, H = 887;
const initialWords = [
  {id:'1', word:'YUI Neko', original:'有一 Neko', enabled:true},
  {id:'2', word:'Groq', original:'Grok', enabled:true},
  {id:'3', word:'Obsidian', original:'歐布西典', enabled:true},
  {id:'4', word:'Hugging Face', original:'黑金費斯', enabled:false},
];
const initialCandidates = [
  {id:'c1', word:'有一策略', original:'有意策略', enabled:true},
  {id:'c2', word:'語音輸入', original:'語音書入', enabled:true},
];
let loadedImage;
function getImage() {
  if (!loadedImage) loadedImage = new Promise((resolve, reject) => {
    const img = new Image(); img.onload = () => resolve(img); img.onerror = reject; img.src = ASSET;
  });
  return loadedImage;
}
function renderCat(ctx, img, t, state, volume=0.65, reduce=false) {
  ctx.clearRect(0,0,W,H);
  ctx.fillStyle = '#161616';
  const speaking = state === 'listening';
  for (let i=0; speaking && volume > 0 && i<11; i++) {
    const envelope = Math.sin((i+1)/12 * Math.PI);
    const oscillation = reduce ? 0.55 : (0.55 + 0.22*Math.sin(t*3.6-i*.65) + 0.18*Math.sin(t*6.1-i*.38));
    const height = volume * (35 + envelope*205) * oscillation;
    ctx.beginPath();
    ctx.roundRect(551+i*62, 385-height, 43, height+12, [22,22,0,0]); ctx.fill();
  }
  ctx.drawImage(img,0,0,W,H);
}
function Cat({state='ready', volume=.65, reduced=false, interactive=false, onCancel, onFinish, className=''}) {
  const canvas = useRef(null);
  useEffect(() => {
    let frame, stopped=false;
    getImage().then(img => {
      const context=canvas.current?.getContext('2d'); if(!context || stopped) return;
      const tick=t=>{ if(stopped) return; renderCat(context,img,t/1000,state,volume,reduced);
        if(state==='listening' && !reduced && !document.hidden) frame=requestAnimationFrame(tick);
      };
      tick(0);
      const restart=()=>{cancelAnimationFrame(frame);tick(performance.now());};
      document.addEventListener('visibilitychange',restart);
      canvas.current._cleanup=()=>document.removeEventListener('visibilitychange',restart);
    });
    return ()=>{stopped=true;cancelAnimationFrame(frame);canvas.current?._cleanup?.();};
  },[state,volume,reduced]);
  const active=state==='listening';
  return <div className={'cat '+className} data-reduced-motion={reduced}>
    <canvas ref={canvas} width={W} height={H} role="img" aria-label="黑色貓頭，耳間音量波形，左眼叉號、右眼勾號"/>
    {interactive&&<>
      <button className="eye eye-cancel" aria-label={state==='processing'?'取消處理示意':'取消錄音示意'} onClick={onCancel} disabled={!active&&state!=='processing'}>
        <span className="eye-tooltip" aria-hidden="true">{state==='processing'?'取消處理':'取消錄音'}</span>
      </button>
      <button className="eye eye-confirm" aria-label="結束錄音並辨識示意" onClick={onFinish} disabled={!active}>
        <span className="eye-tooltip" aria-hidden="true">完成錄音</span>
      </button>
    </>}
  </div>;
}
function Toggle({checked,onChange,label}) {return <button className={'toggle '+(checked?'on':'')} role="switch" aria-checked={checked} aria-label={label} onClick={()=>onChange(!checked)}><span/></button>}
const stateText={ready:'準備好了，慢慢說。',listening:'正在聽你說',processing:'正在辨識…',success:'示意文字已就緒',cancelled:'這次先不說了。',unclear:'未清楚辨識到語音',error:'暫時無法連線'};
const stateHint={ready:'開始示意後，試試貓咪的兩隻眼睛。',listening:'耳間的起伏，是聲音的表情。',processing:'示意處理中，聲波已停止。',success:'這是預設示意內容，沒有實際轉錄。',cancelled:'隨時都可以再開始。',unclear:'可以靠近麥克風，再說一次。',error:'檢查網路後，再試一次。'};

export function App() {
  const [tab,setTab]=useState('voice'),[state,setState]=useState('ready'),[volume,setVolume]=useState(.65);
  const [reduced,setReduced]=useState(()=>window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const [size,setSize]=useState('large'),[seconds,setSeconds]=useState(0),[outcome,setOutcome]=useState('success');
  const [exporting,setExporting]=useState(false),[exportProgress,setExportProgress]=useState(0),[exportError,setExportError]=useState('');
  const [gifUrl,setGifUrl]=useState('');
  const timeout=useRef(null), transaction=useRef(0);
  const [words,setWords]=useState(initialWords),[candidates,setCandidates]=useState(initialCandidates);
  const [filter,setFilter]=useState('words'),[query,setQuery]=useState(''),[selected,setSelected]=useState('1');
  const [draft,setDraft]=useState(initialWords[0]),[dirty,setDirty]=useState(false),[message,setMessage]=useState('');
  const [error,setError]=useState(''),[deleteOpen,setDeleteOpen]=useState(false),[pendingSelection,setPendingSelection]=useState(null);
  useEffect(()=>{if(state!=='listening') return;const id=setInterval(()=>setSeconds(s=>s+1),1000);return()=>clearInterval(id);},[state]);
  useEffect(()=>()=>{clearTimeout(timeout.current);if(gifUrl)URL.revokeObjectURL(gifUrl)},[gifUrl]);
  const start=()=>{clearTimeout(timeout.current);transaction.current++;setSeconds(0);setState('listening');};
  const cancel=()=>{clearTimeout(timeout.current);transaction.current++;setState('cancelled');};
  const finish=()=>{const token=++transaction.current;setState('processing');timeout.current=setTimeout(()=>{if(token===transaction.current)setState(outcome)},1100)};
  const changeTab=next=>{if(next==='dictionary'&&(state==='listening'||state==='processing'))cancel();setTab(next)};
  const collection=filter==='words'?words:candidates;
  const choose=(item)=>{setSelected(item?.id??null);setDraft(item?{...item}:{id:null,word:'',original:'',enabled:true});setDirty(false);setError('');setMessage('')};
  const attemptChoose=item=>{if(dirty){setPendingSelection({item});return;}choose(item)};
  const changeFilter=f=>{if(dirty){setPendingSelection({filter:f});return;}setFilter(f);setQuery('');choose((f==='words'?words:candidates)[0]??null)};
  const proceedSelection=()=>{const next=pendingSelection;setPendingSelection(null);if(next.filter){setFilter(next.filter);setQuery('');choose((next.filter==='words'?words:candidates)[0]??null)}else choose(next.item)};
  const update=(key,value)=>{setDraft(d=>({...d,[key]:value}));setDirty(true);setError('');setMessage('')};
  function save(accept=false){
    const word=draft.word.trim();
    if(!word){setError('請輸入詞條。');return;}
    if([...word].length>40){setError('詞條最多 40 個字。');return;}
    const duplicates=(accept?words:collection).some(w=>w.word.toLocaleLowerCase()===word.toLocaleLowerCase()&&w.id!==draft.id);
    if(duplicates){setError('這個詞條已經存在。');return;}
    const item={...draft,word,id:draft.id??crypto.randomUUID()};
    if(accept){setCandidates(c=>c.filter(w=>w.id!==draft.id));setWords(w=>[...w,item]);setFilter('words');setQuery('');setMessage('已確認加入示意字典。')}
    else if(filter==='words'){setWords(w=>w.some(x=>x.id===item.id)?w.map(x=>x.id===item.id?item:x):[...w,item]);setMessage('變更已儲存在本次示意。')}
    else{setCandidates(w=>w.map(x=>x.id===item.id?item:x));setMessage('候選已儲存，仍等待確認。')}
    setDraft(item);setSelected(item.id);setDirty(false);setError('');
  }
  function remove(){const remaining=collection.filter(w=>w.id!==selected);if(filter==='words')setWords(remaining);else setCandidates(remaining);choose(remaining[0]??null);setDeleteOpen(false);setMessage(filter==='words'?'詞條已從本次示意移除。':'已拒絕這個候選。');}
  async function exportGif(){
    setExporting(true);setExportProgress(0);setExportError('');
    try{
      const image=await getImage();
      const canvas=document.createElement('canvas');canvas.width=800;canvas.height=520;
      const ctx=canvas.getContext('2d',{willReadFrequently:true});
      const layer=document.createElement('canvas');layer.width=W;layer.height=H;const lc=layer.getContext('2d');
      const gif=GIFEncoder();const count=60;
      for(let i=0;i<count;i++){
        const t=i/10,phase=t<.8?'ready':t<4.7?'listening':'success';
        renderCat(lc,image,t,phase,.8,false);
        ctx.fillStyle='#f8f7f3';ctx.fillRect(0,0,800,520);
        ctx.fillStyle='#1c211e';ctx.font='600 25px -apple-system, sans-serif';ctx.textAlign='left';ctx.fillText('YUI Neko',46,56);
        ctx.font='12px -apple-system, sans-serif';ctx.fillStyle='#686e65';ctx.fillText('LIVING SIGNAL',46,80);
        ctx.drawImage(layer,60,97,680,340);
        ctx.textAlign='center';ctx.font='500 18px -apple-system, sans-serif';ctx.fillStyle='#242b25';
        ctx.fillText(phase==='ready'?'準備聆聽':phase==='listening'?'正在聽你說':'示意完成',400,438);
        ctx.fillStyle='#686e65';ctx.font='12px -apple-system, sans-serif';ctx.fillText('動態設計展示 · 模擬音量 · 未連接辨識服務',400,478);
        const data=ctx.getImageData(0,0,800,520).data,palette=quantize(data,128);
        gif.writeFrame(applyPalette(data,palette),800,520,{palette,delay:100,repeat:0});
        if(i%3===0){setExportProgress(Math.round((i+1)/count*100));await new Promise(r=>setTimeout(r,0));}
      }
      gif.finish();const blob=new Blob([gif.bytes()],{type:'image/gif'});
      if(gifUrl)URL.revokeObjectURL(gifUrl);const url=URL.createObjectURL(blob);setGifUrl(url);
      const anchor=document.createElement('a');anchor.href=url;anchor.download='yui-neko-living-signal-demo.gif';anchor.click();
      setExportProgress(100);
    }catch(e){setExportError('動態圖未完成匯出，請稍後再試。');console.error(e)}
    finally{setExporting(false)}
  }
  const visible=collection.filter(w=>(w.word+' '+w.original).toLocaleLowerCase().includes(query.toLocaleLowerCase()));
  return <div className="shell">
    <header className="topbar">
      <a className="brand" href="#voice" onClick={e=>{e.preventDefault();changeTab('voice')}}><img src={ASSET} alt=""/><span>YUI Neko</span></a>
      <nav aria-label="預覽畫面"><button className={tab==='voice'?'active':''} onClick={()=>changeTab('voice')}><Waveform size={18}/>語音浮窗</button><button className={tab==='dictionary'?'active':''} onClick={()=>changeTab('dictionary')}><BookOpen size={18}/>個人字典</button></nav>
      <span className="preview-tag">設計預覽</span>
    </header>
    {tab==='voice'?<main className="voice-page">
      <div className="page-heading"><div><p className="eyebrow">LIVING SIGNAL</p><h1>一點聲音，一點貓的表情。</h1><p className="subtitle">兩隻耳朵之間，讓聲音輕輕流動。</p></div><button className="text-action export-top" onClick={exportGif} disabled={exporting}><DownloadSimple size={18}/>{exporting?'匯出中 '+exportProgress+'%':'匯出動態 GIF'}</button></div>
      <div className="voice-grid">
        <section className="demo-stage" aria-label="語音浮窗互動展示">
          <div className="stage-toolbar"><span><span className={'dot '+(state==='listening'?'live':'')}/>{state==='listening'?String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0'):'互動示意'}</span><div className="size-switch" aria-label="預覽大小"><button className={size==='large'?'chosen':''} onClick={()=>setSize('large')}>放大檢視</button><button className={size==='actual'?'chosen':''} onClick={()=>setSize('actual')}>實際尺寸</button></div></div>
          <div className={'cat-stage '+(size==='actual'?'actual':'')}><Cat state={state} volume={volume} reduced={reduced} interactive onCancel={cancel} onFinish={finish}/><div className="control-hints"><span>取消</span><span>完成</span></div></div>
          <div className="status-area" aria-live="polite"><h2>{state==='processing'&&<CircleNotch className="spinner" size={20}/>} {stateText[state]}</h2><p>{stateHint[state]}</p></div>
          <div className="demo-action">
            {state==='listening'?<p className="listening-tip">點左眼取消，或點右眼完成。</p>:state==='processing'?<button className="subtle-button" onClick={cancel}>取消處理</button>:<button className="primary" onClick={start}>{state==='ready'?<Play size={17} weight="fill"/>:<ArrowClockwise size={17}/>} {state==='ready'?'開始示意':'再試一次'}</button>}
          </div>
          {state==='success'&&<div className="result-box"><span>示意辨識結果</span><p>明天上午十點，討論 YUI Neko 的設計。</p><small>預設示意文字，未貼入其他 App。</small></div>}
          <p className="simulation-note">模擬音量與辨識結果，未啟用麥克風。</p>
        </section>
        <aside className="tuning-panel"><h2>試試不同的動靜</h2><div className="setting-block"><label htmlFor="volume">說話強度<span>{Math.round(volume*100)}%</span></label><input id="volume" aria-label="模擬說話強度" type="range" min="0" max="1" step=".01" value={volume} onChange={e=>setVolume(+e.target.value)}/><div className="range-labels"><span>輕聲</span><span>清楚有力</span></div></div>
        <div className="setting-block toggle-row"><div><label>減少動態效果</label><p>保留形狀與狀態資訊</p></div><Toggle checked={reduced} onChange={setReduced} label="減少動態效果"/></div>
        <div className="setting-block"><label htmlFor="outcome">完成後的示意情境</label><select id="outcome" value={outcome} onChange={e=>setOutcome(e.target.value)}><option value="success">辨識完成</option><option value="unclear">未清楚辨識到語音</option><option value="error">連線失敗</option></select></div>
        <div className="quiet-note"><p>聲波會動，眼睛不亂跑。</p><span>叉號與勾號保持固定，讓每一次取消、完成都容易操作。</span></div>
        {exportError&&<p className="error" role="alert">{exportError}</p>}
        {gifUrl&&<a className="download-again" href={gifUrl} download="yui-neko-living-signal-demo.gif">再次下載動態 GIF <DownloadSimple size={15}/></a>}
        </aside>
      </div>
      <section className="state-strip" aria-label="設計狀態"><div><Cat state="ready" reduced/><span>安靜時</span><p>收起一點動靜</p></div><div><Cat state="listening" volume={.7} reduced={reduced}/><span>說話時</span><p>聲音在兩耳之間流動</p></div><div><Cat state="success" reduced/><span>完成時</span><p>平順回到安靜</p></div></section>
    </main>:<main className="dictionary-page">
      <div className="page-heading"><div><p className="eyebrow">YOUR WORDS, REMEMBERED</p><h1>個人字典</h1><p className="subtitle">讓常用的名稱，下次更容易被聽懂。</p></div><button className="primary" onClick={()=>{if(filter!=='words'){if(dirty){setPendingSelection({filter:'words'});return;}setFilter('words')}attemptChoose(null)}}><Plus size={18}/>新增詞條</button></div>
      <section className="dictionary-window">
        <div className="dictionary-toolbar"><div className="dictionary-tabs"><button className={filter==='words'?'active':''} onClick={()=>changeFilter('words')}>已加入 <span>{words.length}</span></button><button className={filter==='candidates'?'active':''} onClick={()=>changeFilter('candidates')}>待確認 <span>{candidates.length}</span></button></div><label className="search"><MagnifyingGlass size={18}/><input placeholder="搜尋詞條或原辨識" value={query} onChange={e=>setQuery(e.target.value)} aria-label="搜尋詞條或原辨識"/></label></div>
        <div className="dictionary-body"><div className="word-list"><div className="list-heading">{filter==='words'?'已加入的詞條':'等待你確認的修正'}</div>{visible.length?visible.map(w=><button key={w.id} className={'word-row '+(selected===w.id?'selected':'')} onClick={()=>attemptChoose(w)}><div><strong>{w.word}</strong><span>{filter==='candidates'?w.original+' → '+w.word:w.enabled?'啟用中':'已停用'}</span></div><CaretRight size={17}/></button>):<div className="empty"><p>{query?'沒有符合的詞條':'目前沒有待確認的詞'}</p><small>{query?'換個關鍵字試試。':'你也可以手動新增常用詞。'}</small></div>}</div>
        <div className="word-editor">
          <div className="editor-heading"><h2>{filter==='candidates'?'確認這個詞':selected?'編輯詞條':'新增詞條'}</h2>{dirty&&<span className="unsaved">尚未儲存</span>}</div>
          {filter==='candidates'&&<p className="candidate-explainer">這是一次修正產生的候選，確認後才會加入字典。</p>}
          {draft.original&&<div className="original-field"><label>原辨識</label><p>{draft.original}</p></div>}
          <label className="field-label" htmlFor="word">{filter==='candidates'?'正確詞語':'詞條'}<span>{[...draft.word].length} / 40</span></label>
          <input id="word" className={'word-input '+(error?'invalid':'')} value={draft.word} onChange={e=>update('word',e.target.value)} placeholder="輸入常用名稱" aria-invalid={!!error} aria-describedby={error?'word-error':undefined}/>
          {error&&<p id="word-error" className="error" role="alert">{error}</p>}
          <div className="editor-enabled"><div><label>啟用</label><p>依提示額度選用此詞條</p></div><Toggle label="啟用此詞條" checked={draft.enabled} onChange={v=>update('enabled',v)}/></div>
          <div className="prompt-status"><span className="status-dot"/>{filter==='candidates'?'待確認，尚未用於辨識提示':'尚無實際辨識提示紀錄'}</div>
          <div className="editor-actions"><button className="primary" onClick={()=>save(filter==='candidates')} disabled={filter==='candidates'&&!selected}>{filter==='candidates'?'確認加入':selected?'儲存變更':'加入字典'}<Check size={17}/></button>{filter==='candidates'&&selected&&<button className="subtle-button" onClick={()=>save(false)}>儲存候選</button>}{dirty&&<button className="text-action" onClick={()=>choose(collection.find(w=>w.id===selected)??null)}>取消修改</button>}</div>
          {message&&<p className="feedback" role="status"><Check size={15}/>{message}</p>}
          {selected&&<button className="delete-action" onClick={()=>setDeleteOpen(true)}><Trash size={15}/>{filter==='candidates'?'拒絕候選':'刪除詞條'}</button>}
        </div></div>
        <div className="dictionary-footer"><span>僅供設計試用 · 重新整理會還原</span><span>提供提示不保證辨識命中</span></div>
      </section>
      <p className="dictionary-caption">這裡只編輯示意詞條，不會讀取或更動你目前的字典。</p>
    </main>}
    <footer className="footer"><span>YUI Neko / Living Signal</span><span>把功能，藏進一點貓的表情。</span><span>UI prototype · 2026</span></footer>
    {(deleteOpen||pendingSelection)&&<div className="modal-backdrop"><section className="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><h2 id="dialog-title">{deleteOpen?(filter==='words'?'刪除這個詞條？':'拒絕這個候選？'):'還有未儲存的修改'}</h2><p>{deleteOpen?'這個操作只影響本次示意資料。':'放棄修改後再切換，或繼續編輯。'}</p><div><button autoFocus className="subtle-button" onClick={()=>{setDeleteOpen(false);setPendingSelection(null)}}>繼續編輯</button><button className="primary" onClick={deleteOpen?remove:proceedSelection}>{deleteOpen?'確認移除':'放棄修改並切換'}</button></div></section></div>}
  </div>;
}
