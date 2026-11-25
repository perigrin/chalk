my $n=0; my $f; $f=sub { my $k=shift; return 1 if $k<2; $k*$f->($k-1) }; print $f->(5), "\n";
