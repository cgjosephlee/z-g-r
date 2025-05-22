source ${0:A:h}/../JSON.sh

# curl -fsSL https://api.github.com/repos/babarot/afx/releases/latest | .zgr-parse-json | grep "browser_download_url" | sed -E 's/.*"(https:[^"]+)"/\1/'

curl -fsSL https://api.github.com/repos/babarot/afx/releases/tags/v0.2.1 | .zgr-parse-json  | grep "browser_download_url" | sed -E 's/.*"(https:[^"]+)"/\1/'
