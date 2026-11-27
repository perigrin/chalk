sub f { h2(); my ($p) = @_; $p } sub h2 { $main::h{j} = 4; $main::h{k}++ } our %h = (k=>1); print f($h{k}), join(",", sort keys %h), "\n";
