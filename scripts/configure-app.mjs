import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const run=(cmd,args,opts={})=>execFileSync(cmd,args,{encoding:'utf8',...opts});
// Leer valores en memoria, sin imprimir ni copiar el estado a los manifiestos.
const state=JSON.parse(run('terraform',['-chdir=terraform','show','-json']));
const outputs=state.values?.outputs ?? {};
const password=outputs.db_password?.value ?? state.values?.root_module?.resources?.find(r=>r.address==='random_password.db')?.values?.result;
const account=run('aws',['sts','get-caller-identity','--profile','learner-lab','--query','Account','--output','text']).trim();
const host=outputs.db_host?.value ?? JSON.parse(run('aws',['rds','describe-db-instances','--profile','learner-lab','--region','us-east-1','--db-instance-identifier','ary1102-act23'])).DBInstances[0]?.Endpoint?.Address;
if(!password || !host)throw Error('Aún no están disponibles los valores necesarios de RDS');
const ip=run('curl',['--fail','--silent','https://checkip.amazonaws.com']).trim();
if(!/^\d+\.\d+\.\d+\.\d+$/.test(ip))throw Error('No se obtuvo la IPv4 del operador');
fs.mkdirSync('secrets',{recursive:true,mode:0o700});
const generated='secrets/k8s';
fs.mkdirSync(generated,{recursive:true,mode:0o700});
for(const f of fs.readdirSync('app/k8s')){
  if(f==='secret.yaml')continue;
  let text=fs.readFileSync('app/k8s/'+f,'utf8');
  text=text.replaceAll('<ACCOUNT_ID>',account).replaceAll('<RDS_ENDPOINT>',host)
    .replaceAll('<ACT_NAME>','ary1102-act23')
    .replaceAll('/escolaronline-','/ary1102-act23-').replaceAll(':latest',':validation').replaceAll('<OPERATOR_CIDR>',ip+'/32');
  fs.writeFileSync(generated+'/'+f,text,{mode:0o600});
}
fs.writeFileSync(generated+'/secret.json',JSON.stringify({apiVersion:'v1',kind:'Secret',metadata:{name:'escolaronline-secret',namespace:'escolaronline'},type:'Opaque',stringData:{DB_USER:'alumno',DB_PASS:password}}),{mode:0o600});
console.log('Manifiestos preparados en secrets/k8s (no versionados).');
