set -eo pipefail

ZGR_DEBUG=1
ZGR_DIR="/workspaces/z-g-r/test_dir"

source ${0:A:h}/../init.zsh

# zgr-install \
#     --bin 'jq* -> jq' \
#     jqlang/jq

zgr-uninstall jqlang/jq

# zgr-install \
#     --if '[[ -n $GITHUB_TOKEN ]]' \
#     --exec './afx completion zsh > _afx' \
#     --bin 'afx -> afxx' \
#     --comp '_afx' \
#     babarot/afx

# zgr-uninstall babarot/afx