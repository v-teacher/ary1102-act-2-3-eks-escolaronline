# Implementación paso a paso con AWS CLI

## Alcance y precaución

El despliegue de prueba `ary1102-act23` se validó usando Terraform, AWS CLI, Docker
y kubectl. Este guion describe una **ruta alternativa de aprovisionamiento con AWS CLI**:
no se ejecutó un segundo despliegue completo con estos comandos. No ejecutar este
guion contra los recursos gestionados por Terraform ni importar sus IDs por accidente.

Se utiliza el nombre independiente `ary1102-act23-cli` para una eventual reproducción.
También consume presupuesto. Revisar disponibilidad, versiones, permisos y costos
antes de ejecutarlo. No crear otro entorno solo para observar comandos en clase.

AWS CLI crea recursos AWS. Docker construye/publica imágenes y kubectl configura
los objetos Kubernetes. Las tres herramientas cumplen tareas distintas.

Los bloques se ejecutan en la misma terminal Bash, desde la raíz del proyecto.
No activar `set -x` ni imprimir las variables de contraseña. Conservar los IDs de
recursos para su retiro posterior, sin guardar secretos en Git ni capturas.

## 1. Identidad, variables y roles existentes

```bash
set -euo pipefail
export AWS_PROFILE=learner-lab AWS_DEFAULT_REGION=us-east-1
ACT_NAME=ary1102-act23-cli
ACT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ACT_REGISTRY="$ACT_ACCOUNT.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
aws sts get-caller-identity
aws eks list-clusters
ACT_CLUSTER_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LabEksClusterRole')].Arn | [0]" --output text)
ACT_NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LabEksNodeRole')].Arn | [0]" --output text)
test "$ACT_CLUSTER_ROLE" != None && test "$ACT_NODE_ROLE" != None
# Verificar que el nombre no exista y que se está en la cuenta correcta.
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$ACT_NAME"
aws eks describe-cluster-versions \
  --query 'clusterVersions[?versionStatus==`STANDARD_SUPPORT`].clusterVersion'
```

Este laboratorio dispone de roles específicos para clúster y nodos. No crear ni
modificar IAM para reproducir la demostración. Validar nuevamente si se cambia de cuenta.

## 2. VPC, subredes y rutas

```bash
ACT_VPC=$(aws ec2 create-vpc --cidr-block 10.24.0.0/22 --query Vpc.VpcId --output text)
aws ec2 create-tags --resources "$ACT_VPC" --tags "Key=Name,Value=$ACT_NAME" "Key=Project,Value=$ACT_NAME"
aws ec2 modify-vpc-attribute --vpc-id "$ACT_VPC" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$ACT_VPC" --enable-dns-hostnames '{"Value":true}'
ACT_IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$ACT_IGW" --vpc-id "$ACT_VPC"

ACT_PUB=() ACT_APP=() ACT_DATA=()
for ACT_I in 0 1; do
  ACT_AZ=(us-east-1a us-east-1b)
  ACT_PUB+=("$(aws ec2 create-subnet --vpc-id "$ACT_VPC" --availability-zone "${ACT_AZ[$ACT_I]}" --cidr-block "10.24.0.$((ACT_I*128))/25" --query Subnet.SubnetId --output text)")
  ACT_APP+=("$(aws ec2 create-subnet --vpc-id "$ACT_VPC" --availability-zone "${ACT_AZ[$ACT_I]}" --cidr-block "10.24.1.$((ACT_I*128))/25" --query Subnet.SubnetId --output text)")
  ACT_DATA+=("$(aws ec2 create-subnet --vpc-id "$ACT_VPC" --availability-zone "${ACT_AZ[$ACT_I]}" --cidr-block "10.24.2.$((ACT_I*128))/25" --query Subnet.SubnetId --output text)")
  aws ec2 modify-subnet-attribute --subnet-id "${ACT_PUB[$ACT_I]}" --map-public-ip-on-launch
  aws ec2 create-tags --resources "${ACT_PUB[$ACT_I]}" --tags Key=kubernetes.io/role/elb,Value=1 "Key=Project,Value=$ACT_NAME"
  aws ec2 create-tags --resources "${ACT_APP[$ACT_I]}" --tags Key=kubernetes.io/role/internal-elb,Value=1 "Key=Project,Value=$ACT_NAME"
done
ACT_PUBLIC_RT=$(aws ec2 create-route-table --vpc-id "$ACT_VPC" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$ACT_PUBLIC_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$ACT_IGW"
for ACT_SUBNET in "${ACT_PUB[@]}"; do
  aws ec2 associate-route-table --route-table-id "$ACT_PUBLIC_RT" --subnet-id "$ACT_SUBNET"
done
ACT_EIP=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
ACT_NAT=$(aws ec2 create-nat-gateway --subnet-id "${ACT_PUB[0]}" --allocation-id "$ACT_EIP" --query NatGateway.NatGatewayId --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids "$ACT_NAT"
ACT_APP_RT=$(aws ec2 create-route-table --vpc-id "$ACT_VPC" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$ACT_APP_RT" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$ACT_NAT"
for ACT_SUBNET in "${ACT_APP[@]}"; do
  aws ec2 associate-route-table --route-table-id "$ACT_APP_RT" --subnet-id "$ACT_SUBNET"
done
ACT_DATA_RT=$(aws ec2 create-route-table --vpc-id "$ACT_VPC" --query RouteTable.RouteTableId --output text)
for ACT_SUBNET in "${ACT_DATA[@]}"; do
  aws ec2 associate-route-table --route-table-id "$ACT_DATA_RT" --subnet-id "$ACT_SUBNET"
done
```

