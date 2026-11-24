my $f; $f=sub { my $n=shift; $n<=1 ? 1 : $n*$f->($n-1) }; print $f->(5),"\n";
