sub ev { my ($n) = @_; $n == 0 ? 1 : od($n - 1) } sub od { my ($n) = @_; $n == 0 ? 0 : ev($n - 1) } print ev(6), od(6), "\n";
