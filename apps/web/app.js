'use strict';
/* Khanya POS browser entry. Auth stays in memory; all payment totals, inventory,
   tenant and QR permissions are verified by the existing FastAPI backend. */
const $ = id => document.getElementById(id);
const state = { access: null, refresh: null, me: null, tenant: null, branch: null,
  products: [], customers: [], suppliers: [], staff: [], cart: new Map(), busy: false, productEdit: null, pendingId: null, currentView: 'checkout', expensePending: null };
const money = value => 'M ' + Number(value || 0).toLocaleString('en-LS', {
  minimumFractionDigits: 2, maximumFractionDigits: 2
});
const h = (tag, className, textValue) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (textValue !== undefined) node.textContent = String(textValue);
  return node;
};
const notify = (message, error = false) => {
  const toast = $('toast'); toast.textContent = message;
  toast.className = error ? 'error' : ''; toast.hidden = false;
};
const clearNotify = () => { $('toast').hidden = true; };
async function request(path, options = {}, retry = true) {
  const headers = { Accept: 'application/json', ...(options.body ? {'Content-Type':'application/json'} : {}) };
  if (state.access) headers.Authorization = 'Bearer ' + state.access;
  if (state.tenant) headers['X-Tenant-ID'] = state.tenant.tenant_id;
  if (state.branch) headers['X-Branch-ID'] = state.branch.id;
  const result = await fetch('/api/v1' + path, {
    ...options, headers: { ...headers, ...(options.headers || {}) },
    credentials: 'same-origin', cache: 'no-store'
  });
  if (result.status === 401 && retry && state.refresh && !path.startsWith('/auth/')) {
    try {
      const renewed = await request('/auth/refresh', {
        method:'POST', body:JSON.stringify({refresh_token: state.refresh})
      }, false);
      state.access = renewed.access_token; state.refresh = renewed.refresh_token;
      return request(path, options, false);
    } catch (_) { signOut(false); throw new Error('Session expired. Please sign in again.'); }
  }
  if (!result.ok) {
    let detail = 'Request failed (' + result.status + ')';
    try {
      const data = await result.json();
      detail = typeof data.detail === 'string' ? data.detail : detail;
    } catch (_) {}
    throw new Error(detail);
  }
  if (result.status === 204) return null;
  return result.json();
}
function signOut(remote = true) {
  if (remote && state.access) request('/auth/logout',{method:'POST'}).catch(()=>{});
  state.access = null; state.refresh = null; state.me = null; state.tenant = null;
  state.branch = null; state.products = []; state.customers = []; state.suppliers = []; state.staff = []; state.productEdit = null; state.cart.clear(); state.pendingId = null; state.expensePending = null;
  $('app-view').hidden = true; $('session-controls').hidden = true; $('login-view').hidden = false;
  $('password').value = ''; $('identifier').focus(); clearNotify();
}
async function login(event) {
  event.preventDefault();
  if (state.busy) return;
  state.busy = true; $('login-button').disabled = true; clearNotify();
  try {
    const response = await request('/auth/login', {
      method: 'POST',
      body: JSON.stringify({identifier:$('identifier').value.trim(), password:$('password').value})
    });
    state.access = response.access_token; state.refresh = response.refresh_token;
    const me = await request('/auth/me'); state.me = me;
    if (!Array.isArray(me.memberships) || me.memberships.length === 0) {
      throw new Error('No approved business is assigned to your account.');
    }
    $('welcome').textContent = me.display_name || me.email || 'Signed in';
    $('login-view').hidden = true; $('app-view').hidden = false; $('session-controls').hidden = false;
    fillTenants(); await loadProducts();
  } catch (error) { if (!state.me) signOut(false); notify(error.message, true); }
  finally { state.busy = false; $('login-button').disabled = false; }
}
function fillTenants() {
  const selector = $('tenant-picker'); selector.replaceChildren();
  for (const m of state.me.memberships) {
    const option = h('option',null,m.tenant_name); option.value = m.tenant_id; selector.append(option);
  }
  state.tenant = state.me.memberships[0]; selector.value = state.tenant.tenant_id;
  fillBranches();
}
function fillBranches() {
  const selector = $('branch-picker'); selector.replaceChildren();
  const branches = (state.tenant.branches || []).filter(b => b.is_active);
  for (const b of branches) {
    const option = h('option',null,b.name); option.value = b.id; selector.append(option);
  }
  state.branch = branches.find(b=>b.is_main) || branches[0] || null;
  if (state.branch) selector.value = state.branch.id;
  $('business-title').textContent = state.tenant.tenant_name;
  $('branch-title').textContent = (state.branch ? state.branch.name : 'No active branch') +
      ' · ' + state.tenant.role;
}
function switchScope(kind) {
  if (state.busy) return;
  if (kind === 'tenant') {
    state.tenant = state.me.memberships.find(m => m.tenant_id === $('tenant-picker').value);
    fillBranches();
  } else {
    state.branch = (state.tenant.branches || []).find(b=>b.id === $('branch-picker').value);
    $('branch-title').textContent = (state.branch?.name || 'No active branch') + ' · ' + state.tenant.role;
  }
  state.cart.clear(); state.customers=[]; state.suppliers=[]; state.staff=[]; $('suppliers-list').replaceChildren(); $('staff-list').replaceChildren(); cancelProductEdit(); state.pendingId = null; $('cash-received').value = ''; renderCart();
  loadProducts().catch(e=>notify(e.message,true));
}
async function loadProducts() {
  if (!state.branch) { notify('Select an active branch.',true); return; }
  state.products = await request('/products');
  renderProducts(); renderCatalog(); renderStock();
}
function renderProducts() {
  const target = $('product-list'); target.replaceChildren();
  const search = $('product-search').value.trim().toLowerCase();
  const filtered = state.products.filter(p=>[p.name,p.sku,p.barcode]
    .some(v=>String(v||'').toLowerCase().includes(search)));
  if (filtered.length === 0) { target.append(h('p','empty','No products found.')); return; }
  for (const product of filtered) {
    const card = h('button','product-card');
    const out = product.track_stock && product.on_hand !== null &&
        Number(product.on_hand) <= 0;
    card.disabled = out;
    card.append(h('span','product-name',product.name),h('span','product-sku',product.sku),
      h('span','product-price',money(product.selling_price)));
    card.append(h('span','product-stock',out ? 'Out of stock' : (product.on_hand == null ? 'Available' : 'Stock: '+product.on_hand)));
    card.addEventListener('click',()=>addProduct(product.id));
    target.append(card);
  }
}
function renderCatalog() {
  const target=$('catalog-list'); target.replaceChildren();
  for(const p of state.products){
    const row=h('div','record'), l=h('div'), right=h('div');
    l.append(h('strong',null,p.name),h('small',null,'SKU: '+p.sku+(p.barcode?' · '+p.barcode:'')));
    right.append(h('strong',null,money(p.selling_price)),h('small',null,
      p.on_hand == null ? 'No branch stock count' : 'On hand: '+p.on_hand));
    const edit=h('button','secondary','Edit'); edit.type='button'; edit.disabled=state.busy;
    edit.addEventListener('click',()=>beginProductEdit(p.id));
    right.append(edit);
    row.append(l,right); target.append(row);
  }
  if (!state.products.length) target.append(h('p','empty','No products in this business yet.'));
}

