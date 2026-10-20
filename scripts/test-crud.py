"""Prueba de humo CRUD: crea y elimina exclusivamente su propio registro."""
import json
import sys
import time
from urllib.request import Request, urlopen

base = sys.argv[1].rstrip('/')
def request(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    with urlopen(Request(base+path, data=body, method=method, headers={'Content-Type':'application/json'}), timeout=30) as response:
        return response.status, json.load(response)

_, rows = request('GET','/api/products')
print('GET OK, productos:',len(rows))
payload = {'nombre':'Validacion-Act23-'+str(int(time.time())), 'descripcion':'Registro descartable de prueba', 'precio':590, 'stock':2, 'categoria':'Prueba'}
status, created = request('POST','/api/products',payload)
assert status == 201
identifier = created['id']
print('POST OK, id:',identifier)
try:
    payload['stock'] = 3
    status, updated = request('PUT',f'/api/products/{identifier}',payload)
    assert updated['stock'] == 3
    print('PUT OK')
    _, rows = request('GET','/api/products')
    assert any(row['id']==identifier and row['stock']==3 for row in rows)
    print('Persistencia de cambios OK')
finally:
    request('DELETE',f'/api/products/{identifier}')
    print('DELETE OK (registro de prueba retirado)')
