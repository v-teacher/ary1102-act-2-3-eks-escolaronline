import fs from 'node:fs';
for(const key of ['ACT_NAME','ACT_ACCOUNT','ACT_DB_HOST','ACT_DB_PASSWORD','ACT_OPERATOR_CIDR'])if(!process.env[key])throw Error('Falta variable '+key);
const e=process.env;
if(!/^\d+\.\d+\.\d+\.\d+\/32$/.test(e.ACT_OPERATOR_CIDR))throw Error('CIDR de operador inválido');
fs.mkdirSync('secrets/cli-k8s',{recursive:true,mode:0o700});
for(const f of fs.readdirSync('app/k8s')){
 const s=fs.readFileSync('app/k8s/'+f,'utf8').replaceAll('<ACCOUNT_ID>',e.ACT_ACCOUNT).replaceAll('<RDS_ENDPOINT>',e.ACT_DB_HOST).replaceAll('<OPERATOR_CIDR>',e.ACT_OPERATOR_CIDR).replaceAll('<ACT_NAME>',e.ACT_NAME).replaceAll('/escolaronline-','/'+e.ACT_NAME+'-').replaceAll(':latest',':validation');
 fs.writeFileSync('secrets/cli-k8s/'+f,s,{mode:0o600});
}
fs.writeFileSync('secrets/cli-k8s/secret.json',JSON.stringify({apiVersion:'v1',kind:'Secret',metadata:{name:'escolaronline-secret',namespace:'escolaronline'},type:'Opaque',stringData:{DB_USER:'alumno',DB_PASS:e.ACT_DB_PASSWORD}}),{mode:0o600});
console.log('Manifiestos CLI privados preparados.');
