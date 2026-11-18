const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function harness({deferProducts=false}={}){
  const nodes=new Map(), calls=[];
  const element=(id)=>{
    if(!nodes.has(id))nodes.set(id,{
      id, hidden:false, value:'', disabled:false, textContent:'',
      children:[],dataset:{},classList:{toggle(){},remove(){},add(){}},
      setAttribute(){},removeAttribute(){},focus(){},scrollIntoView(){},
      append(...els){this.children.push(...els)},
      replaceChildren(...els){this.children=els},
      addEventListener(){}
    });
    return nodes.get(id);
  };
  let resolveProducts;
  const pending=deferProducts?new Promise(resolve=>{resolveProducts=resolve}):null;
  const context=vm.createContext({
    document:{getElementById:element,createElement:tag=>element(tag+'-'+nodes.size),querySelectorAll:()=>[]},
    fetch:async(url)=>{
      calls.push(url);
      let data=[];
      if(url.endsWith('/products')){
        if(pending)await pending;
        data=[{id:'sku-1',sku:'SKU1',name:'Demo',selling_price:'12.00',on_hand:'10',track_stock:true}];
      }
      return {ok:true,status:200,json:async()=>data};
    },
    console,Date,Promise,
    crypto:{randomUUID:()=>'test-operation-id'},
    confirm:()=>true,
    window:{print(){}},
    FormData:class{constructor(){this.fields={}}get(){return null}has(){return false}}
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname,'app.js'),'utf8'),context);
  vm.runInContext(`state.access='token';state.tenant={tenant_id:'tenant-A',tenant_name:'A'};state.branch={id:'branch-1',name:'One'}`,context);
  return {context,calls,resolveProducts,element,
    run:s=>vm.runInContext(s,context),
    flush:async()=>{await new Promise(resolve=>setImmediate(resolve));}};
}

test('overview does not fetch products until checkout/catalogue/stock needs them',async()=>{
  const h=harness();
  h.run("openView('overview')");
  await h.flush();
  assert.equal(h.calls.length,0);
  h.run("openView('checkout')");
  await h.flush();
  assert.equal(h.calls.filter(x=>x.endsWith('/products')).length,1);
  h.run("openView('catalog')");
  await h.flush();
  assert.equal(h.calls.filter(x=>x.endsWith('/products')).length,1);
});
test('rapid navigation deduplicates pending product requests',async()=>{
  const h=harness({deferProducts:true});
  h.run("openView('checkout')");
  h.run("openView('catalog')");
  await h.flush();
  assert.equal(h.calls.filter(x=>x.endsWith('/products')).length,1);
  h.resolveProducts();
  await h.flush();
  assert.equal(h.run('state.products.length'),1);
});
test('scope change removes lazy cache and reloads for new branch',async()=>{
  const h=harness();
  h.run("openView('checkout')");
  await h.flush();
  h.run("state.branch={id:'branch-2',name:'Two'}; resetLazyScreens(); openView('stock')");
  await h.flush();
  assert.equal(h.calls.filter(x=>x.endsWith('/products')).length,2);
});
test('lazy load skeletons contain three loading rows',()=>{
  const h=harness();
  h.run("showLazySkeleton('history-list')");
  const box=h.element('history-list');
  assert.equal(box.children.length,1);
  assert.equal(box.children[0].children.length,3);
});
