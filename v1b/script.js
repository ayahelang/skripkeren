"use strict";

document.addEventListener("DOMContentLoaded",()=>{

const $=e=>document.querySelector(e);

const $$=e=>document.querySelectorAll(e);

let pagesURL="";

let previewTimer=null;

const splash=$("#repoSplash");

const input=$("#repoInput");

const result=$("#repoResult");

const status=$("#repoStatus");

const link=$("#repoLink");

const viewer=$("#repoViewerWrap");

const frame=$("#repoFrame");

const browserAddress=$("#browserAddress");

const browserStatus=$("#browserStatus");

const btnConvert=$("#btnConvert");

const btnCopy=$("#btnCopyResult");

const btnOpen=$("#btnOpenResult");

const btnReload=$("#btnReload");

const btnClose=$("#btnCloseSplash");

$$(".copy-btn").forEach(btn=>{

btn.addEventListener("click",()=>{

const txt=btn.parentElement.innerText.replace("Copy","").trim();

navigator.clipboard.writeText(txt).then(()=>{

const old=btn.innerText;

btn.innerText="Copied!";

setTimeout(()=>{

btn.innerText=old;

},1500);

});

});

});

window.addEventListener("load",()=>{

setTimeout(()=>{

if(splash){

splash.classList.add("show");

}

},3000);

});

if(btnClose){

btnClose.addEventListener("click",()=>{

splash.classList.remove("show");

});

}

if(splash){

splash.addEventListener("click",e=>{

if(e.target===splash){

splash.classList.remove("show");

}

});

}

document.addEventListener("keydown",e=>{

if(e.key==="Escape"&&splash.classList.contains("show")){

splash.classList.remove("show");

}

});

if(input){

input.addEventListener("keydown",e=>{

if(e.key==="Enter"){

convertRepo();

}

});

}

if(btnConvert){

btnConvert.addEventListener("click",convertRepo);

}

if(btnCopy){

btnCopy.addEventListener("click",copyResult);

}

if(btnOpen){

btnOpen.addEventListener("click",openResult);

}

if(btnReload){

btnReload.addEventListener("click",reloadPreview);

}
