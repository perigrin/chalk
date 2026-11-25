eval { die }; print $@ =~ /^Died at/ ? "died" : "other"; eval { die "msg" }; print $@ =~ /^msg at .* line 1\.$/ ? "line" : "other"; eval { die "a", "b", "\n" }; print $@;
