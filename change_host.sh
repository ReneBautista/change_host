#!/bin/bash

# Verificar si el script se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse con sudo:" >&2
   echo "  sudo $0 [nuevo_hostname] [--reboot]" >&2
   exit 1
fi

# Configuración
SHUTDOWN_CMD="/sbin/shutdown"
HOSTNAME_FILE="/etc/hostname"
HOSTS_FILE="/etc/hosts"
BACKUP_EXT=".bak"

# Capturar hostname original antes de cualquier cambio
OLD_HOSTNAME=$(hostname)

# Función para validar hostname
validar_hostname() {
    local hostname_re='^[a-zA-Z0-9-]{1,63}(\.[a-zA-Z0-9-]{1,63})*$'
    [[ $1 =~ $hostname_re ]] && return 0 || return 1
}

# Procesar parámetros
NUEVO_HOSTNAME=""
REINICIAR=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --reboot)
            REINICIAR=1
            shift
            ;;
        *)
            NUEVO_HOSTNAME=$1
            shift
            ;;
    esac
done

# Modo interactivo si no se pasó hostname
if [[ -z "$NUEVO_HOSTNAME" ]]; then
    read -p "Introduce el nuevo hostname [$OLD_HOSTNAME]: " input_hostname
    NUEVO_HOSTNAME=${input_hostname:-$OLD_HOSTNAME}
fi

# Validar el nuevo hostname
if ! validar_hostname "$NUEVO_HOSTNAME"; then
    echo "Error: El hostname '$NUEVO_HOSTNAME' no es válido." >&2
    echo "Debe contener solo letras, números y guiones, máximo 63 caracteres por etiqueta." >&2
    exit 1
fi

# Crear copia de seguridad
for file in "$HOSTNAME_FILE" "$HOSTS_FILE"; do
    cp -v "$file" "${file}${BACKUP_EXT}" || exit 1
done

# Cambiar hostname temporalmente
if ! hostnamectl set-hostname "$NUEVO_HOSTNAME"; then
    echo "Error al cambiar el hostname temporalmente" >&2
    exit 1
fi

# Actualizar archivo /etc/hostname
echo "$NUEVO_HOSTNAME" > "$HOSTNAME_FILE" || exit 1

# Actualizar /etc/hosts (con escape correcto)
ESCAPED_OLD_HOSTNAME=$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<< "$OLD_HOSTNAME")
sed -i -E "s/\b${ESCAPED_OLD_HOSTNAME}\b/${NUEVO_HOSTNAME}/g" "$HOSTS_FILE"

# Verificar cambios
echo -e "\n=== Cambios realizados ==="
echo "Hostname original: $OLD_HOSTNAME"
echo "Hostname nuevo:    $NUEVO_HOSTNAME"
echo -e "\n=== Diferencias en /etc/hosts ==="
diff --color=always "${HOSTS_FILE}${BACKUP_EXT}" "$HOSTS_FILE"

# Manejo del reinicio
if [[ $REINICIAR -eq 1 ]]; then
    echo -e "\nIniciando reinicio inmediato..."
    $SHUTDOWN_CMD -r now
else
    if [[ -t 0 ]]; then  # Solo preguntar si es una sesión interactiva
        read -p "¿Desea reiniciar ahora? [s/N]: " respuesta
        if [[ "${respuesta,,}" =~ ^(s|y) ]]; then
            echo -e "\nIniciando reinicio inmediato..."
            $SHUTDOWN_CMD -r now
        else
            echo -e "\nReinicio omitido. Recuerda reiniciar para aplicar cambios completamente."
        fi
    fi
fi