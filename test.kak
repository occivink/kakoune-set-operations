try %{
    require-module set-operations
} catch %{
    source set-operations.kak
    require-module set-operations
}

define-command assert-selections-are -params 1 %{
    eval %sh{
        if [ "$1" != "$kak_quoted_selections" ]; then
            printf 'echo -debug %%arg{1} ; '
            printf 'echo -quoting shell -debug %%val{selections} ; '
            printf 'fail "Check failed" ; '
        fi
    }
}

edit -scratch *set-operations-test-1*

exec 'iab cd ef gh ij kl mn op qr st uv wx yz<esc>'
exec -draft -save-regs '' '%s\b\w<ret>)Z'
exec '%s\w+<ret>)'
set-operation intersection
exec '%s\w+<ret>)'
set-operation union
exec '%s\w+<ret>)'
set-operation difference
#assert-selections-are "'foo' 'bar' 'baz'"

#delete-buffer
