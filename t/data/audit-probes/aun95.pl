our $g=1; eval { local $g = 2; warn "w\n"; local $SIG{__WARN__}; die "x\n" }; print "$g\n";
