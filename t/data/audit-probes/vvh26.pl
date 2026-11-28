eval { eval { die "a\n" }; die "c:$@" }; print $@;
