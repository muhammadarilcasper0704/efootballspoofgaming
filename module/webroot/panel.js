const buttons=[...document.querySelectorAll('button')];
const fields=['device','cpu','gpu'].map(id=>document.getElementById(id));
const out=document.getElementById('out');
function run(action) {
  if (!window.ksu?.exec){out.textContent='Buka melalui WebUI yang mendukung ksu.exec.';return;}
  buttons.forEach(b=>b.disabled=true);
  const cb='aril_'+Date.now();
  const done=msg=>{out.textContent=msg;delete window[cb];buttons.forEach(b=>b.disabled=false)};
  const timer=setTimeout(()=>done('Belum ada respons. Tekan Periksa status sebelum mengulangi.'),20000);
  window[cb]=(code,stdout,stderr)=>{
    clearTimeout(timer);
    const msg=Number(code)===0?String(stdout||'Selesai.'):String(stderr||'Operasi gagal.');
    const selected=msg.match(/(?:GPU: |tersimpan: )([01]{3})/);
    if(selected)fields.forEach((f,i)=>f.checked=selected[1][i]==='1');
    done(msg);
  };
  try{window.ksu.exec('sh /data/adb/modules/aril_efo_personal/ctl.sh '+action,'{}',cb);}
  catch(e){clearTimeout(timer);done(e.message);}
}
buttons.forEach(b=>b.onclick=()=>run(b.id==='on'?'set '+fields.map(f=>Number(f.checked)).join(''):b.id==='off'?'set 000':b.id));
run('status');