function validAmount(value) {
  const normalized = String(value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) throw new Error('Enter a non-negative amount with at most two decimals.');
  const n = Number(normalized);
  if (!Number.isFinite(n) || n > 999999999) throw new Error('Amount is outside supported range.');
  return n.toFixed(2);
}
function validDelta(value, adjustmentType) {
  const normalized = String(value).trim();
  if (!/^-?\d+(?:\.\d{1,3})?$/.test(normalized)) throw new Error('Enter a quantity with at most three decimals.');
  const n=Number(normalized);
  if (!Number.isFinite(n) || n === 0 || Math.abs(n) > 100000000) throw new Error('Quantity change must be non-zero and within supported range.');
  if (['opening_balance','count_gain'].includes(adjustmentType) && n < 0) throw new Error('An opening balance or count gain must be positive.');
  if (['count_loss','damage','expiry'].includes(adjustmentType) && n > 0) throw new Error('Loss, damage and expiry must be negative.');
  return n.toFixed(3);
}
function formValue(data, key) { return String(data.get(key) || '').trim(); }
function renderStock() {
  const target=$('stock-list'); target.replaceChildren();
  const selector=$('stock-product'); const selected=selector.value;
  selector.replaceChildren();
  for (const product of state.products) {
    const option=h('option',null,product.name + ' · '+ product.sku);
    option.value=product.id; selector.append(option);
    const row=h('div','record'), left=h('div');
    left.append(h('strong',null,product.name),h('small',null,'SKU: '+product.sku));
    const value=product.track_stock ?
        (product.on_hand === null || product.on_hand === undefined ? 'Not counted' : String(product.on_hand)) :
        'Not tracked';
    row.append(left,h('strong',null,value)); target.append(row);
  }
  if (state.products.some(p=>p.id===selected)) selector.value=selected;
  if (!state.products.length) target.append(h('p','empty','Create a product before adjusting stock.'));
}

function cancelProductEdit(){
  state.productEdit=null;
  const form=$('product-form'); if (form.reset) form.reset();
  $('product-editor-title').textContent='Add product';
  $('save-product').textContent='Save product';
  $('cancel-product-edit').hidden=true;
}
async function beginProductEdit(id){
  if(state.busy) return;
  state.busy=true;$('save-product').disabled=true;
  try{
    const product=await request('/products/'+encodeURIComponent(id));
    if(!state.products.some(p=>p.id===product.id))throw new Error('The product is no longer in this catalogue.');
    state.productEdit=product;
    const form=$('product-form');
    for(const field of ['name','sku','barcode','selling_price','cost_price','unit']){
      const input=form.elements?.namedItem(field);
      if(input)input.value=product[field] ?? '';
    }
    const track=form.elements?.namedItem('track_stock');
    if(track)track.checked=Boolean(product.track_stock);
    $('product-editor-title').textContent='Edit product';
    $('save-product').textContent='Save changes';
    $('cancel-product-edit').hidden=false;
    notify('Editing '+product.name+'. Prices and stock movements remain server-controlled.');
  }catch(e){notify('Could not load product details: '+e.message,true);}
  finally{state.busy=false;$('save-product').disabled=false;}
}
function scanBarcode(value){
  if(state.busy)return false;
  const code=String(value||'').trim().toLowerCase();
  if(!code)return false;
  const matches=state.products.filter(p=>
    (p.barcode && p.barcode.trim().toLowerCase()===code) ||
    (p.sku && p.sku.trim().toLowerCase()===code)
  );
  if(matches.length!==1){
    const message=matches.length?'Multiple products matched this identifier.':'Barcode/SKU not found in this business.';
    $('barcode-feedback').textContent=message;
    notify(message,true);return false;
  }
  const product=matches[0],before=state.cart.get(product.id)||0;
  addProduct(product.id);
  const added=(state.cart.get(product.id)||0)>before;
  $('barcode-feedback').textContent=added?product.name+' added to cart.':'Could not add product. Check current stock.';
  return added;
}
function submitBarcode(event){
  event.preventDefault();
  const input=$('barcode-input');
  if(scanBarcode(input.value)) input.value='';
  if(input.focus)input.focus();
}

