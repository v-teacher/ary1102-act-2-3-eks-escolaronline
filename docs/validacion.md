# Validación manual en AWS Learner Lab: actividad 2.3

Fecha: 2026-10-20. Región: `us-east-1`. Perfil: `learner-lab`.
Stack probado: `ary1102-act23-cli`. El entorno permanece desplegado y genera costos.

## Resultados observados

| Comprobación | Evidencia de la ruta AWS CLI |
|---|---|
| Identidad y acceso | STS confirmó la cuenta del Learner Lab; el API público de EKS está limitado al CIDR `/32` del operador |
| Red | VPC dedicada, seis subredes en dos zonas, un NAT Gateway; nodos y RDS en subredes privadas |
| EKS | Clúster `ACTIVE`, Kubernetes 1.34; dos nodos `Ready` tipo `t3.medium` x86_64 |
| Auto Mode | Actualización `Successful`; balanceo integrado activo |
| ECR | Cinco repositorios; imágenes `validation` de frontend y los cuatro servicios CRUD descargadas por los pods |
| RDS | MySQL 8.0.43 `Available`, Multi-AZ, cifrado y no público; ingreso MySQL permitido solo desde el grupo de seguridad de EKS |
| Inicialización SQL | Job `init-db` completado; cinco productos de muestra disponibles |
| Deployments | Cinco Deployments; todas las réplicas iniciales `Running` y Services `ClusterIP` |
| ALB | Estado `active`; los dos targets del frontend `healthy`; Ingress restringido al CIDR `/32` del operador |
| Frontend | HTTP 200 por el ALB |
| CRUD | GET, POST, PUT y DELETE exitosos por el ALB; el registro sintético se eliminó |
| Persistencia | Registro conservado en RDS tras reemplazar un pod `get-products`; el registro de prueba se eliminó |
| Metrics Server | Add-on `ACTIVE`; `kubectl top` entregó métricas de nodos y pods |
| HPA | `get-products` escaló de 2 a 4 réplicas con carga CPU sintética de 120 s; máximo observado: 125% frente al objetivo de 70% |

Las validaciones CRUD y persistencia se ejecutaron primero desde un port-forward y luego
a través del ALB. Los registros temporales se retiraron; los cinco productos de muestra
permanecieron. El HPA puede tardar unos minutos en regresar al mínimo por su ventana de
estabilización. Esta prueba no representa carga de usuarios.

## Correcciones durante la prueba

- La primera ejecución del Job SQL falló antes de conectarse a MySQL: el generador de
  manifiestos modificó accidentalmente el hostname de RDS al sustituir el nombre de
  la IngressClass. No se ejecutó SQL en ese intento. Se corrigió usando el marcador
  explícito `<ACT_NAME>`, se regeneró el ConfigMap y el Job terminó correctamente.
- Se verificó que el endpoint de RDS renderizado coincide exactamente con el endpoint
  entregado por AWS; la IngressClass de los manifiestos usa `ary1102-act23-cli`.
- El renderer Terraform también reemplaza `<ACT_NAME>` por `ary1102-act23`, de modo que
  la plantilla compartida de Ingress conserva el nombre esperado por esa ruta.
- Las imágenes se construyeron para x86_64 y se publicaron en ECR antes de aplicar los
  Deployments. El token local de Docker se retiró con `docker logout` después del push.

## Límites

- La carga HPA fue un proceso CPU sintético dentro de un pod, no tráfico real de usuarios.
- No se ejecutaron failover de RDS, recuperación de backups ni prueba de pérdida de zona.
- Un solo NAT Gateway reduce costo, pero no ofrece redundancia de salida entre zonas.
- La aplicación no implementa autenticación y el ALB usa HTTP, sin TLS público.
- Container Insights no se instaló ni se acreditó; Metrics Server no lo sustituye.
- Esta validación acredita el despliegue funcional en el laboratorio, no aptitud
  productiva ni una auditoría de seguridad.
- El stack manual no está administrado por Terraform. La prueba Terraform previa se
  destruyó por separado; su antiguo resultado `No changes` no describe este stack CLI.

## Entorno activo y retiro

Los recursos del stack `ary1102-act23-cli` siguen desplegados. EKS, los nodos, RDS
Multi-AZ, NAT, ALB y almacenamiento consumen presupuesto mientras estén activos. No se
ejecutó limpieza al terminar esta validación. Para retirarlos, seguir la sección 11 de
[la guía manual AWS CLI](guia-aws-cli.md), verificando nombre, región e IDs antes de
borrar recursos. No ejecutar `terraform destroy` para este stack.

El kubeconfig utilizado es `secrets/kubeconfig-cli`; los manifiestos con credenciales
están en `secrets/cli-k8s/`. Mantener ambos fuera de Git.
