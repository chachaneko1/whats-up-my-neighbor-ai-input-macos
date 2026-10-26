import RFB from './novnc/core/rfb.js';
const screen=document.querySelector('#screen'), login=document.querySelector('#login'), password=document.querySelector('#password'), username=document.querySelector('#username'), message=document.querySelector('#message'), submit=document.querySelector('#submit');
function notify(event){window.webkit?.messageHandlers?.connection?.postMessage(event);}
const url=new URL('vnc',location.href);url.protocol='ws:';
let rfb=null, waitingForPassword=true, failure='';
login.hidden=false;message.textContent='';notify('credentials');
password.addEventListener('input',()=>{submit.disabled=!waitingForPassword || password.value.length===0;});
function start(credentials){
 rfb=new RFB(screen,url.href,{shared:true,credentials});
 rfb.scaleViewport=true;rfb.resizeSession=false;rfb.viewOnly=true;rfb.showDotCursor=true;
 rfb.addEventListener('connect',()=>{waitingForPassword=false;login.hidden=true;message.textContent='';notify('connected');});
 rfb.addEventListener('credentialsrequired',e=>{waitingForPassword=true;login.hidden=false;username.hidden=!e.detail.types.includes('username');submit.disabled=password.value.length===0;password.focus();message.textContent='';notify('credentials');});
 rfb.addEventListener('securityfailure',e=>{
  failure=/too many security failures/i.test(e.detail.reason||'')?'blocked':'authfailed';
  waitingForPassword=false;submit.disabled=true;password.value='';
  message.textContent=failure==='blocked'?'VPS 暫時限制登入，請稍後再試':'密碼驗證失敗，請重新連線後再試';notify(failure);
 });
 rfb.addEventListener('disconnect',()=>{waitingForPassword=false;submit.disabled=true;login.hidden=true;password.value='';username.value='';if(!failure)message.textContent='遠端桌面已中斷，請按「重新連線並登入」';notify('disconnected');});
}
login.addEventListener('submit',e=>{
 e.preventDefault();
 if(!waitingForPassword || password.value.length===0){password.focus();return;}
 waitingForPassword=false;submit.disabled=true;notify('authenticating');
 const credentials={username:username.value,password:password.value};
 password.value='';username.value='';login.hidden=true;message.textContent='正在驗證…';
 if(rfb)rfb.sendCredentials(credentials);else start(credentials);
});
window.setControl=enabled=>{if(rfb){rfb.viewOnly=!enabled;if(enabled)rfb.focus();}};
window.disconnectViewer=()=>rfb?.disconnect();