// A signed QR is a locator only. Never accept client-supplied product IDs without server resolution.
async function scanProductQr(value) {
  if (state.busy || !state.access || !state.tenant || !state.branch) return false;
  const token=String(value||'').trim(), feedback=$('product-qr-feedback');
  if (!token.startsWith('khanyaqr:v1:') || token.length>4096) {
    feedback.textContent='Scan a valid signed Khanya product QR.';
    return false;
  }
  const tenantId=state.tenant.tenant_id, branchId=state.branch.id;
  feedback.textContent='Verifying product QR…';
  $('product-qr-add').disabled=true;
  try {
    const resolved=await request('/qr/resolve',{method:'POST',body:JSON.stringify({token})});
    if(!state.tenant || !state.branch || state.tenant.tenant_id!==tenantId || state.branch.id!==branchId) {
      feedback.textContent='Business or branch changed; scan again.'; return false;
    }
    if(resolved.kind!=='product' || typeof resolved.resource_id!=='string') {
      feedback.textContent='This QR is not a product QR.';return false;
    }
    const matches=state.products.filter(p=>p.id===resolved.resource_id);
    if(matches.length!==1) {
      feedback.textContent='Product not found in the current branch. Refresh products and scan again.';
      return false;
    }
    const p=matches[0], before=state.cart.get(p.id)||0;
    addProduct(p.id);
    const added=(state.cart.get(p.id)||0)>before;
    feedback.textContent=added?p.name+' added to cart.':'Could not add product. Check available stock.';
    return added;
  } catch(e) { feedback.textContent='QR verification failed: '+e.message;return false; }
  finally { $('product-qr-add').disabled=false; }
}
async function submitProductQr(event) {
  event.preventDefault();
  const input=$('product-qr-input');
  if(await scanProductQr(input.value))input.value='';
  if(input.focus)input.focus();
}

async function saveProduct(event) {
  event.preventDefault();
  if (state.busy) return;
  const form=event.currentTarget, data=new FormData(form);
  let payload;
  try {
    payload={
      name:formValue(data,'name'), sku:formValue(data,'sku').toUpperCase(),
      barcode:formValue(data,'barcode') || null,
      selling_price:validAmount(formValue(data,'selling_price')),
      cost_price:validAmount(formValue(data,'cost_price')),
      unit:formValue(data,'unit'),
      track_stock:data.has('track_stock'),
    };
    if(payload.name.length<2 || !payload.sku || !payload.unit) throw new Error('Enter a product name, SKU and unit.');
  } catch(e){notify(e.message,true);return;}
  const edit=state.productEdit;
  if(!confirm((edit?'Update ':'Create ')+payload.name+' in '+state.tenant.tenant_name+'?')) return;
  state.busy=true; $('save-product').disabled=true;renderCart();
  let created;
  try {
    if(edit){
      // PUT expects the full product schema; retain existing classifications and reorder settings.
      created=await request('/products/'+encodeURIComponent(edit.id),{
        method:'PUT',
        body:JSON.stringify({
          ...payload,
          category_id:edit.category_id ?? null,brand_id:edit.brand_id ?? null,
          unit_id:edit.unit_id ?? null,reorder_level:edit.reorder_level ?? '0',
          is_active:edit.is_active
        })
      });
    }else{
      created=await request('/products',{method:'POST',body:JSON.stringify(payload)});
    }
    cancelProductEdit();
    notify('Product '+created.name+(edit?' updated.':' created.'));
  }catch(e){notify(e.message+' — Check the catalogue before repeating this operation.',true);}
  finally{state.busy=false; $('save-product').disabled=false;renderCart();}
  if(created) {
    try{await loadProducts();}
    catch(e){notify('Product created, but the catalogue could not refresh: '+e.message,true);}
  }
}
async function saveStock(event) {
  event.preventDefault();
  if(state.busy) return;
  const productId=$('stock-product').value;
  const kind=$('stock-type').value;
  const reason=$('stock-reason').value.trim();
  let delta;
  try{
    if(!state.branch)throw new Error('Select a branch.');
    if(!state.products.some(p=>p.id===productId))throw new Error('Select a valid product.');
    if(reason.length<2 || reason.length>240)throw new Error('Enter a reason for the stock change.');
    delta=validDelta($('stock-delta').value,kind);
  }catch(e){notify(e.message,true);return;}
  const product=state.products.find(p=>p.id===productId);
  const payload={
    client_operation_id:crypto.randomUUID(),product_id:productId,
    quantity_delta:delta,adjustment_type:kind,reason
  };
  if(!confirm('Record '+delta+' units for '+product.name+' in '+state.branch.name+'? This changes real stock.'))return;
  state.busy=true;$('save-stock').disabled=true;renderCart();
  let completed=false;
  try{
    const result=await request('/inventory/adjustments',{method:'POST',body:JSON.stringify(payload)});
    completed=true;
    $('stock-delta').value='';$('stock-reason').value='';
    notify('Stock adjustment recorded. Current on hand: '+result.on_hand);
  }catch(e){notify(e.message+' — Check branch stock and audit history before submitting another adjustment.',true);}
  finally{state.busy=false;$('save-stock').disabled=false;renderCart();}
  if(completed){
    try{await loadProducts();}
    catch(e){notify('Adjustment recorded; stock refresh failed: '+e.message,true);}
  }
}
async function loadCustomers(){
  const target=$('customers-list');target.replaceChildren(h('p','empty','Loading customers…'));
  try{
    const customers=await request('/customers?limit=250');
    state.customers=Array.isArray(customers)?customers:[];
    renderCustomers();
  }catch(e){target.replaceChildren(h('p','empty','Unable to load customers: '+e.message));}
}
function renderCustomers(){
  const target=$('customers-list');target.replaceChildren();
  const search=$('customers-search').value.trim().toLowerCase();
  const matches=state.customers.filter(c=>[c.name,c.code,c.phone,c.email]
    .some(x=>String(x||'').toLowerCase().includes(search)));
  for(const c of matches){
    const row=h('div','record'),left=h('div'),right=h('div');
    left.append(h('strong',null,c.name),h('small',null,c.code+' · '+(c.phone||'No phone')));
    right.append(h('small',null,'Balance: '+money(c.outstanding_balance)));
    row.append(left,right);target.append(row);
  }
  if(!matches.length)target.append(h('p','empty','No customers found.'));
}
async function saveCustomer(event){
  event.preventDefault();if(state.busy)return;
  const form=event.currentTarget, data=new FormData(form);
  const payload={
    name:formValue(data,'name'),code:formValue(data,'code').toUpperCase(),
    phone:formValue(data,'phone')||null,email:formValue(data,'email')||null,
    credit_limit:'0.00',payment_terms_days:0
  };
  if(payload.name.length<2 || !payload.code){notify('Enter a customer name and code.',true);return;}
  if(!confirm('Create customer '+payload.name+' with no credit facility?'))return;
  state.busy=true;$('save-customer').disabled=true;renderCart();
  let created;
  try{
    created=await request('/customers',{method:'POST',body:JSON.stringify(payload)});
    form.reset();notify('Customer '+created.name+' created.');
  }catch(e){notify(e.message+' — Check the customer list before creating the same customer again.',true);}
  finally{state.busy=false;$('save-customer').disabled=false;renderCart();}
  if(created)await loadCustomers();
}

