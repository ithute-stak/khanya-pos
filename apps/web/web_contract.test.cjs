const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

function harness() {
  const nodes = new Map();
  const calls = [];
  const node = (id) => {
    if (!nodes.has(id)) {
      nodes.set(id, {
        id, value: '', disabled: false, hidden: false, textContent: '',
        children: [], classList: {toggle() {}},
        append(...values) { this.children.push(...values); },
        replaceChildren(...values) { this.children = values; },
        addEventListener() {}
      });
    }
    return nodes.get(id);
  };
  const productId = 'da25eb22-1b39-4cc7-bf2e-87ef63a8cde0';
  const responses = {
    '/api/v1/pos/sales/complete': {id: 'sale-one', sale_number:'SALE-001'},
    '/api/v1/products': [{id: productId, name:'Notebook',sku:'BOOK',selling_price:'15.50',track_stock:true,on_hand:'20'}],
    '/api/v1/pos/sales?limit=60': [{id:'sale-one',sale_number:'SALE-001',completed_at:'2026-11-16T07:00:00Z',payment_status:'paid',total:'15.50',balance_due:'0.00'}]
  };
  const context = vm.createContext({
    document: { getElementById: node, querySelectorAll: () => [] },
    fetch: async (url, options) => {
      calls.push({url, options});
      assert.ok(url in responses, 'Unknown backend route: ' + url);
      return { ok:true, status:200, json:async()=>responses[url] };
    },
    crypto: { randomUUID: () => 'a2ea51c2-3043-46ea-91f6-a51e8b010da1' },
    confirm: () => true,
    console
  });
  const source = fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
  vm.runInContext(source, context, {filename:'app.js'});
  const state = vm.runInContext('state',context);
  state.access = 'local-test-token';
  state.tenant = {tenant_id:'tenant-1'};
  state.branch = {id:'branch-1'};
  state.products = responses['/api/v1/products'];
  return {context, state, calls, node, productId};
}

test('cash checkout posts an idempotent operation to the actual backend sale route', async () => {
  const {context,state,calls,node,productId} = harness();
  state.cart.set(productId,1);
  node('cash-received').value='20.00';
  vm.runInContext('renderCart()',context);
  assert.equal(node('complete-sale').disabled,false);
  await vm.runInContext('checkout()',context);
  const saleCall=calls.find(x=>x.url==='/api/v1/pos/sales/complete');
  assert.ok(saleCall, 'Expected the real FastAPI POS sales endpoint');
  assert.equal(saleCall.options.method,'POST');
  assert.equal(saleCall.options.headers['X-Tenant-ID'],'tenant-1');
  assert.equal(saleCall.options.headers['X-Branch-ID'],'branch-1');
  const data=JSON.parse(saleCall.options.body);
  assert.equal(data.client_operation_id,'a2ea51c2-3043-46ea-91f6-a51e8b010da1');
  assert.equal(data.payments[0].method,'cash');
  assert.equal(data.payments[0].amount,'15.50');
  assert.equal(data.items[0].product_id,productId);
  assert.equal(data.items[0].quantity,1);
  assert.equal(state.cart.size,0);
  assert.equal(state.pendingId,null);
  assert.equal(node('cash-received').value,'');
  assert.equal(state.busy,false);
});

test('sales history requests backend /pos/sales and shows original sale', async()=>{
  const {context,calls,node}=harness();
  await vm.runInContext('loadHistory()',context);
  assert.ok(calls.some(x=>x.url==='/api/v1/pos/sales?limit=60'));
  assert.ok(node('history-list').children.length > 0);
});

test('invalid and sub-cent cash is rejected before sale', async()=>{
  const {context,state,calls,node,productId}=harness();
  state.cart.set(productId,1);
  for (const amount of ['0', '15.499', '-15.50', 'not-number']) {
    node('cash-received').value=amount;
    vm.runInContext('renderCart()',context);
    assert.equal(node('complete-sale').disabled,true);
    await vm.runInContext('checkout()',context);
  }
  assert.ok(!calls.some(x=>x.url.includes('/pos/sales/complete')));
  assert.equal(state.cart.size,1);
});

test('cart edits, branch changes and clear action are blocked while saving',()=>{
  const {context,state,node,productId}=harness();
  state.products[0].on_hand='20';
  state.cart.set(productId,1);
  state.busy=true;
  vm.runInContext('renderCart()',context);
  assert.equal(node('complete-sale').disabled,true);
  assert.equal(node('clear-cart').disabled,true);
  assert.equal(node('tenant-picker').disabled,true);
  assert.equal(node('branch-picker').disabled,true);
  vm.runInContext('addProduct("'+productId+'")',context);
  vm.runInContext('switchScope("branch")',context);
  assert.equal(state.cart.get(productId),1);
});
