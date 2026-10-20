# Actividad 2.3: EscolarOnline en EKS y RDS

Copia de trabajo para probar el material oficial de ARY1102 en AWS Academy Learner Lab.
Ubicación principal: `repos/ary1102/ary1102-act-2-3-eks-escolaronline`.
Repositorio público: [v-teacher/ary1102-act-2-3-eks-escolaronline](https://github.com/v-teacher/ary1102-act-2-3-eks-escolaronline).

## Estado

Prueba funcional completada: EKS, RDS Multi-AZ, CRUD por ALB,
persistencia tras reemplazar un pod y escalamiento HPA de dos a cuatro réplicas.
Consultar [evidencias y límites](docs/validacion.md).

- [Presentación tipo infografía](docs/index.html), navegable en el navegador.
- [Guía paso a paso AWS CLI](docs/guia-aws-cli.md), ruta alternativa sin un segundo despliegue ejecutado.

## Infraestructura de prueba

- Perfil `learner-lab`, región `us-east-1`.
- VPC dedicada, seis subredes en dos zonas: públicas, aplicación privada y datos privados.
- Un NAT Gateway para reducir el costo de laboratorio. No proporciona redundancia de salida entre zonas.
- EKS 1.34 con roles existentes del laboratorio, sin crear roles ni modificar políticas IAM.
- Dos nodos t3.medium x86_64, máximo cuatro. El máximo del grupo no instala un autoscaler de nodos.
- RDS MySQL 8.0.43 db.t3.micro Multi-AZ, cifrado y sin acceso público.
- Cinco repositorios ECR para frontend y operaciones CRUD.

Los tipos x86_64 sustituyen los Graviton del anexo para esta prueba. Las imágenes
deben coincidir con la arquitectura de los nodos. No copiar versiones sin revisar disponibilidad.

## Correcciones de aplicación

El frontend usa el mismo origen HTTP para todas las operaciones. El Ingress envía
tráfico al frontend Nginx, que selecciona el servicio interno según el método HTTP.
Esto corrige los puertos públicos 3001–3004 y la distribución exclusiva al servicio GET
del paquete original. Los Services de backend siguen siendo ClusterIP.

El frontend Nginx usa DNS de Kubernetes. No se puede usar esta misma configuración
sin cambios dentro del Compose original: ese entorno no tiene el DNS de Kubernetes.

## Secuencia reproducible

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

La inicialización SQL agrega cinco filas por ejecución. No repetir el Job sin revisar
el estado de los datos. El test CRUD crea un registro temporal y elimina solo ese registro.

## Seguridad y costos

El CRUD no implementa autenticación. Mantener el balanceador restringido a una IP
de prueba y usar datos ficticios. HTTP es una limitación de esta demostración, no un
control de seguridad productivo. No publicar credenciales ni archivos de estado.

El estado Terraform contiene la contraseña RDS, aunque la salida esté marcada como
sensible. Proteger `terraform/terraform.tfstate*` y `secrets/`; nunca incorporarlos a Git.
La copia de trabajo excluye el Secret de ejemplo del paquete oficial; las credenciales
reales se generan desde Terraform y se configuran solo en los manifiestos privados.

EKS, nodos, RDS Multi-AZ, NAT, balanceador y almacenamiento consumen presupuesto.
Al cerrar, retirar primero Ingress y esperar la eliminación del balanceador, luego
eliminar cargas y ejecutar `terraform destroy` tras revisar el plan. Esta configuración
de laboratorio omite el snapshot final de RDS y permite borrar imágenes ECR: destruirla
elimina datos e imágenes de la prueba.
