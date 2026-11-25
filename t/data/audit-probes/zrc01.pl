sub r { my $n=shift; return 0 unless $n; my $t=$n; my $s=r($n-1); $t+$s } print r(3), "\n";
