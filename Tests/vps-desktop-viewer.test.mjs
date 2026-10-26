import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
function fixture() {
 const nodes=new Map();
 for(const name of ['screen','login','password','username','message','submit'])nodes.set('#'+name,{value:'',hidden:false,disabled:true,handlers:{},addEventListener(e,f){this.handlers[e]=f;},focus(){this.focused=true;}});
 let rfb, connections=0, sent=0;const events=[];
 class RFB {constructor(screen,url,options){rfb=this;connections++;assert.equal(options.credentials.password,'test-only');this.handlers={};}addEventListener(e,f){this.handlers[e]=f;}sendCredentials(){sent++;}}
 const context={RFB,document:{querySelector:s=>nodes.get(s)},window:{webkit:{messageHandlers:{connection:{postMessage:e=>events.push(e)}}}},URL,location:{href:'http://127.0.0.1:1/test/'}};
 vm.runInNewContext(fs.readFileSync(new URL('../Resources/VPSDesktop/client.js',import.meta.url),'utf8').replace(/^import .*?;\n/,''),context);
 return {nodes,events,get connections(){return connections;},get sent(){return sent;},fire:(event,detail={})=>rfb.handlers[event]({detail}),submit(){nodes.get('#login').handlers.submit({preventDefault(){}});},fill(){nodes.get('#password').value='test-only';nodes.get('#password').handlers.input();}};
}
test('waiting or submitting empty password never opens a VNC connection',()=>{
 const f=fixture();assert.equal(f.connections,0);assert.equal(f.nodes.get('#submit').disabled,true);f.submit();
 assert.equal(f.connections,0);assert.equal(f.sent,0);assert.equal(f.nodes.get('#login').hidden,false);assert.deepEqual(f.events,['credentials']);
});
test('nonempty submission opens exactly one connection and blocks double submit',()=>{
 const f=fixture();f.fill();assert.equal(f.nodes.get('#submit').disabled,false);f.submit();f.submit();
 assert.equal(f.connections,1);assert.equal(f.nodes.get('#password').value,'');assert.equal(f.nodes.get('#submit').disabled,true);assert.equal(f.events.at(-1),'authenticating');
});
test('unexpected disconnect presents recovery without automatic retry',()=>{
 const f=fixture();f.fill();f.submit();f.fire('disconnect');
 assert.equal(f.events.at(-1),'disconnected');assert.match(f.nodes.get('#message').textContent,/重新連線並登入/);assert.equal(f.connections,1);assert.equal(f.nodes.get('#submit').disabled,true);
});
test('temporary server restriction stays distinct from incorrect password',()=>{
 const f=fixture();f.fill();f.submit();f.fire('securityfailure',{reason:'Too many security failures'});f.fire('disconnect');
 assert.deepEqual(f.events.slice(-2),['blocked','disconnected']);assert.match(f.nodes.get('#message').textContent,/暫時限制登入/);assert.equal(f.connections,1);
});
test('only server connect event marks authenticated desktop',()=>{
 const f=fixture();f.fill();f.submit();assert.equal(f.events.includes('connected'),false);f.fire('connect');assert.equal(f.events.at(-1),'connected');assert.equal(f.nodes.get('#login').hidden,true);
});
