my $f; $f = sub { my $n = shift; $n ? $n * $f->($n-1) : 1 }; print $f->(5), "\n";
