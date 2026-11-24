our $g=1; sub f { my $i=0; while ($i<3) { local $g=$g*2; $i++; die "x$g\n" if $i==2 } } eval { f() }; print "$g $@";
