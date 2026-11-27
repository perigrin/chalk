sub f { h2(); my ($p) = @_; $p } sub h2 { $main::h{k} = 2 } our %h = (k=>1); print f($h{k}), "\n";