Datos no tiene ruta a Internet. Un NAT para las dos zonas es una simplificación
de laboratorio y no acredita redundancia de salida. Antes de seguir, revisar
subredes, rutas, tags, DNS y los recursos creados.

## 3. EKS y acceso de administración

```bash
aws eks create-cluster --name "$ACT_NAME" --kubernetes-version 1.34 \
  --role-arn "$ACT_CLUSTER_ROLE" \
  --resources-vpc-config "subnetIds=${ACT_APP[0]},${ACT_APP[1]},endpointPrivateAccess=true,endpointPublicAccess=true" \
  --access-config authenticationMode=API_AND_CONFIG_MAP,bootstrapClusterCreatorAdminPermissions=true \
  --tags "Project=$ACT_NAME"
aws eks wait cluster-active --name "$ACT_NAME"
export KUBECONFIG="$PWD/secrets/kubeconfig-cli"
mkdir -p secrets && chmod 700 secrets
aws eks update-kubeconfig --name "$ACT_NAME" --alias "$ACT_NAME" --kubeconfig "$KUBECONFIG"
ACT_EKS_SG=$(aws eks describe-cluster --name "$ACT_NAME" --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
```

El endpoint público usa autenticación AWS y autorización Kubernetes. Para mayor
restricción, limitar sus CIDR de acceso al operador o usar acceso privado con conectividad adecuada.

## 4. Dos nodos privados x86_64

```bash
aws eks create-nodegroup --cluster-name "$ACT_NAME" --nodegroup-name "$ACT_NAME" \
  --node-role "$ACT_NODE_ROLE" --subnets "${ACT_APP[@]}" \
  --instance-types t3.medium --ami-type AL2023_x86_64_STANDARD \
  --scaling-config minSize=2,maxSize=4,desiredSize=2
aws eks wait nodegroup-active --cluster-name "$ACT_NAME" --nodegroup-name "$ACT_NAME"
kubectl get nodes
```

El máximo cuatro del node group no instala un autoscaler de nodos. Comprobar dos
nodos `Ready` y CoreDNS/CNI/kube-proxy funcionales antes de continuar.

## 5. RDS MySQL privado y Multi-AZ

```bash
ACT_DB_SG=$(aws ec2 create-security-group --group-name "$ACT_NAME-db" --description 'MySQL desde EKS' --vpc-id "$ACT_VPC" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$ACT_DB_SG" --protocol tcp --port 3306 --source-group "$ACT_EKS_SG"
aws rds create-db-subnet-group --db-subnet-group-name "$ACT_NAME" \
  --db-subnet-group-description 'Datos privados en dos AZ' --subnet-ids "${ACT_DATA[@]}"
export ACT_NAME ACT_DB_SG
export ACT_DB_PASSWORD=$(openssl rand -hex 16)
node scripts/cli-rds-input.mjs
aws rds create-db-instance --cli-input-json file://secrets/rds-cli.json
aws rds wait db-instance-available --db-instance-identifier "$ACT_NAME"
ACT_DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "$ACT_NAME" --query 'DBInstances[0].Endpoint.Address' --output text)
aws rds describe-db-instances --db-instance-identifier "$ACT_NAME" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ,Public:PubliclyAccessible}'
```

