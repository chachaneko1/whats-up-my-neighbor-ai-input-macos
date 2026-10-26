import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import crypto from 'node:crypto';
import {WebSocketServer} from 'ws';
const root = path.dirname(fileURLToPath(import.meta.url));
const token = crypto.randomBytes(24).toString('hex');
const vncPort = 15927;
const parentPID = process.ppid;
let ssh, server, stopping = false;
const sockets = new Set();
function report(event, extra={}) { process.stdout.write(JSON.stringify({event,...extra})+'\n'); }
function stop() {
  if(stopping)return; stopping=true;
  for(const s of sockets)s.destroy?.();
  server?.close(); ssh?.kill('SIGTERM');
  setTimeout(()=>process.exit(0),500).unref();
}
process.on('SIGTERM',stop); process.on('SIGINT',stop);
setInterval(()=>{if(process.ppid!==parentPID)stop();},1000).unref();
async function freePort() { await new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',reject);s.listen(vncPort,'127.0.0.1',()=>s.close(resolve));}); }
// Check only the local listener. Never create an unauthenticated VNC probe.
async function localForwardReady() {
 return new Promise((resolve,reject)=>{
  const listener=net.createServer();
  listener.once('error',error=>error.code==='EADDRINUSE'?resolve(true):reject(error));
  listener.listen(vncPort,'127.0.0.1',()=>listener.close(()=>resolve(false)));
 });
}
try {
 await freePort();
 ssh=spawn('/usr/bin/ssh',['-N','-T','-n','-a','-x','-o','BatchMode=yes','-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no','-o','StrictHostKeyChecking=yes','-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=10','-o','ConnectionAttempts=1','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=2','-o','ControlMaster=no','-o','ControlPath=none','-o','ControlPersist=no','-o','ForkAfterAuthentication=no','-o','PermitLocalCommand=no','-o','RemoteCommand=none','-o','ForwardAgent=no','-o','ForwardX11=no','-L',`127.0.0.1:${vncPort}:127.0.0.1:5901`,'--','neighbor-vps'],{stdio:'ignore'});
 ssh.on('error',()=>{report('error',{message:'無法啟動安全連線'});stop();});
 ssh.on('exit',()=>{if(!stopping){report('error',{message:'SSH 通道已中斷，請重新連線'});stop();}});
 let ready=false;
 for(let i=0;i<25&&!stopping;i++){if(await localForwardReady()){ready=true;break;}await new Promise(r=>setTimeout(r,400));}
 if(!ready)throw new Error('安全通道未就緒，請檢查連線後重試');
 const base=`/${token}/`;
 server=http.createServer(async(req,res)=>{
   const host=`127.0.0.1:${server.address().port}`;
   if(req.headers.host!==host){res.writeHead(403);res.end();return;}
   if(req.method!=='GET'||!req.url.startsWith(base)){res.writeHead(404);res.end();return;}
   const relative=req.url.slice(base.length).split('?')[0];
   let file;
   if(relative==='')file=path.join(root,'index.html');
   else if(relative==='client.js')file=path.join(root,'client.js');
   else if(/^novnc\/(core|vendor)\/[a-zA-Z0-9_/.-]+\.js$/.test(relative)&&!relative.includes('..'))file=path.join(root,'node_modules/@novnc/novnc',relative.slice(6));
   else {res.writeHead(404);res.end();return;}
   try{const data=await fs.readFile(file);res.writeHead(200,{'Content-Type':file.endsWith('.html')?'text/html; charset=utf-8':'text/javascript; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://"+host+"; img-src 'self' data:; frame-ancestors 'none'; form-action 'none'"});res.end(data);}catch{res.writeHead(404);res.end();}
 });
 const wss=new WebSocketServer({noServer:true,maxPayload:4*1024*1024,perMessageDeflate:false});
 server.on('upgrade',(req,socket,head)=>{
   const origin=`http://127.0.0.1:${server.address().port}`;
   if(req.url!==`${base}vnc`||req.headers.origin!==origin){socket.destroy();return;}
   wss.handleUpgrade(req,socket,head,ws=>{
     const tcp=net.connect(vncPort,'127.0.0.1');sockets.add(tcp);
     tcp.on('data',data=>{if(ws.readyState===1)ws.send(data,{binary:true});});
     ws.on('message',data=>tcp.write(data));
     tcp.on('error',()=>ws.close());tcp.on('close',()=>{sockets.delete(tcp);ws.close();});
     ws.on('close',()=>tcp.destroy());ws.on('error',()=>tcp.destroy());
   });
 });
 server.listen(0,'127.0.0.1',()=>report('ready',{url:`http://127.0.0.1:${server.address().port}${base}`}));
}catch(e){report('error',{message:e.code==='EADDRINUSE'?'預覽連線埠已被使用，請關閉舊預覽後重試':e.message});stop();}
