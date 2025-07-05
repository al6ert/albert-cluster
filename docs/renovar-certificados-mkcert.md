# Renovar certificados TLS con mkcert en Minikube

Esta guía explica cómo renovar manualmente los certificados TLS generados con mkcert para usarlos en Minikube y Traefik.

> **Importante:** Los certificados deben generarse y mantenerse en la carpeta oculta `.certs/` (ya incluida en el `.gitignore`).

## Pasos para renovar el certificado

1. **Regenera el certificado wildcard**

   Ejecuta en tu terminal:
   ```sh
   mkcert -cert-file .certs/_wildcard.127.0.0.1.nip.io.pem -key-file .certs/_wildcard.127.0.0.1.nip.io-key.pem '*.127.0.0.1.nip.io'
   ```
   Esto generará dos archivos en `.certs/`:
   - `_wildcard.127.0.0.1.nip.io.pem` (certificado)
   - `_wildcard.127.0.0.1.nip.io-key.pem` (clave privada)

2. **Actualiza el Secret en Kubernetes**

   Sube el nuevo certificado y clave como un Secret TLS en el namespace correspondiente (por ejemplo, `kube-system` o `traefik`):
   ```sh
   kubectl create secret tls traefik-local-tls \
     --cert=.certs/_wildcard.127.0.0.1.nip.io.pem \
     --key=.certs/_wildcard.127.0.0.1.nip.io-key.pem \
     -n traefik --dry-run=client -o yaml | kubectl apply -f -
   ```
   > **Nota:** Cambia el namespace si usas otro distinto.

3. **Reinicia Traefik para aplicar el nuevo certificado**

   ```sh
   kubectl rollout restart deployment traefik -n traefik
   ```

4. **Verifica el certificado**

   Accede a tu servicio en `https://<subdominio>.127.0.0.1.nip.io` y comprueba que el navegador reconoce el nuevo certificado.

---

**¿Por qué es manual?**

mkcert no tiene un sistema de renovación automática. Si el certificado expira o lo eliminas, repite estos pasos. 