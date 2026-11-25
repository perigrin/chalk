our $g=0; eval { my @r = map { local $g=$_; die "x\n" if $_==2; $_ } 1..3 }; print "$g\n";
