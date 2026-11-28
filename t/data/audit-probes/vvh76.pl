eval { warn "w\n" if 0; die "x\n" unless 0 }; print $@;