function addProduct(id) {
  if (state.busy) return;
  const product=state.products.find(p=>p.id===id); if(!product)return;
  const old=state.cart.get(id)||0;
  if (product.track_stock && product.on_hand != null && old+1>Number(product.on_hand)) {
    notify('Insufficient current stock for '+product.name,true);return;
  }
  state.cart.set(id,old+1); state.pendingId=null; renderCart();
}
function renderCart() {
  const box=$('cart-items');box.replaceChildren();
  let total=0,count=0;
  for(const [id,qty] of state.cart) {
    const p=state.products.find(x=>x.id===id);if(!p)continue;
    total+=Math.round(Number(p.selling_price)*100)*qty;count+=qty;
    const row=h('div','cart-line'), info=h('div'), controls=h('div','qty');
    info.append(h('strong',null,p.name),h('small',null,money(p.selling_price)+' each'));
    const minus=h('button',null,'−');minus.type='button'; minus.disabled=state.busy;
    minus.addEventListener('click',()=>{ if(state.busy)return; if(qty<=1)state.cart.delete(id);else state.cart.set(id,qty-1);state.pendingId=null;renderCart();});
    const plus=h('button',null,'+');plus.type='button'; plus.disabled=state.busy;
    plus.addEventListener('click',()=>addProduct(id));
    controls.append(minus,h('span',null,qty),plus);
    row.append(info,controls);box.append(row);
  }
  if (!count) box.append(h('p','empty','Your cart is empty'));
  $('cart-count').textContent=String(count);$('cart-total').textContent=money(total/100);
  const received=Number($('cash-received').value);
  $('change-total').textContent=money(Math.max(0,received-total/100));
  const validCash=/^\d+(?:\.\d{1,2})?$/.test($('cash-received').value.trim());
  $('clear-cart').disabled=state.busy;
  $('tenant-picker').disabled=state.busy;
  $('branch-picker').disabled=state.busy;
  $('complete-sale').disabled=!count || state.busy || !state.branch ||
      !validCash || !Number.isFinite(received) || received < total/100;
}
async function checkout() {
  if ($('complete-sale').disabled || state.busy) return;
  const items=[...state.cart].map(([product_id,quantity])=>({product_id,quantity}));
  if (!items.length) return;
  const totalCents=[...state.cart].reduce((sum,[id,qty])=>{
    const p=state.products.find(x=>x.id===id);
    return sum + (p?Math.round(Number(p.selling_price)*100)*qty:0);
  },0);
  const cashCents=Math.round(Number($('cash-received').value)*100);
  if(!/^\d+(?:\.\d{1,2})?$/.test($('cash-received').value.trim()) || !Number.isSafeInteger(cashCents)||cashCents<totalCents) {notify('Cash received is below the sale total.',true);return;}
  if(!confirm('Record a CASH sale of '+money(totalCents/100)+'?'))return;
  state.busy=true;renderCart();clearNotify();
  const operation=state.pendingId || crypto.randomUUID();
  state.pendingId=operation;
  let sale;
  try {
    sale=await request('/pos/sales/complete',{
      method:'POST',body:JSON.stringify({
        client_operation_id:operation,
        items, payments:[{method:'cash',amount:(totalCents/100).toFixed(2)}]
      })
    });
    state.cart.clear();state.pendingId=null;$('cash-received').value='';
    notify('Sale '+sale.sale_number+' recorded successfully. Change: '+money((cashCents-totalCents)/100));
  }catch(e){notify(e.message+' — Do not repeat the transaction until you confirm whether the sale was recorded.',true);}
  finally{state.busy=false;renderCart();}
  if (sale) {
    try { await loadProducts(); }
    catch(e) { notify('Sale '+sale.sale_number+' recorded successfully, but refreshing products failed: '+e.message,true); }
  }
}

function receiptLine(label, value, className=''){
  const line=h('div','receipt-row '+className);
  line.append(h('span',null,label),h('strong',null,value));
  return line;
}
function renderSaleReceipt(detail) {
  if (!detail || detail.status!=='completed' || !Array.isArray(detail.lines) ||
      !Array.isArray(detail.payments) || !detail.sale_number) {
    throw new Error('The server did not return a completed sale receipt.');
  }
  const merchant=state.tenant?.tenant_name || '';
  const branch=state.branch?.name || '';
  $('receipt-merchant').textContent=merchant;
  $('receipt-branch').textContent=branch;
  $('receipt-number').textContent='Sale '+detail.sale_number;
  $('receipt-date').textContent='Date: '+new Date(detail.completed_at).toLocaleString();
  $('receipt-payment-status').textContent='Payment status: '+String(detail.payment_status || 'unknown');
  const lines=$('receipt-lines');lines.replaceChildren();
  for(const item of detail.lines){
    const row=h('div','receipt-item');
    row.append(h('strong',null,item.product_name||'Item'),
      receiptLine(String(item.quantity)+' × '+money(item.unit_price),money(item.line_total)));
    if(Number(item.returned_quantity)>0) row.append(h('small',null,'Returned: '+item.returned_quantity));
    lines.append(row);
  }
  $('receipt-subtotal').textContent=money(detail.subtotal);
  $('receipt-tax').textContent=money(detail.tax_total);
  $('receipt-total').textContent=money(detail.total);
  $('receipt-balance').textContent=money(detail.balance_due);
  const payments=$('receipt-payments'); payments.replaceChildren(h('strong',null,'Payments'));
  if(detail.payments.length){
    for(const payment of detail.payments) payments.append(receiptLine(
      String(payment.method).replace(/_/g,' '),money(payment.amount)));
  }else payments.append(h('div',null,'No payments recorded'));
  const returns=$('receipt-returns');returns.replaceChildren();
  if(Number(detail.returned_total)>0){
    returns.append(h('strong',null,'Returns / refunds recorded'),
      receiptLine('Returned value',money(detail.returned_total)));
    for(const item of detail.returns||[]){
      returns.append(receiptLine(item.return_number||'Return',money(item.total)));
    }
  }
}
async function printSaleReceipt(saleId){
  if(state.busy || !state.branch || !state.tenant)return;
  state.busy=true;
  try{
    const detail=await request('/pos/sales/'+encodeURIComponent(saleId));
    // Only the authoritative server detail is printed, never locally cached cart prices.
    renderSaleReceipt(detail);
    $('receipt-print').hidden=false;
    // The browser's native print dialog prints a dedicated thermal-width layout.
    // If the user cancels, no sale, payment or inventory action is performed.
    window.print();
  }catch(e){
    notify('Cannot print sale receipt: '+e.message,true);
  }finally{
    $('receipt-print').hidden=true;
    state.busy=false;
  }
}

