# Prueba local de capacidad: 8 GiB

**Fecha:** 2026-11-02 UTC. **Resultado:** RAM local PASS; reducción a `t3a.large` no aprobada para EKS.

Se retiraron los tres workers `counter` de demostración, que no forman parte de la PoC AWS. Quedaron dos workers `codex-poc`. Se reinició el perfil Colima `substrate-poc` con 4 CPU y 8 GiB. Tras recuperar los pods que Docker dejó en estado `Unknown`, todos los pods activos de `ate-system` estuvieron `Ready` y el WorkerPool Codex informó 2/2 workers listos. La prueba `infra/local/smoke-topology.sh` pasó: actor asignado, worker ocupado, suspensión y retorno a idle.

Se crearon dos actores Codex simultáneos sin llamar a OpenAI. Ambos respondieron `/healthz` y Substrate los asignó a workers distintos. Durante cinco muestras consecutivas, el contenedor `kind-control-plane` usó aproximadamente 2,08 GiB de los 7,738 GiB visibles para Docker. Kubernetes reportó `MemoryPressure=False`, 4.290 MiB de solicitudes de memoria (54 % del nodo local) y 5.716 MiB de límites (72 %). El test borró ambos actores al terminar. La clave OpenAI ya había sido eliminada del clúster local.

La reserva de CPU local fue 2.110 millicores (52 % del nodo de 4 vCPU), incluyendo el plano de control propio de kind. En EKS parte de ese plano corre fuera del nodo, pero se suman EBS CSI, Pod Identity, VPC CNI, frontend y API. Por eso esta prueba confirma memoria disponible, no capacidad de `t3a.large` con 2 vCPU. No se ha ejecutado el despliegue EKS ni una medición de CPU de esa configuración.

Según [precios públicos EC2 de AWS](https://aws.amazon.com/ec2/instance-types/t3/) para Linux en `us-east-1`, `t3a.large` cuesta USD 0,0752/h y `t3a.xlarge` USD 0,1504/h. En una ventana de 48 horas la reducción ahorraría USD 3,61 en EC2; el cargo de EKS y demás componentes no cambia. Se mantiene `t3a.xlarge` como valor inicial hasta que un smoke real en EKS demuestre que una instancia menor soporta el conjunto completo.
