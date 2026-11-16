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
        reset() { this.fields = {}; },
        replaceChildren(...values) { this.children = values; },
        addEventListener() {}
      });
    }
    return nodes.get(id);
  };
  const productId = 'da25eb22-1b39-4cc7-bf2e-87ef63a8cde0';
  const responses = {
    '/api/v1/customers?limit=250': [{id:'customer-one',code:'C1',name:'Test Customer',outstanding_balance:'0.00'}],
    '/api/v1/customers': {id:'customer-new',code:'CNEW',name:'New Customer'},
    '/api/v1/products': [{id: productId, name:'Notebook',sku:'BOOK',selling_price:'15.50',track_stock:true,on_hand:'20'}],
    '/api/v1/inventory/adjustments': {movement_id:'movement-one',on_hand:'25.000'},
    '/api/v1/pos/sales/complete': {id: 'sale-one', sale_number:'SALE-001'},
    '/api/v1/pos/sales?limit=60': [{id:'sale-one',sale_number:'SALE-001',completed_at:'2026-11-16T07:00:00Z',payment_status:'paid',total:'15.50',balance_due:'0.00'}]
  };
  const context = vm.createContext({
    document: { getElementById: node, createElement: tag => node('created-' + tag + '-' + nodes.size), querySelectorAll: () => [] },
    fetch: async (url, options) => {
      calls.push({url, options});
      assert.ok(url in responses, 'Unknown backend route: ' + url);
      return { ok:true, status:200, json:async()=>responses[url] };
    },
    crypto: { randomUUID: () => 'a2ea51c2-3043-46ea-91f6-a51e8b010da1' },
    FormData: class { constructor(form) {this.fields=form.fields||{};} get(k) {return this.fields[k]??null;} has(k){return Object.prototype.hasOwnProperty.call(this.fields,k);} },
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


test('product creation uses catalog API and does not invent opening stock',async()=>{
  const {context,calls,node}=harness();
  const form=node('product-form');
  form.fields={name:'Paper pack',sku:'PAPER',selling_price:'25.50',cost_price:'18.00',unit:'pack',track_stock:'on'};
  await vm.runInContext('saveProduct({preventDefault(){}, currentTarget:document.getElementById("product-form")})',context);
  const call=calls.find(x=>x.url==='/api/v1/products'&&x.options.method==='POST');
  assert.ok(call);
  const body=JSON.parse(call.options.body);
  assert.deepEqual({...body}, {name:'Paper pack',sku:'PAPER',barcode:null,selling_price:'25.50',cost_price:'18.00',unit:'pack',track_stock:true});
  assert.equal('on_hand' in body,false);
  assert.equal('quantity_delta' in body,false);
});
test('stock adjustment is branch-scoped, signed and explicit',async()=>{
  const {context,calls,node,productId}=harness();
  node('stock-product').value=productId;node('stock-type').value='count_gain';
  node('stock-delta').value='5';node('stock-reason').value='Physical count';
  await vm.runInContext('saveStock({preventDefault(){}})',context);
  const call=calls.find(x=>x.url==='/api/v1/inventory/adjustments');
  assert.ok(call);
  assert.equal(call.options.headers['X-Branch-ID'],'branch-1');
  const body=JSON.parse(call.options.body);
  assert.equal(body.product_id,productId);assert.equal(body.quantity_delta,'5.000');
  assert.equal(body.adjustment_type,'count_gain');assert.equal(body.reason,'Physical count');
  assert.equal(body.client_operation_id,'a2ea51c2-3043-46ea-91f6-a51e8b010da1');
});
test('invalid loss direction is not submitted',async()=>{
  const {context,calls,node,productId}=harness();
  node('stock-product').value=productId;node('stock-type').value='count_loss';
  node('stock-delta').value='5';node('stock-reason').value='Physical count';
  await vm.runInContext('saveStock({preventDefault(){}})',context);
  assert.equal(calls.some(x=>x.url==='/api/v1/inventory/adjustments'),false);
  assert.equal(node('stock-delta').value,'5');
});
test('customer creation defaults to zero credit and uses scoped API',async()=>{
  const {context,calls,node}=harness();
  node('customer-form').fields={name:'New Customer',code:'CNEW',phone:'50000000',email:''};
  await vm.runInContext('saveCustomer({preventDefault(){}, currentTarget:document.getElementById("customer-form")})',context);
  const call=calls.find(x=>x.url==='/api/v1/customers'&&x.options.method==='POST');
  assert.ok(call);
  const body=JSON.parse(call.options.body);
  assert.equal(body.credit_limit,'0.00');assert.equal(body.payment_terms_days,0);
  assert.equal(body.name,'New Customer');
  assert.equal(call.options.headers['X-Tenant-ID'],'tenant-1');
  assert.equal(calls.some(x=>x.url==='/api/v1/customers?limit=250'),true);
});
test('money and quantity inputs enforce backend decimal precision',()=>{
  const {context}=harness();
  assert.equal(vm.runInContext('validAmount("12.5")',context),'12.50');
  assert.equal(vm.runInContext('validDelta("-2.25","count_loss")',context),'-2.250');
  assert.throws(()=>vm.runInContext('validAmount("12.345")',context));
  assert.throws(()=>vm.runInContext('validDelta("-1","opening_balance")',context));
  assert.throws(()=>vm.runInContext('validDelta("1","damage")',context));
});
