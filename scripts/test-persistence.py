"""Comprueba persistencia al reemplazar un pod GET, no un failover RDS."""
import json
import os
import subprocess
import sys
import time
from urllib.request import Request, urlopen

base=sys.argv[1].rstrip('/')
def request(method,path,data=None):
    with urlopen(Request(base+path,method=method,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'}),timeout=30) as r:
        return json.load(r)
def kube(*args):
    return subprocess.check_output(['kubectl','--kubeconfig',os.environ.get('KUBECONFIG','.kubeconfig'),*args],text=True)
created=request('POST','/api/products',{'nombre':'Persistencia-'+str(int(time.time())),'descripcion':'Prueba descartable','precio':100,'stock':1,'categoria':'Prueba'})
identifier=created['id']
try:
    pods=json.loads(kube('get','pods','-n','escolaronline','-l','app=get-products','-o','json'))['items']
    pod=pods[0]['metadata']['name']
    print('Registro creado:',identifier,'Pod a reemplazar:',pod,flush=True)
    print(kube('delete','pod',pod,'-n','escolaronline','--timeout=60s').strip(),flush=True)
    print(kube('rollout','status','deployment/get-products','-n','escolaronline','--timeout=90s').strip(),flush=True)
    rows=request('GET','/api/products')
    assert any(row['id']==identifier for row in rows)
    remaining=json.loads(kube('get','pods','-n','escolaronline','-l','app=get-products','-o','json'))['items']
    assert pod not in [p['metadata']['name'] for p in remaining]
    print('Persistencia tras reemplazo de pod: OK',flush=True)
finally:
    request('DELETE',f'/api/products/{identifier}')
    print('Registro de prueba retirado',flush=True)