El JSON privado evita poner la contraseña literal en los argumentos del proceso.
Si el waiter agota su tiempo, consultar el estado antes de repetir la creación.
No perder la contraseña antes de configurar el Secret. RDS Multi-AZ de instancia
mantiene un standby, no una réplica de lectura.

## 6. ECR, construcción y publicación

```bash
for ACT_SERVICE in frontend get-products create-product update-product delete-product; do
  aws ecr create-repository --repository-name "$ACT_NAME-$ACT_SERVICE" \
    --image-scanning-configuration scanOnPush=true
done
bash scripts/build-images.sh
aws ecr get-login-password | docker login --username AWS --password-stdin "$ACT_REGISTRY"
for ACT_SERVICE in frontend get-products create-product update-product delete-product; do
  docker tag "ary1102-act23-$ACT_SERVICE:validation" "$ACT_REGISTRY/$ACT_NAME-$ACT_SERVICE:validation"
  docker push "$ACT_REGISTRY/$ACT_NAME-$ACT_SERVICE:validation"
done
```

No confundir el nombre de la imagen local con el del repositorio remoto.

## 7. Balanceo administrado y Metrics Server

```bash
ACT_UPDATE=$(aws eks update-cluster-config --name "$ACT_NAME" \
  --compute-config '{"enabled":true,"nodePools":[]}' \
  --kubernetes-network-config '{"elasticLoadBalancing":{"enabled":true}}' \
  --storage-config '{"blockStorage":{"enabled":true}}' --query update.id --output text)
aws eks describe-update --name "$ACT_NAME" --update-id "$ACT_UPDATE"
# Esperar Status=Successful. Si hay errores, detener y diagnosticarlos.
aws eks describe-addon-versions --addon-name metrics-server --kubernetes-version 1.34 \
  --query 'addons[].addonVersions[0].addonVersion'
aws eks create-addon --cluster-name "$ACT_NAME" --addon-name metrics-server \
  --addon-version v0.9.0-eksbuild.13
# Comprobar ACTIVE y métricas antes de atribuir escalamiento al HPA.
aws eks describe-addon --cluster-name "$ACT_NAME" --addon-name metrics-server
kubectl top nodes
```

Los roles preconfigurados de esta cuenta permitieron Auto Mode. Se mantienen los
dos nodos convencionales, sin crear node pools automáticos. Esta adaptación reemplaza
la instalación manual de AWS Load Balancer Controller del anexo. Revisar nuevamente
versiones y compatibilidad si se reproduce en otro momento.

## 8. Configuración privada y esquema SQL

```bash
export ACT_ACCOUNT ACT_DB_HOST
export ACT_OPERATOR_CIDR="$(curl --fail --silent https://checkip.amazonaws.com | tr -d '\n')/32"
node scripts/cli-render-app.mjs
kubectl apply -f secrets/cli-k8s/namespace.yaml
kubectl apply -f secrets/cli-k8s/configmap.yaml -f secrets/cli-k8s/secret.json
kubectl create configmap init-db-sql -n escolaronline --from-file=init.sql=app/init.sql
kubectl apply -f secrets/cli-k8s/init-db-job.yaml
kubectl wait --for=condition=complete job/init-db -n escolaronline --timeout=120s
unset ACT_DB_PASSWORD
```

No volver a ejecutar la inicialización sin revisar los datos: cada ejecución SQL
agrega cinco productos. No usar `kubectl get secret -o yaml` en una captura.

## 9. Deployments, Services, Ingress y HPA

