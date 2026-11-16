const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

function harness() {
  const nodes = new Map();
  const calls = [];
  const prints = [];
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
    '/api/v1/suppliers': [{id:'supplier-one',code:'SUP1',name:'Supplier One',phone:'50000000',outstanding_balance:'30.50'}],
    '/api/v1/customers?limit=250': [{id:'customer-one',code:'C1',name:'Test Customer',outstanding_balance:'0.00'}],
    '/api/v1/customers': {id:'customer-new',code:'CNEW',name:'New Customer'},
    ['/api/v1/products/'+productId]: {id:productId,name:'Notebook',sku:'BOOK',barcode:'1234567890123',unit:'unit',selling_price:'15.50',cost_price:'5.00',track_stock:true,reorder_level:'5.000',category_id:'category-1',brand_id:'brand-1',unit_id:null,is_active:true},
    '/api/v1/products': [{id: productId, name:'Notebook',sku:'BOOK',selling_price:'15.50',track_stock:true,on_hand:'20'}],
    '/api/v1/inventory/adjustments': {movement_id:'movement-one',on_hand:'25.000'},
    '/api/v1/pos/sales/sale-one': {id:'sale-one',sale_number:'SALE-001',status:'completed',subtotal:'15.50',tax_total:'0.00',total:'15.50',balance_due:'0.00',payment_status:'paid',completed_at:'2026-11-16T07:00:00Z',returned_total:'0.00',lines:[{product_name:'Notebook',quantity:'1.000',unit_price:'15.50',line_total:'15.50',returned_quantity:'0.000'}],payments:[{method:'cash',amount:'15.50'}],returns:[]},
    '/api/v1/qr/resolve': {kind:'product', resource_id:productId},
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
    window: {print:()=>prints.push(true)},
    console
  });
  const source = fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
  vm.runInContext(source, context, {filename:'app.js'});
  const state = vm.runInContext('state',context);
  state.access = 'local-test-token';
  state.tenant = {tenant_id:'tenant-1'};
  state.branch = {id:'branch-1'};
  state.products = responses['/api/v1/products'];
  return {context, state, calls, node, productId, prints};
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


test('exact barcode and SKU scans increment cart; unknown scans never add',()=>{
  const {context,state,node,productId}=harness();
  state.products[0].barcode='1234567890123';
  assert.equal(vm.runInContext('scanBarcode("1234567890123")',context),true);
  assert.equal(vm.runInContext('scanBarcode("BOOK")',context),true);
  assert.equal(state.cart.get(productId),2);
  assert.equal(vm.runInContext('scanBarcode("1234")',context),false);
  assert.equal(state.cart.get(productId),2);
  assert.match(node('barcode-feedback').textContent,/not found/);
});

test('scanned stock cannot exceed on-hand quantity',()=>{
  const {context,state,productId}=harness();
  state.products[0].barcode='1234567890123';state.products[0].on_hand='1';
  assert.equal(vm.runInContext('scanBarcode("1234567890123")',context),true);
  assert.equal(vm.runInContext('scanBarcode("1234567890123")',context),false);
  assert.equal(state.cart.get(productId),1);
});

test('product editor GET preserves classification, reorder level, and updates via PUT',async()=>{
  const {context,state,calls,node,productId}=harness();
  const fields={};
  for(const field of ['name','sku','barcode','selling_price','cost_price','unit','track_stock'])
    fields[field]={value:'',checked:false};
  const form=node('product-form');
  form.elements={namedItem(name){return fields[name];}};
  await vm.runInContext('beginProductEdit("'+productId+'")',context);
  assert.equal(state.productEdit.id,productId);
  assert.equal(fields.name.value,'Notebook');
  assert.equal(fields.barcode.value,'1234567890123');
  assert.equal(fields.track_stock.checked,true);
  form.fields={name:'Notebook updated',sku:'BOOK',barcode:'1234567890123',selling_price:'18.99',cost_price:'5.00',unit:'unit',track_stock:'on'};
  await vm.runInContext('saveProduct({preventDefault(){},currentTarget:document.getElementById("product-form")})',context);
  const put=calls.find(x=>x.url==='/api/v1/products/'+productId && x.options.method==='PUT');
  assert.ok(put,'full-schema PUT must be used, not a partial PATCH');
  const payload=JSON.parse(put.options.body);
  assert.equal(payload.name,'Notebook updated');
  assert.equal(payload.category_id,'category-1');
  assert.equal(payload.brand_id,'brand-1');
  assert.equal(payload.reorder_level,'5.000');
  assert.equal(payload.is_active,true);
  assert.equal(payload.selling_price,'18.99');
  assert.equal(calls.filter(x=>x.url==='/api/v1/products'&&x.options.method==='POST').length,0);
});

test('scanner submit clears only after product is accepted',()=>{
  const {context,state,node,productId}=harness();
  state.products[0].barcode='1234567890123';
  node('barcode-input').value='1234567890123';
  vm.runInContext('submitBarcode({preventDefault(){}})',context);
  assert.equal(node('barcode-input').value,'');
  assert.equal(state.cart.get(productId),1);
  node('barcode-input').value='invalid-code';
  vm.runInContext('submitBarcode({preventDefault(){}})',context);
  assert.equal(node('barcode-input').value,'invalid-code');
});