async function loadHistory(){
  const box=$('history-list');box.replaceChildren(h('p','empty','Loading sales…'));
  try{
    const sales=await request('/pos/sales?limit=60');box.replaceChildren();
    for(const sale of sales){
      const row=h('div','record'),left=h('div'),right=h('div');
      left.append(h('strong',null,sale.sale_number),h('small',null,
        new Date(sale.completed_at).toLocaleString()+' · '+sale.payment_status));
      right.append(h('strong',null,money(sale.total)),h('small',null,
        'Balance: '+money(sale.balance_due)));
      const receiptButton=h('button','secondary','Print receipt');
      receiptButton.type='button';
      receiptButton.addEventListener('click',()=>printSaleReceipt(sale.id));
      right.append(receiptButton);
      row.append(left,right);box.append(row);
    }
    if(!sales.length)box.append(h('p','empty','No sales recorded yet.'));
  }catch(e){box.replaceChildren(h('p','empty',e.message));}
}
async function loadSuppliers(){
  const target=$('suppliers-list');target.replaceChildren(h('p','empty','Loading suppliers…'));
  const tenant=state.tenant?.tenant_id;
  try {
    const suppliers=await request('/suppliers');
    if(!state.tenant || state.tenant.tenant_id!==tenant)return;
    state.suppliers=Array.isArray(suppliers)?suppliers:[];
    renderSuppliers();
  }catch(e){target.replaceChildren(h('p','empty','Unable to load suppliers: '+e.message));}
}
function renderSuppliers(){
  const target=$('suppliers-list');target.replaceChildren();
  const term=$('suppliers-search').value.trim().toLowerCase();
  const found=state.suppliers.filter(p=>[p.name,p.code,p.phone]
    .some(value=>String(value||'').toLowerCase().includes(term)));
  for(const supplier of found){
    const row=h('div','record'),left=h('div'),right=h('div');
    left.append(h('strong',null,supplier.name),h('small',null,supplier.code+' · '+(supplier.phone||'No phone')));
    right.append(h('small',null,'Outstanding: '+money(supplier.outstanding_balance)));
    row.append(left,right);target.append(row);
  }
  if(!found.length)target.append(h('p','empty','No suppliers found.'));
}
async function saveSupplier(event){
  event.preventDefault();if(state.busy || !state.tenant || !state.branch)return;
  const data=new FormData(event.currentTarget);
  const payload={name:formValue(data,'name'),code:formValue(data,'code').toUpperCase(),phone:formValue(data,'phone')||null};
  if(payload.name.length<2 || !payload.code){notify('Enter supplier name and code.',true);return;}
  if(!confirm('Create supplier '+payload.name+' for the current business?'))return;
  const tenant=state.tenant.tenant_id;
  state.busy=true;$('save-supplier').disabled=true;
  try {
    await request('/suppliers',{method:'POST',body:JSON.stringify(payload)});
    if(state.tenant?.tenant_id===tenant){event.currentTarget.reset();await loadSuppliers();}
    notify('Supplier saved.');
  }catch(e){notify('Supplier was not confirmed: '+e.message+'; check the list before retrying.',true);}
  finally{state.busy=false;$('save-supplier').disabled=false;}
}

async function loadExpenses(){
  const target=$('expenses-list'), tenant=state.tenant?.tenant_id, branch=state.branch?.id;
  target.replaceChildren(h('p','empty','Loading expenses…'));
  if(!tenant||!branch)return;
  try{
    const entries=await request('/expenses');
    if(state.tenant?.tenant_id!==tenant || state.branch?.id!==branch)return;
    target.replaceChildren();
    for(const expense of (Array.isArray(entries)?entries:[])){
      const row=h('div','record'),left=h('div'),right=h('div');
      left.append(h('strong',null,expense.description||expense.expense_number),
        h('small',null,(expense.expense_number||'Expense')+' · '+(expense.category||'Uncategorised')+' · '+(expense.payment_method||'')));
      right.append(h('strong',null,money(expense.amount)),h('small',null,expense.expense_date||''));
      row.append(left,right);target.append(row);
    }
    if(!target.children.length)target.append(h('p','empty','No expenses recorded.'));
  }catch(e){target.replaceChildren(h('p','empty','Unable to load expenses: '+e.message));}
}
async function saveExpense(event){
  event.preventDefault();if(state.busy || !state.tenant || !state.branch)return;
  const form=event.currentTarget, fields=new FormData(form);
  const category=formValue(fields,'category'),description=formValue(fields,'description');
  const amount=formValue(fields,'amount'),payment_method=formValue(fields,'payment_method');
  if(category.length<2 || description.length<2 || !/^\d+(?:\.\d{1,2})?$/.test(amount) || Number(amount)<=0 ||
    !['cash','bank_transfer','card','mobile_money'].includes(payment_method)){
    notify('Enter a valid category, description, positive amount and payment method.',true);return;
  }
  if(!confirm('Record paid expense of '+money(amount)+' for '+description+'?'))return;
  const tenant=state.tenant.tenant_id,branch=state.branch.id;
  // Keep the operation ID stable after an uncertain server response to avoid accidental duplicate postings.
  if(!state.expensePending)state.expensePending={id:crypto.randomUUID(),tenant,branch,
    category,description,amount,payment_method};
  const pending=state.expensePending;
  if(pending.tenant!==tenant||pending.branch!==branch || pending.category!==category ||
      pending.description!==description||pending.amount!==amount||pending.payment_method!==payment_method){
    notify('A previous expense is awaiting confirmation. Reload the expense list before changing it.',true);
    return;
  }
  state.busy=true;$('save-expense').disabled=true;
  try{
    await request('/expenses',{method:'POST',body:JSON.stringify({
      client_operation_id:pending.id,category,description,amount,payment_method,receipt_document_id:null
    })});
    state.expensePending=null;form.reset();
    notify('Expense recorded.');
    if(state.tenant?.tenant_id===tenant&&state.branch?.id===branch)await loadExpenses();
  }catch(e){notify('Expense was not confirmed: '+e.message+'. Check records before retrying.',true);}
  finally{state.busy=false;$('save-expense').disabled=false;}
}