```bash
for ACT_SERVICE in frontend get-products create-product update-product delete-product; do
  kubectl apply -f "secrets/cli-k8s/$ACT_SERVICE-deployment.yaml" -f "secrets/cli-k8s/$ACT_SERVICE-service.yaml"
  kubectl rollout status "deployment/$ACT_SERVICE" -n escolaronline --timeout=120s
done
kubectl apply -f secrets/cli-k8s/ingressclass.yaml -f secrets/cli-k8s/ingress.yaml
for ACT_SERVICE in get-products create-product update-product delete-product; do
  kubectl apply -f "secrets/cli-k8s/hpa-$ACT_SERVICE.yaml"
done
kubectl get pods,services,ingress,hpa -n escolaronline
```

Esperar un DNS de ALB y destinos saludables. El frontend usa un solo origen y Nginx
distribuye por método HTTP a los Services internos con DNS completo.

## 10. Validación funcional y persistencia

```bash
ACT_ALB=$(kubectl get ingress escolaronline-ingress -n escolaronline -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl --fail "http://$ACT_ALB/"
python3 scripts/test-crud.py "http://$ACT_ALB"
```

Con `KUBECONFIG` apuntando a este entorno CLI, ejecutar:

```bash
python3 scripts/test-persistence.py "http://$ACT_ALB"
```

El script respeta `KUBECONFIG`; de no estar definido, utiliza `.kubeconfig` de la
prueba Terraform. No cambiar el contexto de otros cursos.

Para observar el HPA, ejecutar una carga CPU acotada en un pod propio y monitorear
`kubectl top pods` y `kubectl get hpa -w`. En la prueba validada aumentó de dos a
cuatro réplicas. Esto no demuestra capacidad bajo tráfico de usuarios.

Container Insights no está acreditado por esta prueba. Metrics Server y logs del
plano de control no lo sustituyen. No modificar roles IAM preconfigurados para
forzar su instalación sin revisar la autorización del laboratorio.

## 11. Retiro de un entorno creado exclusivamente con este guion

Inventariar primero los recursos por nombre, VPC y los IDs conservados en esta terminal.
Eliminar solo recursos propios. Los siguientes comandos eliminan datos e imágenes:

```bash
kubectl delete ingress escolaronline-ingress -n escolaronline
# Esperar a que el controlador retire el ALB, target groups y sus security groups.
kubectl delete namespace escolaronline
kubectl delete ingressclass ary1102-act23
kubectl delete ingressclassparams ary1102-act23
aws eks delete-addon --cluster-name "$ACT_NAME" --addon-name metrics-server
aws eks delete-nodegroup --cluster-name "$ACT_NAME" --nodegroup-name "$ACT_NAME"
aws eks wait nodegroup-deleted --cluster-name "$ACT_NAME" --nodegroup-name "$ACT_NAME"
aws eks delete-cluster --name "$ACT_NAME"
aws eks wait cluster-deleted --name "$ACT_NAME"
aws rds delete-db-instance --db-instance-identifier "$ACT_NAME" --skip-final-snapshot --delete-automated-backups
aws rds wait db-instance-deleted --db-instance-identifier "$ACT_NAME"
aws rds delete-db-subnet-group --db-subnet-group-name "$ACT_NAME"
aws ec2 delete-security-group --group-id "$ACT_DB_SG"
for ACT_SERVICE in frontend get-products create-product update-product delete-product; do
  aws ecr delete-repository --repository-name "$ACT_NAME-$ACT_SERVICE" --force
done
aws ec2 delete-nat-gateway --nat-gateway-id "$ACT_NAT"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$ACT_NAT"
aws ec2 release-address --allocation-id "$ACT_EIP"
```

La red requiere además desasociar las tablas, retirar sus rutas y subredes, eliminar
tablas no principales, desconectar/eliminar el Internet Gateway y finalmente la VPC.
Verificar ENI y grupos de seguridad residuales antes de eliminar dependencias.
No borrar la VPC por defecto ni usar IDs de otros entornos. Para **la prueba actual
gestionada por Terraform**, usar el procedimiento de su README, no estos comandos
de eliminación individual.

## Fuentes técnicas

- [AWS CLI EKS](https://docs.aws.amazon.com/cli/latest/reference/eks/)
- [EKS Auto Mode en clúster existente](https://docs.aws.amazon.com/eks/latest/userguide/auto-enable-existing.html)
- [Ingress y ALB administrado](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- [RDS create-db-instance](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html)
