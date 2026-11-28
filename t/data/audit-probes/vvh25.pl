eval { eval { die "a\n" }; print $@; die "b\n" }; print $@;
