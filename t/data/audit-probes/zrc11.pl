sub ev { my $n=shift; $n==0 ? 1 : od($n-1) } sub od { my $n=shift; $n==0 ? 0 : ev($n-1) } print ev(4), od(3), ev(3), "\n";
