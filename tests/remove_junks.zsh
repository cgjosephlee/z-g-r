asset_names=(
    'normal.zip'
    'ok.tar'
    'foo.txt'
    'bar.sha256'
    'baz.sig'
    'qux.md5'
    'quux.apk'
    'corge.b3'
    'grault.deb'
    'garply.json'
    'waldo.pkg'
    'fred.rpm'
    'plugh.sh'
    'xyzzy.zst'
)

local junk='*((sha256|sig|sum|386|asc|md5|txt|vsix)*|(apk|b3|deb|json|pkg|rpm|sh|zst)(#e))'
local filtered

echo "${(m)asset_names[1]:#(#i)${~junk}}"

# flag m ??
filtered=(${(m@)asset_names:#(#i)${~junk}}) && \
    (( $#filtered > 0 )) && \
    asset_names=(${filtered[@]})

echo "Filtered asset names: ${asset_names[@]}"
