my %h = (a=>1,b=>2,c=>3); sub cl { my ($r, @k) = @_; delete @$r{@k} } cl(\%h, "b", "c"); print join(",", keys %h), "\n";
