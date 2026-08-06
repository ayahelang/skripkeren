document.addEventListener("DOMContentLoaded",()=>{

document.querySelectorAll(".copy-btn").forEach(btn=>{
btn.addEventListener("click",()=>{
const code=btn.parentElement.innerText.replace("Copy","").trim();
navigator.clipboard.writeText(code).then(()=>{
const old=btn.innerText;
btn.innerText="Copied!";
setTimeout(()=>{
btn.innerText=old;
},1500);
});
});
});

const splash=document.getElementById("repoSplash");
const input=document.getElementById("repoInput");
const result=document.getElementById("repoResult");
const status=document.getElementById("repoStatus");
const thumb=document.getElementById("repoThumb");
const link=document.getElementById("repoLink");

const btnConvert=document.getElementById("btnConvert");
const btnCopy=document.getElementById("btnCopyResult");
const btnOpen=document.getElementById("btnOpenResult");
const btnClose=document.getElementById("btnCloseSplash");

let pagesURL="";

window.addEventListener("load",()=>{
setTimeout(()=>{
splash.classList.add("show");
input.focus();
},3000);
});

btnClose.addEventListener("click",()=>{
splash.classList.remove("show");
});

splash.addEventListener("click",e=>{
if(e.target===splash){
splash.classList.remove("show");
}
});

document.addEventListener("keydown",e=>{
if(e.key==="Escape"){
splash.classList.remove("show");
}
});

btnConvert.addEventListener("click",convertRepo);

input.addEventListener("keydown",e=>{
if(e.key==="Enter"){
convertRepo();
}
});

btnCopy.addEventListener("click",()=>{

if(!pagesURL){
alert("Belum ada hasil.");
return;
}

navigator.clipboard.writeText(pagesURL).then(()=>{
const old=btnCopy.innerText;
btnCopy.innerText="Copied!";
setTimeout(()=>{
btnCopy.innerText=old;
},1500);
});

});

btnOpen.addEventListener("click",()=>{

if(!pagesURL){
alert("Belum ada hasil.");
return;
}

window.open(pagesURL,"_blank");

});

function convertRepo(){

const url=input.value.trim();

const match=url.match(/github\.com\/([^\/]+)\/([^\/?#]+)/i);

if(!match){

status.innerHTML="<span style='color:#dc2626'>❌ URL Repository tidak valid.</span>";

result.innerHTML="";

thumb.style.display="none";

return;

}

const username=match[1];

const repo=match[2].replace(/\.git$/i,"");

pagesURL=`https://${username}.github.io/${repo}/`;

status.innerHTML="<span style='color:#2563eb'>🔄 Membuat URL GitHub Pages...</span>";

result.innerHTML=
`<a href="${pagesURL}" target="_blank">${pagesURL}</a>`;

link.href=pagesURL;

thumb.onload=()=>{

thumb.style.display="block";

status.innerHTML="<span style='color:#16a34a'>✅ Preview berhasil dimuat.</span>";

};

thumb.onerror=()=>{

thumb.style.display="none";

status.innerHTML="<span style='color:#ea580c'>⚠️ Thumbnail belum tersedia. Website mungkin belum aktif.</span>";

};

thumb.src=
"https://s.wordpress.com/mshots/v1/"+encodeURIComponent(pagesURL)+"?w=1280&h=720";

fetch("https://api.github.com/repos/"+username+"/"+repo)
.then(r=>{

if(!r.ok)throw new Error();

return r.json();

})
.then(data=>{

status.innerHTML=
`
<div>
<b>Repository ditemukan</b><br>
⭐ ${data.stargazers_count} |
🍴 ${data.forks_count}<br>
📝 ${data.description??"-"}
</div>
`;

})
.catch(()=>{

});

}

});
