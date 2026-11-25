our $g=1; sub f { local $g=$g+1; die "deep\n" if $_[0]==0; f($_[0]-1) } eval { f(3) }; print "$g $@";
