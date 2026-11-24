our $d=0; sub r { my $n=shift; local $d=$d+1; die "deep$d\n" unless $n; r($n-1) } eval { r(2) }; print "$d $@";
