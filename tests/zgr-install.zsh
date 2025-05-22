set -eo pipefail

ZGR_DEBUG=1
ZGR_DIR="/workspaces/z-g-r/test_dir"

source ${0:A:h}/../init.zsh

zgr-install jqlang/jq

zgr-install babarot/afx

