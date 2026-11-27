document.addEventListener("DOMContentLoaded",()=>{
  document.querySelectorAll(".copy-btn").forEach(btn=>{
    btn.addEventListener("click",e=>{
      e.preventDefault();
      e.stopPropagation();
      const pre=btn.closest("pre")||btn.parentElement;
      const text=(pre.innerText||pre.textContent||"").replace(/^\s*Copy\s*/i,"").trim();
      navigator.clipboard.writeText(text).then(()=>{
        const old=btn.innerText;
        btn.innerText="Copied!";
        setTimeout(()=>{btn.innerText=old;},1500);
      }).catch(()=>{
        // fallback
        const ta=document.createElement("textarea");
        ta.value=text;document.body.appendChild(ta);ta.select();
        try{document.execCommand("copy");btn.innerText="Copied!";}catch(_){}
        document.body.removeChild(ta);
        setTimeout(()=>{btn.innerText="Copy";},1500);
      });
    });
  });

  // prevent summary click on nested controls only; details stay collapsed by default
  const b=document.getElementById("autoDeps");
  if(b){
    b.style.transition="box-shadow .6s ease";
    setTimeout(()=>{
      b.style.boxShadow="0 0 0 3px rgba(11,110,79,.25)";
      setTimeout(()=>{b.style.boxShadow="none";},1800);
    },600);
  }
});