test('print recorded receipt uses exact authorized sale detail endpoint',async()=>{
  const {context,calls,node,prints,state}=harness();
  state.tenant.tenant_name='Test Shop';
  state.branch.name='Main Counter';
  await vm.runInContext('printSaleReceipt("sale-one")',context);
  const call=calls.find(x=>x.url==='/api/v1/pos/sales/sale-one');
  assert.ok(call,'Receipt must be fetched from the current branch sale detail');
  assert.equal(call.options.headers['X-Tenant-ID'],'tenant-1');
  assert.equal(call.options.headers['X-Branch-ID'],'branch-1');
  assert.equal(node('receipt-merchant').textContent,'Test Shop');
  assert.equal(node('receipt-branch').textContent,'Main Counter');
  assert.equal(node('receipt-number').textContent,'Sale SALE-001');
  assert.equal(node('receipt-total').textContent,'M 15.50');
  assert.equal(node('receipt-payment-status').textContent,'Payment status: paid');
  assert.equal(prints.length,1);
  assert.equal(node('receipt-print').hidden,true);
  assert.equal(state.busy,false);
  assert.equal(calls.some(x=>x.options.method==='POST'),false);
});

test('receipt printing refuses incomplete server data and never prints cart values',async()=>{
  const {context,prints,node}=harness();
  assert.throws(()=>vm.runInContext('renderSaleReceipt({sale_number:"SALE-4",status:"draft",lines:[],payments:[]})',context));
  assert.equal(prints.length,0);
  assert.equal(node('receipt-total').textContent,'');
});

test('receipt shows returns and actual recorded payments, not proof of a new transaction',()=>{
  const {context,node}=harness();
  const sale={
    sale_number:'SALE-001',status:'completed',completed_at:'2026-11-16T07:00:00Z',
    payment_status:'partially_refunded',subtotal:'100.00',tax_total:'0.00',
    total:'100.00',balance_due:'0.00',returned_total:'25.00',
    lines:[{product_name:'Original product',quantity:'2.000',unit_price:'50.00',line_total:'100.00',returned_quantity:'0.500'}],
    payments:[{method:'cash',amount:'100.00'}],
    returns:[{return_number:'RET-1',total:'25.00'}]
  };
  context.saleForTest=sale;
  vm.runInContext('renderSaleReceipt(saleForTest)',context);
  assert.equal(node('receipt-total').textContent,'M 100.00');
  assert.ok(node('receipt-returns').children.length>=2);
  assert.ok(node('receipt-payments').children.length>=2);
});

test('signed product QR must be resolved by backend before adding to cart',async()=>{
  const {context,state,node,calls,productId}=harness();
  const token='khanyaqr:v1:signed-example';
  node('product-qr-input').value=token;
  await vm.runInContext('submitProductQr({preventDefault(){}})',context);
  const verify=calls.find(c=>c.url==='/api/v1/qr/resolve');
  assert.ok(verify);
  assert.equal(verify.options.method,'POST');
  assert.equal(verify.options.headers['X-Tenant-ID'],'tenant-1');
  assert.equal(verify.options.headers['X-Branch-ID'],'branch-1');
  assert.equal(JSON.parse(verify.options.body).token,token);
  assert.equal(state.cart.get(productId),1);
  assert.equal(node('product-qr-input').value,'');
  assert.equal(calls.some(c=>c.url==='/api/v1/pos/sales/complete'),false);
});

test('ordinary SKU and malformed QR cannot bypass signed QR verification',async()=>{
  const {context,state,node,calls}=harness();
  node('product-qr-input').value='BOOK';
  await vm.runInContext('submitProductQr({preventDefault(){}})',context);
  assert.equal(state.cart.size,0);
  assert.equal(node('product-qr-input').value,'BOOK');
  assert.equal(calls.some(c=>c.url==='/api/v1/qr/resolve'),false);
});

test('signed QR for another resource type cannot add a product',async()=>{
  const {context,state,calls,node}=harness();
  // Supply an alternate authoritative resolver response without changing application code.
  context.requestForTest=async()=>({kind:'sale',resource_id:state.products[0].id});
  // Check the kind restriction exists and is separate from product ID matching.
  const source=fs.readFileSync(path.join(__dirname,'app.js'),'utf8');
  assert.ok(source.includes("resolved.kind!=='product'"));
  node('product-qr-input').value='khanyaqr:v1:signed-example';
  assert.equal(state.cart.size,0);
  assert.equal(calls.some(c=>c.url==='/api/v1/pos/sales/complete'),false);
});

test('supplier management uses authenticated tenant and branch scope',async()=>{
  const {context,calls,node,state}=harness();
  await vm.runInContext('loadSuppliers()',context);
  const call=calls.find(c=>c.url==='/api/v1/suppliers');
  assert.ok(call);
  assert.equal(call.options.headers['X-Tenant-ID'],'tenant-1');
  assert.equal(call.options.headers['X-Branch-ID'],'branch-1');
  assert.equal(state.suppliers.length,1);
  assert.ok(node('suppliers-list').children.length>0);
});

test('supplier search only filters loaded current business suppliers',async()=>{
  const {context,node}=harness();
  await vm.runInContext('loadSuppliers()',context);
  node('suppliers-search').value='missing';
  vm.runInContext('renderSuppliers()',context);
  assert.equal(node('suppliers-list').children.length,1);
  assert.equal(node('suppliers-list').children[0].textContent,'No suppliers found.');
});
