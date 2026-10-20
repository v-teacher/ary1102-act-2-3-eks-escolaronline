# Aplicación EscolarOnline adaptada para la actividad 2.3

Código de apoyo basado en el material oficial de ARY1102, diseñado por Ignacio A.
Pastenet M. Esta copia incorpora ajustes verificados en AWS Learner Lab.

Consultar el [README principal](../README.md) para el procedimiento vigente,
la [guía AWS CLI](../docs/guia-aws-cli.md) y los [resultados](../docs/validacion.md).

## Componentes

- Frontend Nginx con llamadas del navegador al mismo origen público.
- Cuatro servicios Node.js: get-products, create-product, update-product y delete-product.
- Manifiestos Kubernetes en `k8s/` y esquema de inicialización en `init.sql`.

La prueba usa imágenes x86_64, nodos t3.medium, RDS db.t3.micro Multi-AZ y ALB
administrado por EKS Auto Mode con roles existentes del laboratorio. No seguir
las versiones, rutas ARM ni pasos de instalación del controlador del anexo sin adaptación.

La configuración Nginx utiliza DNS de Kubernetes. El Compose original queda como
antecedente y no se validó con esta adaptación: no usarlo como una ruta equivalente.
Las credenciales reales se generan fuera de esta carpeta, en `secrets/`, excluido de Git.
