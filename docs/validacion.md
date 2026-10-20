# Validación en AWS Learner Lab: actividad 2.3

Fecha: 2026-10-20. Región: us-east-1. Perfil: learner-lab.
Proyecto: `ary1102-act23`. Recursos de la prueba permanecen desplegados y generan costos.

## Resultados observados

| Comprobación | Evidencia obtenida |
|---|---|
| Credenciales | STS respondió correctamente para el perfil learner-lab |
| EKS | Clúster ACTIVE, versión 1.34, dos nodos Ready |
| ECR | Cinco repositorios con imágenes descargadas por los pods |
| Aplicación | Cinco Deployments con dos réplicas iniciales: diez pods Running |
| Publicación | ALB activo, target-type ip, frontend HTTP 200 |
| RDS | Available, MultiAZ true, cifrado y sin acceso público |
| Inicialización SQL | Job completado, cinco productos originales |
| CRUD por ALB | GET, POST, PUT y DELETE exitosos con registro sintético propio |
| Persistencia | Registro conservado tras eliminar y reemplazar un pod GET |
| Métricas | Add-on Metrics Server ACTIVE; kubectl top entregó métricas |
| HPA | get-products aumentó de dos a cuatro réplicas; métrica CPU observada 125% frente a objetivo 70% |
| Consistencia Terraform | Plan posterior: No changes |

Los registros creados por las pruebas CRUD y persistencia se retiraron. Los cinco
productos de muestra se conservaron. La carga CPU terminó automáticamente tras dos minutos.
El número de pods puede superar diez durante el escalamiento y regresar al mínimo tras estabilización.

## Adaptaciones y problemas corregidos

- x86_64 con t3.medium en lugar de los Graviton indicados en el anexo.
- Roles EKS específicos ya existentes. No se crearon roles ni se modificaron políticas IAM.
- EKS Auto Mode administró el ALB. No se instaló AWS Load Balancer Controller manualmente.
- Frontend con un único origen; Nginx distribuye GET/POST/PUT/DELETE a los Services internos.
- El primer GET por ALB falló con 502 por DNS corto en el resolver de Nginx.
  Se corrigió usando nombres completos `servicio.escolaronline.svc.cluster.local`.
- Se controló la descarga de la imagen corregida con `imagePullPolicy: Always`.
  Durante la actualización hubo un 504 transitorio antes del CRUD exitoso.
- MySQL se inicializó mediante un Job privado, sin publicar el puerto 3306.
- ALB restringido al CIDR /32 del operador. No se abrió el CRUD sin autenticación a todo Internet.

## Límites

- La prueba HPA usó CPU sintética dentro de un pod, no tráfico real de usuarios.
- No se ejecutó failover de RDS, recuperación de backup ni prueba de pérdida de zona.
- Un NAT Gateway no proporciona redundancia de salida.
- No hay TLS público ni autenticación de usuarios en el código de ejemplo.
- Container Insights no se instaló ni se acreditó. El rol de nodos no tiene adjunta
  CloudWatchAgentServerPolicy; no se modificó IAM para agregarla. No se afirma un
  AccessDenied de instalación porque esa instalación no se ejecutó.
- Metrics Server no sustituye Container Insights. Los logs del plano de control tampoco.
- El código recibido usa Node 18 y dependencias sin lockfile. Esta prueba acredita
  funcionalidad del laboratorio, no aptitud productiva ni una auditoría de seguridad.
- La ruta AWS CLI de la guía es una alternativa documental. El aprovisionamiento
  ejecutado usó Terraform y después AWS CLI/kubectl para complementos y aplicación.

## Ubicación y cierre

Conservar el estado Terraform y `secrets/` fuera de Git. El kubeconfig es exclusivo
de este proyecto. No publicar contraseñas, kubeconfigs ni planes.

Para retirar, eliminar primero el Ingress y esperar que desaparezcan ALB y recursos
asociados. Revisar después el plan `terraform plan -destroy` y ejecutar la destrucción
solo cuando corresponda cerrar la demostración. Esta configuración elimina los
datos RDS sin snapshot final y las imágenes ECR de la prueba.
