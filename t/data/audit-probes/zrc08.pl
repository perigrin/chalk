sub r { my $n=shift; my @l=(1) x $n; r($n-1) if $n; scalar(@l) } print r(3), "\n";
