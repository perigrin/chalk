sub f { $_[0] = 1 } my %h; f($h{a}); print exists $h{a} ? 1 : 0, "\n";
