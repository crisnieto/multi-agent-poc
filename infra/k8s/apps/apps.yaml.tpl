apiVersion: v1
kind: ServiceAccount
metadata:
  name: poc-control-plane
  namespace: ate-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: poc-control-plane
  namespace: ate-system
rules:
- apiGroups: [""]
  resources: ["services", "pods"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["get", "create"]
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  resourceNames: ["ate-client"]
  verbs: ["create"]
- apiGroups: ["certificates.k8s.io"]
  resources: ["podcertificaterequests"]
  verbs: ["create", "get", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: poc-control-plane
  namespace: ate-system
subjects:
- kind: ServiceAccount
  name: poc-control-plane
  namespace: ate-system
roleRef:
  kind: Role
  name: poc-control-plane
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: poc-control-plane-trust-bundles
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["clustertrustbundles"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: poc-control-plane-trust-bundles
subjects:
- kind: ServiceAccount
  name: poc-control-plane
  namespace: ate-system
roleRef:
  kind: ClusterRole
  name: poc-control-plane-trust-bundles
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: poc-control-plane-data
  namespace: ate-system
  labels:
    Project: substrate-poc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: substrate-poc-gp3
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: poc-control-plane
  namespace: ate-system
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: poc-control-plane
  template:
    metadata:
      labels:
        app: poc-control-plane
    spec:
      serviceAccountName: poc-control-plane
      securityContext:
        fsGroup: 10001
      containers:
      - name: api
        image: __CONTROL_PLANE_IMAGE__
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: POC_OPERATOR_PASSWORD
          valueFrom:
            secretKeyRef:
              name: poc-operator-login
              key: password
        - name: POC_COOKIE_SECURE
          value: "false"
        - name: POC_ATESPACE
          value: ate-demo-counter
        - name: POC_ACTOR_TEMPLATE
          value: codex-poc
        - name: POC_IDLE_SUSPEND_MS
          value: "60000"
        volumeMounts:
        - name: data
          mountPath: /data
        readinessProbe:
          httpGet:
            path: /api/healthz
            port: http
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /api/healthz
            port: http
          periodSeconds: 15
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 768Mi
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: poc-control-plane-data
---
apiVersion: v1
kind: Service
metadata:
  name: control-plane
  namespace: ate-system
spec:
  type: ClusterIP
  selector:
    app: poc-control-plane
  ports:
  - name: http
    port: 8080
    targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: poc-web
  namespace: ate-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: poc-web
  template:
    metadata:
      labels:
        app: poc-web
    spec:
      containers:
      - name: web
        image: __WEB_IMAGE__
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
        readinessProbe:
          httpGet:
            path: /
            port: http
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: http
          periodSeconds: 15
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 250m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: poc-web
  namespace: ate-system
spec:
  type: __WEB_SERVICE_TYPE__
  selector:
    app: poc-web
  ports:
  - name: http
    port: 8080
    targetPort: http
__WEB_NODE_PORT_LINE__
