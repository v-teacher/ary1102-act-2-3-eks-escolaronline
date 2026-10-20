# Actividad 2.3: EscolarOnline en EKS y RDS

## Estado

La ruta manual AWS CLI fue probada de punta a punta en Learner Lab: EKS, RDS
Multi-AZ, cinco imágenes en ECR, CRUD por ALB, persistencia tras reemplazar un pod
y escalamiento HPA de dos a cuatro réplicas. Consultar
[evidencias y límites](docs/validacion.md).

- [Presentación tipo infografía](docs/index.html), navegable en el navegador.
- [Guía paso a paso AWS CLI](docs/guia-aws-cli.md), usada para el despliegue manual.

## Infraestructura de prueba

- Perfil `learner-lab`, región `us-east-1`.
- VPC dedicada, seis subredes en dos zonas: públicas, aplicación privada y datos privados.
- Un NAT Gateway para reducir el costo de laboratorio. No proporciona redundancia de salida entre zonas.
- EKS 1.34 con roles existentes del laboratorio, sin crear roles ni modificar políticas IAM.
- Dos nodos t3.medium x86_64, máximo cuatro. El máximo del grupo no instala un autoscaler de nodos.
- RDS MySQL 8.0.43 db.t3.micro Multi-AZ, cifrado y sin acceso público.
- Cinco repositorios ECR para frontend y operaciones CRUD.
- Endpoint de administración de EKS y ALB restringidos a la IP del operador (/32).

Los tipos x86_64 sustituyen los Graviton del anexo para esta prueba. Las imágenes
deben coincidir con la arquitectura de los nodos. No copiar versiones sin revisar disponibilidad.

## Correcciones de aplicación

El frontend usa el mismo origen HTTP para todas las operaciones. El Ingress envía
tráfico al frontend Nginx, que selecciona el servicio interno según el método HTTP.
Esto corrige los puertos públicos 3001–3004 y la distribución exclusiva al servicio GET
del paquete original. Los Services de backend siguen siendo ClusterIP.

El frontend Nginx usa DNS de Kubernetes. No se puede usar esta misma configuración
sin cambios dentro del Compose original: ese entorno no tiene el DNS de Kubernetes.

## Ruta Terraform

1. Validar identidad: `aws sts get-caller-identity --profile learner-lab`.
2. Revisar roles/servicios permitidos, presupuesto y región.
3. Ejecutar `terraform init`, `terraform plan` y revisar antes de `terraform apply` dentro de `terraform/`.
4. Ejecutar `bash scripts/build-images.sh` para construir las cinco imágenes x86_64.
5. Ejecutar `bash scripts/push-images.sh` desde la raíz.
6. Configurar un kubeconfig exclusivo del proyecto, sin reemplazar configuraciones de otros clústeres.
7. Ejecutar `node scripts/configure-app.mjs`. Los manifiestos reales y credenciales quedan en `secrets/`, excluido de Git.
8. Aplicar namespace, configuración y credenciales. Crear ConfigMap de `app/init.sql` y ejecutar el Job de inicialización una sola vez.
9. Aplicar deployments y servicios. Verificar su disponibilidad antes de publicar.
10. Configurar el balanceador con el mecanismo compatible con IAM del laboratorio y restringir acceso al operador.
11. Instalar Metrics Server compatible, aplicar HPA y medir su comportamiento.
12. Ejecutar `python3 scripts/test-crud.py http://DNS_DEL_ALB`.

## Ruta manual AWS CLI

Para aprovisionar los mismos componentes sin Terraform, seguir
[la guía manual de AWS CLI](docs/guia-aws-cli.md). Esta ruta usa el identificador
independiente `ary1102-act23-cli`; no mezclar sus recursos ni su limpieza con la
ruta Terraform.

La inicialización SQL agrega cinco filas por ejecución. No repetir el Job sin revisar
el estado de los datos. El test CRUD crea un registro temporal y elimina solo ese registro.

## Seguridad y costos

El CRUD no implementa autenticación. Mantener el balanceador restringido a una IP
de prueba y usar datos ficticios. HTTP es una limitación de esta demostración, no un
control de seguridad productivo. No publicar credenciales ni archivos de estado.

El estado Terraform contiene la contraseña RDS, aunque la salida esté marcada como
sensible. Proteger `terraform/terraform.tfstate*` y `secrets/`; nunca incorporarlos a Git.
La copia de trabajo excluye el Secret de ejemplo del paquete oficial; las credenciales
reales se generan mediante Terraform o el helper de la ruta CLI y solo se configuran
en manifiestos privados.

EKS, nodos, RDS Multi-AZ, NAT, balanceador y almacenamiento consumen presupuesto.
Los recursos CLI de la prueba permanecen desplegados y generan costos. Para retirarlos,
seguir la sección de limpieza de la [guía manual AWS CLI](docs/guia-aws-cli.md), que
elimina los datos y las imágenes de prueba. La ruta Terraform se destruye por separado,
revisando su plan antes de ejecutar `terraform destroy`.
