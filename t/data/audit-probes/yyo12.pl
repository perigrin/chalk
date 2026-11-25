use Carp; sub f { croak "bad arg" } eval { f() }; print $@ =~ /^bad arg at .* line 1\.?$/ ? "croak" : "other:$@", "\n";
