my $n=0; my $f; $f=sub { my $k=shift; return 0 unless $k; $n+=$k; $f->($k-1) }; $f->(3); print "$n\n";
