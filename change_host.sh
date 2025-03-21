#!/bin/bash

# Verificar si el script se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root" >&2
   exit 1
fi

# Configuración
HOSTNAME_FILE="/etc/hostname"
HOSTS_FILE="/etc/hosts"
BACKUP_EXT=".bak"

# Función para validar hostname
validar_hostname() {
    local hostname_re='^[a-zA-Z0-9-]{1,63}(\.[a-zA-Z0-9-]{1,63})*$'
    [[ $1 =~ $hostname_re ]] && return 0 || return 1
}

# Obtener parámetro si se usa de forma no interactiva
if [[ $# -eq 1 ]]; then
    NEW_HOSTNAME="$1"
else
    # Obtener el hostname actual
    CURRENT_HOSTNAME=$(hostname)

    # Solicitar el nuevo hostname
    read -p "Introduce el nuevo hostname [$CURRENT_HOSTNAME]: " NEW_HOSTNAME
    NEW_HOSTNAME=${NEW_HOSTNAME:-$CURRENT_HOSTNAME}
fi

# Validar el nuevo hostname
if ! validar_hostname "$NEW_HOSTNAME"; then
    echo "Error: El hostname '$NEW_HOSTNAME' no es válido." >&2
    echo "Debe contener solo letras, números y guiones, máximo 63 caracteres por etiqueta." >&2
    exit 1
fi

# Crear copia de seguridad de los archivos
cp "$HOSTNAME_FILE" "${HOSTNAME_FILE}${BACKUP_EXT}" || exit 1
cp "$HOSTS_FILE" "${HOSTS_FILE}${BACKUP_EXT}" || exit 1

# Cambiar hostname temporalmente
if ! hostnamectl set-hostname "$NEW_HOSTNAME"; then
    echo "Error al cambiar el hostname temporalmente" >&2
    exit 1
fi

# Actualizar archivo /etc/hostname
echo "$NEW_HOSTNAME" > "$HOSTNAME_FILE" || exit 1

# Actualizar /etc/hosts
CURRENT_HOSTNAME_ESCAPED=$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<< "$CURRENT_HOSTNAME")
sed -i -E "/\s$CURRENT_HOSTNAME_ESCAPED(\s|$)/s/$CURRENT_HOSTNAME_ESCAPED/$NEW_HOSTNAME/g" "$HOSTS_FILE"

# Verificar cambios en hosts
if ! grep -q "\s$NEW_HOSTNAME\s*$" "$HOSTS_FILE"; then
    echo "Advertencia: No se encontró el nuevo hostname en $HOSTS_FILE" >&2
    echo "Es posible que necesite actualizar manualmente las entradas de red." >&2
fi

# Mostrar cambios
echo -e "\nHostname cambiado de: $(cat "${HOSTNAME_FILE}${BACKUP_EXT}")"
echo "               a: $NEW_HOSTNAME"
echo -e "\nArchivos modificados:"
echo "- $HOSTNAME_FILE (backup: ${HOSTNAME_FILE}${BACKUP_EXT})"
echo "- $HOSTS_FILE (backup: ${HOSTS_FILE}${BACKUP_EXT})"

# Preguntar por reinicio
if [[ -z $1 ]]; then  # Solo en modo interactivo
    read -p "¿Desea reiniciar ahora? [s/N]: " REINICIAR
    if [[ ${REINICIAR,,} =~ ^s ]]; then
        shutdown -r now
    else
        echo "Recuerda que los cambios completos se aplicarán después del reinicio."
    fi
fi
