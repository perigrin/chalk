sub f { $_[0] = 1 if @_ > 1 } my %h; f($h{a}); f($h{b}, 0); print join(",", sort keys %h), "\n";
