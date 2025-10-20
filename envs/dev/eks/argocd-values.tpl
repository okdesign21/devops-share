global:
  domain: "argocd.${env}.${base_domain}"

server:
  service:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: "alb"
    annotations:
      alb.ingress.kubernetes.io/scheme: "internet-facing"
      alb.ingress.kubernetes.io/target-type: "ip"
      alb.ingress.kubernetes.io/listen-ports: '[{ "HTTP": 80 }]'
      alb.ingress.kubernetes.io/healthcheck-path: "/healthz"
      alb.ingress.kubernetes.io/backend-protocol: "HTTP"
    hosts:
      - "argocd.${env}.${base_domain}"

configs:
  params:
    server.insecure: true
  cm:
    timeout.reconciliation: "180s"
    application.resourceTrackingMethod: "annotation"