async function loadSalesReport(event){
  event.preventDefault();
  const start=$('report-start').value,end=$('report-end').value;
  const target=$('sales-report-result');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end)||start>end){
    target.replaceChildren(h('p','empty','Select a valid beginning and ending date.'));return;
  }
  if(!state.tenant || !state.branch)return;
  const tenant=state.tenant.tenant_id,branch=state.branch.id;
  $('run-sales-report').disabled=true;
  target.replaceChildren(h('p','empty','Loading sales report…'));
  try{
    const startIso=start+'T00:00:00.000Z', endIso=end+'T23:59:59.999Z';
    const report=await request('/reports/sales-summary?start='+encodeURIComponent(startIso)+'&end='+encodeURIComponent(endIso));
    if(state.tenant?.tenant_id!==tenant || state.branch?.id!==branch)return;
    target.replaceChildren();
    const records=[
      ['Completed sales',String(report.sale_count??0)],
      ['Gross sales',money(report.gross_sales)],
      ['Returns',money(report.returns_total)],
      ['Net sales',money(report.net_sales)],
      ['Tax',money(report.tax_total)],
      ['Outstanding',money(report.balance_due)],
      ['Cost of goods',money(report.cost_of_goods)],
      ['Gross profit',money(report.gross_profit)],
      ['Refunded amount',money(report.refunded_amount)]
    ];
    for(const [name,value] of records){
      const line=h('div','record');
      line.append(h('strong',null,name),h('span',null,value));
      target.append(line);
    }
  }catch(e){target.replaceChildren(h('p','empty','Sales report unavailable: '+e.message));}
  finally{$('run-sales-report').disabled=false;}
}
async function loadStaff(){
  const target=$('staff-list'),tenant=state.tenant?.tenant_id,branch=state.branch?.id;
  target.replaceChildren(h('p','empty','Loading staff directory…'));
  if(!tenant||!branch)return;
  try{
    const data=await request('/staff');
    if(state.tenant?.tenant_id!==tenant || state.branch?.id!==branch)return;
    state.staff=Array.isArray(data)?data:[];
    renderStaff();
  }catch(e){target.replaceChildren(h('p','empty','Unable to load staff: '+e.message));}
}
function renderStaff(){
  const target=$('staff-list');target.replaceChildren();
  const term=$('staff-search').value.trim().toLowerCase();
  const matches=state.staff.filter(p=>[p.display_name,p.email,p.role].some(v=>
    String(v||'').toLowerCase().includes(term)));
  for(const person of matches){
    const row=h('div','record'),left=h('div'),right=h('div');
    left.append(h('strong',null,person.display_name),
      h('small',null,(person.email||'')+' · '+(person.phone||'No phone')));
    right.append(h('strong',null,person.role||'Unassigned'),
      h('small',null,person.is_active?'Active':'Inactive'),
      h('small',null,(person.branch_ids||[]).length+' assigned branches'));
    row.append(left,right);target.append(row);
  }
  if(!matches.length)target.append(h('p','empty','No staff members found or accessible.'));
}
async function loadPurchasing(){
  const tenant=state.tenant?.tenant_id,branch=state.branch?.id;
  if(!tenant||!branch)return;
  const kinds=[
    {path:'/purchases',target:'purchases-list',empty:'No purchases recorded.',render:(item)=>{
      const row=h('div','record'),left=h('div'),right=h('div');
      left.append(h('strong',null,item.purchase_number||'Purchase'),h('small',null,(item.status||'')+' · '+(item.supplier_invoice_number||'No supplier invoice')));
      right.append(h('strong',null,money(item.total)),h('small',null,'Balance: '+money(item.balance_due)));
      row.append(left,right);return row;
    }},
    {path:'/purchase-orders',target:'orders-list',empty:'No purchase orders found.',render:(item)=>{
      const row=h('div','record'),left=h('div'),right=h('div');
      left.append(h('strong',null,item.order_number||item.purchase_order_number||'Purchase order'),h('small',null,item.status||'Status unavailable'));
      right.append(h('strong',null,money(item.total||item.total_amount)));
      if(item.id){
        const details=h('button','secondary','Details');details.type='button';
        details.addEventListener('click',()=>openPurchaseOrderDetail(item.id));
        right.append(details);
      }
      row.append(left,right);return row;
    }}
  ];
  await Promise.all(kinds.map(async kind=>{
    const target=$(kind.target);target.replaceChildren(h('p','empty','Loading…'));
    try{
      const result=await request(kind.path);
      if(state.tenant?.tenant_id!==tenant||state.branch?.id!==branch)return;
      target.replaceChildren();
      for(const item of (Array.isArray(result)?result:[]))target.append(kind.render(item));
      if(!target.children.length)target.append(h('p','empty',kind.empty));
    }catch(e){target.replaceChildren(h('p','empty','Unable to load: '+e.message));}
  }));
}
async function openPurchaseOrderDetail(id){
  if(!state.tenant||!state.branch)return;
  const tenant=state.tenant.tenant_id,branch=state.branch.id;
  const target=$('order-detail-content');
  target.replaceChildren(h('p','empty','Loading purchase order…'));
  $('order-status-panel').hidden=true;
  $('order-receiving-preview').replaceChildren();
  openView('order-detail');
  try{
    const order=await request('/purchase-orders/'+encodeURIComponent(id));
    if(state.tenant?.tenant_id!==tenant||state.branch?.id!==branch)return;
    if(!order||order.id!==id||!Array.isArray(order.lines))throw new Error('Incomplete purchase order detail.');
    target.replaceChildren();
    const header=h('div','record'),labels=h('div'),totals=h('div');
    labels.append(h('strong',null,order.order_number||'Purchase order'),h('small',null,'Status: '+(order.status||'unknown')));
    totals.append(h('strong',null,money(order.total)),h('small',null,'Subtotal: '+money(order.subtotal)+' · Tax: '+money(order.tax_total)));
    header.append(labels,totals);target.append(header);
    const heading=h('h3',null,'Order line items');target.append(heading);
    for(const line of order.lines){
      const row=h('div','record'),info=h('div'),amount=h('div');
      const product=state.products.find(p=>p.id===line.product_id);
      info.append(h('strong',null,product?.name||'Product '+line.product_id),
        h('small',null,'Ordered: '+line.quantity+' · Received: '+(line.quantity_received||'0')));
      amount.append(h('strong',null,money(line.line_total)),
        h('small',null,'Unit cost: '+money(line.unit_cost)));
      row.append(info,amount);target.append(row);
    }
    if(!order.lines.length)target.append(h('p','empty','No line items available.'));
    renderPurchaseOrderActions(order,tenant,branch);
    renderReceivingReadiness(order);
  }catch(e){target.replaceChildren(h('p','empty','Unable to load purchase order: '+e.message));}
}
function renderReceivingReadiness(order){
  const target=$('order-receiving-preview');target.replaceChildren();
  if(!order||!Array.isArray(order.lines))return;
  const heading=h('h3',null,'Goods receiving readiness');target.append(heading);
  const remaining=order.lines.map(line=>{
    const ordered=Number(line.quantity),received=Number(line.quantity_received||0);
    return {line,ordered,received,outstanding:ordered-received};
  });
  const corrupt=remaining.some(r=>!Number.isFinite(r.ordered)||!Number.isFinite(r.received)||
    r.ordered<=0||r.received<0||r.outstanding<0);
  if(corrupt){target.append(h('p','empty','Invalid receipt quantities. Contact an administrator before receiving goods.'));return;}
  for(const {line,outstanding} of remaining){
    const p=state.products.find(item=>item.id===line.product_id);
    const row=h('div','record');
    row.append(h('strong',null,p?.name||'Product '+line.product_id),
      h('span',null,'Remaining: '+outstanding.toFixed(3)));
    target.append(row);
  }
  const ready=['approved','part_received'].includes(order.status);
  target.append(h('p','hint',ready?
    'Order is eligible for receiving, but web receipt posting is disabled until duplicate protection and stock-ledger updates are verified.':
    'Goods cannot be received until the order is approved. Receipt posting is currently disabled.'));
}
function renderPurchaseOrderActions(order,tenant,branch){
  const panel=$('order-status-panel'),actions=$('order-status-actions');
  panel.hidden=true;actions.replaceChildren();$('order-status-feedback').textContent='';
  if(!order?.id || !state.access || !state.tenant || !state.branch ||
     state.tenant.tenant_id!==tenant||state.branch.id!==branch)return;
  const transitions={draft:'submitted',submitted:'approved'};
  const target=transitions[order.status];
  if(!target)return;
  // Server enforces purchases.write and purchases.approve. Client role is only a presentation hint.
  if(target==='approved' && !['owner','admin','manager'].includes(String(state.tenant.role||'').toLowerCase()))return;
  const button=h('button','primary',target==='approved'?'Approve purchase order':'Submit for approval');
  button.type='button';
  button.addEventListener('click',async()=>{
    if(state.busy||button.disabled || state.tenant?.tenant_id!==tenant || state.branch?.id!==branch)return;
    if(!confirm((target==='approved'?'Approve':'Submit')+' purchase order '+(order.order_number||'')+'? This does not receive stock.'))return;
    state.busy=true;button.disabled=true;
    $('order-status-feedback').textContent='Updating order status…';
    try{
      await request('/purchase-orders/'+encodeURIComponent(order.id)+'/status',
        {method:'PATCH',body:JSON.stringify({status:target})});
      $('order-status-feedback').textContent='Status updated. Refreshing order details…';
      if(state.tenant?.tenant_id===tenant&&state.branch?.id===branch)await openPurchaseOrderDetail(order.id);
    }catch(e){
      $('order-status-feedback').textContent='Status change not confirmed: '+e.message+
        '. Review the current order before attempting another change.';
    }finally{state.busy=false;}
  });
  actions.append(button);panel.hidden=false;
}
async function openPurchaseOrderForm(){
  if(!state.tenant||!state.branch)return;
  const tenant=state.tenant.tenant_id,branch=state.branch.id;
  const supplierSelect=$('purchase-order-supplier'),productSelect=$('purchase-order-product');
  supplierSelect.replaceChildren();productSelect.replaceChildren();
  $('purchase-order-save').disabled=true;
  $('purchase-order-feedback').textContent='Loading current suppliers and products…';
  openView('order-create');
  try{
    const suppliers=await request('/suppliers');
    if(state.tenant?.tenant_id!==tenant||state.branch?.id!==branch)return;
    for(const p of (Array.isArray(suppliers)?suppliers:[])){
      if(!p.id)continue;
      const option=h('option',null,p.name||p.code);option.value=p.id;supplierSelect.append(option);
    }
    for(const p of state.products.filter(item=>item.id&&item.is_active!==false)){
      const option=h('option',null,p.name+' · '+(p.sku||''));option.value=p.id;productSelect.append(option);
    }
    const ready=!!supplierSelect.children.length&&!!productSelect.children.length;
    $('purchase-order-save').disabled=!ready;
    $('purchase-order-feedback').textContent=ready?'': 'Create a supplier and an active product first.';
  }catch(e){$('purchase-order-feedback').textContent='Unable to load suppliers: '+e.message;}
}
async function savePurchaseOrder(event){
  event.preventDefault();
  if(state.busy||$('purchase-order-save').disabled||!state.tenant||!state.branch)return;
  const form=event.currentTarget,fields=new FormData(form);
  const supplier_id=formValue(fields,'supplier_id'),product_id=formValue(fields,'product_id');
  const quantity=formValue(fields,'quantity'),unit_cost=formValue(fields,'unit_cost');
  const notes=formValue(fields,'notes')||null;
  if(!Array.from($('purchase-order-supplier').children).some(x=>x.value===supplier_id) ||
     !state.products.some(p=>p.id===product_id&&p.is_active!==false) ||
     !/^\d+(?:\.\d{1,3})?$/.test(quantity) || Number(quantity)<=0 ||
     !/^\d+(?:\.\d{1,2})?$/.test(unit_cost) || Number(unit_cost)<=0){
    $('purchase-order-feedback').textContent='Select a valid supplier, product, quantity and unit cost.';
    return;
  }
  if(!confirm('Create purchase order? This does not receive stock or pay a supplier.'))return;
  const tenant=state.tenant.tenant_id,branch=state.branch.id;
  state.busy=true;$('purchase-order-save').disabled=true;
  $('purchase-order-feedback').textContent='Submitting purchase order…';
  try{
    await request('/purchase-orders',{method:'POST',body:JSON.stringify({
      supplier_id,notes,lines:[{product_id,quantity,unit_cost,tax_total:0}]
    })});
    $('purchase-order-feedback').textContent='Purchase order created.';
    form.reset();
    if(state.tenant?.tenant_id===tenant&&state.branch?.id===branch){
      openView('purchasing');
    }
  }catch(e){
    // The order endpoint has no documented idempotency contract: refuse blind resubmits.
    $('purchase-order-feedback').textContent='Submission is unconfirmed: '+e.message+
      '. Return to Purchasing, refresh orders and verify before trying again.';
  }finally{state.busy=false;}
}
async function verifyQr(){
  const token=$('qr-code').value.trim(),box=$('qr-result');box.hidden=false;
  if(!token.startsWith('khanyaqr:v1:')){box.textContent='This is not a Khanya QR locator.';return;}
  box.textContent='Checking signed QR with the server…';
  try{
    const response=await request('/qr/resolve',{method:'POST',body:JSON.stringify({token})});
    box.textContent='Verified '+response.kind+' · '+response.resource_id+'\nAccessible within your current business.';
  }catch(e){box.textContent='QR verification failed: '+e.message;}
}
function openView(name){
  state.currentView=name;
  for(const el of document.querySelectorAll('.view'))el.hidden=el.id!==name+'-view';
  for(const el of document.querySelectorAll('.tab'))el.classList.toggle('active',el.dataset.view===name);
  if(name==='history')loadHistory();
  if(name==='customers')loadCustomers();
  if(name==='suppliers')loadSuppliers();
  if(name==='expenses')loadExpenses();
  if(name==='staff')loadStaff();
  if(name==='purchasing')loadPurchasing();
  if(name==='stock')renderStock();
}
$('login-form').addEventListener('submit',login);
$('logout').addEventListener('click',()=>signOut());
$('tenant-picker').addEventListener('change',()=>switchScope('tenant'));
$('branch-picker').addEventListener('change',()=>switchScope('branch'));
$('product-search').addEventListener('input',renderProducts);
$('cash-received').addEventListener('input',renderCart);
$('clear-cart').addEventListener('click',()=>{if(state.busy)return;state.cart.clear();state.pendingId=null;renderCart();});
$('complete-sale').addEventListener('click',checkout);
$('refresh-products').addEventListener('click',()=>loadProducts().catch(e=>notify(e.message,true)));
$('catalog-refresh').addEventListener('click',()=>loadProducts().catch(e=>notify(e.message,true)));
$('history-refresh').addEventListener('click',loadHistory);
$('verify-qr').addEventListener('click',verifyQr);
$('product-form').addEventListener('submit',saveProduct);
$('cancel-product-edit').addEventListener('click',()=>{if(!state.busy)cancelProductEdit();});
$('barcode-form').addEventListener('submit',submitBarcode);
$('product-qr-form').addEventListener('submit',submitProductQr);
$('stock-form').addEventListener('submit',saveStock);
$('customer-form').addEventListener('submit',saveCustomer);
$('stock-refresh').addEventListener('click',()=>loadProducts().catch(e=>notify(e.message,true)));
$('customers-refresh').addEventListener('click',loadCustomers);
$('suppliers-refresh').addEventListener('click',loadSuppliers);
$('suppliers-search').addEventListener('input',renderSuppliers);
$('supplier-form').addEventListener('submit',saveSupplier);
$('expenses-refresh').addEventListener('click',loadExpenses);
$('expense-form').addEventListener('submit',saveExpense);
$('sales-report-form').addEventListener('submit',loadSalesReport);
$('staff-refresh').addEventListener('click',loadStaff);
$('staff-search').addEventListener('input',renderStaff);
$('purchases-refresh').addEventListener('click',loadPurchasing);
$('orders-refresh').addEventListener('click',loadPurchasing);
$('order-create-open').addEventListener('click',openPurchaseOrderForm);
$('order-create-back').addEventListener('click',()=>openView('purchasing'));
$('order-detail-back').addEventListener('click',()=>openView('purchasing'));
$('purchase-order-form').addEventListener('submit',savePurchaseOrder);
$('customers-search').addEventListener('input',renderCustomers);
for(const tab of document.querySelectorAll('.tab'))tab.addEventListener('click',()=>openView(tab.dataset.view));
renderCart();
