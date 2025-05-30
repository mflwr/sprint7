#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Генерация пользовательских сертификатов и настройка kubeconfig
# -----------------------------------------------------------------------------

# Путь до CA Minikube
CA_CERT="${HOME}/.minikube/ca.crt"
CA_KEY="${HOME}/.minikube/ca.key"
CA_SERIAL="${HOME}/.minikube/ca.srl"

# Целевой кластер и его kubeconfig
CLUSTER_NAME="minikube"
KUBECONFIG="${HOME}/.kube/config"

# Папка для хранения артефактов
WORKDIR="$(pwd)/users"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# Пользователи в формате "username:group"
declare -a USERS=(
  "admin-user:admins"
  "ns-admin-user:namespace-admins"
  "dev-user:developers"
  "auditor-user:security"
  "viewer-user:viewers"
)

# Функция для генерации сертификата
gen_cert() {
  local user="$1"
  local group="$2"
  local key_file="${user}.key"
  local csr_file="${user}.csr"
  local crt_file="${user}.crt"

  echo ">>> Generating key and CSR for ${user} (group: ${group})"
  openssl genrsa -out "${key_file}" 2048
  openssl req -new -key "${key_file}" -out "${csr_file}" \
    -subj "/CN=${user}/O=${group}"

  echo ">>> Signing certificate for ${user}"
  openssl x509 -req -in "${csr_file}" \
    -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
    -CAserial "${CA_SERIAL}" \
    -out "${crt_file}" -days 365 \
    -extensions usr_cert

  # clean up CSR
  rm -f "${csr_file}"
}

# Функция для создания контекста в kubeconfig
setup_kubeconfig() {
  local user="$1"
  local key_file="${WORKDIR}/${user}.key"
  local crt_file="${WORKDIR}/${user}.crt"
  local ctx_name="${user}-context"

  echo ">>> Configuring kubeconfig for ${user}"
  kubectl config set-credentials "${user}" \
    --client-certificate="${crt_file}" \
    --client-key="${key_file}" \
    --kubeconfig="${KUBECONFIG}"

  kubectl config set-context "${ctx_name}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${user}" \
    --kubeconfig="${KUBECONFIG}"
}

# Основной цикл
for entry in "${USERS[@]}"; do
  IFS=":" read -r user group <<< "${entry}"
  gen_cert "${user}" "${group}"
  setup_kubeconfig "${user}"
done

echo ">>> All done! Certificates are in ${WORKDIR}, kubeconfig updated at ${KUBECONFIG}"
